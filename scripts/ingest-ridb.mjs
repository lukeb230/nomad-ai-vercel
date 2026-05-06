// scripts/ingest-ridb.mjs
//
// Bulk-ingests federal recreation facilities (campgrounds + similar) from
// RIDB (https://ridb.recreation.gov/) into Supabase's `campsites` table.
//
// Run:
//   npm run ingest:ridb           — full ingest, all camping facilities (~5-10K rows)
//   npm run ingest:ridb -- --dry  — preview pages 1-2 without writing to DB
//
// Reads RIDB_KEY + SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY from .env.
//
// RIDB has informal rate limits — we sleep 250ms between requests, which is
// well under any reasonable cap and keeps total runtime under ~5 minutes.

import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const RIDB_KEY = process.env.RIDB_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!RIDB_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    "Missing env. Set RIDB_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY in .env"
  );
  process.exit(1);
}

const DRY_RUN = process.argv.includes("--dry");
const BASE = "https://ridb.recreation.gov/api/v1";
const PAGE_SIZE = 50;
const SLEEP_MS = 250;
const UPSERT_BATCH = 200;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// RIDB FacilityTypeDescription values that represent camping. Day-use,
// trailheads, picnic areas, marinas etc. are excluded.
const CAMPING_TYPES = new Set([
  "Campground",
  "Group Campground",
  "RV Site",
  "Cabin",
  "Cabin/Lodge",
  "Lodging",
  "Tent",
  "Yurt",
]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchFacilitiesPage(offset) {
  const url = `${BASE}/facilities?limit=${PAGE_SIZE}&offset=${offset}&state=&activity=CAMPING`;
  const res = await fetch(url, { headers: { apikey: RIDB_KEY, accept: "application/json" } });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`RIDB ${res.status}: ${body.slice(0, 200)}`);
  }
  return res.json();
}

function isCampingFacility(f) {
  // Some facilities have empty FacilityTypeDescription but are tagged with
  // CAMPING via the activity filter — keep those too.
  if (!f.FacilityTypeDescription) return true;
  return CAMPING_TYPES.has(f.FacilityTypeDescription);
}

function hasUsableCoords(f) {
  const lat = Number(f.FacilityLatitude);
  const lng = Number(f.FacilityLongitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat === 0 && lng === 0) return false;
  return true;
}

function toRow(f) {
  return {
    external_id: `ridb:facility:${f.FacilityID}`,
    source: "ridb",
    name: (f.FacilityName || "").trim(),
    description: (f.FacilityDescription || "").trim() || null,
    lat: Number(f.FacilityLatitude),
    lng: Number(f.FacilityLongitude),
    phone: (f.FacilityPhone || "").trim() || null,
    email: (f.FacilityEmail || "").trim() || null,
    reservation_url: (f.FacilityReservationURL || "").trim() || null,
    reservable: !!f.Reservable,
    facility_type: f.FacilityTypeDescription || null,
    agency: null, // populated in a future pass via ParentRecAreaID lookup
    last_updated: f.LastUpdatedDate ? new Date(f.LastUpdatedDate).toISOString() : null,
    raw: f,
  };
}

async function upsertBatch(rows) {
  if (DRY_RUN) {
    console.log(`  [dry] would upsert ${rows.length} rows`);
    return;
  }
  const { error } = await supabase
    .from("campsites")
    .upsert(rows, { onConflict: "external_id" });
  if (error) throw new Error(`Supabase upsert failed: ${error.message}`);
}

async function main() {
  console.log(`RIDB ingest starting${DRY_RUN ? " (DRY RUN — no DB writes)" : ""}`);

  let offset = 0;
  let totalSeen = 0;
  let totalKept = 0;
  let totalDropped = 0;
  let buffer = [];

  while (true) {
    const page = await fetchFacilitiesPage(offset);
    const data = page.RECDATA || [];
    const meta = page.METADATA?.RESULTS || {};

    if (data.length === 0) break;

    totalSeen += data.length;

    for (const f of data) {
      if (!isCampingFacility(f)) {
        totalDropped++;
        continue;
      }
      if (!hasUsableCoords(f)) {
        totalDropped++;
        continue;
      }
      buffer.push(toRow(f));
      totalKept++;
    }

    if (buffer.length >= UPSERT_BATCH) {
      await upsertBatch(buffer);
      buffer = [];
    }

    offset += PAGE_SIZE;
    const totalCount = meta.TOTAL_COUNT ?? "?";
    console.log(`  page @${offset - PAGE_SIZE}/${totalCount} — kept ${totalKept}, dropped ${totalDropped}`);

    if (DRY_RUN && offset >= PAGE_SIZE * 2) break;
    if (offset >= (meta.TOTAL_COUNT ?? Infinity)) break;

    await sleep(SLEEP_MS);
  }

  if (buffer.length > 0) {
    await upsertBatch(buffer);
  }

  console.log(`\nDone. Saw ${totalSeen}, kept ${totalKept}, dropped ${totalDropped}.`);
}

main().catch((err) => {
  console.error("\nIngest failed:", err.message);
  process.exit(1);
});
