# CSS attributes

Reference for mapping CSS to `Widget_config` (`oni/types.odin`).

## In `Widget_config`

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
| `flex-grow` | `flex` | Number only; not full `flex` shorthand |
| `font-family` | `font` | `Font_Handle`, not a CSS string |
| `font-size` | `font_size` | |
| `gap` | `gap` | Single value; no separate row/column gap |
| `height` | `height` | `f32` px; `Height` union exists but not on struct |
| `justify-content` + `align-items` | `justify` | Combined in `Justify_Pos` |
| `left` | `x` | Fixed offset only |
| `letter-spacing` | `letter_spacing` | |
| `line-height` | `line_height` | |
| `max-height` | `max_h` | |
| `max-width` | `max_w` | |
| `min-height` | `min_h` | |
| `min-width` | `min_w` | |
| `overflow` | `overflow` | `Auto`, `Scroll`, `Hidden` |
| `overflow-x` | `overflow_x` | |
| `overflow-y` | `overflow_y` | |
| `padding` | `padding` | Per-side via `Padding` union |
| `text-align` | `align` | Left / Center / Right |
| `top` | `y` | Fixed offset only |
| `width` | `width` | `f32` px; `Width` union exists but not on struct |
| `white-space` / wrapping | `wrap` | `None`, `Newlines`, `Balance` — not full `white-space` |

Non-CSS fields on `Widget_config`: `id`, `kind`, `auto_focus`, `disabled`, `space` (`Draw_Space`: artboard vs screen).

---

## Not in `Widget_config`

All CSS properties below have no corresponding field on `Widget_config`.

### Layout — display & flow

- `display`
- `float`
- `clear`
- `visibility`
- `content`
- `contain`
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
- `order`
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

- `position` (`static`, `relative`, `absolute`, `fixed`, `sticky`)
- `top` (only `y` offset; no positioning mode)
- `right`
- `bottom`
- `left` (only `x` offset; no positioning mode)
- `inset`
- `inset-block`
- `inset-block-end`
- `inset-block-start`
- `inset-inline`
- `inset-inline-end`
- `inset-inline-start`
- `z-index`
- `isolation`

### Box model

- `margin`
- `margin-top`
- `margin-right`
- `margin-bottom`
- `margin-left`
- `margin-block`
- `margin-block-end`
- `margin-block-start`
- `margin-inline`
- `margin-inline-end`
- `margin-inline-start`
- `box-sizing`
- `width` keywords (`auto`, `fit-content`, `min-content`, `max-content`) — struct uses `f32` only
- `height` keywords (`auto`, `fit-content`, `min-content`, `max-content`) — struct uses `f32` only
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
- `font-weight`
- `font-style`
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
- `text-decoration`
- `text-decoration-color`
- `text-decoration-line`
- `text-decoration-style`
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

- `opacity`
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
