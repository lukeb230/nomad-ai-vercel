# State Model

The web app uses 16 `cf_*` localStorage keys plus 6 Supabase tables. iOS should consolidate these into typed Swift models persisted via **SwiftData** (recommended) or `Codable` + a single JSON file in `Application Support`.

## localStorage keys → Swift mapping

| Web key | Type | Shape | Swift home | Notes |
|---|---|---|---|---|
| `cf_saved` | array | `[Campsite]` | `@Model class SavedSpot` | The user's bookmarked sites |
| `cf_visited` | array of strings | `[String]` (just site names) | `@Model class VisitedSpot` | Set of site names the user marked visited |
| `cf_visited_states` | array | `[{state: String, ...}]` | `@Model class VisitedState` | Per-state metadata |
| `cf_notes` | object | `[siteName: String]` | `@Model class Note` | One note per site |
| `cf_ratings` | object | `[siteName: Int]` | `@Model class Rating` | 1–5 stars per visited site |
| `cf_trip` | array | `[Campsite]` | `@Model class TripStop` (sorted) | Current trip's ordered stops |
| `cf_trip_index` | integer | `Int` | `UserDefaults` | Which stop is "current" in the active trip |
| `cf_trip_dates` | object | `[siteName: ISO8601]` | merge into `TripStop.scheduledDate` | Per-stop scheduled date |
| `cf_completed_trips` | array | `[CompletedTrip]` | `@Model class CompletedTrip` | Trip history for passport stats |
| `cf_home_cache` | array | `[Campsite]` | `Data` blob in cache dir | Home tab's last AI suggestion list |
| `cf_home_cache_time` | string | timestamp | `Date` paired with cache | TTL ≈ 4h in web — match on iOS |
| `cf_search_history` | array | `[String]` | `UserDefaults` | Recent search queries (max 20) |
| `cf_search_count` | object | `{date: String, count: Int}` | ephemeral — derive from rate-limit headers if possible | Daily/hourly search counter |
| `cf_recent` | array | `[Campsite]` | `@Model class RecentSpot` | Recently-viewed sites |
| `cf_default_radius` | string | `"25"|"50"|"100"|"200"` | `@AppStorage` enum | Default search radius |
| `cf_light_mode` | string | `"0"|"1"` | `@AppStorage` `ColorScheme` | `1` = light, `0` = dark. iOS default: dark. |
| `cf_profile` | object | `{name, avatar_url}` | `@Model class Profile` (single row) | User profile |

## Recommended Swift architecture

### SwiftData models

```swift
import SwiftData
import Foundation

@Model
final class Campsite {
  @Attribute(.unique) var id: String   // composite of source + name + lat or upstream id
  var name: String
  var source: CampsiteSource           // enum: dyrt, recreationGov, ioverlander, blm, campendium, other
  var sourceLabel: String
  var url: String?
  var fee: String?                     // "Free" | "$22/night" | "Unknown"
  var reservable: Bool
  var siteDescription: String?
  var tags: [String]
  var directions: String?
  var lat: Double?
  var lng: Double?
  var city: String?
  var state: String?
  var seasonal: SeasonalAvailability   // year-round, summer-only, winter-closed, spring-fall, unknown
  var amenities: [String]

  // User-attached state
  var isSaved: Bool = false
  var isVisited: Bool = false
  var savedAt: Date?
  var visitedAt: Date?
  var rating: Int?                     // 1...5
  var note: String?
}

@Model
final class TripStop {
  var trip: Trip?                      // back-reference
  var order: Int
  var campsiteId: String               // ref to Campsite.id
  var scheduledDate: Date?
}

@Model
final class Trip {
  @Attribute(.unique) var id: UUID
  var startedAt: Date
  var completedAt: Date?
  var stops: [TripStop]                // sorted by order
  var currentStopIndex: Int = 0
  var roundTrip: Bool = false
  var startFromUserLocation: Bool = true
}

@Model
final class CompletedTrip {
  @Attribute(.unique) var id: UUID
  var completedAt: Date
  var stopNames: [String]
  var stopCount: Int                   // ≥ 3 for the trip to "count"
}
```

### `@AppStorage`-backed prefs

```swift
extension UserDefaults {
  static let standard = UserDefaults.standard
}

enum AppPreferenceKey {
  static let defaultRadius = "default_radius"   // Int
  static let colorScheme = "color_scheme"       // String: "light" | "dark"
  static let searchHistory = "search_history"   // [String], max 20
  static let homeCacheTimestamp = "home_cache_timestamp"
}

struct ContentView: View {
  @AppStorage(AppPreferenceKey.defaultRadius) var radius: Int = 50
  @AppStorage(AppPreferenceKey.colorScheme) var schemePref: String = "dark"
  // ...
}
```

### Cache directory

Cache the home AI suggestions and weather/sunrise responses in `URL.cachesDirectory/`:

```swift
extension URL {
  static var nomadCacheDir: URL {
    URL.cachesDirectory.appending(path: "NomadAI", directoryHint: .isDirectory)
  }
}
```

The OS may purge this directory under low disk pressure, which is fine — cached data is regenerable.

## Sync to Supabase

The web app does background `syncToSupabase()` after every write. iOS should:

1. **On app foreground** — pull from Supabase, merge with local SwiftData, prefer the latest `updated_at` on each row.
2. **On every local mutation** — debounce (1s) and push to Supabase in the background.
3. **On signout** — clear all SwiftData + UserDefaults entries that are user-scoped. Keep app-wide prefs.

Use `Combine` or `swift-concurrency` (Task + AsyncSequence) to coordinate.

### Sync conflict policy

If both web and iOS modified the same record, **last-write-wins** by Supabase's `updated_at` server timestamp. This is what the web does today.

For high-stakes data (the active trip), consider stronger merging — but for v1, last-write-wins is fine.

## Migration from web to iOS

If a user was on web and signs into iOS with the same Supabase account, all their data syncs automatically through the existing `saved_spots`, `visited_spots`, `notes`, `settings`, `trips`, `profile` Supabase tables. No iOS-specific migration code needed.

The only thing that won't transfer is `cf_home_cache` (intentionally — let iOS regenerate fresh suggestions) and `cf_search_count` (rate-limit counter, server-side anyway).
