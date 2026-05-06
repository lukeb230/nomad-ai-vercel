// supabase/functions/search-campsites/index.ts
//
// Live proxy to RIDB (https://ridb.recreation.gov/api/v1/facilities) for
// federal campground search by lat/lng radius. The RIDB_KEY lives in Supabase
// secrets — iOS never sees it.
//
// Returns an array of CampsiteDTO-shaped objects matching what
// CampsiteParser/Campsite.swift already decode. Fields with `_fromDatabase: true`
// tell the iOS app these coordinates are authoritative — skip the
// MKLocalSearch-based CoordinateValidator pass.

const RIDB_KEY = Deno.env.get("RIDB_KEY");

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

// Whitelisted facility types that represent camping. Day-use, picnic, marina,
// trailhead, etc. are dropped. Empty FacilityTypeDescription is kept because
// RIDB sometimes leaves it blank but the activity=CAMPING filter has matched.
const CAMPING_TYPES = new Set([
  "Campground",
  "Group Campground",
  "RV Site",
  "Cabin",
  "Cabin/Lodge",
  "Lodging",
  "Tent",
  "Yurt",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!RIDB_KEY) {
    return json({ error: "RIDB_KEY not configured" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const lat = Number(body.lat);
  const lng = Number(body.lng);
  const radius = Math.min(Math.max(Number(body.radius ?? 50), 1), 500);
  const limit = Math.min(Math.max(Number(body.limit ?? 20), 1), 50);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return json({ error: "lat and lng required" }, 400);
  }

  // Overfetch then filter — RIDB's facility-type filter is loose, so we may
  // drop a chunk before reaching `limit`.
  const upstreamUrl = new URL("https://ridb.recreation.gov/api/v1/facilities");
  upstreamUrl.searchParams.set("latitude", String(lat));
  upstreamUrl.searchParams.set("longitude", String(lng));
  upstreamUrl.searchParams.set("radius", String(radius));
  upstreamUrl.searchParams.set("activity", "CAMPING");
  upstreamUrl.searchParams.set("limit", String(Math.max(limit * 2, 50)));

  const upstream = await fetch(upstreamUrl.toString(), {
    headers: { apikey: RIDB_KEY, accept: "application/json" },
  });

  if (!upstream.ok) {
    const text = await upstream.text();
    console.error(`[search-campsites] RIDB ${upstream.status}: ${text.slice(0, 200)}`);
    return json({ error: `RIDB upstream ${upstream.status}` }, 502);
  }

  // deno-lint-ignore no-explicit-any
  const data: any = await upstream.json();
  // deno-lint-ignore no-explicit-any
  const facilities: any[] = (data.RECDATA ?? [])
    // deno-lint-ignore no-explicit-any
    .filter((f: any) => isCampingFacility(f) && hasUsableCoords(f));

  const dtos = facilities.slice(0, limit).map((f) => mapToDTO(f, lat, lng));

  console.log(`[search-campsites] lat=${lat.toFixed(3)} lng=${lng.toFixed(3)} r=${radius} → ${dtos.length} facilities`);

  return json(dtos);
});

// deno-lint-ignore no-explicit-any
function isCampingFacility(f: any): boolean {
  if (!f.FacilityTypeDescription) return true;
  return CAMPING_TYPES.has(f.FacilityTypeDescription);
}

// deno-lint-ignore no-explicit-any
function hasUsableCoords(f: any): boolean {
  const lat = Number(f.FacilityLatitude);
  const lng = Number(f.FacilityLongitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat === 0 && lng === 0) return false;
  return true;
}

// deno-lint-ignore no-explicit-any
function mapToDTO(f: any, queryLat: number, queryLng: number) {
  const fLat = Number(f.FacilityLatitude);
  const fLng = Number(f.FacilityLongitude);
  const distMi = haversineMiles(queryLat, queryLng, fLat, fLng);
  const desc = (f.FacilityDescription ?? "")
    .replace(/<[^>]*>/g, "")  // strip HTML
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 280);
  // RIDB FacilityID is the canonical key for recreation.gov URLs:
  //   https://www.recreation.gov/camping/campgrounds/<FacilityID>
  // Pass it through so iOS can synthesize the Source link when
  // FacilityReservationURL is missing (very common for non-reservable sites).
  const facilityId = f.FacilityID != null ? String(f.FacilityID) : null;
  return {
    name: (f.FacilityName ?? "").trim(),
    source: "recreation.gov",
    sourceLabel: "Recreation.gov",
    url: (f.FacilityReservationURL ?? "").trim() || null,
    distance: `~${Math.round(distMi)} miles`,
    fee: "Unknown",
    reservable: !!f.Reservable,
    description: desc || null,
    tags: ["federal"],
    directions: null,
    coordinates: { lat: fLat, lng: fLng },
    city: null,
    state: null,
    seasonal: "unknown",
    amenities: [],
    _fromDatabase: true,
    _externalId: facilityId,
  };
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
