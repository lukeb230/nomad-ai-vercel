# Business Logic

The non-UI logic that needs to port. Most of this lives in `app.html` between lines 3000–4500.

## 1. Query classification (route vs location vs app-question)

Three regex tests on the user's free-text input determine which prompt template and model to use.

```swift
func classify(_ query: String) -> QueryKind {
  let q = query.lowercased()

  // App question — the user is asking ABOUT NomadAI itself, not for sites
  let appQuestion = #"""
  (^|\s)(what can|how do|how does|how to|what is|what are|what do|who are|tell me|explain|help me|features|capabilities|can you|do you|are you|how work|nomadai|about you|about this|where is|what's in|what.*like|good time|best time|weather in|things to do|near.*what|recommend|suggest|tips for|far from|drive.*from|distance)
  """#
  if q.range(of: appQuestion, options: .regularExpression) != nil { return .appQuestion }

  // Route query — multi-stop trip
  let route = #"""
  along|on the way|on my way|en route|between .* and|from .* to|drive.*through|road trip|highway|interstate|\bI-\d|\bUS-\d|\bhwy\b|\broute\b.*\d
  """#
  if q.range(of: route, options: .regularExpression) != nil { return .route }

  return .location
}

enum QueryKind { case appQuestion, route, location }
```

**Why it matters:**
- `route` → use **Claude Sonnet** (`claude-sonnet-4-5-20241022`), `max_tokens: 8000`, with the strict route-distribution prompt
- `appQuestion` and `location` → **Claude Haiku** (`claude-haiku-4-5-20251001`), `max_tokens: 4000`, with shorter prompts
- `appQuestion` → don't even call `/api/search-campsites` — Claude answers directly

## 2. Route prompt construction

When a route query is detected, the prompt has strict distribution rules to prevent the AI from clustering all stops near the start or end. From `app.html:3395+`:

```
ROUTE DISTRIBUTION RULES — follow exactly:
1. SEGMENTS: At least N stops geographically BETWEEN <city1> → <city2>; ...
2. ENDPOINT CAP: No more than 2 stops within 80 miles of <start> and no more than 2 stops within 80 miles of <end>.
3. MIDDLE BIAS: The majority of stops must be in the middle portion of the route, NOT near the endpoints.
4. ORDER: List all <N> stops in strict geographic order from <start> to <end>.
```

Plus a planning preamble:

```
BEFORE outputting results, THINK STEP BY STEP inside a <planning> block:
1. List the states/regions this route passes through in order.
2. For each segment between stops, name 2-3 real, well-known camping areas in that region.
3. Assign N stops across segments — heavier in the middle, lighter near endpoints.
4. For each stop, verify: does this lat/lng actually fall in the city/state I listed? If not, fix it.

COORDINATE RULES:
- Every lat/lng MUST be within 50 miles of the actual route path.
- Every lat/lng MUST match the city and state fields.
- No two consecutive stops should be more than 250 miles apart.

After </planning>, output:
MSG: <one friendly sentence>
<JSON array of exactly N campsites>
```

Each campsite JSON object follows this exact shape (the `fields` constant at `app.html:3345`):

```jsonc
{
  "name": "...",
  "source": "dyrt|recreation.gov|ioverlander|blm|campendium|other",
  "sourceLabel": "...",
  "url": "real URL or empty",
  "distance": "~XX miles",
  "fee": "Free or $XX/night",
  "reservable": false,
  "description": "2 sentences",
  "tags": ["tag1","tag2"],
  "directions": "10 words max",
  "coordinates": { "lat": 0.0, "lng": 0.0 },
  "city": "...",
  "state": "...",
  "seasonal": "year-round|summer-only|winter-closed|spring-fall|unknown",
  "views": ["mountain","ocean","lake","river","desert","forest","valley","canyon","meadow","waterfall","beach","glacier","dunes","cliff","plains","none"]
}
```

The web app parses the response by:
1. Splitting on `</planning>` and discarding the planning block
2. Extracting the line starting with `MSG:` for the chat message
3. Parsing the rest as a JSON array

## 3. Trip-stops estimator

Estimates how many stops a route should have based on query verbosity and number of mentioned locations. From `app.html:3400` (`estimateTripStops`):

```swift
func estimateTripStops(query: String, mentionedLocations: Int) -> Int {
  // From the web heuristic — find this function in app.html ~3220
  // Defaults to ~6–10 depending on hints
  // Heuristics: explicit "5 day" mentions, mentioned-location count, "long route" keywords
  // TODO: port the exact heuristic
}
```

**Action item for iOS:** Find `estimateTripStops` in `app.html` (search for the function name) and port it line-for-line. It's ~30 lines.

## 4. Database-first search pattern

