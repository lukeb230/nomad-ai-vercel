# Design Tokens

All values lifted from the canonical [`NomadAI Redesign.html`](../reference/NomadAI Redesign.html).
A Swift implementation lives in [`Sources/NomadAI/Design/Tokens.swift`](../Sources/NomadAI/Design/Tokens.swift).

## Color palette

### Dark theme (default)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#141c17` | Page background |
| `bark` | `#1c2720` | Card base / elevated surface |
| `surface` | `#243028` | Raised surface |
| `surface2` | `#2b382f` | Doubly-raised |
| `line` | `#34433a` | Hairline border |
| `lineSoft` | `#2a362e` | Subtle dashed dividers |
| `fg` | `#ecdfc2` | Primary text (parchment) |
| `fgDim` | `#c8b994` | Secondary text |
| `muted` | `#8fa38e` | Tertiary text / labels |
| `faint` | `#667066` | Quaternary / placeholder |
| `clay` | `#c4825e` | **Primary accent — canyon clay** |
| `clayInk` | `#1b120b` | Text on clay backgrounds |
| `moss` | `#88a578` | Secondary accent — sage/moss |
| `sage` | `#b8c9a8` | Sage highlight |
| `rust` | `#b05a3c` | Hot accent / warnings |
| `sand` | `#d9bf91` | Warm highlight |
| `slate` | `#7e968f` | Cool gray-green |
| `sky` | `#9fb8b8` | Info / location accent |
| `berry` | `#b77878` | Destructive |

### Light theme (parchment)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#f1e9d3` | Parchment page |
| `bark` | `#f7efd9` | Card base |
| `surface` | `#fbf5e3` | Raised |
| `surface2` | `#f3eacf` | Doubly-raised |
| `line` | `#d9caa1` | Hairline |
| `lineSoft` | `#e2d5af` | Soft hairline |
| `fg` | `#22312a` | Primary text |
| `fgDim` | `#3c4b41` | Secondary |
| `muted` | `#62715f` | Tertiary |
| `faint` | `#8a9182` | Quaternary |
| `clay` | `#9c5b3a` | Primary accent (darker) |
| `clayInk` | `#fff5e6` | Text on clay |
| `moss` | `#4a7246` | Secondary accent (darker) |
| `sage` | `#6a8855` | Sage |
| `rust` | `#8a3e24` | Hot accent |
| `sand` | `#a48452` | Warm highlight |
| `slate` | `#54706a` | Cool |
| `sky` | `#5a8080` | Info |
| `berry` | `#8a4b4b` | Destructive |

### Source brand colors (theme-adaptive)

| Source | Dark | Light |
|---|---|---|
| The Dyrt | `#c08b5c` | `#9c7143` |
| Recreation.gov | `#8aac7a` | `#4a7246` |
| iOverlander | `#688c9a` | `#3f6576` |
| BLM / Dispersed | `#7e968f` | `#54706a` |
| Campendium | `#8a7355` | `#6a553a` |

## Typography

Three families. Download the variable font files (`.ttf` or `.otf`) into `Sources/NomadAI/Resources/Fonts/` and register them in `Info.plist` under `UIAppFonts`.

| Family | Use | Notes |
|---|---|---|
| **Fraunces** | Display headlines, card titles, stat numerals | Use the variable font. Axes: `opsz` 9–144, `SOFT` 0–100, `wght` 300–800. The italic italic-emphasis style sets `opsz: 144, SOFT: 100, wght: 400` and `font-style: italic`. |
| **Inter Tight** | Body text, UI labels, buttons | Weights 400–700. Regular weight (500) is the default body weight. |
| **JetBrains Mono** | Micro-labels, numerals, mono captions | Weights 400–700. Use at 10–11px, uppercase, with `letter-spacing: .12em–.18em`. |

### Type scale (from the redesign)

| Token | Family | Size | Weight | Line-height | Letter-spacing | Notes |
|---|---|---|---|---|---|---|
| `display.hero` | Fraunces | 36–40 pt | 400 | 1.02 | -0.03em | Home hero, italic-emphasis option |
| `display.title` | Fraunces | 28–34 pt | 500 | 1.0 | -0.02em | Modal titles, section headlines |
| `display.card` | Fraunces | 19 pt | 500 | 1.15 | -0.01em | Campsite card name |
| `display.subhead` | Fraunces | 16 pt | 500 | 1.2 | -0.01em | Journal entry, route stop name |
| `display.numeral` | Fraunces | 28 pt | 500 | 1.0 | -0.02em | Stats numerals |
| `body.lg` | Inter Tight | 14 pt | 500 | 1.45 | -0.005em | Chat messages, descriptions |
| `body.md` | Inter Tight | 13 pt | 500 | 1.5 | 0 | Card description |
| `body.sm` | Inter Tight | 12 pt | 500 | 1.4 | 0 | Sub text, pills, action buttons |
| `body.xs` | Inter Tight | 11 pt | 500 | 1.4 | 0 | Tag chips, hints |
| `mono.label` | JetBrains Mono | 10 pt | 500 | 1.0 | 0.18em | Section labels, eyebrows |
| `mono.tag` | JetBrains Mono | 10 pt | 500 | 1.0 | 0.06em | Card tag chips |
| `mono.value` | JetBrains Mono | 11 pt | 600 | 1.0 | 0.05em–0.10em | Distance, mileage values |

In SwiftUI:

```swift
Text("Where to,")
  .font(.fraunces(.heroDisplay))

Text("THIS WEEKEND") + Text("?")
  .font(.fraunces(.heroDisplayItalic))
```

