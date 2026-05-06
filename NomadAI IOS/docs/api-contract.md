# API Contract

All endpoints are existing Vercel Functions in [`/api/*`](../../api/). They serve both web and iOS unchanged.

**Base URL** (production): `https://nomadai.us` or whatever the production Vercel domain is — check `.vercel/project.json`.

---

## `POST /api/claude` — Claude API proxy

Anthropic API proxy with rate limiting. Lets the iOS app talk to Claude without shipping the API key.

**Body:** Pass-through of Anthropic's [Messages API](https://docs.anthropic.com/en/api/messages) request body. Common fields:

```jsonc
{
  "model": "claude-sonnet-4-5-20241022",  // or "claude-haiku-4-5-20251001"
  "max_tokens": 4000,                       // 4000 for general, 8000 for route queries
  "messages": [
    { "role": "user", "content": "..." }
  ]
}
```

**Model selection** (mirror this logic):
- **Route queries** (multi-stop trip planning) → `claude-sonnet-4-5-20241022`, `max_tokens: 8000`
- **All other queries** → `claude-haiku-4-5-20251001`, `max_tokens: 4000` (or `3000` for short tasks)

**Response:** Raw Anthropic response (status mirrors Anthropic's status code):
```jsonc
{
  "content": [{ "type": "text", "text": "..." }],
  "id": "msg_...",
  "model": "...",
  "role": "assistant",
  "stop_reason": "end_turn",
  "type": "message",
  "usage": { "input_tokens": 0, "output_tokens": 0 }
}
```

**Rate limit:** 10 requests per IP per hour, sliding window. On limit, returns:
```jsonc
{
  "error": {
    "type": "rate_limit",
    "message": "You have reached the limit of 10 searches per hour. Please try again later."
  }
}
```
Status: `429`. The iOS client should show a "10/hr cap" banner and disable the send button gracefully.

**Auth:** None at the HTTP layer. The Vercel Function holds `ANTHROPIC_KEY`.

**Swift:** see `Sources/NomadAI/Services/ClaudeService.swift`.

---

## `GET /api/places` — Google Places photo proxy

Two modes via `?type=` query param.

### `?type=search&input=<query>`
Find a place's photo references by free-text name.

**Response:**
```jsonc
{
  "candidates": [
    {
      "photos": [
        { "photo_reference": "AeJbb3..." },
        { "photo_reference": "AeJbb3..." }
        // up to 5
      ]
    }
  ]
}
```

### `?type=photo&ref=<photo_reference>`
Returns the actual JPEG image bytes (not base64). Set `<img src="...">` directly to the URL.

**Response:** `image/jpeg` binary. `Cache-Control: public, max-age=86400`.

**Auth:** None at the HTTP layer. Function holds `GOOGLE_PLACES_KEY`.

**Swift:** Use `URLSession` to fetch the JPEG into `Data`, then `UIImage(data:)` / `Image(uiImage:)`. Cache aggressively (NSCache or SDWebImage).

---

## `GET /api/search-campsites` — Database campsite search

Searches the Supabase `campsites` table for sites within a radius of a lat/lng.

**Query params:**

| Param | Required | Default | Notes |
|---|---|---|---|
| `lat` | yes | — | Decimal latitude |
| `lng` | yes | — | Decimal longitude |
| `radius` | no | 50 | Miles |
| `limit` | no | 20 | Max 50 |
| `tags` | no | — | Comma-separated, e.g. `dispersed,blm,free` |
| `source` | no | — | One of `recreation_gov`, `osm`, `usfs`, `blm` |

**Response:**
```jsonc
{
  "sites": [
    {
      "name": "Ward Mountain BLM",
      "source": "blm",                         // normalized to lowercase short form
      "sourceLabel": "BLM",                    // human-readable
      "url": "https://...",
      "distance": "~12 miles",                 // string, includes ~
      "fee": "Free",                           // or "$22/night" or "Unknown"
      "reservable": false,
      "description": "...",
      "tags": ["dispersed","pit-toilet"],
      "directions": "",
      "coordinates": { "lat": 39.21, "lng": -114.92 },
      "city": "Ely",
      "state": "NV",
      "seasonal": "year-round",                // or summer-only|winter-closed|spring-fall|unknown
      "amenities": [],
      "_fromDatabase": true                    // marker so AI prompts know it's verified
    }
  ],
  "total": 14,
  "radius": 50
}
```

**Auth:** None at the HTTP layer. Function holds `SUPABASE_SERVICE_KEY`.

**Use:** This is the FIRST call when doing a location-based search. Prefer it over Claude when possible — verified, faster, cheaper. Pass results into Claude as `dbContext` when you do need AI augmentation.

---

## `POST /api/import-recgov` — Recreation.gov import (admin)
## `POST /api/import-osm` — OpenStreetMap import (admin)
## `POST /api/import-usfs` — USFS / BLM import (admin)
## `POST /api/setup-campsites` — One-time table setup (admin)
## `GET /api/refresh-campsites` — Weekly cron refresh

These are admin/cron endpoints. **The iOS app does not call any of these.** They run server-side via cron or admin tools to keep the campsites table fresh. Document them only so you don't accidentally hit them.

`/api/refresh-campsites` is wired to Vercel Cron at `0 3 * * 0` (Sundays 3am UTC) via `vercel.json`.

Admin endpoints require header `x-admin-key: <ADMIN_SECRET>` matching the env var.

---

## Open-Meteo (weather + sunrise/sunset)

**Not** proxied — the web app calls Open-Meteo directly. iOS should do the same:

```
GET https://api.open-meteo.com/v1/forecast
  ?latitude=39.21
  &longitude=-114.92
  &current=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code
  &daily=sunrise,sunset
  &timezone=auto
  &temperature_unit=fahrenheit
  &wind_speed_unit=mph
```

Open-Meteo is free with no API key for non-commercial use. The web app caches each lat/lng's response for ~6 hours. Mirror that on iOS via NSCache or a small SwiftData entity keyed on `(roundedLat, roundedLng)`.

Weather code → icon mapping is documented in [Open-Meteo's docs](https://open-meteo.com/en/docs#weathervariables) — store the mapping locally:

| Code | Description | SF Symbol |
|---|---|---|
| 0 | Clear | `sun.max` |
| 1, 2, 3 | Partly cloudy | `cloud.sun` |
| 45, 48 | Fog | `cloud.fog` |
| 51–67 | Rain | `cloud.rain` |
| 71–77 | Snow | `cloud.snow` |
| 80–82 | Showers | `cloud.heavyrain` |
| 95–99 | Thunderstorm | `cloud.bolt.rain` |

---

## Supabase

Auth + sync layer. The web app uses the JS SDK directly; iOS should use the [official Supabase Swift SDK](https://github.com/supabase-community/supabase-swift).

```swift
import Supabase

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://<project-ref>.supabase.co")!,
  supabaseKey: "<anon-public-key>"
)
```

The anon key in the web app is hardcoded at `app.html:3522` — the same key works for iOS. (Supabase RLS policies enforce per-user access; the anon key is intentionally public.)

### Tables used (inferred from `syncToSupabase` / `syncFromSupabase` in `app.html:4540+`)

| Table | Columns | Notes |
|---|---|---|
| `saved_spots` | `user_id`, `data` (jsonb) | One row per saved spot. `data` is the campsite JSON. |
| `visited_spots` | `user_id`, `spot_name` | One row per visited site name. |
| `notes` | `user_id`, `spot_name`, `note` | Free-text notes. |
| `settings` | `user_id`, `light_mode`, `default_radius`, `search_history`, `ratings`, `visited_states` | Single row per user. |
| `trips` | `user_id`, `current_trip` (jsonb), `completed_trips` (jsonb), `trip_index` | Single row per user. |
| `profile` | `user_id`, `name`, `avatar_url` | Single row per user. |
| `campsites` | (see [setup-campsites.js](../../api/setup-campsites.js)) | The canonical campsite table. iOS reads via `/api/search-campsites`. |

See [`state-model.md`](./state-model.md) for the full mapping.

### Auth flow

The web uses `supabase.auth.signInWithPassword` and `supabase.auth.signUp`. iOS should:
1. Default to **Sign in with Apple** via `AuthenticationServices` + Supabase's third-party provider integration
2. Keep email/password as a secondary option for users migrating from web (so their saved data syncs)

---

## Vercel deployment

The same Vercel project hosts these functions. Production domain: check the team's Vercel dashboard or `.vercel/project.json` (project: `nomad-ai-vercel`, team: `team_jyWSq0WBGzY85qxrP6QZEGMh`).

iOS hits `https://nomadai.us` (or the production preview alias).

---

## Error handling conventions

| Status | Meaning | Client behavior |
|---|---|---|
| `200` | OK | Parse and use |
| `400` | Bad request (e.g. missing `lat`/`lng`) | Show inline error, don't retry |
| `401` | Unauthorized (admin endpoints) | Should never happen for client calls |
| `405` | Method not allowed | Programming error |
| `429` | Rate limited (Claude proxy) | Show "10/hr cap" banner, disable send for the rest of the hour, mention `Try again at <next hour>` |
| `500` | Server error | Show "Something broke — try again" |

Always check the response body for an `error.type === 'rate_limit'` shape on `429` — the message is user-presentable.