Before calling Claude, **always** query `/api/search-campsites` with the user's lat/lng. Pass the database results into Claude as context (in the `dbContext` variable). This:
- Reduces hallucination (Claude has verified ground truth)
- Improves quality (verified sites get prioritized)
- Saves money (smaller prompt, fewer tokens needed)

From `app.html:3380`:

```javascript
const dbSites = await searchDatabase(userLat, userLng, isRouteQuery ? 300 : radius, 12);
if (dbSites.length > 0) {
  dbContext = '\n\nVERIFIED campsites from our database near the search area. Use these as a foundation — include the best matches for the query and supplement with your own knowledge:\n' +
    dbSites.map(s => `- ${s.name} (${s.city ? s.city + ', ' : ''}${s.state}) [${s.fee}] lat:${s.coordinates.lat} lng:${s.coordinates.lng} tags:${(s.tags||[]).join(',')}`).join('\n');
}
```

Note the radius bump: `300mi` for route queries vs the user's normal radius for location queries.

## 5. Response cache (location queries only)

For non-route, non-app-question queries, the web caches Claude responses by query string. From `app.html:3352`:

```swift
// Pseudo-code
func searchCacheKey(query: String, lat: Double, lng: Double, radius: Int) -> String {
  let q = query.lowercased().trimmingCharacters(in: .whitespaces)
  // Include rounded lat/lng so the cache scopes to a region
  return "\(q)|\(Int(lat * 10) / 10)|\(Int(lng * 10) / 10)|\(radius)"
}
```

The web stores cache entries in `localStorage` with a TTL of 7 days. iOS should:
- Use `URLCache` if responses come through a `URLProtocol`-friendly path
- Or a SwiftData entity `@Model class SearchCache` keyed on query + region

When showing a cache hit, show a `⚡ Showing cached results` banner (the redesign uses an `.ai-note` callout for this).

## 6. Route optimizer (nearest-neighbor)

From `app.html:4133+`. Takes the user's saved trip stops and reorders them for shortest total distance, optionally starting from the user's current location.

```swift
func optimizeRoute(stops: [TripStop], startFromUserLocation: Bool, userLocation: CLLocation?, roundTrip: Bool) -> [TripStop] {
  let withCoords = stops.filter { $0.lat != nil && $0.lng != nil }
  guard withCoords.count >= 3 else { return stops }

  // Use a simple Euclidean-ish distance — accurate enough at typical inter-camp distances (<500 mi)
  func dist(_ a: TripStop, _ b: TripStop) -> Double {
    let dLat = (a.lat ?? 0) - (b.lat ?? 0)
    let dLng = (a.lng ?? 0) - (b.lng ?? 0)
    return sqrt(dLat * dLat + dLng * dLng)
  }

  // Nearest neighbor:
  var unvisited = withCoords
  var optimized: [TripStop] = []

  // Pick starting stop: closest to user if startFromUserLocation, else first stop
  if startFromUserLocation, let userLoc = userLocation {
    let startStop = unvisited.min { a, b in
      distFromCoord(userLoc, a) < distFromCoord(userLoc, b)
    }
    if let s = startStop {
      optimized.append(s)
      unvisited.removeAll { $0.id == s.id }
    }
  } else {
    optimized.append(unvisited.removeFirst())
  }

  while !unvisited.isEmpty {
    let last = optimized.last!
    let nearest = unvisited.min { a, b in dist(last, a) < dist(last, b) }!
    optimized.append(nearest)
    unvisited.removeAll { $0.id == nearest.id }
  }

  // Round trip: rotate so the stop closest back to start is last
  if roundTrip {
    let returnLat = startFromUserLocation ? userLocation?.coordinate.latitude ?? optimized[0].lat ?? 0 : optimized[0].lat ?? 0
    let returnLng = startFromUserLocation ? userLocation?.coordinate.longitude ?? optimized[0].lng ?? 0 : optimized[0].lng ?? 0
    let bestEndIdx = optimized.indices.min { i, j in
      let a = optimized[i], b = optimized[j]
      let da = pow((a.lat ?? 0) - returnLat, 2) + pow((a.lng ?? 0) - returnLng, 2)
      let db = pow((b.lat ?? 0) - returnLat, 2) + pow((b.lng ?? 0) - returnLng, 2)
      return da < db
    } ?? optimized.count - 1

    if bestEndIdx != optimized.count - 1 {
      // Rotate so optimized[bestEndIdx] is last
      // (port the exact rotation from app.html:4193+ — there's a subtle slice-and-merge)
    }
  }

  // Append stops without coordinates at the end
  let noCoords = stops.filter { $0.lat == nil || $0.lng == nil }
  return optimized + noCoords
}
```

This is intentionally a simple greedy heuristic — fast, good-enough for ≤15 stops. For >15 stops, consider 2-opt or LKH later.

