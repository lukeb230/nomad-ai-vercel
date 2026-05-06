# Fonts

Drop the variable font files here:

- **Fraunces** — both regular and italic axes. https://fonts.google.com/specimen/Fraunces
- **Inter Tight** — variable weight 400-700. https://fonts.google.com/specimen/Inter+Tight
- **JetBrains Mono** — variable weight 400-700. https://fonts.google.com/specimen/JetBrains+Mono

After dropping the `.ttf` files in:
1. Drag them into the Xcode project navigator (with target membership ✓)
2. Add filenames to `Info.plist` under `UIAppFonts`
3. Verify the PostScript names match the strings in `Sources/NomadAI/Design/Typography.swift`'s `FontFamily` enum — open the font in `Font Book.app` and check Get Info → PostScript name.

Common PostScript names (verify yours):

| Family | Likely PostScript name |
|---|---|
| Fraunces (regular) | `Fraunces` or `Fraunces-Variable` |
| Fraunces (italic) | `Fraunces-Italic` |
| Inter Tight | `InterTight` or `InterTight-Variable` |
| JetBrains Mono | `JetBrainsMono` or `JetBrainsMonoNL-Regular` |

Update `FontFamily` in `Typography.swift` to match.
