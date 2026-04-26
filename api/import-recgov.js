// Import campgrounds from Recreation.gov RIDB API
// POST /api/import-recgov with header x-admin-key
// Paginates through all camping facilities and upserts into Supabase
// Requires env: RECGOV_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const adminKey = req.headers['x-admin-key'];
  if (!adminKey || adminKey !== process.env.ADMIN_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const RECGOV_KEY = process.env.RECGOV_API_KEY;
  const SUPA_URL = process.env.SUPABASE_URL;
  const SUPA_KEY = process.env.SUPABASE_SERVICE_KEY;

  if (!RECGOV_KEY) return res.status(500).json({ error: 'Missing RECGOV_API_KEY' });
  if (!SUPA_URL || !SUPA_KEY) return res.status(500).json({ error: 'Missing Supabase config' });

  const offset = parseInt(req.query.offset) || 0;
  const batchSize = 50;
  let totalInserted = 0;
  let totalSkipped = 0;
  let currentOffset = offset;
  let hasMore = true;

  // Vercel function timeout is 10s on hobby, so limit batches
  const maxPages = 5;
  let pages = 0;

  try {
    while (hasMore && pages < maxPages) {
      const url = `https://ridb.recreation.gov/api/v1/facilities?limit=${batchSize}&offset=${currentOffset}&activity=CAMPING&state=`;
      const r = await fetch(url, {
        headers: { 'apikey': RECGOV_KEY, 'accept': 'application/json' }
      });

      if (!r.ok) {
        const errText = await r.text();
        return res.status(r.status).json({ error: `RIDB API error: ${errText}`, offset: currentOffset });
      }

      const data = await r.json();
      const facilities = data.RECDATA || [];

      if (facilities.length === 0) {
        hasMore = false;
        break;
      }

      // Map facilities to our schema
      const rows = facilities
        .filter(f => f.FacilityLatitude && f.FacilityLongitude)
        .map(f => ({
          name: cleanName(f.FacilityName),
          source: 'recreation_gov',
          source_id: String(f.FacilityID),
          url: `https://www.recreation.gov/camping/campgrounds/${f.FacilityID}`,
          fee: parseFee(f),
          reservable: f.Reservable === true || f.Reservable === 'true',
          description: cleanDescription(f.FacilityDescription),
          tags: buildTags(f),
          lat: f.FacilityLatitude,
          lng: f.FacilityLongitude,
          city: f.FACILITYADDRESS?.[0]?.City || '',
          state: f.FACILITYADDRESS?.[0]?.AddressStateCode || '',
          amenities: [],
          seasonal: parseSeasonal(f),
          last_updated: new Date().toISOString()
        }));

      if (rows.length > 0) {
        // Upsert batch into Supabase
        const upsertRes = await fetch(`${SUPA_URL}/rest/v1/campsites`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPA_KEY,
            'Authorization': `Bearer ${SUPA_KEY}`,
            'Prefer': 'resolution=merge-duplicates'
          },
          body: JSON.stringify(rows)
        });

        if (upsertRes.ok) {
          totalInserted += rows.length;
        } else {
          const err = await upsertRes.text();
          console.error('Supabase upsert error:', err);
          totalSkipped += rows.length;
        }
      }

      currentOffset += batchSize;
      pages++;

      if (facilities.length < batchSize) {
        hasMore = false;
      }

      // Small delay to respect rate limits
      await new Promise(r => setTimeout(r, 200));
    }

    return res.status(200).json({
      success: true,
      inserted: totalInserted,
      skipped: totalSkipped,
      nextOffset: hasMore ? currentOffset : null,
      message: hasMore
        ? `Processed ${pages} pages. Call again with ?offset=${currentOffset} to continue.`
        : `Import complete. ${totalInserted} campgrounds imported.`
    });
  } catch (e) {
    return res.status(500).json({ error: e.message, offset: currentOffset });
  }
}

function cleanName(name) {
  if (!name) return 'Unknown';
  // Remove HTML tags and excessive whitespace
  return name.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}

function cleanDescription(desc) {
  if (!desc) return '';
  // Strip HTML, limit to 200 chars
  const clean = desc.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/\s+/g, ' ').trim();
  return clean.length > 200 ? clean.substring(0, 197) + '...' : clean;
}

function parseFee(facility) {
  if (facility.FacilityUseFeeDescription) {
    const match = facility.FacilityUseFeeDescription.match(/\$[\d.]+/);
    if (match) return match[0] + '/night';
  }
  return facility.Reservable ? 'Varies' : 'Free';
}

function parseSeasonal(facility) {
  // Check for season keywords in description
  const desc = (facility.FacilityDescription || '').toLowerCase();
  if (desc.includes('year-round') || desc.includes('year round')) return 'year-round';
  if (desc.includes('summer only') || desc.includes('memorial day') && desc.includes('labor day')) return 'summer-only';
  if (desc.includes('closed in winter') || desc.includes('winter closure')) return 'winter-closed';
  return 'unknown';
}

function buildTags(facility) {
  const tags = [];
  const type = (facility.FacilityTypeDescription || '').toLowerCase();
  const desc = (facility.FacilityDescription || '').toLowerCase();
  const name = (facility.FacilityName || '').toLowerCase();

  if (desc.includes('tent') || desc.includes('walk-in')) tags.push('tent');
  if (desc.includes('rv') || desc.includes('hookup') || desc.includes('pull-through')) tags.push('rv');
  if (desc.includes('cabin') || desc.includes('yurt')) tags.push('cabin');
  if (desc.includes('group')) tags.push('group');
  if (desc.includes('horse') || desc.includes('equestrian')) tags.push('equestrian');
  if (desc.includes('boat') || desc.includes('marina')) tags.push('boating');
  if (desc.includes('fish')) tags.push('fishing');
  if (desc.includes('hik')) tags.push('hiking');
  if (desc.includes('lake') || name.includes('lake')) tags.push('lake');
  if (desc.includes('river') || name.includes('river')) tags.push('river');
  if (desc.includes('mountain') || name.includes('mountain')) tags.push('mountain');
  if (desc.includes('beach') || name.includes('beach')) tags.push('beach');
  if (desc.includes('shower')) tags.push('showers');
  if (desc.includes('flush toilet')) tags.push('flush-toilets');
  if (desc.includes('electric') || desc.includes('hookup')) tags.push('electric');
  if (desc.includes('water hookup') || desc.includes('potable water')) tags.push('water');
  if (!facility.Reservable && (desc.includes('first come') || desc.includes('first-come'))) tags.push('first-come-first-served');
  if (facility.Reservable) tags.push('reservable');

  return [...new Set(tags)];
}
