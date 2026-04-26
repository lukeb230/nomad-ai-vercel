// Import campsites from USFS (US Forest Service) and BLM open data
// POST /api/import-usfs with header x-admin-key
// Sources:
//   - USFS: ArcGIS REST service for developed recreation sites
//   - BLM: ArcGIS REST service for recreation sites
// Requires env: SUPABASE_URL, SUPABASE_SERVICE_KEY

const SOURCES = [
  {
    name: 'usfs',
    label: 'US Forest Service',
    // USFS Recreation Sites - developed campgrounds
    url: 'https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RecreationSites_01/MapServer/0/query',
    params: {
      where: "RECAREANAME IS NOT NULL AND RECAREATYPE = 'Campground'",
      outFields: 'RECAREANAME,RECAREADESCRIPTION,LATITUDE,LONGITUDE,RECAREAURL,ADMINORGNAME,OPEN_STATUS',
      f: 'json',
      returnGeometry: 'false',
      resultRecordCount: '1000'
    },
    mapRow: (f) => ({
      name: f.attributes.RECAREANAME,
      source: 'usfs',
      source_id: 'usfs_' + (f.attributes.OBJECTID || f.attributes.RECAREANAME),
      url: f.attributes.RECAREAURL || '',
      fee: 'Varies',
      reservable: false,
      description: cleanDesc(f.attributes.RECAREADESCRIPTION),
      tags: ['national-forest', 'campground'],
      lat: f.attributes.LATITUDE,
      lng: f.attributes.LONGITUDE,
      city: '',
      state: extractState(f.attributes.ADMINORGNAME),
      amenities: [],
      seasonal: f.attributes.OPEN_STATUS === 'Open' ? 'year-round' : 'unknown',
      last_updated: new Date().toISOString()
    })
  },
  {
    name: 'blm',
    label: 'Bureau of Land Management',
    // BLM Recreation Sites
    url: 'https://gis.blm.gov/arcgis/rest/services/rec/BLM_Natl_Recreation_Sites/MapServer/0/query',
    params: {
      where: "REC_ACTIVITY LIKE '%Camp%'",
      outFields: 'SITE_NAME,SITE_DESC,LATITUDE,LONGITUDE,WEB_LINK,ADMIN_STATE,FEE_YN',
      f: 'json',
      returnGeometry: 'false',
      resultRecordCount: '1000'
    },
    mapRow: (f) => ({
      name: f.attributes.SITE_NAME,
      source: 'blm',
      source_id: 'blm_' + (f.attributes.OBJECTID || f.attributes.SITE_NAME),
      url: f.attributes.WEB_LINK || '',
      fee: f.attributes.FEE_YN === 'Y' ? 'Paid' : 'Free',
      reservable: false,
      description: cleanDesc(f.attributes.SITE_DESC),
      tags: buildBlmTags(f.attributes),
      lat: f.attributes.LATITUDE,
      lng: f.attributes.LONGITUDE,
      city: '',
      state: f.attributes.ADMIN_STATE || '',
      amenities: [],
      seasonal: 'unknown',
      last_updated: new Date().toISOString()
    })
  }
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

  const sourceIdx = parseInt(req.query.source) || 0;
  const offset = parseInt(req.query.offset) || 0;

  if (sourceIdx >= SOURCES.length) {
    return res.status(200).json({ success: true, message: 'All sources imported' });
  }

  const src = SOURCES[sourceIdx];

  try {
    // Build query URL with pagination
    const params = new URLSearchParams({ ...src.params, resultOffset: String(offset) });
    const fetchUrl = `${src.url}?${params.toString()}`;

    const r = await fetch(fetchUrl);
    if (!r.ok) {
      return res.status(r.status).json({ error: `${src.label} API error`, source: sourceIdx });
    }

    const data = await r.json();

    if (data.error) {
      return res.status(500).json({ error: data.error.message || 'ArcGIS query error', source: src.name });
    }

    const features = data.features || [];

    // Map and filter
    const rows = features
      .map(src.mapRow)
      .filter(r => r.name && r.lat && r.lng && r.lat > 24 && r.lat < 72 && r.lng > -170 && r.lng < -50);

    // Upsert to Supabase
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
        console.error(`${src.name} upsert error:`, await upsertRes.text());
      }
    }

    const hasMore = features.length >= parseInt(src.params.resultRecordCount);
    const nextOffset = hasMore ? offset + features.length : null;

    return res.status(200).json({
      success: true,
      source: src.name,
      sourceIndex: sourceIdx,
      found: features.length,
      valid: rows.length,
      inserted,
      nextOffset,
      nextSource: !hasMore && sourceIdx + 1 < SOURCES.length ? sourceIdx + 1 : null,
      message: hasMore
        ? `${src.label}: page done. Call again with ?source=${sourceIdx}&offset=${offset + features.length}`
        : sourceIdx + 1 < SOURCES.length
          ? `${src.label} complete. Call with ?source=${sourceIdx + 1} for ${SOURCES[sourceIdx + 1].label}`
          : 'All sources complete!'
    });
  } catch (e) {
    return res.status(500).json({ error: e.message, source: src.name });
  }
}

function cleanDesc(desc) {
  if (!desc) return '';
  return desc.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim().substring(0, 200);
}

function extractState(adminOrg) {
  if (!adminOrg) return '';
  // USFS admin org names often contain state abbreviations
  const match = adminOrg.match(/\b([A-Z]{2})\b/);
  return match ? match[1] : '';
}

function buildBlmTags(attrs) {
  const tags = ['blm', 'public-land'];
  if (attrs.FEE_YN === 'N') tags.push('free', 'dispersed');
  const desc = (attrs.SITE_DESC || '').toLowerCase();
  if (desc.includes('primitive') || desc.includes('dispersed')) tags.push('dispersed');
  if (desc.includes('hik')) tags.push('hiking');
  if (desc.includes('fish')) tags.push('fishing');
  if (desc.includes('ohv') || desc.includes('off-road')) tags.push('ohv');
  return tags;
}
