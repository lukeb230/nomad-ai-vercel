// One-time setup: creates the campsites table in Supabase
// Call POST /api/setup-campsites with header x-admin-key matching ADMIN_SECRET env var

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

  const sql = `
    CREATE TABLE IF NOT EXISTS campsites (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      name text NOT NULL,
      source text NOT NULL,
      source_id text,
      url text,
      fee text,
      reservable boolean DEFAULT false,
      description text,
      tags jsonb DEFAULT '[]'::jsonb,
      lat double precision,
      lng double precision,
      city text,
      state text,
      amenities jsonb DEFAULT '[]'::jsonb,
      seasonal text DEFAULT 'unknown',
      last_updated timestamptz DEFAULT now(),
      UNIQUE(source, source_id)
    );

    CREATE INDEX IF NOT EXISTS idx_campsites_lat ON campsites(lat);
    CREATE INDEX IF NOT EXISTS idx_campsites_lng ON campsites(lng);
    CREATE INDEX IF NOT EXISTS idx_campsites_state ON campsites(state);
    CREATE INDEX IF NOT EXISTS idx_campsites_source ON campsites(source);
    CREATE INDEX IF NOT EXISTS idx_campsites_lat_lng ON campsites(lat, lng);
  `;

  try {
    const r = await fetch(`${SUPA_URL}/rest/v1/rpc/exec_sql`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPA_KEY,
        'Authorization': `Bearer ${SUPA_KEY}`
      },
      body: JSON.stringify({ query: sql })
    });

    // If the RPC doesn't exist, fall back to raw SQL via the management API
    if (!r.ok) {
      // Try using Supabase SQL editor endpoint
      const r2 = await fetch(`${SUPA_URL}/rest/v1/`, {
        method: 'GET',
        headers: { 'apikey': SUPA_KEY, 'Authorization': `Bearer ${SUPA_KEY}` }
      });

      return res.status(200).json({
        message: 'RPC not available. Please run this SQL manually in Supabase SQL Editor:',
        sql: sql.trim()
      });
    }

    return res.status(200).json({ success: true, message: 'Campsites table created' });
  } catch (e) {
    return res.status(500).json({ error: e.message, sql: sql.trim() });
  }
}