## 7. Search-area-on-map UX

When the user pans the Leaflet map, after the pan settles, the web shows a "🔍 Search this area" floating button. Tap → location-search at the new map center.

iOS port:

```swift
struct CampsiteMapView: View {
  @State var region: MKCoordinateRegion = ...
  @State var lastSearchedRegion: MKCoordinateRegion?
  @State var showSearchAreaButton = false

  var body: some View {
    Map(coordinateRegion: $region) { ... }
      .onChange(of: region) { _, newRegion in
        // Only show button if user panned at least 0.05 degrees from last search
        if let last = lastSearchedRegion,
           abs(newRegion.center.latitude - last.center.latitude) > 0.05 ||
           abs(newRegion.center.longitude - last.center.longitude) > 0.05 {
          showSearchAreaButton = true
        }
      }
      .overlay(alignment: .bottom) {
        if showSearchAreaButton {
          Button("Search this area") { searchArea() }
            .buttonStyle(.clayPrimary)
        }
      }
  }

  func searchArea() {
    Task {
      let radius = 50.0  // miles
      let sites = try await searchCampsites(lat: region.center.latitude, lng: region.center.longitude, radius: radius)
      // populate map markers
      lastSearchedRegion = region
      showSearchAreaButton = false
    }
  }
}
```

## 8. Trip completion → passport stamps

When the user marks the active trip "complete", every stop in the trip becomes a `Campsite.isVisited = true` and a passport stamp is generated. From `app.html:4087+`:

```swift
func completeTrip(_ trip: Trip) {
  // Each stop becomes visited
  for stop in trip.stops {
    if let campsite = findCampsite(byName: stop.campsiteName) {
      campsite.isVisited = true
      campsite.visitedAt = Date()
    }
  }

  // Save trip to history if it had ≥3 stops
  if trip.stops.count >= 3 {
    let completed = CompletedTrip(
      id: trip.id,
      completedAt: Date(),
      stopNames: trip.stops.map(\.campsiteName),
      stopCount: trip.stops.count
    )
    modelContext.insert(completed)
  }

  // Clear the active trip
  modelContext.delete(trip)
  syncToSupabase()
}
```

## 9. Rate-limit awareness

Claude's `/api/claude` enforces 10 req/IP/hr. The iOS app should:

1. **Track local count** — every successful Claude call increments a counter in `UserDefaults` (rolling 1hr window)
2. **Show remaining** — small mono caption above the search bar: `7/10 used this hour`
3. **On 429** — show banner, disable the send button until the hour resets
4. **Suggestion:** when at 10/10, offer location-mode-only fallback: "AI search paused — try location search for now"

The 10/hr limit is per-IP, not per-user. On a phone with cellular data, the IP changes more often than on Wi-Fi, which somewhat softens the limit. Don't rely on this for UX — assume the limit is real.

## 10. Photo loading priority

The web has a 3-tier photo source preference (in `app.html` around the carousel rendering):

1. **Wikimedia Commons** — best quality, no API limits. Try first.
2. **Mapbox satellite** — fallback for sites with no Wikimedia coverage. Uses lat/lng.
3. **Google Places photos** — final fallback via `/api/places`. Rate-limited by Google.

For iOS, recommend starting simpler: just use `/api/places` (already proxied, no API keys to ship). Add Wikimedia + Mapbox in a v2 iteration if photo coverage is poor.

## 11. Voice search

The web uses Web Speech API. iOS uses `Speech` framework:

```swift
import Speech

let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
let request = SFSpeechAudioBufferRecognitionRequest()
let audioEngine = AVAudioEngine()

// Tap mic button → start recording, transcribe live, on stop populate query
```

Requires `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in `Info.plist`.

## 12. Trip share-link

The web uses Supabase to store a trip and gives the user a shareable URL. iOS should:
- Use the **same Supabase row** so a web → iOS or iOS → web share works
- Use `UIActivityViewController` (or SwiftUI's `ShareLink`) to present the share sheet

```swift
ShareLink(item: URL(string: "https://nomadai.us/spot/\(trip.shareId)")!) {
  Label("Share trip", systemImage: "square.and.arrow.up")
}
```

## Open implementation questions

1. **Offline-first vs online-only** — SwiftData makes offline-first cheap. Recommend: cards/saved/visited/notes work offline; AI search and `/api/search-campsites` need network. Show a banner when offline.
2. **Background sync** — should we sync to Supabase in `applicationWillResignActive`? Probably yes for write-heavy paths (saving a spot).
3. **Push notifications for trip reminders** — `cf_*` doesn't track this directly but the web has a "trip reminders" toggle in Settings. Wire to `UNUserNotificationCenter` and schedule a notification per `TripStop.scheduledDate`.
