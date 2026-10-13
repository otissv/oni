# CSS attributes

Reference for mapping CSS to `Widget_Style` (`oni/types.odin`).

## In `Widget_Style`

| CSS property | Field | Notes |
|---|---|---|
| `aspect-ratio` | `aspect_ratio` | |
| `background` / `background-color` | `background` | `Colors` union (Tailwind palette, callbacks) |
| `border-width` | `border` | Per-side via `Border` union |
| `border-color` | `border_color` | |
| `border-radius` | `radius` | Per-corner via `Radius` union |
| `color` | `color` | |
| `direction` (bidi) | `text_direction` | `Text_Direction` enum |
| `flex-direction` | `direction` | Row/column only (`.Horizontal` / `.Vertical`) |
| `flex-grow` | `flex` | Number only; not full `flex` shorthand. Axis `.GROW` is weight 1 when `flex` unset |
| `font-family` | `font` | `Font_Handle` (registered family), not a CSS string |
| `font-size` | `font_size` | |
| `font-style` | `font_style` | `NORMAL` / `ITALIC`; missing italic faces use synthetic oblique |
| `font-weight` | `font_weight` | `Font_Weight` 100–900; VF `wght` or closest static face + fake bold |
| `gap` | `gap` | Single value; no separate row/column gap |
| `height` | `height` | `Height` / `Length`: `f32`, `%` via `Dim_struct`, unset (content) / `.GROW` (fill free space) / `.AUTO` (fill parent content area) / `.FIT` (shrink to content) / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT` |
| `justify-content` + `align-items` | `justify` | Combined in `Justify_Pos` |
| `left` | `x` | Inset / offset; with `position` absolute/fixed, pairs with `right` |
| `letter-spacing` | `letter_spacing` | |
| `line-height` | `line_height` | |
| `margin` | `margin` | Per-side via `Margin` union; outside border box; not painted or hit-tested; no CSS margin collapse |
| `max-height` | `max_h` | |
| `max-width` | `max_w` | |
| `min-height` | `min_h` | |
| `min-width` | `min_w` | |
| `order` | `order` | Flex item order; optional `Cfg(Style_F32)`, default `0` |
| `opacity` | `opacity` | `0`–`1` via `Cfg(Style_F32)`; default `1`; not inherited; nested values multiply like CSS group opacity |
| `overflow` | `overflow` | `Auto`, `Scroll`, `Hidden` |
| `overflow-x` | `overflow_x` | Clip when `Hidden`/`Scroll`/`Auto`; hit-test intersects clip. `Scroll`/`Auto` are scrollports; overlay bars show on hover (or bar drag) when content overflows |
| `overflow-y` | `overflow_y` | Same as `overflow_x` |
| `padding` | `padding` | Per-side via `Padding` union |
| `pointer-events` | `pointer_events` | `AUTO` (default) or `NONE` (paint, skip hit) |
| `position` | `position` | `RELATIVE` (default, in flow), `ABSOLUTE` / `FIXED` (out of flow), `STICKY` |
| `right` | `right` | Absolute/fixed inset; with `left` stretches width |
| `bottom` | `bottom` | Absolute/fixed inset; with `top`/`y` stretches height |
| `text-align` | `align` | Left / Center / Right |
| `text-decoration-line` | `text_decoration` | `bit_set` of underline / line-through / overline |
| `text-decoration-style` | `text_decoration_style` | solid, double, dotted, dashed, wavy |
| `text-decoration-color` | `text_decoration_color` | Unset uses text `color` (currentColor) |
| `top` | `y` | Inset / offset; with absolute/fixed pairs with `bottom` |
| `visibility` | `visibility` | `VISIBLE` (default), `HIDDEN` (layout hole, no paint/hit), `NONE` (removed from tree) |
| `width` | `width` | `Width` / `Length`: `f32`, `%` via `Dim_struct`, `.AUTO` / `.FIT` / `.GROW` / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT`. Unset defaults to `.GROW` |
| `white-space` / wrapping | `wrap` | `None`, `Newlines`, `Preserve`, `Balance` — not full `white-space`; unset inherits parent (theme at root) |
| `tab-size` | `tab_size` | Preserve text tab stops in space columns; default `4` |
| `word-spacing` | `word_spacing` | Extra advance on space clusters; default `0` |
| `z-index` | `z_index` | Local stacking context; layout builds paint/hit `stack_index` (default `0`) |

Non-CSS fields on `Widget_Style`: `id`, `kind`, `auto_focus`, `disabled`, `space` (`Draw_Space`: artboard, screen, or popover — popover paints/hits above screen+artboard with its own stacking context).

**Stacking:** Layout owns order. Paint lists: artboard → screen → popover. Negative-z children paint under parent chrome; then parent; then non-negative children. Sorted by `(z_index, order, source)` within each stacking context. Each popover root is its own stacking context. Draw tags `stack_index` only. Hit order: popover → screen → artboard.

---

## Not in `Widget_Style`

All CSS properties below have no corresponding field on `Widget_Style`.

### Layout — display & flow

- `display`
- `float`
- `clear`
- `content`- `contain`
- `container-type`
- `container-name`

### Layout — flexbox (gaps in current model)

- `flex` (shorthand — only `flex-grow` via `flex`)
- `flex-shrink`
- `flex-basis`
- `flex-wrap`
- `flex-flow`
- `align-content`
- `align-self`
- `row-gap` (only unified `gap`)
- `column-gap` (only unified `gap`)

### Layout — grid

- `grid`
- `grid-area`
- `grid-auto-columns`
- `grid-auto-flow`
- `grid-auto-rows`
- `grid-column`
- `grid-column-end`
- `grid-column-start`
- `grid-row`
- `grid-row-end`
- `grid-row-start`
- `grid-template`
- `grid-template-areas`
- `grid-template-columns`
- `grid-template-rows`

