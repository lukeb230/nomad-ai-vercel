// Import campsites from OpenStreetMap via Overpass API
// POST /api/import-osm with header x-admin-key
// Queries tourism=camp_site nodes/ways in North America by state-level bounding boxes
// No API key needed — free and open
// Requires env: SUPABASE_URL, SUPABASE_SERVICE_KEY

const STATE_BOXES = [
  // West
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
  // Southwest/Central
  { name: 'TX', s: 25.8, n: 36.5, w: -106.7, e: -93.5 },
  { name: 'OK_KS', s: 33.6, n: 40, w: -103, e: -94.4 },
  { name: 'NE_SD_ND', s: 40, n: 49, w: -104.1, e: -96.4 },
  // Midwest
  { name: 'MN_WI', s: 42.5, n: 49.4, w: -97.3, e: -86.8 },
  { name: 'MI', s: 41.7, n: 48.3, w: -90.4, e: -82.1 },
  { name: 'IA_MO_IL', s: 36, n: 43.5, w: -96.7, e: -87.5 },
  { name: 'IN_OH', s: 38.4, n: 42, w: -87.5, e: -80.5 },
  // Southeast
  { name: 'FL_GA_SC', s: 24.5, n: 35.2, w: -87.6, e: -79.9 },
  { name: 'AL_MS_LA_AR', s: 29, n: 36.5, w: -94.1, e: -84.9 },
  { name: 'TN_KY_WV_VA', s: 35, n: 40.6, w: -90, e: -75.2 },
  { name: 'NC', s: 33.8, n: 36.6, w: -84.3, e: -75.5 },
  // Northeast
  { name: 'PA_NJ_DE_MD', s: 38.5, n: 42.3, w: -80.5, e: -73.9 },
  { name: 'NY_CT_RI_MA', s: 40.5, n: 45.1, w: -79.8, e: -69.9 },
  { name: 'VT_NH_ME', s: 42.7, n: 47.5, w: -73.5, e: -66.9 },
  // Alaska & Hawaii
  { name: 'AK', s: 51, n: 71.4, w: -170, e: -130 },
  { name: 'HI', s: 18.9, n: 22.3, w: -160.3, e: -154.8 },
];

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const adminKey = req.headers['x-admin-key'];
  if (!adminKey || adminKey !== process.env.ADMIN_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const SUPA_URL = process.env.SUPABASE_URL;
  const SUPA_KEY = process.env.SUPABASE_SERVICE_KEY;
  if (!SUPA_URL || !SUPA_KEY) return res.status(500).json({ error: 'Missing Supabase config' });

  // Process one region at a time (pass ?region=0 to start, increment)
  const regionIdx = parseInt(req.query.region) || 0;

  if (regionIdx >= STATE_BOXES.length) {
    return res.status(200).json({ success: true, message: 'All regions imported', totalRegions: STATE_BOXES.length });
  }

  const box = STATE_BOXES[regionIdx];

  try {
    // Query Overpass for camp_site nodes and ways in this bounding box
    const query = `[out:json][timeout:60];
(
  node["tourism"="camp_site"](${box.s},${box.w},${box.n},${box.e});
  way["tourism"="camp_site"](${box.s},${box.w},${box.n},${box.e});
);
out center body;`;

    const overpassRes = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'data=' + encodeURIComponent(query)
    });

    if (!overpassRes.ok) {
      const errText = await overpassRes.text();
      return res.status(overpassRes.status).json({
        error: `Overpass API error for region ${box.name}`,
        details: errText.substring(0, 500),
        region: regionIdx
      });
    }

    const data = await overpassRes.json();
    const elements = data.elements || [];

    // Map OSM elements to our schema
    const rows = elements
      .map(el => {
        const lat = el.lat || el.center?.lat;
        const lng = el.lon || el.center?.lon;
        if (!lat || !lng) return null;

        const tags = el.tags || {};
        const name = tags.name || tags['name:en'] || '';
        if (!name) return null; // Skip unnamed sites

        return {
          name: name.trim(),
          source: 'osm',
          source_id: String(el.id),
          url: tags.website || tags['contact:website'] || '',
          fee: parseFee(tags),
          reservable: tags.reservation === 'required' || tags.reservation === 'recommended',
          description: tags.description || tags.note || '',
          tags: buildOsmTags(tags),
          lat,
          lng,
          city: tags['addr:city'] || '',
          state: tags['addr:state'] || box.name.split('_')[0],
          amenities: buildAmenities(tags),
          seasonal: parseSeasonal(tags),
          last_updated: new Date().toISOString()
        };
      })
      .filter(Boolean);

    // Batch upsert to Supabase (max 500 at a time)
    let inserted = 0;
    for (let i = 0; i < rows.length; i += 500) {
      const batch = rows.slice(i, i + 500);
      const upsertRes = await fetch(`${SUPA_URL}/rest/v1/campsites`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SUPA_KEY,
          'Authorization': `Bearer ${SUPA_KEY}`,
          'Prefer': 'resolution=merge-duplicates'
        },
        body: JSON.stringify(batch)
      });

      if (upsertRes.ok) {
        inserted += batch.length;
      } else {
        console.error('Supabase error:', await upsertRes.text());
      }
    }

    return res.status(200).json({
      success: true,
      region: box.name,
      regionIndex: regionIdx,
      found: elements.length,
      named: rows.length,
      inserted,
      nextRegion: regionIdx + 1 < STATE_BOXES.length ? regionIdx + 1 : null,
      message: regionIdx + 1 < STATE_BOXES.length
        ? `Region ${box.name} done. Call again with ?region=${regionIdx + 1} for next region.`
        : `All regions complete!`
    });
  } catch (e) {
    return res.status(500).json({ error: e.message, region: regionIdx, regionName: box.name });
  }
}

