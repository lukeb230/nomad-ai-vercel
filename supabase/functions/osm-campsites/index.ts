// supabase/functions/osm-campsites/index.ts
//
// Live proxy to the OpenStreetMap Overpass API for campsite POIs near a point.
// Free, no API key, public mirror at overpass-api.de. We POST an Overpass QL
// query and reshape the result into CampsiteDTO objects so iOS can consume
// them the same way it consumes RIDB results.
//
// Same `_fromDatabase: true` marker → CoordinateValidator skips them.
//
// Coverage: tourism=camp_site + tourism=caravan_site, both nodes and ways.
// This includes most state parks, BLM dispersed sites users have tagged,
// primitive sites, RV parks, international sites, etc. Quality varies — many
// entries have a name and not much else; we still return them because the
// name + coords are what Claude needs as grounding.

// Multiple Overpass mirrors — try in order. overpass-api.de sometimes 406s
// requests from cloud IPs without a clear User-Agent; the kumi.systems mirror
// is more permissive. Both are free and identical APIs.
const OVERPASS_URLS = [
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass-api.de/api/interpreter",
];
const OVERPASS_TIMEOUT_S = 20;
const USER_AGENT = "NomadAI/1.0 (https://nomadai.us; contact: lukebrowneo20@gmail.com)";

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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const lat = Number(body.lat);
  const lng = Number(body.lng);
  const radiusMiles = Math.min(Math.max(Number(body.radius ?? 50), 1), 200);
  const limit = Math.min(Math.max(Number(body.limit ?? 20), 1), 50);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return json({ error: "lat and lng required" }, 400);
  }

  const radiusMeters = Math.round(radiusMiles * 1609.34);
  // Broad camping-relevant POI query. Goes well beyond `tourism=camp_site` to
  // catch overlander-relevant primitive shelters and huts that many overlanders
  // actually rely on for backcountry stops:
  //   - tourism=camp_site / caravan_site  → standard / RV camping
  //   - tourism=wilderness_hut            → primitive backcountry shelters
  //   - tourism=alpine_hut                → mountain refuges
  //   - amenity=shelter (basic_hut/lean_to/weather_shelter) → trail shelters
  // We require a `name` tag downstream, which keeps the noise level reasonable.
  const query = `
[out:json][timeout:${OVERPASS_TIMEOUT_S}];
(
  node["tourism"="camp_site"](around:${radiusMeters},${lat},${lng});
  node["tourism"="caravan_site"](around:${radiusMeters},${lat},${lng});
  node["tourism"="wilderness_hut"](around:${radiusMeters},${lat},${lng});
  node["tourism"="alpine_hut"](around:${radiusMeters},${lat},${lng});
  node["amenity"="shelter"]["shelter_type"~"^(basic_hut|lean_to|weather_shelter)$"](around:${radiusMeters},${lat},${lng});
  way["tourism"="camp_site"](around:${radiusMeters},${lat},${lng});
  way["tourism"="caravan_site"](around:${radiusMeters},${lat},${lng});
  way["tourism"="wilderness_hut"](around:${radiusMeters},${lat},${lng});
  way["tourism"="alpine_hut"](around:${radiusMeters},${lat},${lng});
);
out center tags;
`.trim();

  // Overpass picks response format from the [out:json] directive in the query
  // itself — sending `Accept: application/json` makes some mirrors return 406.
  // Overpass also expects a UA — anonymous cloud-IP requests get throttled or
  // rejected outright.
  let upstream: Response | null = null;
  let lastErr = "";
  for (const url of OVERPASS_URLS) {
    try {
      const r = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "User-Agent": USER_AGENT,
        },
        body: `data=${encodeURIComponent(query)}`,
      });
      if (r.ok) {
        upstream = r;
        break;
      }
      const text = await r.text();
      lastErr = `${url} → ${r.status}: ${text.slice(0, 200)}`;
      console.warn(`[osm-campsites] mirror failed: ${lastErr}`);
    } catch (e) {
      lastErr = `${url} → ${e instanceof Error ? e.message : String(e)}`;
      console.warn(`[osm-campsites] mirror threw: ${lastErr}`);
    }
  }

  if (!upstream) {
    console.error(`[osm-campsites] all Overpass mirrors failed. last: ${lastErr}`);
    return json({ error: `Overpass upstream unavailable` }, 502);
  }

  // deno-lint-ignore no-explicit-any
  const data: any = await upstream.json();
  // deno-lint-ignore no-explicit-any
  const elements: any[] = data.elements ?? [];

  const dtos = elements
    .filter(usable)
    .map((el) => mapToDTO(el, lat, lng))
    // De-duplicate exact-name + sub-mile collisions (OSM sometimes has both
    // a node and a way for the same place).
    .filter(uniqueByNameAndCoord())
    // Closer first.
    .sort((a, b) => extractDistance(a) - extractDistance(b))
    .slice(0, limit);

  console.log(`[osm-campsites] lat=${lat.toFixed(3)} lng=${lng.toFixed(3)} r=${radiusMiles}mi → ${dtos.length} sites (raw ${elements.length})`);

  return json(dtos);
});

