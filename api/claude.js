export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
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

  // Transform string `system` field into the Anthropic array form with
  // cache_control so the system prompt is cached server-side. The iOS client
  // sends `system: "..."`, but Anthropic's prompt-caching API requires the
  // structured-block form. Single-place change; iOS doesn't need to know.
  //
  // First call writes the cache (1.25× input cost for that one call); cached
  // hits within ~5 min run at 0.1× input cost. Net savings ~30–50% on input
  // tokens at our usage. Output is byte-identical to the uncached path.
  //
  // If the system prompt is below the model's minimum cacheable size
  // (~1024 tokens for Sonnet/Opus, ~2048 for Haiku), Anthropic silently
  // ignores cache_control — no error, no caching, no harm.
  const body = { ...req.body };
  if (typeof body.system === 'string' && body.system.length > 0) {
    body.system = [
      {
        type: 'text',
        text: body.system,
        cache_control: { type: 'ephemeral' }
      }
    ];
  }

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify(body)
    });
    const data = await response.json();

    // Lightweight cache visibility in Vercel runtime logs.
    if (data?.usage) {
      const u = data.usage;
      console.log(
        `[claude] in=${u.input_tokens ?? 0} out=${u.output_tokens ?? 0} ` +
        `cache_read=${u.cache_read_input_tokens ?? 0} ` +
        `cache_write=${u.cache_creation_input_tokens ?? 0}`
      );
    }

    return res.status(response.status).json(data);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
