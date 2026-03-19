export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  const GKEY = process.env.GOOGLE_PLACES_KEY;
  if (!GKEY) return res.status(500).json({ error: 'Missing API key' });

  const { type, input, ref } = req.query;

  if (type === 'search') {
    try {
      // Single call — Find Place with photos field directly, no Details needed
      const url = `https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=${encodeURIComponent(input)}&inputtype=textquery&fields=photos&key=${GKEY}`;
      const r = await fetch(url);
      const d = await r.json();
      const photos = (d.candidates && d.candidates[0] && d.candidates[0].photos)
        ? d.candidates[0].photos.slice(0, 5)
        : [];
      return res.status(200).json({ candidates: [{ photos }] });
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  if (type === 'photo') {
    try {
      const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${ref}&key=${GKEY}`;
      const r = await fetch(photoUrl, { redirect: 'follow' });
      const contentType = r.headers.get('content-type') || 'image/jpeg';
      const arrayBuf = await r.arrayBuffer();
      const uint8 = new Uint8Array(arrayBuf);
      let binary = '';
      for (let i = 0; i < uint8.length; i++) binary += String.fromCharCode(uint8[i]);
      const base64 = btoa(binary);
      res.setHeader('Content-Type', contentType);
      res.setHeader('Cache-Control', 'public, max-age=86400');
      return res.status(200).send(Buffer.from(base64, 'base64'));
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  return res.status(400).json({ error: 'Missing type param' });
}
