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

  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    if (!allowOrigin) return res.status(403).end();
    return res.status(200).end();
  }

  if (!allowOrigin) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const ANTHROPIC_KEY = process.env.ANTHROPIC_KEY;
  if (!ANTHROPIC_KEY) {
    return res.status(500).json({ error: 'Missing API key' });
  }

  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || 'unknown';
  const now = Date.now();

  if (!global.rateLimitStore) global.rateLimitStore = {};
  const store = global.rateLimitStore;

  if (!store[ip]) store[ip] = [];
  store[ip] = store[ip].filter((t) => now - t < 60 * 60 * 1000);

  if (store[ip].length >= 10) {
    return res.status(429).json({
      error: {
        type: 'rate_limit',
        message: 'You have reached the limit of 10 searches per hour. Please try again later.'
      }
    });
  }

  store[ip].push(now);

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify(req.body)
    });

    const data = await response.json();
    return res.status(response.status).json(data);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
