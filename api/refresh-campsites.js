// Weekly cron job to refresh campsite data
// Triggered by Vercel Cron: GET /api/refresh-campsites
// Updates Recreation.gov data and a few OSM regions per run

export default async function handler(req, res) {
  // Vercel cron sends GET requests
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  // Verify cron secret (Vercel sets CRON_SECRET automatically)
  const authHeader = req.headers.authorization;
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const RECGOV_KEY = process.env.RECGOV_API_KEY;
  const SUPA_URL = process.env.SUPABASE_URL;
  const SUPA_KEY = process.env.SUPABASE_SERVICE_KEY;

  if (!SUPA_URL || !SUPA_KEY) return res.status(500).json({ error: 'Missing Supabase config' });

  const results = { recgov: null, osm: null };

  // 1. Refresh Recreation.gov — fetch recent updates
  if (RECGOV_KEY) {
    try {
      // Get facilities updated in the last 7 days
      const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
      let totalUpdated = 0;
      let offset = 0;
      let hasMore = true;

      while (hasMore && offset < 500) {
        const url = `https://ridb.recreation.gov/api/v1/facilities?limit=50&offset=${offset}&activity=CAMPING&lastUpdatedDate=${weekAgo}`;
        const r = await fetch(url, {
          headers: { 'apikey': RECGOV_KEY, 'accept': 'application/json' }
        });

        if (!r.ok) break;
        const data = await r.json();
        const facilities = data.RECDATA || [];

        if (facilities.length === 0) { hasMore = false; break; }

        const rows = facilities
          .filter(f => f.FacilityLatitude && f.FacilityLongitude)
          .map(f => ({
            name: (f.FacilityName || '').replace(/<[^>]*>/g, '').trim(),
            source: 'recreation_gov',
            source_id: String(f.FacilityID),
            url: `https://www.recreation.gov/camping/campgrounds/${f.FacilityID}`,
            fee: f.Reservable ? 'Varies' : 'Free',
            reservable: f.Reservable === true,
            description: (f.FacilityDescription || '').replace(/<[^>]*>/g, '').substring(0, 200),
            tags: [],
            lat: f.FacilityLatitude,
            lng: f.FacilityLongitude,
            city: f.FACILITYADDRESS?.[0]?.City || '',
            state: f.FACILITYADDRESS?.[0]?.AddressStateCode || '',
            amenities: [],
            seasonal: 'unknown',
            last_updated: new Date().toISOString()
          }));

        if (rows.length > 0) {
          await fetch(`${SUPA_URL}/rest/v1/campsites`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPA_KEY,
              'Authorization': `Bearer ${SUPA_KEY}`,
              'Prefer': 'resolution=merge-duplicates'
            },
            body: JSON.stringify(rows)
          });
          totalUpdated += rows.length;
        }

        offset += 50;
        if (facilities.length < 50) hasMore = false;
        await new Promise(r => setTimeout(r, 200));
      }

      results.recgov = { updated: totalUpdated };
    } catch (e) {
      results.recgov = { error: e.message };
    }
  }

  // 2. Refresh a rotating set of OSM regions (3 per week)
  try {
    // Use week number to rotate through 27 regions
    const weekNum = Math.floor(Date.now() / (7 * 24 * 60 * 60 * 1000));
    const regionStart = (weekNum * 3) % 27;
    const regions = [regionStart, (regionStart + 1) % 27, (regionStart + 2) % 27];

    const STATE_BOXES = [
      { name: 'CA', s: 32.5, n: 42, w: -124.5, e: -114 },
      { name: 'OR', s: 42, n: 46.3, w: -124.6, e: -116.5 },
      { name: 'WA', s: 45.5, n: 49, w: -124.8, e: -116.9 },
      { name: 'NV', s: 35, n: 42, w: -120, e: -114 },
      { name: 'AZ', s: 31.3, n: 37, w: -114.8, e: -109 },
      { name: 'UT', s: 37, n: 42, w: -114.1, e: -109 },
      { name: 'CO', s: 37, n: 41, w: -109.1, e: -102 },
      { name: 'NM', s: 31.3, n: 37, w: -109.1, e: -103 },
      { name: 'ID', s: 42, n: 49, w: -117.2, e: -111 },
      { name: 'MT', s: 44.4, n: 49, w: -116.1, e: -104 },
      { name: 'WY', s: 41, n: 45, w: -111.1, e: -104.1 },
      { name: 'TX', s: 25.8, n: 36.5, w: -106.7, e: -93.5 },
      { name: 'OK_KS', s: 33.6, n: 40, w: -103, e: -94.4 },
      { name: 'NE_SD_ND', s: 40, n: 49, w: -104.1, e: -96.4 },
      { name: 'MN_WI', s: 42.5, n: 49.4, w: -97.3, e: -86.8 },
      { name: 'MI', s: 41.7, n: 48.3, w: -90.4, e: -82.1 },
      { name: 'IA_MO_IL', s: 36, n: 43.5, w: -96.7, e: -87.5 },
      { name: 'IN_OH', s: 38.4, n: 42, w: -87.5, e: -80.5 },
      { name: 'FL_GA_SC', s: 24.5, n: 35.2, w: -87.6, e: -79.9 },
      { name: 'AL_MS_LA_AR', s: 29, n: 36.5, w: -94.1, e: -84.9 },
      { name: 'TN_KY_WV_VA', s: 35, n: 40.6, w: -90, e: -75.2 },
      { name: 'NC', s: 33.8, n: 36.6, w: -84.3, e: -75.5 },
      { name: 'PA_NJ_DE_MD', s: 38.5, n: 42.3, w: -80.5, e: -73.9 },
      { name: 'NY_CT_RI_MA', s: 40.5, n: 45.1, w: -79.8, e: -69.9 },
      { name: 'VT_NH_ME', s: 42.7, n: 47.5, w: -73.5, e: -66.9 },
      { name: 'AK', s: 51, n: 71.4, w: -170, e: -130 },
      { name: 'HI', s: 18.9, n: 22.3, w: -160.3, e: -154.8 },
    ];

    let osmTotal = 0;
    for (const idx of regions) {
      const box = STATE_BOXES[idx];
      if (!box) continue;

      const query = `[out:json][timeout:60];(node["tourism"="camp_site"](${box.s},${box.w},${box.n},${box.e});way["tourism"="camp_site"](${box.s},${box.w},${box.n},${box.e}););out center body;`;
      const overpassRes = await fetch('https://overpass-api.de/api/interpreter', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'data=' + encodeURIComponent(query)
      });

      if (!overpassRes.ok) continue;
      const data = await overpassRes.json();

      const rows = (data.elements || [])
        .map(el => {
          const lat = el.lat || el.center?.lat;
          const lon = el.lon || el.center?.lon;
          const tags = el.tags || {};
          if (!lat || !lon || !tags.name) return null;
          return {
            name: tags.name.trim(),
            source: 'osm',
            source_id: String(el.id),
            url: tags.website || '',
            fee: tags.fee === 'no' ? 'Free' : tags.fee === 'yes' ? 'Paid' : 'Unknown',
            reservable: tags.reservation === 'required',
            description: tags.description || '',
            tags: [],
            lat, lng: lon,
            city: tags['addr:city'] || '',
            state: tags['addr:state'] || box.name.split('_')[0],
            amenities: [],
            seasonal: 'unknown',
            last_updated: new Date().toISOString()
          };
        })
        .filter(Boolean);

      if (rows.length > 0) {
        for (let i = 0; i < rows.length; i += 500) {
          await fetch(`${SUPA_URL}/rest/v1/campsites`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPA_KEY,
              'Authorization': `Bearer ${SUPA_KEY}`,
              'Prefer': 'resolution=merge-duplicates'
            },
            body: JSON.stringify(rows.slice(i, i + 500))
          });
        }
        osmTotal += rows.length;
      }

      await new Promise(r => setTimeout(r, 2000)); // Overpass rate limit
    }

    results.osm = { regions: regions.map(i => STATE_BOXES[i]?.name), updated: osmTotal };
  } catch (e) {
    results.osm = { error: e.message };
  }

  return res.status(200).json({ success: true, results, timestamp: new Date().toISOString() });
}
