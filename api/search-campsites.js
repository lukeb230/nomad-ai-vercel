// Database-first campsite search
// GET /api/search-campsites?lat=38.5&lng=-109.5&radius=50&tags=dispersed&limit=20

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const SUPA_URL = process.env.SUPABASE_URL;
  const SUPA_KEY = process.env.SUPABASE_SERVICE_KEY;
  if (!SUPA_URL || !SUPA_KEY) return res.status(500).json({ error: 'Missing Supabase config' });

  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const radius = parseFloat(req.query.radius) || 50;
  const limit = Math.min(parseInt(req.query.limit) || 20, 50);
  const tags = req.query.tags ? req.query.tags.split(',') : [];
  const source = req.query.source || '';

  if (isNaN(lat) || isNaN(lng)) {
    return res.status(400).json({ error: 'lat and lng are required' });
  }

  // Bounding box: 1 degree of latitude ≈ 69 miles
  const latDelta = radius / 69;
  const lngDelta = radius / (69 * Math.cos(lat * Math.PI / 180));

  // Build Supabase REST query
  let url = `${SUPA_URL}/rest/v1/campsites?select=*`;
  url += `&lat=gte.${(lat - latDelta).toFixed(6)}&lat=lte.${(lat + latDelta).toFixed(6)}`;
  url += `&lng=gte.${(lng - lngDelta).toFixed(6)}&lng=lte.${(lng + lngDelta).toFixed(6)}`;

  if (source) {
    url += `&source=eq.${encodeURIComponent(source)}`;
  }

  url += `&limit=${limit * 2}`; // Fetch extra, filter by exact distance

  try {
    const r = await fetch(url, {
      headers: {
        'apikey': SUPA_KEY,
        'Authorization': `Bearer ${SUPA_KEY}`
      }
    });

    if (!r.ok) {
      const errText = await r.text();
      return res.status(r.status).json({ error: errText });
    }

    let rows = await r.json();

    // Haversine filter for exact radius
    rows = rows.map(row => {
      const d = haversine(lat, lng, row.lat, row.lng);
      return { ...row, _dist: d };
    }).filter(r => r._dist <= radius);

    // Tag filter
    if (tags.length) {
      rows = rows.filter(row => {
        const rowTags = row.tags || [];
        return tags.some(t => rowTags.includes(t));
      });
    }

    // Sort by distance
    rows.sort((a, b) => a._dist - b._dist);
    rows = rows.slice(0, limit);

    // Map to app format
    const sites = rows.map(row => ({
      name: row.name,
      source: mapSource(row.source),
      sourceLabel: mapSourceLabel(row.source),
      url: row.url || '',
      distance: '~' + Math.round(row._dist) + ' miles',
      fee: row.fee || 'Unknown',
      reservable: row.reservable || false,
      description: row.description || '',
      tags: row.tags || [],
      directions: '',
      coordinates: { lat: row.lat, lng: row.lng },
      city: row.city || '',
      state: row.state || '',
      seasonal: row.seasonal || 'unknown',
      amenities: row.amenities || [],
      _fromDatabase: true
    }));

    return res.status(200).json({ sites, total: sites.length, radius });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}

function haversine(lat1, lng1, lat2, lng2) {
  const R = 3958.8;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function mapSource(src) {
  const m = { recreation_gov: 'recreation.gov', osm: 'other', usfs: 'blm', blm: 'blm' };
  return m[src] || 'other';
}

function mapSourceLabel(src) {
  const m = { recreation_gov: 'Recreation.gov', osm: 'OpenStreetMap', usfs: 'US Forest Service', blm: 'BLM' };
  return m[src] || src;
}