function parseFee(tags) {
  if (tags.fee === 'no' || tags.fee === 'free') return 'Free';
  if (tags.fee === 'yes' && tags['fee:amount']) return '$' + tags['fee:amount'] + '/night';
  if (tags.fee === 'yes') return 'Paid';
  return 'Unknown';
}

function parseSeasonal(tags) {
  const opening = tags.opening_hours || '';
  if (opening.includes('24/7') || opening === 'Mo-Su') return 'year-round';
  if (opening.includes('May') || opening.includes('Jun')) return 'summer-only';
  return 'unknown';
}

function buildOsmTags(tags) {
  const result = [];
  if (tags.backcountry === 'yes' || tags.camp_site === 'basic') result.push('dispersed');
  if (tags.camp_site === 'pitch' || tags.tents === 'yes') result.push('tent');
  if (tags.caravans === 'yes' || tags.motorcar === 'yes') result.push('rv');
  if (tags.group_only === 'yes') result.push('group');
  if (tags.fee === 'no') result.push('free');
  if (tags.drinking_water === 'yes') result.push('water');
  if (tags.shower === 'yes') result.push('showers');
  if (tags.power_supply === 'yes') result.push('electric');
  if (tags.toilets === 'yes' || tags.toilet === 'yes') result.push('toilets');
  if (tags.fire === 'yes' || tags.fireplace === 'yes' || tags.bbq === 'yes') result.push('fire-ring');
  if (tags.internet_access === 'wlan' || tags.internet_access === 'yes') result.push('wifi');
  if (tags.dog === 'yes') result.push('pets-allowed');
  return result;
}

function buildAmenities(tags) {
  const amenities = [];
  if (tags.drinking_water === 'yes') amenities.push('potable water');
  if (tags.shower === 'yes') amenities.push('showers');
  if (tags.toilets === 'yes') amenities.push('toilets');
  if (tags.toilet === 'flush') amenities.push('flush toilets');
  if (tags.toilet === 'pit_latrine') amenities.push('pit toilet');
  if (tags.power_supply === 'yes') amenities.push('electric hookups');
  if (tags.sanitary_dump_station === 'yes') amenities.push('dump station');
  if (tags.internet_access === 'wlan') amenities.push('wifi');
  if (tags.picnic_table === 'yes') amenities.push('picnic tables');
  if (tags.fire === 'yes' || tags.fireplace === 'yes') amenities.push('fire rings');
  return amenities;
}
