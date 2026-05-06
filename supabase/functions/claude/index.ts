// supabase/functions/claude/index.ts
// Proxies Anthropic Messages API calls. The ANTHROPIC_KEY lives in Supabase
// secrets. iOS calls this via the Supabase SDK's `client.functions.invoke(...)`.
//
// Behavior:
//   - Per-IP rate limits enforced via the public.rate_limits table:
//       15/hour, 75/day, 300/week, 800/month.
//     Successful calls log a row; failures don't burn quota. Failed lookups
//     fail open so a DB hiccup never blocks real users.
//   - Transforms a string `system` field into Anthropic's prompt-caching
//     array form (cache_control: ephemeral). ~30–50% input cost reduction
//     when the system prompt is reused across calls.
//   - Logs cache_read / cache_write token counts for visibility in the
//     Supabase Functions log viewer.
//
// Tier-aware (per-user) limits replace per-IP when StoreKit ships — see
// CLAUDE.md "Monetization plan".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OWNER_USER_ID = Deno.env.get("OWNER_USER_ID");

const LIMITS = {
  hour: 15,
  day: 75,
  week: 300,
  month: 800,
} as const;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!ANTHROPIC_KEY) {
    return json({ error: "ANTHROPIC_KEY not configured" }, 500);
  }

  const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
    .split(",")[0]
    .trim();

  // Owner bypass: verify the caller's JWT and skip rate limiting if it's the
  // app owner. JWT verification is delegated to Supabase's auth endpoint.
  const isOwner = await isOwnerRequest(req);

  if (!isOwner) {
    const { data: counts, error: rlErr } = await supabase
      .rpc("check_rate_limit", { p_ip: ip })
      .single();

    if (rlErr) {
      // Fail open — don't block users on a DB blip.
      console.error(`[claude] rate-limit lookup failed: ${rlErr.message}`);
    } else if (counts) {
      const breach = checkBreach(counts as Counts);
      if (breach) {
        console.log(
          `[claude] rate limited ip=${ip} window=${breach.window} ${breach.count}/${breach.limit}`,
        );
        return json(
          {
            error: {
              type: "rate_limit",
              message: `Rate limit reached (${breach.limit} per ${breach.window}). Try again later.`,
            },
          },
          429,
        );
      }
    }
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (typeof body.system === "string" && (body.system as string).length > 0) {
    body.system = [
      { type: "text", text: body.system, cache_control: { type: "ephemeral" } },
    ];
  }

  // The web_search tool is gated behind an Anthropic beta header. Detect it in
  // the tool list iOS sent and add the header conditionally so non-search
  // calls aren't affected.
  const toolList = Array.isArray(body.tools) ? body.tools : [];
  const usesWebSearch = toolList.some(
    // deno-lint-ignore no-explicit-any
    (t: any) => typeof t?.type === "string" && t.type.startsWith("web_search"),
  );

  const upstreamHeaders: Record<string, string> = {
    "Content-Type": "application/json",
    "x-api-key": ANTHROPIC_KEY,
    "anthropic-version": "2023-06-01",
  };
  if (usesWebSearch) {
    upstreamHeaders["anthropic-beta"] = "web-search-2025-03-05";
  }

  const wantsStream = body.stream === true;

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: upstreamHeaders,
    body: JSON.stringify(body),
  });

  // Charge the rate-limit row at request-accept time on success — works
  // for both buffered and streaming paths (the latter wouldn't otherwise
  // count toward the per-IP limit because we don't watch the stream finish).
  if (upstream.ok && !isOwner) {
    const { error: insertErr } = await supabase
      .from("rate_limits")
      .insert({ ip });
    if (insertErr) {
      console.error(`[claude] rate-limit insert failed: ${insertErr.message}`);
    }
  }

  // Non-2xx: forward the body (likely an Anthropic error JSON) as-is.
  if (!upstream.ok) {
    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  // Streaming path — forward Anthropic's SSE response straight to the client.
  // We skip usage logging in this mode (would require parsing the stream
  // ourselves to capture the final message_delta event with usage stats).
  if (wantsStream) {
    console.log(`[claude] streaming response`);
    return new Response(upstream.body, {
      status: 200,
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        ...corsHeaders,
      },
    });
  }

  // Buffered path — existing behavior.
  const data = await upstream.json();
  // deno-lint-ignore no-explicit-any
  const u = (data as any)?.usage;
  if (u) {
    const ws = u.server_tool_use?.web_search_requests ?? 0;
    console.log(
      `[claude] in=${u.input_tokens ?? 0} out=${u.output_tokens ?? 0} ` +
        `cache_read=${u.cache_read_input_tokens ?? 0} cache_write=${u.cache_creation_input_tokens ?? 0} ` +
        `web_search=${ws}`,
    );
  }

  return json(data, upstream.status);
});

type Counts = {
  hour_count: number;
  day_count: number;
  week_count: number;
  month_count: number;
};

function checkBreach(
  c: Counts,
): { window: string; count: number; limit: number } | null {
  if (c.hour_count >= LIMITS.hour) {
    return { window: "hour", count: c.hour_count, limit: LIMITS.hour };
  }
  if (c.day_count >= LIMITS.day) {
    return { window: "day", count: c.day_count, limit: LIMITS.day };
  }
  if (c.week_count >= LIMITS.week) {
    return { window: "week", count: c.week_count, limit: LIMITS.week };
  }
  if (c.month_count >= LIMITS.month) {
    return { window: "month", count: c.month_count, limit: LIMITS.month };
  }
  return null;
}

async function isOwnerRequest(req: Request): Promise<boolean> {
  if (!OWNER_USER_ID) return false;
  const auth = req.headers.get("authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "").trim();
  // Anon callers send the publishable key here, not a JWT — skip cheaply.
  if (jwt.split(".").length !== 3) return false;
  try {
    const { data, error } = await supabase.auth.getUser(jwt);
    if (error) return false;
    return data.user?.id === OWNER_USER_ID;
  } catch {
    return false;
  }
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