### Layout — positioning

- `static` position (Oni defaults every widget to `RELATIVE`)
- `inset` shorthand (set `x`/`y`/`right`/`bottom` individually)
- `inset-block`
- `inset-block-end`
- `inset-block-start`
- `inset-inline`
- `inset-inline-end`
- `inset-inline-start`
- `isolation`

### Box model

- `margin-top` / `margin-right` / `margin-bottom` / `margin-left` (use `margin` / `Pd` / `Pd_struct` sides)
- `margin-block` / `margin-inline` and logical longhands
- CSS margin collapse (Oni does not collapse adjacent margins; use `gap_*` for sibling spacing)
- `box-sizing`
- `width` / `height` keywords beyond `.AUTO` / `.FIT` / fit-content / `.GROW` / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT`
- `block-size`
- `inline-size`
- `min-block-size`
- `max-block-size`
- `min-inline-size`
- `max-inline-size`
- `aspect-ratio` keywords (`auto`, `none`) — only numeric ratio supported

### Borders & outlines

- `border` (shorthand — width/color only; no style)
- `border-style`
- `border-top`
- `border-right`
- `border-bottom`
- `border-left`
- `border-top-width`
- `border-right-width`
- `border-bottom-width`
- `border-left-width`
- `border-top-color`
- `border-right-color`
- `border-bottom-color`
- `border-left-color`
- `border-top-style`
- `border-right-style`
- `border-bottom-style`
- `border-left-style`
- `border-top-left-radius`
- `border-top-right-radius`
- `border-bottom-right-radius`
- `border-bottom-left-radius`
- `border-image`
- `border-image-source`
- `border-image-slice`
- `border-image-width`
- `border-image-outset`
- `border-image-repeat`
- `outline`
- `outline-color`
- `outline-offset`
- `outline-style`
- `outline-width`
- `box-shadow`

### Background

- `background-image`
- `background-size`
- `background-position`
- `background-position-x`
- `background-position-y`
- `background-repeat`
- `background-attachment`
- `background-clip`
- `background-origin`
- `background-blend-mode`

### Overflow & clipping

- `clip`
- `clip-path`
- `overflow-clip-margin`
- `overscroll-behavior`
- `overscroll-behavior-x`
- `overscroll-behavior-y`
- `scroll-behavior`
- `scroll-margin`
- `scroll-margin-top`
- `scroll-margin-right`
- `scroll-margin-bottom`
- `scroll-margin-left`
- `scroll-padding`
- `scroll-padding-top`
- `scroll-padding-right`
- `scroll-padding-bottom`
- `scroll-padding-left`
- `scrollbar-color`
- `scrollbar-gutter`
- `scrollbar-width`

### Typography

- `font` (shorthand)
- `font-stretch`
- `font-variant`
- `font-variant-caps`
- `font-variant-numeric`
- `font-feature-settings`
- `font-kerning`
- `font-optical-sizing`
- `font-size-adjust`
- `font-synthesis`
- `font-variation-settings`
- `word-spacing`
- `text-decoration` (shorthand — use line/style/color fields)
- `text-decoration-thickness`
- `text-underline-offset`
- `text-underline-position`
- `text-transform`
- `text-overflow`
- `text-indent`
- `text-shadow`
- `white-space` (full keyword set — `wrap` is partial)
- `white-space-collapse`
- `text-wrap`
- `text-wrap-mode`
- `text-wrap-style`
- `word-break`
- `overflow-wrap`
- `word-wrap`
- `hyphens`
- `hyphenate-character`
- `hyphenate-limit-chars`
- `line-break`
- `tab-size`
- `vertical-align`
- `writing-mode`
- `text-orientation`
- `unicode-bidi`
- `direction` (full CSS bidi — `text_direction` is simplified)
- `text-align-last`
- `text-justify`
- `text-combine-upright`
- `initial-letter`
- `orphans`
- `widows`

### Visual effects

- `mix-blend-mode`
- `background-blend-mode`
- `filter`
- `backdrop-filter`
- `transform`
- `transform-origin`
- `transform-box`
- `transform-style`
- `perspective`
- `perspective-origin`
- `backface-visibility`
- `will-change`

### Transitions & animation

- `transition`
- `transition-property`
- `transition-duration`
- `transition-timing-function`
- `transition-delay`
- `animation`
- `animation-name`
- `animation-duration`
- `animation-timing-function`
- `animation-delay`
- `animation-iteration-count`
- `animation-direction`
- `animation-fill-mode`
- `animation-play-state`

(`Transition` is commented out in `types.odin`.)

### Images & replaced content

- `object-fit`
- `object-position`
- `image-rendering`

### Interaction

- `cursor`
- `pointer-events`
- `user-select`
- `touch-action`
- `caret-color`
- `accent-color`
- `resize`

### Lists & tables (rare for widgets, but CSS)

- `list-style`
- `list-style-type`
- `list-style-position`
- `list-style-image`
- `table-layout`
- `border-collapse`
- `border-spacing`
- `caption-side`
- `empty-cells`

### Multi-column

- `columns`
- `column-count`
- `column-width`
- `column-gap`
- `column-rule`
- `column-rule-color`
- `column-rule-style`
- `column-rule-width`
- `column-span`
- `column-fill`
- `break-before`
- `break-after`
- `break-inside`

### Logical / modern sizing

- `field-sizing`
- `interpolate-size`
- `anchor-name`
- `anchor-default`
- `position-anchor`
- `position-area`
- `position-try`
- `position-try-fallbacks`
- `position-visibility`
