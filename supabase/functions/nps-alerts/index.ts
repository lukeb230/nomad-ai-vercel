// supabase/functions/nps-alerts/index.ts
//
// Returns active NPS alerts for parks in a given US state. Two-step pipeline:
//   1. GET /api/v1/parks?stateCode=XX  → list of NPS units in that state
//   2. GET /api/v1/alerts?parkCode=...  → alerts for those units
//
// We resolve park names from step 1 so the response is self-contained — iOS
// gets `parkName` per alert without a second lookup. NPS_API_KEY lives in
// Supabase secrets; iOS never sees it.

const NPS_API_KEY = Deno.env.get("NPS_API_KEY");
const NPS_BASE = "https://developer.nps.gov/api/v1";

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
  if (!NPS_API_KEY) {
    return json({ error: "NPS_API_KEY not configured" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const stateCode = String(body.stateCode ?? "").trim().toUpperCase();
  if (stateCode.length !== 2) {
    return json({ error: "stateCode must be a 2-letter US state code" }, 400);
  }

  // Step 1: parks in that state.
  const parksUrl = new URL(`${NPS_BASE}/parks`);
  parksUrl.searchParams.set("stateCode", stateCode);
  parksUrl.searchParams.set("limit", "50");
  parksUrl.searchParams.set("api_key", NPS_API_KEY);

  const parksResp = await fetch(parksUrl.toString(), {
    headers: { accept: "application/json" },
  });
  if (!parksResp.ok) {
    const text = await parksResp.text();
    console.error(`[nps-alerts] parks ${parksResp.status}: ${text.slice(0, 200)}`);
    return json({ error: `NPS parks upstream ${parksResp.status}` }, 502);
  }
  // deno-lint-ignore no-explicit-any
  const parksData: any = await parksResp.json();
  // deno-lint-ignore no-explicit-any
  const parks: { parkCode: string; fullName: string }[] = (parksData.data ?? []).map((p: any) => ({
    parkCode: String(p.parkCode ?? ""),
    fullName: String(p.fullName ?? ""),
  })).filter((p: { parkCode: string }) => p.parkCode);

  if (parks.length === 0) {
    return json({ stateCode, parks: [], alerts: [] });
  }

  const parkCodes = parks.map((p) => p.parkCode);
  const parkNameByCode = Object.fromEntries(parks.map((p) => [p.parkCode, p.fullName]));

  // Step 2: alerts for those parks.
  const alertsUrl = new URL(`${NPS_BASE}/alerts`);
  alertsUrl.searchParams.set("parkCode", parkCodes.join(","));
  alertsUrl.searchParams.set("limit", "200");
  alertsUrl.searchParams.set("api_key", NPS_API_KEY);

  const alertsResp = await fetch(alertsUrl.toString(), {
    headers: { accept: "application/json" },
  });
  if (!alertsResp.ok) {
    const text = await alertsResp.text();
    console.error(`[nps-alerts] alerts ${alertsResp.status}: ${text.slice(0, 200)}`);
    return json({ error: `NPS alerts upstream ${alertsResp.status}` }, 502);
  }
  // deno-lint-ignore no-explicit-any
  const alertsData: any = await alertsResp.json();
  // deno-lint-ignore no-explicit-any
  const rawAlerts: any[] = alertsData.data ?? [];

  // deno-lint-ignore no-explicit-any
  const alerts = rawAlerts.map((a: any) => ({
    id: String(a.id ?? crypto.randomUUID()),
    title: String(a.title ?? "").trim(),
    description: String(a.description ?? "").trim(),
    category: String(a.category ?? "Information").trim(),
    parkCode: String(a.parkCode ?? ""),
    parkName: parkNameByCode[String(a.parkCode ?? "")] ?? "",
    url: String(a.url ?? "").trim(),
    lastIndexed: String(a.lastIndexedDate ?? ""),
  })).filter((a: { title: string }) => a.title.length > 0);

  console.log(`[nps-alerts] state=${stateCode} parks=${parks.length} alerts=${alerts.length}`);

  return json({ stateCode, parks: parks.length, alerts });
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
