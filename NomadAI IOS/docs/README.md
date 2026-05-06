# NomadAI iOS — Handoff Package

You are starting a SwiftUI rewrite of NomadAI. This folder is the spec.

## Read in this order

1. **[`/reference/NomadAI-Design-Brief.md`](../reference/NomadAI-Design-Brief.md)** — what the product *is*, who it serves, what every screen contains. Read top to bottom.
2. **[`screen-inventory.md`](./screen-inventory.md)** — every screen + modal, mapped to where they live in the canonical redesign HTML.
3. **[`design-tokens.md`](./design-tokens.md)** — colors, typography, spacing, radii. Already translated to Swift.
4. **[`api-contract.md`](./api-contract.md)** — every Vercel Function you'll call, request/response shapes, rate limits.
5. **[`state-model.md`](./state-model.md)** — every persistent piece of state. Where it lives in the web app and where it should live in iOS.
6. **[`business-logic.md`](./business-logic.md)** — non-UI logic that needs to port: route-vs-location query detection, route prompt construction, nearest-neighbor optimizer, weather/sunrise integration, caching, rate-limit handling.
7. **[`/reference/NomadAI Redesign.html`](../reference/NomadAI Redesign.html)** — pixel-accurate visual reference. Open in a browser when implementing each component. **This is the canonical design** — when web and design diverge, design wins.

## What's intentionally NOT in this package

- The web app's HTML/CSS/JS source code — it's a prototype. Don't port the structure.
- The desktop sidebar layout — iOS is mobile-first, no desktop equivalent.
- The PWA install banner / iOS home-screen hint — irrelevant for a native app.
- The web app's audit issues — they're CSS/JS implementation bugs that don't transfer.

## Backend stays unchanged

The existing `/api/*` Vercel Functions and Supabase project serve both apps. iOS hits the same URLs. No backend work needed for the port.

## Folder layout

```
NomadAI IOS/
├── README.md                  # how to set up the Xcode project
├── docs/                      # this folder — the spec
├── reference/                 # canonical design HTML + product brief
└── Sources/NomadAI/           # starter Swift source you can drag into Xcode
    ├── App/                   # @main entry point
    ├── Design/                # Tokens, Typography, Theme
    ├── Models/                # Campsite, Trip, Stamp, etc.
    ├── Services/              # ClaudeService, SupabaseService, PlacesService
    ├── Views/                 # Tabs (Home, Search, Map, Saved) + Components + Modals
    └── Resources/Fonts/       # download Fraunces, InterTight, JetBrainsMono here
```

## Open questions you'll need to settle

1. **Auth provider** — keep Supabase Auth or move to Sign in with Apple? Sign in with Apple is required by App Store review if any other auth is offered. Recommendation: support both — Sign in with Apple as primary, Supabase email/password as fallback.
2. **Map provider** — MapKit (free, built-in, slightly less stylable) or Mapbox (custom canyon-palette tiles possible, but $$$). The brief calls out the brand opportunity of a custom map style. Default to MapKit; revisit later.
3. **Photo source** — Google Places photos (current) or Apple Maps Look Around / Wikimedia / iOS Photos picker for user-supplied? The web uses Google Places via the `/api/places` proxy. iOS can keep using that, or move to a native option.
4. **Local DB** — Core Data, SwiftData, or just Codable + UserDefaults? Saved spots / trip / passport are small datasets (≤500 items typical). SwiftData is the modern choice and probably right here.
5. **Voice search** — `SFSpeechRecognizer` (iOS native) replaces the web's Web Speech API. New code, but native APIs are cleaner.

These are noted in [`business-logic.md`](./business-logic.md) where relevant.