See `Sources/NomadAI/Design/Typography.swift` for the implementation.

## Spacing scale

The redesign uses an irregular but consistent spacing rhythm. Map it to a small enum:

| Token | Pixels | Use |
|---|---|---|
| `xs` | 4 | Micro gaps (icon to text in pill) |
| `sm` | 6 | Chip-to-chip horizontal gaps, fine paddings |
| `md` | 10 | Card body internal padding small axis |
| `lg` | 14 | Card body padding, row spacing |
| `xl` | 20 | Section padding horizontal |
| `2xl` | 28 | Section padding vertical |

Page horizontal padding is consistently 16–20px. Tabs use 16px (`page.padding`).

## Corner radii

| Token | Pixels | Use |
|---|---|---|
| `pill` | 999 | Capsule pills, chips, action buttons |
| `lg` | 18–20 | Cards (`.site-card`, `.trip-dash`, `.passport-cover`) |
| `md` | 14 | Inputs, smaller cards |
| `sm` | 10–12 | Buttons, action-btn, data cells |
| `xs` | 6 | Tag chips |

## Hairlines & dividers

- **Solid:** 1px `var(--line)` for static borders
- **Dashed:** `1px dashed var(--line)` for section dividers within cards (evokes topo lines / paper folds)
- **Dotted-spine:** `repeating-linear-gradient(to bottom, var(--line) 0, var(--line) 3px, transparent 3px, transparent 7px)` for the route-planner timeline

## Shadows

Defined in CSS as three tiers — translate to `.shadow` modifiers in SwiftUI:

| Token | CSS | SwiftUI |
|---|---|---|
| `sm` | `0 1px 2px rgba(0,0,0,.28), 0 0 0 1px rgba(0,0,0,.18)` | `.shadow(color: .black.opacity(0.28), radius: 1, y: 1)` |
| `md` | `0 10px 30px -12px rgba(0,0,0,.55), 0 2px 6px rgba(0,0,0,.25)` | `.shadow(color: .black.opacity(0.4), radius: 10, y: 4)` |
| `lg` | `0 30px 60px -20px rgba(0,0,0,.7), 0 8px 24px rgba(0,0,0,.35)` | `.shadow(color: .black.opacity(0.5), radius: 24, y: 8)` |

## Iconography

Custom **1.5px stroke**, rounded caps, organic — never geometric. The redesign HTML defines an `ICONS` library in JS at lines ~2023–2044. Each icon is a `<path>` in a 24×24 viewBox.

For SwiftUI, two paths:
- **SF Symbols (recommended)** — get 80% there with no asset wrangling. `Image(systemName: "tent")`, `mappin`, `location.north`, `compass`, `sun.horizon`, `moon`, `dollarsign.circle`, `lock.fill`, `mountain.2`. Use SF Symbol weights `Light` (1.5px) or `Ultralight`.
- **Custom SVGs** — for the icons SF Symbols doesn't have (the topo line decorations, the custom tent/passport/canyon glyphs), import SVG → `Image` asset catalog → render with `.foregroundStyle(.clay)`.

The full icon list from the redesign HTML, with SF Symbol equivalents:

| Redesign | SF Symbol | Notes |
|---|---|---|
| `tree` | `tree.fill` (iOS 18+) or custom | A pine triangle |
| `shield` | `shield` | BLM badge |
| `truck` | `car.side.fill` | Vehicle icon |
| `water` | `drop` | |
| `toilet` | `toilet.fill` (iOS 17+) | |
| `tent` | `tent.fill` (iOS 18+) or custom | Use custom for older iOS |
| `mountain` | `mountain.2` | |
| `sun` | `sun.max` | |
| `sunrise` | `sun.horizon` | |
| `moon` | `moon` | Sunset |
| `compass` | custom | SF doesn't have |
| `lock` | `lock` | Locked passport stamp |
| `wave` | `waveform` or custom | |
| `dollar` | `dollarsign.circle` | Fee |
| `reserve` | `calendar` | |

## Topo / paper textures

The redesign uses two layered backgrounds:

1. **`paper-tex`** — soft radial gradients, gives surfaces depth without an image
2. **`topo`** — concentric SVG circles at low opacity, evokes topographic lines

In SwiftUI, the topo is best implemented as a `Canvas` overlay or a vector shape. Sample SwiftUI:

```swift
struct TopoOverlay: View {
  var body: some View {
    Canvas { ctx, size in
      let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
      for r in stride(from: 20, through: 138, by: 24) {
        let path = Path(ellipseIn: CGRect(x: center.x - CGFloat(r),
                                          y: center.y - CGFloat(r),
                                          width: CGFloat(r*2),
                                          height: CGFloat(r*2)))
        ctx.stroke(path, with: .color(.fg.opacity(0.035)), lineWidth: 0.8)
      }
    }
    .allowsHitTesting(false)
  }
}
```

## Motion

| Pattern | Spec |
|---|---|
| Card fade-up on mount | 0.3s ease-out, opacity 0→1, translateY 10→0 |
| Pulse dot (active eyebrow) | 2s ease-in-out, opacity 1↔0.55 |
| Hover lift (CTA) | 0.15s, translateY -1 to -2 |
| Active scale | 0.15s, scale 0.96 |
| Carousel slide | 0.35s ease |
| Bottom-sheet enter | 0.25s ease-out from bottom |

In SwiftUI, prefer `.animation(.easeOut(duration: 0.3), value: ...)` and `.transition(.asymmetric(...))`.
