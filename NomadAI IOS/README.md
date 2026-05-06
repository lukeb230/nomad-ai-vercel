# NomadAI — iOS

A SwiftUI rewrite of [NomadAI](https://nomadai.us). The web version is being deprecated in favor of this native iOS app.

## What's in this folder

```
NomadAI IOS/
├── README.md                  ← you are here
├── docs/                      ← the spec — read this first
│   ├── README.md              ← handoff index
│   ├── design-tokens.md       ← colors, type, spacing, radii (already in Swift form)
│   ├── api-contract.md        ← every /api/* endpoint
│   ├── state-model.md         ← persistent data, SwiftData models
│   ├── business-logic.md      ← non-UI logic that needs to port (route detection, optimizer, prompts)
│   └── screen-inventory.md    ← every screen + modal, mapped to redesign HTML
├── reference/
│   ├── NomadAI Redesign.html  ← canonical pixel-accurate design — open in browser
│   └── NomadAI-Design-Brief.md ← canonical product spec
└── Sources/NomadAI/           ← starter Swift source — drag into Xcode after step 1 below
    ├── App/                   ← @main entry
    ├── Design/                ← Tokens.swift, Typography.swift
    ├── Models/                ← Campsite, Trip, etc. (SwiftData @Models)
    ├── Services/              ← ClaudeService, CampsiteService, WeatherService
    ├── Views/
    │   ├── ContentView.swift  ← root with custom pill TabView
    │   ├── Tabs/              ← Home, Search, Map, Saved
    │   └── Components/        ← CampsiteCard (the atom)
    └── Resources/Fonts/       ← drop Fraunces/InterTight/JetBrainsMono .ttf files here
```

## First-time setup

### 1. Create the Xcode project

```
Open Xcode → File → New → Project…
  Platform: iOS
  Template: App
  Product Name: NomadAI
  Team: <your team>
  Organization Identifier: us.nomadai (or whatever you prefer)
  Interface: SwiftUI
  Language: Swift
  Storage: SwiftData
  Save in: /Users/Shared/nomadai/nomad-ai-vercel-main/NomadAI IOS/
  ✗ Create Git repository  (we'll handle this separately)
```

This creates `NomadAI IOS/NomadAI/NomadAI.xcodeproj`.

### 2. Replace the auto-generated files with the starter sources

Xcode generates a default `NomadAIApp.swift` and `ContentView.swift`. Delete those, then drag everything from `Sources/NomadAI/` into the Xcode project navigator (uncheck "Copy items if needed" so the files stay in the `Sources` folder — easier to keep in sync with this repo).

**Folder groups to create in Xcode** (mirror the `Sources/NomadAI/` layout):

- `App/`
- `Design/`
- `Models/`
- `Services/`
- `Views/Tabs/`
- `Views/Components/`
- `Views/Modals/` (you'll add modals here later)

### 3. Add the fonts

Download the variable font files from Google Fonts:

- [Fraunces](https://fonts.google.com/specimen/Fraunces) — both regular and italic variable files
- [Inter Tight](https://fonts.google.com/specimen/Inter+Tight)
- [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono)

Drop the `.ttf` files into `Sources/NomadAI/Resources/Fonts/` and add them to the Xcode target. Then add their filenames to `Info.plist` under `UIAppFonts`:

```xml
<key>UIAppFonts</key>
<array>
  <string>Fraunces[opsz,SOFT,WONK,wght].ttf</string>
  <string>Fraunces-Italic[opsz,SOFT,WONK,wght].ttf</string>
  <string>InterTight-Variable.ttf</string>
  <string>JetBrainsMono-Variable.ttf</string>
</array>
```

The names in `Typography.swift` (`Fraunces`, `Fraunces-Italic`, `InterTight`, `JetBrainsMono`) need to match the **PostScript names** of the loaded fonts — verify with `Font Book.app → Get Info` after dropping the files in.

### 4. Set up the asset catalog

Create `Sources/NomadAI/Resources/Assets.xcassets/` and add a Color Set for each token in `Tokens.swift`:

`bg`, `bark`, `surface`, `surface2`, `line`, `lineSoft`, `fg`, `fgDim`, `muted`, `faint`, `clay`, `clayInk`, `moss`, `sage`, `rust`, `sand`, `slate`, `sky`, `berry`, `dyrt`, `rec`, `iov`, `blm`, `camp`.

Each Color Set needs an "Any" appearance (dark theme by default) and a "Light" appearance. Hex values are in [`docs/design-tokens.md`](./docs/design-tokens.md).

Quick way: the values are already laid out in the redesign HTML. You can either type them in by hand (~10 minutes) or use [Asset Catalog Tinkerer](https://github.com/insidegui/AssetCatalogTinkerer) / a small Python script to generate the JSON files.

### 5. Add the Supabase Swift SDK

In Xcode → Project → Package Dependencies → Add Package…

```
URL: https://github.com/supabase-community/supabase-swift
Version: from latest
```

Add `Supabase` to your app target. Then create `Sources/NomadAI/Services/SupabaseService.swift`:

```swift
import Supabase
import Foundation

actor SupabaseService {
    static let shared = SupabaseService()
    let client = SupabaseClient(
        supabaseURL: URL(string: "https://<project-ref>.supabase.co")!,
        supabaseKey: "<anon-public-key>"  // from app.html:3522 of the web project
    )
}
```

(Both values are already in the web app — check `app.html` lines 3520-3530 for the URL and anon key.)

### 6. Configure capabilities

Project → Signing & Capabilities → add:

- **Maps** (for MapKit)
- **Sign in with Apple** (recommended primary auth path)
- **Push Notifications** (only if implementing trip reminders)

In `Info.plist`, add usage descriptions:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>NomadAI uses your location to find nearby campsites and start your trip from where you are.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>NomadAI uses speech recognition to let you search for campsites by voice.</string>

<key>NSMicrophoneUsageDescription</key>
<string>NomadAI uses your microphone for voice search.</string>

<key>NSCameraUsageDescription</key>
<string>NomadAI lets you set a profile photo from your camera.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>NomadAI lets you set a profile photo from your photo library.</string>
```

### 7. Build & run

```
Cmd+B → builds
Cmd+R → runs in the iOS simulator
```

You should see the dark earthy palette, Fraunces "Where to, *this weekend*?" headline on Home, and a clay-active pill tab bar at the bottom.

If fonts haven't loaded, the app will fall back to the system font — the layout will still be correct, just visually less branded. Verify your `Info.plist` `UIAppFonts` entries.

## Where to go from here

Read [`docs/README.md`](./docs/README.md) and start ticking off the implementation order in [`docs/screen-inventory.md`](./docs/screen-inventory.md).

The **first milestone** to aim for: build [`HomeView`](./Sources/NomadAI/Views/Tabs/HomeView.swift) pixel-perfect with mock data. Once Home matches the design, every other screen follows the same patterns.

## Don't port these patterns from web

- The `cardHTML` legacy structure with emoji icons — use [`CampsiteCard.swift`](./Sources/NomadAI/Views/Components/CampsiteCard.swift) as the spec instead
- The web's localStorage `cf_*` keys — use SwiftData (see [`docs/state-model.md`](./docs/state-model.md))
- `#app.light` class toggle — use SwiftUI's `colorScheme` modifier or the asset catalog's automatic theming
- `setTimeout` and `setInterval` — use Swift Concurrency (`Task`, `AsyncSequence`) instead
- The web's manual ID strings — SwiftUI handles identity via `@Identifiable` / `id:`

## Backend notes

The existing Vercel Functions ([`/api/*`](../api/)) and Supabase project work unchanged. iOS hits the same URLs. No backend changes are part of this iOS effort.

If/when web is decommissioned, the only thing to clean up is:
- The Vercel rewrites for `/app`, `/spot/:id` in `vercel.json` — once nothing points there, remove
- The `claude.js` and `places.js` API key proxies — keep, iOS still uses them
- The `import-*` and `refresh-campsites` jobs — keep, they populate the database iOS reads from

## Open questions

See [`docs/README.md`](./docs/README.md) — five product decisions you'll need to make before shipping. Most can wait until v0.1 is on TestFlight, but the auth provider choice (Sign in with Apple vs email/password) affects schema and should be decided early.
