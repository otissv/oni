# CSS attributes

Reference for mapping CSS concepts to author-time [`Widget_Config`](../types.odin) fields and [`set` helpers](../set/set.odin). Resolved values live in `Resolved_Widget_Style` / `Resolved_Widget_Config`; there is no author-time `Widget_Style` type. Oni is a declarative style API, not a CSS parser. Wrap typed values with the matching `set.*` helper where available.

## In `Widget_Config`

| CSS property | Field | Notes |
|---|---|---|
| `background` / `background-color` | `background` | `Colors` union (Tailwind palette, callbacks) |
| `border-width` | `border` | Per-side via `Border` union |
| `border-color` | `border_color` | |
| `border-radius` | `radius` | Per-corner via `Radius` union |
| `color` | `color` | |
| `direction` (bidi) | `text_direction` | `Text_Direction` enum |
| `flex-direction` | `direction` | `.HORIZONTAL` / `.VERTICAL`, plus `_WRAP`, `_REVERSE` and `_WRAP_REVERSE` variants |
| `flex-grow` | `flex` | Number only; not full `flex` shorthand. Axis `.GROW` is weight 1 when `flex` unset |
| `font-family` | `font` | `Font_Handle` (registered family), not a CSS string |
| `font-size` | `font_size` | |
| `font-style` | `font_style` | `NORMAL` / `ITALIC`; missing italic faces use synthetic oblique |
| `font-weight` | `font_weight` | `Font_Weight` 100–900; VF `wght` or closest static face + fake bold |
| `column-gap` | `gap_x` | Horizontal gap; `set.Gap_X` |
| `row-gap` | `gap_y` | Vertical gap; `set.Gap_Y` |
| `gap` | `gap_x` + `gap_y` | Set both; no unified `gap` field |
| `align-self` | `self` | `set.Self`; per-child justify override |
| `flex-wrap` / `flex-flow` | `direction` | Wrap/reverse variants of `Direction_Layout`; not separate fields |
| `height` | `height` | `Height` / `Length`: `f32`, `%` via `Dim_struct`, unset (content) / `.GROW` (fill free space) / `.AUTO` (fill parent content area) / `.FIT` (shrink to content) / `.SHRINK` (content basis; share main-axis deficit; ignore leftover) / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT` |
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
| `opacity` | `opacity` | `0`–`1` via `Cfg(Style_F32)`; default `1`; not inherited; nested values multiply per emitted primitive; isolated vector group opacity is a separate `Vector_Node` contract |
| `overflow` | `overflow_x` + `overflow_y` | Set both; no unified `overflow` field. `.HIDDEN`, `.SCROLL`, `.AUTO`; an unset union does not request clipping |
| `overflow-x` | `overflow_x` | Clip when `.HIDDEN`/`.SCROLL`/`.AUTO`; hit-test intersects clip. `.SCROLL`/`.AUTO` are scrollports; overlay bars show on hover (or bar drag) when content overflows |
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
| `width` | `width` | `Width` / `Length`: `f32`, `%` via `Dim_struct`, `.AUTO` / `.FIT` / `.GROW` / `.SHRINK` / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT`. Unset defaults to `.GROW` |
| `white-space` / wrapping | `wrap` | `.NONE`, `.NEWLINES`, `.PRESERVE`, `.BALANCE` — not full `white-space`; unset inherits parent (theme at root) |
| `tab-size` | `tab_size` | Preserve text tab stops in space columns; default `4` |
| `word-spacing` | `word_spacing` | Extra advance on space clusters; default `0` |
| `z-index` | `z_index` | Local stacking context; layout builds paint/hit `stack_index` (default `0`) |

Non-CSS fields on `Widget_Config` include `id`, `kind`, `title`, `auto_focus`, `disabled`, `tabbable`, `accepts_text_input`, `scroll_x`, `scroll_y` and `space`. Draw spaces are `.ARTBOARD`, `.SCREEN`, `.POPOVER` and `.OVERLAY`; later layers paint/hit above earlier ones.