// deno-lint-ignore no-explicit-any
function usable(el: any): boolean {
  // Need a name — anonymous sites are useless as grounding context.
  const name = el?.tags?.name;
  if (typeof name !== "string" || !name.trim()) return false;

  // Skip explicitly private sites.
  if (el?.tags?.access === "private") return false;
  if (el?.tags?.access === "no") return false;

  // Need usable coords — for ways/relations, Overpass returns center.
  const lat = Number(el.lat ?? el.center?.lat);
  const lng = Number(el.lon ?? el.center?.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat === 0 && lng === 0) return false;
  return true;
}

// deno-lint-ignore no-explicit-any
function mapToDTO(el: any, queryLat: number, queryLng: number) {
  const lat = Number(el.lat ?? el.center?.lat);
  const lng = Number(el.lon ?? el.center?.lon);
  const tags = el.tags ?? {};
  const distMi = haversineMiles(queryLat, queryLng, lat, lng);

  // Derive a tag list from POI type + common amenity bools.
  const derivedTags: string[] = ["osm"];
  switch (tags.tourism) {
    case "camp_site":      derivedTags.push("tent"); break;
    case "caravan_site":   derivedTags.push("rv"); break;
    case "wilderness_hut": derivedTags.push("primitive", "backcountry", "hut"); break;
    case "alpine_hut":     derivedTags.push("alpine", "hut"); break;
  }
  if (tags.amenity === "shelter") {
    derivedTags.push("shelter");
    if (typeof tags.shelter_type === "string") {
      derivedTags.push(tags.shelter_type.replace(/_/g, "-"));
    }
  }
  if (tags.tents === "yes") derivedTags.push("tent");
  if (tags.caravans === "yes") derivedTags.push("rv");
  if (tags.access === "permissive") derivedTags.push("walk-up");
  if (tags.fee === "no") derivedTags.push("free");
  if (tags.power_supply === "yes") derivedTags.push("electric");
  if (tags.shower === "yes") derivedTags.push("shower");
  if (tags.toilets === "yes") derivedTags.push("toilet");
  if (tags.drinking_water === "yes") derivedTags.push("water");
  if (tags.dog === "yes") derivedTags.push("dog-friendly");

  let fee = "Unknown";
  if (tags.fee === "no") fee = "Free";
  else if (typeof tags.fee === "string" && /^\d/.test(tags.fee)) fee = tags.fee;

  const description: string | null =
    (tags.description ?? "").trim() ||
    (tags.note ?? "").trim() ||
    null;

  // Source URL: prefer the operator's website; fall back to OSM-tagged
  // contact info, then a Wikipedia page if the site has one. As a last
  // resort, link to the OSM element page itself so the user can see the
  // raw tags + edit history.
  const website = (tags.website ?? "").trim();
  const contactWebsite = (tags["contact:website"] ?? "").trim();
  const wikipedia = (tags.wikipedia ?? "").trim();  // e.g. "en:Sand Flats Recreation Area"
  let url: string | null = null;
  if (website) {
    url = website;
  } else if (contactWebsite) {
    url = contactWebsite;
  } else if (wikipedia.includes(":")) {
    const [lang, page] = wikipedia.split(":");
    if (lang && page) {
      url = `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(page.replace(/ /g, "_"))}`;
    }
  } else if (el.type && el.id != null) {
    url = `https://www.openstreetmap.org/${el.type}/${el.id}`;
  }

  // OSM element id ("node/1234", "way/5678") — stable identifier we can
  // use later if we want to link straight to the raw OSM page.
  const externalId = el.type && el.id != null ? `${el.type}/${el.id}` : null;

  return {
    name: String(tags.name).trim(),
    source: "other",
    sourceLabel: "OpenStreetMap",
    url,
    distance: `~${Math.round(distMi)} miles`,
    fee,
    reservable: tags.reservation === "required",
    description,
    tags: dedupe(derivedTags),
    directions: null,
    coordinates: { lat, lng },
    city: tags["addr:city"] ?? null,
    state: tags["addr:state"] ?? null,
    seasonal: tags.seasonal === "summer" ? "summer-only" : "unknown",
    amenities: [],
    _fromDatabase: true,
    _externalId: externalId,
  };
}

function dedupe(arr: string[]): string[] {
  return [...new Set(arr)];
}

function uniqueByNameAndCoord(): (dto: ReturnType<typeof mapToDTO>) => boolean {
  const seen = new Set<string>();
  return (dto) => {
    const k = `${dto.name.toLowerCase()}|${dto.coordinates.lat.toFixed(2)}|${dto.coordinates.lng.toFixed(2)}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  };
}

function extractDistance(dto: ReturnType<typeof mapToDTO>): number {
  const m = String(dto.distance ?? "").match(/-?\d+(\.\d+)?/);
  return m ? Number(m[0]) : Infinity;
}

function haversineMiles(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 3958.8;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
