export default async function handler(req, res) {
  const origin = req.headers.origin;
  const allowedOrigins = [
    'https://nomadai.us',
    'http://localhost:3000',
    'http://127.0.0.1:3000'
  ];

  const isAllowedVercelPreview =
    typeof origin === 'string' &&
    /^https:\/\/[a-z0-9-]+-.*\.vercel\.app$/.test(origin);

  const allowOrigin =
    allowedOrigins.includes(origin) || isAllowedVercelPreview ? origin : null;

  res.setHeader('Vary', 'Origin');

  if (allowOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    if (!allowOrigin) return res.status(403).end();
    return res.status(200).end();
  }

  if (!allowOrigin) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const GKEY = process.env.GOOGLE_PLACES_KEY;
  if (!GKEY) return res.status(500).json({ error: 'Missing API key' });

  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || 'unknown';
  const now = Date.now();

  if (!global.placesRateLimitStore) global.placesRateLimitStore = {};
  const store = global.placesRateLimitStore;

  if (!store[ip]) store[ip] = [];
  store[ip] = store[ip].filter((t) => now - t < 60 * 60 * 1000);

  if (store[ip].length >= 60) {
    return res.status(429).json({ error: 'Rate limit exceeded. Try again later.' });
  }

  store[ip].push(now);

  const { type, input, ref } = req.query;

  if (!type || !['search', 'photo'].includes(type)) {
    return res.status(400).json({ error: 'Invalid type param' });
  }

  if (type === 'search') {
    if (!input || typeof input !== 'string' || input.length > 200) {
      return res.status(400).json({ error: 'Invalid input param' });
    }

    try {
      const url =
        `https://maps.googleapis.com/maps/api/place/findplacefromtext/json` +
        `?input=${encodeURIComponent(input)}` +
        `&inputtype=textquery&fields=photos&key=${GKEY}`;

      const r = await fetch(url);
      const d = await r.json();

      const photos =
        d.candidates && d.candidates[0] && d.candidates[0].photos
          ? d.candidates[0].photos.slice(0, 5)
          : [];

      return res.status(200).json({ candidates: [{ photos }] });
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  if (type === 'photo') {
    if (!ref || typeof ref !== 'string' || ref.length > 500) {
      return res.status(400).json({ error: 'Invalid ref param' });
    }

    try {
      const photoUrl =
        `https://maps.googleapis.com/maps/api/place/photo` +
        `?maxwidth=800&photoreference=${encodeURIComponent(ref)}&key=${GKEY}`;

      res.setHeader('Cache-Control', 'public, max-age=86400');
      return res.redirect(302, photoUrl);
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  return res.status(400).json({ error: 'Missing type param' });
}
