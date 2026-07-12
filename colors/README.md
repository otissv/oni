# Colors

Standalone Odin color package. Depends only on `core:math` — no Oni dependency.

Provides sRGB `RGBA`, a Tailwind-style named palette, alternate color spaces (hex, HSL, HWB, LCH, OKLCH), and conversions to byte and normalized float channels.

## Quick start

```odin
import col "../colors" // adjust path to your project layout

red := col.css_color_to_rgba(.RED_500)
tint := col.to_rgba_color(col.Hex(0xFF0000FF))
clear := col.color_to_f32(col.Colors(col.Color.BACKGROUND))
```

## Types

| Type | Description |
|------|-------------|
| `RGBA` | 8-bit sRGB channels `{r, g, b, a}` |
| `Color` | Named palette enum (semantic tokens + Tailwind shades) |
| `Hex` | Packed `#RRGGBBAA` as `distinct u32` |
| `HSLA` | Hue °, saturation/lightness/alpha in 0–1 |
| `HWBA` | Hue °, whiteness/blackness/alpha in 0–1 |
| `LCHA` | CIE LCH: L 0–100, chroma ≥ 0, hue °, alpha 0–1 |
| `OKLCHA` | OKLCH: L 0–1, chroma ≥ 0, hue °, alpha 0–1 |
| `Colors` | Union of the static variants above |
| `Palette` | `[Color]RGBA` |

## Palette

`palette` is the default table keyed by `Color`. Semantic entries (`.PRIMARY`, `.BACKGROUND`, …) ship with Oni-oriented defaults; shade scales (`.RED_50` … `.TAUPE_950`) follow Tailwind CSS v4 sRGB values.

```odin
fg := col.palette[.FOREGROUND]
accent := col.css_color_to_rgba(.BLUE_500)
```

`.INVALID` and `.INHERIT` resolve to empty `RGBA` via `css_color_to_rgba` (inherit is for host UI layers; this package does not walk a style stack).

## Conversions

Normalize any concrete space to `RGBA`:

```odin
to_rgba_color :: proc { ... } // overload set
```

| Input | Proc |
|-------|------|
| `Color` | `css_color_to_rgba` / `css_color_to_rba` |
| `RGBA` | `rgba_to_rgba` (identity) |
| `Hex` | `hex_to_rgba` |
| `HSLA` | `hsla_to_rgba` |
| `HWBA` | `hwba_to_rgba` |
| `LCHA` | `lcha_to_rgba` |
| `OKLCHA` | `oklcha_to_rgba` |

For GPU / shaders:

```odin
rgba_to_f32(c)   // RGBA → [4]f32 in 0–1
color_to_f32(c)  // Colors → [4]f32 (`.INVALID` → zero)
```

## With Oni

Oni re-exports these types as `o.Color`, `o.RGBA`, etc., and extends `Colors` with a widget callback variant plus context-aware `to_rgba` for `.INHERIT` and procs. Import this package directly when you do not need that UI layer.

## Tests

```bash
odin test colors -vet -strict-style
```

`colors_test.odin` covers API/branch behavior for every public conversion helper.

`colors_external_test.odin` + `colors_external_goldens.odin` audit **external correctness**:

| Suite | Source of truth |
|-------|-----------------|
| All 286 Tailwind shades | Official `theme.css` OKLCH → sRGB via ColorAide |
| OKLCH → sRGB | WPT `css/css-color/oklch-*.html` (CSS Color Level 4) |
| LCH → sRGB | ColorAide `lch-d65` (CIE Lab D65; matches this package) |
| HSL / HWB | CSS Color Level 4 / WPT vectors |
| Semantic theme tokens | Frozen Oni palette goldens (not Tailwind) |

CSS Color 4 / WPT `lch()` uses **D50** Lab; this package uses **D65**. A dedicated test asserts that divergence so a silent white-point change is visible.
