// supabase/functions/places/index.ts
// Proxies Google Places: text-search → photo references, and ref → JPEG bytes.
// Deploy with --no-verify-jwt so AsyncImage in iOS can GET the photo URL with
// no Authorization header (the Google key stays secret server-side regardless).
//
// Two modes via ?type=:
//   ?type=search&input=<query>   → JSON { candidates: [{ photos: [{ photo_reference }] }] }
//   ?type=photo&ref=<reference>  → image/jpeg bytes, Cache-Control: public, max-age=86400

const GKEY = Deno.env.get("GOOGLE_PLACES_KEY");

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!GKEY) {
    return json({ error: "GOOGLE_PLACES_KEY not configured" }, 500);
  }

  const url = new URL(req.url);
  const type = url.searchParams.get("type");

  if (type === "search") {
    const input = url.searchParams.get("input");
    if (!input) return json({ error: "Missing input param" }, 400);
    try {
      const upstream = `https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=${
        encodeURIComponent(input)
      }&inputtype=textquery&fields=photos&key=${GKEY}`;
      const r = await fetch(upstream);
      const d = await r.json();
      const photos = d?.candidates?.[0]?.photos?.slice(0, 5) ?? [];
      return json({ candidates: [{ photos }] });
    } catch (e) {
      return json({ error: (e as Error).message }, 500);
    }
  }

  if (type === "photo") {
    const ref = url.searchParams.get("ref");
    if (!ref) return json({ error: "Missing ref param" }, 400);
    try {
      const photoUrl =
        `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${ref}&key=${GKEY}`;
      const r = await fetch(photoUrl, { redirect: "follow" });
      if (!r.ok) {
        return json({ error: `Upstream ${r.status}` }, r.status);
      }
      const contentType = r.headers.get("content-type") ?? "image/jpeg";
      const buf = await r.arrayBuffer();
      return new Response(buf, {
        status: 200,
        headers: {
          "Content-Type": contentType,
          "Cache-Control": "public, max-age=86400",
          ...corsHeaders,
        },
      });
    } catch (e) {
      return json({ error: (e as Error).message }, 500);
    }
  }

  return json({ error: "Missing or invalid type param" }, 400);
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
