export default async function handler(req, res) {
  const allowedOrigin = 'https://nomadai.us';

res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const ANTHROPIC_KEY = process.env.ANTHROPIC_KEY;
  if (!ANTHROPIC_KEY) return res.status(500).json({ error: 'Missing API key' });

  // Rate limiting — 10 requests per IP per hour
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || 'unknown';
  const now = Date.now();
  if (!global.rateLimitStore) global.rateLimitStore = {};
  const store = global.rateLimitStore;
  if (!store[ip]) store[ip] = [];
  store[ip] = store[ip].filter(t => now - t < 60 * 60 * 1000);
  if (store[ip].length >= 10) {
    return res.status(429).json({ error: { type: 'rate_limit', message: 'You have reached the limit of 10 searches per hour. Please try again later.' } });
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