**Stacking:** Layout owns order. Paint lists: artboard → screen → popover → overlay. Negative-z children paint under parent chrome; then parent; then non-negative children. Sorted by `(z_index, order, source)` within each stacking context. Each popover/overlay root is its own stacking context. Draw tags `stack_index` only. Hit order: overlay → popover → screen → artboard.

---

## CSS differences and remaining gaps

The entries below have no direct field or lack the full CSS semantics. Where typed alternatives exist, use the mappings above and the grid/image sections below.

### Layout — display & flow

- `display`
- `float`
- `clear`
- `content`
- `contain`
- `container-type`
- `container-name`

### Layout — flexbox (gaps in current model)

- `flex` (shorthand — only `flex-grow` via `flex`)
- `flex-shrink`
- `flex-basis`
- `align-content`

## Grid mappings

`w.Grid` selects the CSS-like grid solver. These fields exist on `Widget_Config`; track/placement strings are parsed by Oni's grid parser rather than a general CSS engine.

| CSS concept | Field | Helper |
| --- | --- | --- |
| `grid-template-columns` / rows | `grid_template_columns` / `grid_template_rows` | `Grid_Template_Columns` / `Grid_Template_Rows`, or `Grid_Cols` / `Grid_Rows` |
| `grid-auto-columns` / rows | `grid_auto_columns` / `grid_auto_rows` | `Grid_Auto_Columns` / `Grid_Auto_Rows` |
| `grid-auto-flow` | `grid_auto_flow` | `Grid_Auto_Flow` |
| `grid-template-areas` | `grid_template_areas` | `Grid_Template_Areas` |
| `grid-column` / row | `grid_column` / `grid_row` | `Grid_Column` / `Grid_Row` |
| Column start/end | `grid_column_start` / `grid_column_end` | `Col_Start` / `Col_End` / `Col_Span` |
| Row start/end | `grid_row_start` / `grid_row_end` | `Row_Start` / `Row_End` / `Row_Span` |
| `grid-area` | `grid_area` | `Grid_Area` |

The combined CSS `grid` and `grid-template` shorthands have no direct field. See [`style_grid.odin`](../style_grid.odin) for accepted syntax and [`layout_grid.odin`](../layout_grid.odin) for sizing behavior.

## Remaining CSS gaps

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

- `margin-top` / `margin-right` / `margin-bottom` / `margin-left` (use `margin` / `Mg` / `Mg_struct` sides)
- `margin-block` / `margin-inline` and logical longhands
- CSS margin collapse (Oni does not collapse adjacent margins; use `gap_*` for sibling spacing)
- `box-sizing`
- `width` / `height` keywords beyond `.AUTO` / `.FIT` / fit-content / `.GROW` / `.SHRINK` / `.MIN_CONTENT` / `.MAX_CONTENT` / `.INHERIT`
- `block-size`
- `inline-size`
- `min-block-size`
- `max-block-size`
- `min-inline-size`
- `max-inline-size`
- `aspect-ratio` (no general field, including numeric ratios; Svg/Vector intrinsic sizing is separate)

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

Drive animations from app-owned state (for example, Tengu) and pass the resulting values each frame. Wake on-demand rendering while animation changes pixels; see [FRAME_MODES.md](FRAME_MODES.md).

## Image mappings

`texture_fit` (`set.Texture_Fit`) maps object-fit to `.CONTAIN`, `.COVER`, `.FILL`, `.NONE` or `.SCALE_DOWN`. `texture_pos` uses `set.Texture_Pos` or `set.Texture_Pos_Edges` for placement. These fields apply to image geometry; native vector widgets use their own `Vector_Fit`. There is no general CSS `image-rendering` field.

### Interaction

- `cursor`
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
- `border-collapse` / `border-spacing` as standalone CSS fields (table collapse uses `gap_x` / `gap_y` and the table border solver)
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
