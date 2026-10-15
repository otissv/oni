package oni

import "core:hash"
import "core:mem"

/*
Resolves a Length value against a parent axis size.

Fixed / percent / inherit resolve to pixels. Auto, fit-content, grow, shrink,
and min/max-content are indefinite at this stage and return 0; layout applies
content / free-space / intrinsic rules.
*/
length_resolve :: proc(length: Length, parent: f32) -> f32 {
	switch length.kind {
	case .FIXED:
		return length.value
	case .PERCENT:
		return parent * length.value * 0.01
	case .INHERIT:
		return parent
	case .UNSET, .AUTO, .FIT, .GROW, .SHRINK, .MIN_CONTENT, .MAX_CONTENT:
		return 0
	}
	return 0
}

/*
Returns whether a length has a definite (non-content / non-grow) kind.
*/
length_is_definite :: proc(length: Length) -> bool {
	switch length.kind {
	case .FIXED, .PERCENT, .INHERIT:
		return true
	case .UNSET, .AUTO, .FIT, .GROW, .SHRINK, .MIN_CONTENT, .MAX_CONTENT:
		return false
	}
	return false
}

/*
Returns whether a length is CSS fit-content (`.FIT`).
*/
length_is_fit :: proc(length: Length) -> bool {
	return length.kind == .FIT
}

/*
Returns whether a length is the `.GROW` keyword.
*/
length_is_grow :: proc(length: Length) -> bool {
	return length.kind == .GROW
}

/*
Returns whether a length is the `.SHRINK` keyword.
*/
length_is_shrink :: proc(length: Length) -> bool {
	return length.kind == .SHRINK
}

/*
Returns whether a length fills free space via flex weight (`.GROW`).

Width unset defaults to `.GROW`. Height `.GROW` shares free vertical space.
Height `.AUTO` fills the parent content area through axis resolve (not flex
weight). `.SHRINK` does not take positive free space.
*/
length_fills_free_space :: proc(length: Length, is_height := false) -> bool {
	_ = is_height
	return length.kind == .GROW
}

/*
Returns whether a height may expand after nested soft-wrap remasure.

Height `.FIT` / `.SHRINK` / min/max-content / unresolved content may grow with
remasured children. Height `.AUTO` (parent content area / scrollport) and
`.GROW` (free space) must not — that would collapse scroll range.
*/
length_height_expands_with_content :: proc(length: Length) -> bool {
	switch length.kind {
	case .UNSET, .FIT, .SHRINK, .MIN_CONTENT, .MAX_CONTENT:
		return true
	case .AUTO, .GROW, .FIXED, .PERCENT, .INHERIT:
		return false
	}

	return false
}

/*
Returns whether height fills the parent content area (`.AUTO`).

Distinct from `.GROW` free-space flex weight: `.AUTO` takes the parent content
box as its size (scrollport viewport) without participating in flex grow.
*/
length_height_fills_parent :: proc(length: Length) -> bool {
	return length.kind == .AUTO
}

/*
Returns whether a length is CSS `min-content`.
*/
length_is_min_content :: proc(length: Length) -> bool {
	return length.kind == .MIN_CONTENT
}

/*
Returns whether a length is CSS `max-content`.
*/
length_is_max_content :: proc(length: Length) -> bool {
	return length.kind == .MAX_CONTENT
}

/*
Returns whether a length uses intrinsic content sizing (fit / shrink / min / max-content).
*/
length_is_intrinsic :: proc(length: Length) -> bool {
	switch length.kind {
	case .FIT, .SHRINK, .MIN_CONTENT, .MAX_CONTENT:
		return true
	case .UNSET, .AUTO, .FIXED, .PERCENT, .INHERIT, .GROW:
		return false
	}
	return false
}

/*
Returns whether a length is indefinite for descendant measure.

Intrinsic axes and `.GROW` must not advertise a provisional parent size to
descendants — theme `wrap = .BALANCE` would otherwise inflate nested text to the
row width during bottom-up measure, breaking `.FIT` / `.GROW` without an
explicit `wrap = .NONE`. `.UNSET` and `.AUTO` still forward provisional size.
*/
length_is_measure_indefinite :: proc(length: Length) -> bool {
	switch length.kind {
	case .FIT, .SHRINK, .MIN_CONTENT, .MAX_CONTENT, .GROW:
		return true
	case .UNSET, .AUTO, .FIXED, .PERCENT, .INHERIT:
		return false
	}
	return false
}

/*
Returns whether a Width union carries an explicit value.
*/
@(private)
cfg_width_is_set :: proc(w: Width) -> bool {
	// Zero-value unions are nil (untagged), not struct{}.
	if w == nil do return false
	#partial switch _ in w {
	case struct{}:
		return false
	}
	return true
}

/*
Returns whether a Height union carries an explicit value.
*/
@(private)
cfg_height_is_set :: proc(h: Height) -> bool {
	// Zero-value unions are nil (untagged), not struct{}.
	if h == nil do return false
	#partial switch _ in h {
	case struct{}:
		return false
	}
	return true
}

/*
Copies a Cfg field from src to dst when src is not unset.
*/
@(private)
merge_cfg :: proc($T: typeid, dst: ^Cfg(T), src: Cfg(T)) {
	if src.mode != .UNSET do dst^ = src
}

/*
Returns the explicit bool from a Style_Bool config, or false when unset/inherit.
*/
cfg_style_bool :: proc(field: Cfg(Style_Bool)) -> bool {
	if field.mode != .Value do return false
	#partial switch v in field.value {
	case bool:
		return v
	}
	return false
}

/*
Returns the explicit f32 from a Style_F32 config, or default when unset/inherit.
*/
cfg_style_f32 :: proc(field: Cfg(Style_F32), default: f32 = 0) -> f32 {
	if field.mode != .Value do return default
	#partial switch v in field.value {
	case f32:
		return v
	}
	return default
}

/*
Clamps opacity to the CSS range [0, 1].
*/
clamp_opacity :: proc(value: f32) -> f32 {
	return clamp(value, 0, 1)
}

/*
Resolves a Cfg field using unset or explicit value modes.

Value-level `.INHERIT` returns parent. No Cfg-level inherit mode.
*/
@(private)
resolve_cfg :: proc($T: typeid, field: Cfg(T), parent: T, theme_default: T) -> T {
	switch field.mode {
	case .UNSET:
		return theme_default
	case .Value:
		#partial switch _ in field.value {
		case Inherit:
			return parent
		}
		return field.value
	}
	return theme_default
}

/*
Like resolve_cfg, but UNSET inherits from the parent style (CSS-like).

Used for properties such as `wrap` where a container setting (e.g. button
`wrap = NONE`) must reach label text. Theme is the root fallback via the
style stack, not an UNSET override of an explicit parent value.
*/
resolve_cfg_inherited :: proc($T: typeid, field: Cfg(T), parent: T, theme_default: T) -> T {
	switch field.mode {
	case .UNSET:
		return parent
	case .Value:
		#partial switch _ in field.value {
		case Inherit:
			return parent
		}
		return field.value
	}
	return theme_default
}

@(private)
resolve_style_f32_value :: proc(
	value: Style_F32,
	parent: f32,
	theme_default: f32,
	state: ^$S,
	event: Widget_Event(S),
) -> f32 {
	switch v in value {
	case Inherit:
		return parent
	case f32:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Style_F32:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_style_f32_value(v(ui_state, ui_event), parent, theme_default, state, event)
	}
	return theme_default
}

@(private)
resolve_cfg_f32 :: proc(
	field: Cfg(Style_F32),
	parent: f32,
	theme_default: f32,
	state: ^$S,
	event: Widget_Event(S),
) -> f32 {
	switch field.mode {
	case .UNSET:
		return theme_default
	case .Value:
		return resolve_style_f32_value(field.value, parent, theme_default, state, event)
	}
	return theme_default
}

@(private)
resolve_cfg_bool :: proc(field: Cfg(Style_Bool), parent: bool, theme_default: bool) -> bool {
	switch field.mode {
	case .UNSET:
		return theme_default
	case .Value:
		switch v in field.value {
		case Inherit:
			return parent
		case bool:
			return v
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Style_Bool:
			panic("resolve_cfg_bool: unresolved Style_Bool proc")
		}
	}
	return theme_default
}

@(private)
resolve_cfg_font :: proc(
	field: Cfg(Style_Font),
	parent: Font_Handle,
	theme_default: Font_Handle,
) -> Font_Handle {
	switch field.mode {
	case .UNSET:
		return theme_default
	case .Value:
		switch v in field.value {
		case Inherit:
			return parent
		case Font_Handle:
			return v
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Style_Font:
			panic("resolve_cfg_font: unresolved Style_Font proc")
		}
	}
	return theme_default
}

@(private)
resolve_cfg_space :: proc(
	field: Cfg(Style_Space),
	parent: Draw_Space,
	theme_default: Draw_Space,
) -> Draw_Space {
	switch field.mode {
	case .UNSET:
		return theme_default
	case .Value:
		switch v in field.value {
		case Inherit:
			return parent
		case Draw_Space:
			return v
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Style_Space:
			panic("resolve_cfg_space: unresolved Style_Space proc")
		}
	}
	return theme_default
}

/*
Converts a Width union to a resolved Length, evaluating proc callbacks when present.

Unset / empty width defaults to `.GROW` so widgets fill free horizontal space
unless the author opts into `.AUTO`, `.FIT`, or another mode.
*/
@(private)
resolve_length_from_width :: proc(
	w: Width,
	parent_w: f32,
	state: ^$S,
	event: Widget_Event(S),
) -> Length {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)

	switch v in w {
	case struct{}:
		return {kind = .GROW}
	case Width_Mode:
		switch v {
		case .INHERIT:
			return {kind = .INHERIT}
		case .AUTO:
			return {kind = .AUTO}
		case .FIT:
			return {kind = .FIT}
		case .GROW:
			return {kind = .GROW}
		case .SHRINK:
			return {kind = .SHRINK}
		case .MIN_CONTENT:
			return {kind = .MIN_CONTENT}
		case .MAX_CONTENT:
			return {kind = .MAX_CONTENT}
		}
	case f32:
		return {kind = .FIXED, value = v}
	case Dim_struct:
		percent := f32_i_resolve(v.percent, 0)
		min_v := f32_i_resolve(v.min, 0)
		max_v := f32_i_resolve(v.max, 0)
		if percent > 0 do return {kind = .PERCENT, value = percent}
		if min_v > 0 do return {kind = .FIXED, value = min_v}
		if max_v > 0 do return {kind = .FIXED, value = max_v}
		return {kind = .GROW}
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Width:
		return resolve_length_from_width(v(ui_state, ui_event), parent_w, state, event)
	}
	return {kind = .GROW}
}

/*
Converts a Height union to a resolved Length, evaluating proc callbacks when present.

Unset / empty height stays content-sized (`Length_Kind.UNSET`) so widgets hug
content. Pass `.AUTO` to fill the parent content area (scrollport viewport),
`.GROW` to fill free vertical space, `.FIT` to shrink to content clamped to
available space, or `.SHRINK` for content basis that shares main-axis deficit.
*/
@(private)
resolve_length_from_height :: proc(
	h: Height,
	parent_h: f32,
	state: ^$S,
	event: Widget_Event(S),
) -> Length {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)

	switch v in h {
	case struct{}:
		return {kind = .UNSET}
	case Height_Mode:
		switch v {
		case .INHERIT:
			return {kind = .INHERIT}
		case .AUTO:
			return {kind = .AUTO}
		case .FIT:
			return {kind = .FIT}
		case .GROW:
			return {kind = .GROW}
		case .SHRINK:
			return {kind = .SHRINK}
		case .MIN_CONTENT:
			return {kind = .MIN_CONTENT}
		case .MAX_CONTENT:
			return {kind = .MAX_CONTENT}
		}
	case f32:
		return {kind = .FIXED, value = v}
	case Dim_struct:
		percent := f32_i_resolve(v.percent, 0)
		min_v := f32_i_resolve(v.min, 0)
		max_v := f32_i_resolve(v.max, 0)
		if percent > 0 do return {kind = .PERCENT, value = percent}
		if min_v > 0 do return {kind = .FIXED, value = min_v}
		if max_v > 0 do return {kind = .FIXED, value = max_v}
		return {kind = .UNSET}
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Height:
		return resolve_length_from_height(v(ui_state, ui_event), parent_h, state, event)
	}
	return {kind = .UNSET}
}

/*
Resolves a Cfg(Gap_X) field.

UNSET uses the theme gap when set, otherwise 0. Gap does not inherit from the
parent unless the value is explicitly `.INHERIT`.
*/
@(private)
resolve_cfg_gap_x :: proc(
	gap: Cfg(Gap_X),
	parent: u16,
	state: ^$S,
	event: Widget_Event(S),
) -> u16 {
	switch gap.mode {
	case .UNSET:
		if resolved, ok := resolve_gap_x_value(theme.gap_x); ok do return resolved

		return 0
	case .Value:
		#partial switch v in gap.value {
		case Inherit:
			return parent
		}
		if resolved, ok := resolve_child_gap_x(gap.value, state, event); ok do return resolved
		if resolved, ok := resolve_gap_x_value(gap.value); ok do return resolved
	}

	return 0
}

/*
Resolves a Cfg(Gap_Y) field.

UNSET uses the theme gap when set, otherwise 0. Gap does not inherit from the
parent unless the value is explicitly `.INHERIT`.
*/
@(private)
resolve_cfg_gap_y :: proc(
	gap: Cfg(Gap_Y),
	parent: u16,
	state: ^$S,
	event: Widget_Event(S),
) -> u16 {
	switch gap.mode {
	case .UNSET:
		if resolved, ok := resolve_gap_y_value(theme.gap_y); ok do return resolved

		return 0
	case .Value:
		#partial switch v in gap.value {
		case Inherit:
			return parent
		}
		if resolved, ok := resolve_child_gap_y(gap.value, state, event); ok do return resolved
		if resolved, ok := resolve_gap_y_value(gap.value); ok do return resolved
	}

	return 0
}

/*
Resolves a Cfg(Widget_Direction) field from theme, parent, or explicit value.
*/
@(private)
resolve_cfg_direction :: proc(
	direction: Cfg(Widget_Direction),
	parent: Direction_Layout,
	state: ^$S,
	event: Widget_Event(S),
) -> Direction_Layout {
	switch direction.mode {
	case .UNSET:
		if resolved, ok := resolve_direction_value(theme.direction); ok do return resolved
		return parent
	case .Value:
		#partial switch v in direction.value {
		case Inherit:
			return parent
		}
		if layout, layout_ok := resolve_direction_value(direction.value); layout_ok do return layout
		if dir, ok := resolve_direction(direction.value, state, event); ok {
			if layout, layout_ok := resolve_direction_value(dir); layout_ok do return layout
		}
	}
	return parent
}

/*
Resolves a Cfg(Justify) field from theme, parent, or explicit value.
*/
@(private)
resolve_cfg_justify :: proc(
	justify: Cfg(Justify),
	parent: Justify_Pos,
	state: ^$S,
	event: Widget_Event(S),
) -> Justify_Pos {
	switch justify.mode {
	case .UNSET:
		if resolved, ok := resolve_justify_value(theme.justify); ok do return resolved
		return parent
	case .Value:
		#partial switch v in justify.value {
		case Inherit:
			return parent
		}
		if resolved, ok := resolve_align(justify.value, state, event); ok do return resolved
		if resolved, ok := resolve_justify_value(justify.value); ok do return resolved
	}
	return parent
}

/*
Resolves a Cfg(Justify) self-alignment override on a child widget.
*/
@(private)
resolve_cfg_self :: proc(self: Cfg(Justify), state: ^$S, event: Widget_Event(S)) -> Justify_Pos {
	switch self.mode {
	case .UNSET:
		return {}
	case .Value:
		#partial switch v in self.value {
		case Inherit:
			return {}
		case Justify_Pos:
			if resolved, ok := resolve_justify_pos_partial(v); ok do return resolved
		}
		if resolved, ok := resolve_align(self.value, state, event); ok do return resolved
		if resolved, ok := resolve_justify_value(self.value); ok do return resolved
	}
	return {}
}

/*
Resolves a Cfg(Colors) field, handling inherit and proc-valued colors.
*/
@(private)
resolve_cfg_colors :: proc(
	field: Cfg(Colors),
	parent: Colors,
	state: ^$S,
	event: Widget_Event(S),
) -> Colors {
	switch field.mode {
	case .UNSET:
		return parent
	case .Value:
		#partial switch v in field.value {
		case Color:
			if v == .INHERIT do return parent
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Colors:
			return field.value
		}
		if rgba, ok := to_rgba(field.value, state, event); ok do return rgba
		return field.value
	}
	return parent
}

@(private)
theme_widget_style_cache: Resolved_Widget_Style
@(private)
theme_widget_style_cache_valid: bool
@(private)
theme_widget_style_cache_sig: u64

/*
Builds a signature of theme fields that feed theme_widget_style.

Hashes the whole Theme so in-place mutations bust the memo without an explicit
invalidate call.
*/
@(private)
theme_widget_style_signature :: proc() -> u64 {
	if theme == nil do return 0
	bytes := mem.byte_slice(rawptr(theme), size_of(Theme))
	return hash.fnv64a(bytes)
}

/*
Invalidates the memoized theme widget style base.

Call when the active theme pointer changes (bind / hot reload).
*/
theme_widget_style_invalidate :: proc() {
	theme_widget_style_cache_valid = false
	theme_widget_style_cache_sig = 0
}

/*
Builds default resolved widget style values from the active theme.

Memoized while the theme fields that feed this proc are unchanged.
*/
@(private)
theme_widget_style :: proc() -> Resolved_Widget_Style {
	sig := theme_widget_style_signature()
	if theme_widget_style_cache_valid && theme_widget_style_cache_sig == sig {
		return theme_widget_style_cache
	}

	gap_x: u16
	if resolved_gap_x, ok := resolve_gap_x_value(theme.gap_x); ok {
		gap_x = resolved_gap_x
	}

	gap_y: u16
	if resolved_gap_y, ok := resolve_gap_y_value(theme.gap_y); ok {
		gap_y = resolved_gap_y
	}

	justify := Justify_Pos {
		x = .START,
		y = .START,
	}
	if resolved_justify, ok := resolve_justify_value(theme.justify); ok {
		justify = resolved_justify
	}

	direction := Direction_Layout.HORIZONTAL
	if resolved_direction, ok := resolve_direction_value(theme.direction); ok {
		direction = resolved_direction
	}

	theme_widget_style_cache = Resolved_Widget_Style {
		font                  = theme.font_body,
		font_size             = theme.font_body.size_px,
		font_weight           = Font_Weights.Normal,
		font_style            = Font_Styles.NORMAL,
		color                 = theme.palette[.FOREGROUND],
		background            = theme.background,
		border                = theme.border,
		border_color          = theme.border_color,
		margin                = theme.margin,
		padding               = theme.padding,
		radius                = theme.radius,
		gap_x                 = gap_x,
		gap_y                 = gap_y,
		direction             = direction,
		justify               = justify,
		line_height           = 1,
		letter_spacing        = 0,
		align                 = .LEFT,
		wrap                  = .BALANCE,
		text_decoration       = Text_Decoration_Lines{},
		text_decoration_style = Text_Decoration_Style_Kind.SOLID,
		text_decoration_color = Color.INHERIT,
		text_direction        = Text_Direction_Kind.LTR,
		space                 = .SCREEN,
		texture_fit           = .FILL,
		texture_pos           = {},
		position              = .RELATIVE,
		visibility            = .VISIBLE,
		pointer_events        = .AUTO,
		opacity               = 1,
		order                 = 0,
		z_index               = 0,
		tab_size              = DEFAULT_TAB_SIZE,
		word_spacing          = 0,
		grid_auto_flow        = .ROW,
	}
	theme_widget_style_cache_valid = true
	theme_widget_style_cache_sig = sig
	return theme_widget_style_cache
}

/*
Merges override widget config fields into a base config.

Only non-unset Cfg fields and explicit width/height override the base.
*/
merge_widget_config :: proc(base, override: Widget_Config) -> Widget_Config {
	result := base

	if override.id != "" do result.id = override.id

	// Author/composed kinds override theme defaults. Zero value `.RECT` means unset.
	if override.kind != .RECT do result.kind = override.kind

	merge_cfg(Text_Align, &result.align, override.align)
	merge_cfg(Style_Bool, &result.auto_focus, override.auto_focus)
	merge_cfg(Style_Bool, &result.tabbable, override.tabbable)

	if override.accepts_text_input do result.accepts_text_input = true

	merge_cfg(Colors, &result.background, override.background)
	merge_cfg(Border, &result.border, override.border)
	merge_cfg(Colors, &result.border_color, override.border_color)
	merge_cfg(Colors, &result.color, override.color)
	merge_cfg(Widget_Direction, &result.direction, override.direction)
	merge_cfg(Style_Bool, &result.disabled, override.disabled)
	merge_cfg(Style_F32, &result.flex, override.flex)
	merge_cfg(Style_Font, &result.font, override.font)
	merge_cfg(Style_F32, &result.font_size, override.font_size)
	merge_cfg(Font_Style, &result.font_style, override.font_style)
	merge_cfg(Font_Weight, &result.font_weight, override.font_weight)
	merge_cfg(Gap_X, &result.gap_x, override.gap_x)
	merge_cfg(Gap_Y, &result.gap_y, override.gap_y)

	if cfg_height_is_set(override.height) do result.height = override.height

	merge_cfg(Justify, &result.justify, override.justify)
	merge_cfg(Style_F32, &result.letter_spacing, override.letter_spacing)
	merge_cfg(Style_F32, &result.line_height, override.line_height)
	merge_cfg(Style_F32, &result.max_h, override.max_h)
	merge_cfg(Style_F32, &result.max_w, override.max_w)
	merge_cfg(Style_F32, &result.min_h, override.min_h)
	merge_cfg(Style_F32, &result.min_w, override.min_w)
	merge_cfg(Style_F32, &result.order, override.order)
	merge_cfg(Margin, &result.margin, override.margin)
	merge_cfg(Padding, &result.padding, override.padding)
	merge_cfg(Pointer_Events, &result.pointer_events, override.pointer_events)
	merge_cfg(Radius, &result.radius, override.radius)
	merge_cfg(Style_Space, &result.space, override.space)
	merge_cfg(Text_Decoration, &result.text_decoration, override.text_decoration)
	merge_cfg(Colors, &result.text_decoration_color, override.text_decoration_color)
	merge_cfg(Text_Decoration_Style, &result.text_decoration_style, override.text_decoration_style)
	merge_cfg(Text_Direction, &result.text_direction, override.text_direction)

	if cfg_width_is_set(override.width) do result.width = override.width

	merge_cfg(Text_Wrap, &result.wrap, override.wrap)
	merge_cfg(Style_F32, &result.tab_size, override.tab_size)
	merge_cfg(Style_F32, &result.word_spacing, override.word_spacing)
	merge_cfg(Style_F32, &result.x, override.x)
	merge_cfg(Style_F32, &result.y, override.y)
	merge_cfg(Style_F32, &result.right, override.right)
	merge_cfg(Style_F32, &result.bottom, override.bottom)
	merge_cfg(Overflow, &result.overflow_x, override.overflow_x)
	merge_cfg(Overflow, &result.overflow_y, override.overflow_y)
	merge_cfg(Style_F32, &result.opacity, override.opacity)
	merge_cfg(Visibility, &result.visibility, override.visibility)
	merge_cfg(Style_F32, &result.z_index, override.z_index)
	merge_cfg(Position, &result.position, override.position)
	merge_cfg(Justify, &result.self, override.self)
	merge_cfg(Style_Texture_Fit, &result.texture_fit, override.texture_fit)
	merge_cfg(Style_Texture_Pos, &result.texture_pos, override.texture_pos)

	if scroll_value_is_set(override.scroll_x) do result.scroll_x = override.scroll_x
	if scroll_value_is_set(override.scroll_y) do result.scroll_y = override.scroll_y

	merge_cfg(Grid_Template_Columns, &result.grid_template_columns, override.grid_template_columns)
	merge_cfg(Grid_Template_Rows, &result.grid_template_rows, override.grid_template_rows)
	merge_cfg(Grid_Auto_Track, &result.grid_auto_columns, override.grid_auto_columns)
	merge_cfg(Grid_Auto_Track, &result.grid_auto_rows, override.grid_auto_rows)
	merge_cfg(Grid_Auto_Flow, &result.grid_auto_flow, override.grid_auto_flow)
	merge_cfg(string, &result.grid_template_areas, override.grid_template_areas)
	merge_cfg(Grid_Line_Value, &result.grid_column_start, override.grid_column_start)
	merge_cfg(Grid_Line_Value, &result.grid_column_end, override.grid_column_end)
	merge_cfg(Grid_Line_Value, &result.grid_row_start, override.grid_row_start)
	merge_cfg(Grid_Line_Value, &result.grid_row_end, override.grid_row_end)
	merge_cfg(string, &result.grid_column, override.grid_column)
	merge_cfg(string, &result.grid_row, override.grid_row)
	merge_cfg(string, &result.grid_area, override.grid_area)

	return result
}

/*
Evaluates proc-valued style fields on a resolved config in place.

Resolves margin, padding, radius, border, colors, text, overflow, and texture fields.
*/
@(private)
finalize_resolved_procs :: proc(
	config: ^Resolved_Widget_Config,
	state: ^$S,
	event: Widget_Event(S),
) {
	if margin, margin_ok := resolve_margin(config.margin, state, event); margin_ok {
		config.margin = margin_px_to_mg(margin)
	}
	if padding, padding_ok := resolve_padding(config.padding, state, event); padding_ok {
		config.padding = padding_px_to_pd(padding)
	}
	if radius, radius_ok := resolve_radius(config.radius, state, event); radius_ok {
		config.radius = radius_px_to_corners(radius)
	}
	if border, border_ok := resolve_border(config.border, state, event); border_ok {
		config.border = border_px_to_bd(border)
	}
	if !colors_is_proc(config.border_color) {
		if color, color_ok := to_rgba(config.border_color, state, event); color_ok {
			config.border_color = color
		}
	}
	if !colors_is_proc(config.background) {
		if background, bg_ok := to_rgba(config.background, state, event); bg_ok {
			config.background = background
		}
	}
	if !colors_is_proc(config.color) {
		if color, color_ok := to_rgba(config.color, state, event); color_ok {
			config.color = color
		}
	}
	if align, align_ok := resolve_text_align(config.align, state, event); align_ok {
		config.align = align
	}
	if wrap, wrap_ok := resolve_text_wrap(config.wrap, state, event); wrap_ok {
		config.wrap = wrap
	}
	if decoration, decoration_ok := resolve_text_decoration(config.text_decoration, state, event);
	   decoration_ok {
		config.text_decoration = decoration
	}
	if deco_style, deco_style_ok := resolve_text_decoration_style(
		config.text_decoration_style,
		state,
		event,
	); deco_style_ok {
		config.text_decoration_style = deco_style
	}
	if !colors_is_proc(config.text_decoration_color) {
		if color, color_ok := to_rgba(config.text_decoration_color, state, event); color_ok {
			#partial switch v in config.text_decoration_color {
			case Color:
				if v != .INHERIT {
					config.text_decoration_color = color
				}
			case:
				config.text_decoration_color = color
			}
		}
	}
	if direction, direction_ok := resolve_text_direction(config.text_direction, state, event);
	   direction_ok {
		config.text_direction = direction
	}
	if weight, weight_ok := resolve_font_weight(config.font_weight, state, event); weight_ok {
		config.font_weight = weight
	}
	if font_style, font_style_ok := resolve_font_style(config.font_style, state, event);
	   font_style_ok {
		config.font_style = font_style
	}
	if overflow, overflow_ok := resolve_overflow(config.overflow_x, state, event); overflow_ok {
		config.overflow_x = overflow
	}
	if overflow, overflow_ok := resolve_overflow(config.overflow_y, state, event); overflow_ok {
		config.overflow_y = overflow
	}
	if visibility, visibility_ok := resolve_visibility(config.visibility, state, event);
	   visibility_ok {
		config.visibility = visibility
	}
	if position, position_ok := resolve_position(config.position, state, event); position_ok {
		config.position = position
	}
	if pointer_events, pointer_ok := resolve_pointer_events(config.pointer_events, state, event);
	   pointer_ok {
		config.pointer_events = pointer_events
	}
	if fit, fit_ok := resolve_texture_fit(config.texture_fit, state, event); fit_ok {
		config.texture_fit = fit
	}
	if pos, pos_ok := resolve_texture_pos(config.texture_pos, state, event); pos_ok {
		config.texture_pos = pos
	}
}

/*
Resolves font weight, evaluating proc callbacks when present.
*/
@(private)
resolve_font_weight :: proc(
	weight: Font_Weight,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Font_Weight,
	bool,
) {
	switch v in weight {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Font_Weight:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_font_weight(v(ui_state, ui_event), state, event)
	case Font_Weights:
		return v, true
	case f32:
		return v, true
	}
	return {}, false
}

/*
Resolves font style, evaluating proc callbacks when present.
*/
@(private)
resolve_font_style :: proc(
	style: Font_Style,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Font_Style,
	bool,
) {
	switch v in style {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Font_Style:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_font_style(v(ui_state, ui_event), state, event)
	case Font_Styles:
		return v, true
	}
	return {}, false
}

/*
Resolves text alignment, evaluating proc callbacks when present.
*/
@(private)
resolve_text_align :: proc(
	align: Text_Align,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Align,
	bool,
) {
	#partial switch v in align {
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Text_Align:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_align(v(ui_state, ui_event), state, event)
	case Text_Align_Kind:
		return v, true
	}
	return {}, false
}


/*
Resolves text wrap mode, evaluating proc callbacks when present.
*/
@(private)
resolve_text_wrap :: proc(
	wrap: Text_Wrap,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Wrap,
	bool,
) {
	#partial switch v in wrap {
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Text_Wrap:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_wrap(v(ui_state, ui_event), state, event)
	case Text_Wrap_Kind:
		return v, true
	}
	return {}, false
}

/*
Resolves text decoration lines, evaluating proc callbacks when present.
*/
@(private)
resolve_text_decoration :: proc(
	decoration: Text_Decoration,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Decoration,
	bool,
) {
	#partial switch v in decoration {
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Text_Decoration:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_decoration(v(ui_state, ui_event), state, event)
	case Text_Decoration_Lines:
		return v, true
	}
	return {}, false
}

/*
Resolves text decoration style, evaluating proc callbacks when present.
*/
@(private)
resolve_text_decoration_style :: proc(
	style: Text_Decoration_Style,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Decoration_Style,
	bool,
) {
	#partial switch v in style {
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Text_Decoration_Style:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_decoration_style(v(ui_state, ui_event), state, event)
	case Text_Decoration_Style_Kind:
		return v, true
	}
	return {}, false
}

/*
Resolves text direction, evaluating proc callbacks when present.
*/
@(private)
resolve_text_direction :: proc(
	direction: Text_Direction,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Direction,
	bool,
) {
	#partial switch v in direction {
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Text_Direction:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_direction(v(ui_state, ui_event), state, event)
	case Text_Direction_Kind:
		return v, true
	}
	return {}, false
}

/*
Resolves overflow mode, evaluating proc callbacks when present.
*/
@(private)
resolve_overflow :: proc(
	overflow: Overflow,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Overflow,
	bool,
) {
	#partial switch v in overflow {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Overflow:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_overflow(v(ui_state, ui_event), state, event)
	}
	return overflow, true
}

/*
Resolves visibility mode, evaluating proc callbacks when present.
*/
@(private)
resolve_visibility :: proc(
	visibility: Visibility,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Visibility,
	bool,
) {
	#partial switch v in visibility {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Visibility:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_visibility(v(ui_state, ui_event), state, event)
	}
	return visibility, true
}

/*
Resolves CSS-like position mode, evaluating proc callbacks when present.
*/
@(private)
resolve_position :: proc(
	position: Position,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Position,
	bool,
) {
	#partial switch v in position {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Position:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_position(v(ui_state, ui_event), state, event)
	}
	return position, true
}

/*
Resolves pointer-events mode, evaluating proc callbacks when present.
*/
@(private)
resolve_pointer_events :: proc(
	pointer_events: Pointer_Events,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Pointer_Events,
	bool,
) {
	#partial switch v in pointer_events {
	case Inherit:
		return {}, false
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Pointer_Events:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_pointer_events(v(ui_state, ui_event), state, event)
	}
	return pointer_events, true
}

/*
Merges base and override configs, then resolves style against parent and theme.

Returns a fully resolved widget config ready for layout and draw.
*/
resolve_widget_config :: proc(
	base: Widget_Config,
	override: Widget_Config,
	state: ^$S,
	event: Widget_Event(S),
) -> Resolved_Widget_Config {
	parent_ctx := ui_style_current()
	parent := parent_ctx.style
	theme := theme_widget_style()

	decl := merge_widget_config(base, override)

	style := Resolved_Widget_Style {
		align                 = resolve_cfg(Text_Align, decl.align, parent.align, theme.align),
		auto_focus            = resolve_cfg_bool(
			decl.auto_focus,
			parent.auto_focus,
			theme.auto_focus,
		),
		background            = resolve_cfg_colors(
			decl.background,
			parent.background,
			state,
			event,
		),
		border                = resolve_cfg(Border, decl.border, parent.border, theme.border),
		border_color          = resolve_cfg_colors(
			decl.border_color,
			parent.border_color,
			state,
			event,
		),
		color                 = resolve_cfg_colors(decl.color, parent.color, state, event),
		direction             = resolve_cfg_direction(
			decl.direction,
			parent.direction,
			state,
			event,
		),
		disabled              = resolve_cfg_bool(decl.disabled, parent.disabled, theme.disabled),
		flex                  = resolve_cfg_f32(decl.flex, parent.flex, theme.flex, state, event),
		font                  = resolve_cfg_font(decl.font, parent.font, theme.font),
		font_size             = resolve_cfg_f32(
			decl.font_size,
			parent.font_size,
			theme.font_size,
			state,
			event,
		),
		font_style            = resolve_cfg(
			Font_Style,
			decl.font_style,
			parent.font_style,
			theme.font_style,
		),
		font_weight           = resolve_cfg(
			Font_Weight,
			decl.font_weight,
			parent.font_weight,
			theme.font_weight,
		),
		gap_x                 = resolve_cfg_gap_x(decl.gap_x, parent.gap_x, state, event),
		gap_y                 = resolve_cfg_gap_y(decl.gap_y, parent.gap_y, state, event),
		height                = resolve_length_from_height(
			decl.height,
			parent_ctx.content_h,
			state,
			event,
		),
		justify               = resolve_cfg_justify(decl.justify, parent.justify, state, event),
		letter_spacing        = resolve_cfg_f32(
			decl.letter_spacing,
			parent.letter_spacing,
			theme.letter_spacing,
			state,
			event,
		),
		line_height           = resolve_cfg_f32(
			decl.line_height,
			parent.line_height,
			theme.line_height,
			state,
			event,
		),
		max_h                 = resolve_cfg_f32(
			decl.max_h,
			parent.max_h,
			theme.max_h,
			state,
			event,
		),
		max_w                 = resolve_cfg_f32(
			decl.max_w,
			parent.max_w,
			theme.max_w,
			state,
			event,
		),
		min_h                 = resolve_cfg_f32(
			decl.min_h,
			parent.min_h,
			theme.min_h,
			state,
			event,
		),
		min_w                 = resolve_cfg_f32(
			decl.min_w,
			parent.min_w,
			theme.min_w,
			state,
			event,
		),
		order                 = resolve_cfg_f32(
			decl.order,
			parent.order,
			theme.order,
			state,
			event,
		),
		margin                = resolve_cfg(Margin, decl.margin, parent.margin, theme.margin),
		padding               = resolve_cfg(Padding, decl.padding, parent.padding, theme.padding),
		pointer_events        = resolve_cfg(
			Pointer_Events,
			decl.pointer_events,
			parent.pointer_events,
			theme.pointer_events,
		),
		radius                = resolve_cfg(Radius, decl.radius, parent.radius, theme.radius),
		space                 = resolve_cfg_space(decl.space, parent.space, theme.space),
		text_decoration       = resolve_cfg(
			Text_Decoration,
			decl.text_decoration,
			parent.text_decoration,
			theme.text_decoration,
		),
		text_decoration_color = resolve_cfg_colors(
			decl.text_decoration_color,
			parent.text_decoration_color,
			state,
			event,
		),
		text_decoration_style = resolve_cfg(
			Text_Decoration_Style,
			decl.text_decoration_style,
			parent.text_decoration_style,
			theme.text_decoration_style,
		),
		text_direction        = resolve_cfg(
			Text_Direction,
			decl.text_direction,
			parent.text_direction,
			theme.text_direction,
		),
		width                 = resolve_length_from_width(
			decl.width,
			parent_ctx.content_w,
			state,
			event,
		),
		wrap                  = resolve_cfg_inherited(
			Text_Wrap,
			decl.wrap,
			parent.wrap,
			theme.wrap,
		),
		tab_size              = resolve_cfg_f32(
			decl.tab_size,
			parent.tab_size,
			theme.tab_size,
			state,
			event,
		),
		word_spacing          = resolve_cfg_f32(
			decl.word_spacing,
			parent.word_spacing,
			theme.word_spacing,
			state,
			event,
		),
		x                     = resolve_cfg_f32(decl.x, parent.x, theme.x, state, event),
		y                     = resolve_cfg_f32(decl.y, parent.y, theme.y, state, event),
		right                 = resolve_cfg_f32(
			decl.right,
			parent.right,
			theme.right,
			state,
			event,
		),
		bottom                = resolve_cfg_f32(
			decl.bottom,
			parent.bottom,
			theme.bottom,
			state,
			event,
		),
		x_set                 = cfg_f32_is_set(decl.x, parent.x_set),
		y_set                 = cfg_f32_is_set(decl.y, parent.y_set),
		right_set             = cfg_f32_is_set(decl.right, parent.right_set),
		bottom_set            = cfg_f32_is_set(decl.bottom, parent.bottom_set),
		overflow_x            = resolve_cfg(
			Overflow,
			decl.overflow_x,
			parent.overflow_x,
			theme.overflow_x,
		),
		overflow_y            = resolve_cfg(
			Overflow,
			decl.overflow_y,
			parent.overflow_y,
			theme.overflow_y,
		),
		opacity               = clamp_opacity(
			resolve_cfg_f32(decl.opacity, parent.opacity, theme.opacity, state, event),
		),
		visibility            = resolve_cfg(
			Visibility,
			decl.visibility,
			parent.visibility,
			theme.visibility,
		),
		z_index               = resolve_cfg_f32(
			decl.z_index,
			parent.z_index,
			theme.z_index,
			state,
			event,
		),
		position              = resolve_cfg(
			Position,
			decl.position,
			parent.position,
			theme.position,
		),
		self                  = resolve_cfg_self(decl.self, state, event),
		texture_fit           = resolve_cfg(
			Style_Texture_Fit,
			decl.texture_fit,
			parent.texture_fit,
			theme.texture_fit,
		),
		texture_pos           = resolve_cfg(
			Style_Texture_Pos,
			decl.texture_pos,
			parent.texture_pos,
			theme.texture_pos,
		),
		tabbable              = resolve_cfg_bool(decl.tabbable, parent.tabbable, theme.tabbable),
		accepts_text_input    = decl.accepts_text_input,
		scroll_x              = 0,
		scroll_y              = 0,
		grid_template_columns = resolve_cfg_grid_template_columns(
			decl.grid_template_columns,
			parent.grid_template_columns,
			theme.grid_template_columns,
			state,
			event,
		),
		grid_template_rows    = resolve_cfg_grid_template_rows(
			decl.grid_template_rows,
			parent.grid_template_rows,
			theme.grid_template_rows,
			state,
			event,
		),
		grid_auto_columns     = resolve_cfg_grid_auto_track(
			decl.grid_auto_columns,
			parent.grid_auto_columns,
			theme.grid_auto_columns,
			state,
			event,
		),
		grid_auto_rows        = resolve_cfg_grid_auto_track(
			decl.grid_auto_rows,
			parent.grid_auto_rows,
			theme.grid_auto_rows,
			state,
			event,
		),
		grid_auto_flow        = resolve_cfg_grid_auto_flow(
			decl.grid_auto_flow,
			parent.grid_auto_flow,
			theme.grid_auto_flow,
		),
		grid_template_areas   = resolve_cfg_grid_string(
			decl.grid_template_areas,
			parent.grid_template_areas,
		),
		grid_column_start     = resolve_cfg_grid_line(
			decl.grid_column_start,
			parent.grid_column_start,
			theme.grid_column_start,
			state,
			event,
		),
		grid_column_end       = resolve_cfg_grid_line(
			decl.grid_column_end,
			parent.grid_column_end,
			theme.grid_column_end,
			state,
			event,
		),
		grid_row_start        = resolve_cfg_grid_line(
			decl.grid_row_start,
			parent.grid_row_start,
			theme.grid_row_start,
			state,
			event,
		),
		grid_row_end          = resolve_cfg_grid_line(
			decl.grid_row_end,
			parent.grid_row_end,
			theme.grid_row_end,
			state,
			event,
		),
		grid_column           = resolve_cfg_grid_string(decl.grid_column, parent.grid_column),
		grid_row              = resolve_cfg_grid_string(decl.grid_row, parent.grid_row),
		grid_area             = resolve_cfg_grid_string(decl.grid_area, parent.grid_area),
	}

	grid_apply_line_shorthands(&style)

	resolved := Resolved_Widget_Config {
		id    = decl.id,
		kind  = decl.kind,
		style = style,
	}
	finalize_resolved_procs(&resolved, state, event)
	style_cache_concrete_rgba(&resolved.style)
	return resolved
}

/*
Creates the root style context for a draw space and layout bounds.
*/
style_root :: proc(space: Draw_Space, bounds: Rect) -> Style_Context {
	style := theme_widget_style()
	style.space = space
	return Style_Context{style = style, content_w = bounds.w, content_h = bounds.h}
}

/*
Builds a child style context with content size reduced by padding and border.

When this node has a definite width/height, descendants measure against that
resolved box (minus insets) — not the parent's provisional content size. That
keeps `width = 300` sidebars from advertising the full row width to nested
`.GROW` / `.AUTO` children during bottom-up measure.

Measure-indefinite axes (`.FIT` / `.MIN_CONTENT` / `.MAX_CONTENT` / `.GROW`) are
indefinite for descendants: children measure intrinsic content instead of
stretching to the parent's provisional content size. That keeps theme
`wrap = .BALANCE` text from inflating fit/grow widgets to the full row width
during bottom-up measure.
*/
style_child_context :: proc(config: Resolved_Widget_Config) -> Style_Context {
	parent := ui_style_current()

	padding, _ := resolve_padding_value(config.padding)
	border, _ := resolve_border_value(config.border)

	inset_w := padding.l + padding.r + border.l + border.r
	inset_h := padding.t + padding.b + border.t + border.b

	content_w := max(0, parent.content_w - inset_w)
	content_h := max(0, parent.content_h - inset_h)

	if length_is_definite(config.width) {
		resolved_w := length_resolve(config.width, parent.content_w)

		if resolved_w > 0 {
			content_w = max(0, resolved_w - inset_w)
		}
	}

	if length_is_definite(config.height) {
		resolved_h := length_resolve(config.height, parent.content_h)

		if resolved_h > 0 {
			content_h = max(0, resolved_h - inset_h)
		}
	}

	if length_is_measure_indefinite(config.width) {
		content_w = 0
	}

	if length_is_measure_indefinite(config.height) {
		content_h = 0
	}

	return Style_Context{style = config.style, content_w = content_w, content_h = content_h}
}

/*
Returns the current top-of-stack style context.

Panics if the style stack is empty.
*/
ui_style_current :: proc() -> ^Style_Context {
	assert(
		len(state.ui.style_stack) > 0,
		"style stack is empty — push a root style before building widgets",
	)
	return &state.ui.style_stack[len(state.ui.style_stack) - 1]
}

/*
Pushes a style context onto the style stack.
*/
ui_push_style :: proc(ctx: Style_Context) {
	append(&state.ui.style_stack, ctx)
}

/*
Pops the top style context from the stack.

Panics on underflow.
*/
ui_pop_style :: proc() {
	assert(len(state.ui.style_stack) > 0, "style stack underflow")
	ordered_remove(&state.ui.style_stack, len(state.ui.style_stack) - 1)
}

/*
Pushes scope, layout node, and child style when entering a container.

Called at the start of a children block during layout and draw.
*/
being_children :: proc(layout_id: UI_Id, config: Resolved_Widget_Config) {
	ui_push_scope(layout_id)
	if ui_pass() == .Layout {
		layout_push_node(layout_id, config)
	}

	pushed_draw_space := false
	if ui_pass() == .Draw && layout_space_is_layer(config.space) {
		draw_push_space(config.space)
		pushed_draw_space = true
	}

	append(&state.ui.draw_children_space_pushed, pushed_draw_space)
	ui_push_style(style_child_context(config))
}

/*
Pops child style, finalizes layout node, and pops scope when leaving a container.
*/
end_children :: proc() {
	ui_pop_style()
	if ui_pass() == .Layout {
		layout_pop_node()
	}

	if len(state.ui.draw_children_space_pushed) > 0 {
		pushed := state.ui.draw_children_space_pushed[len(state.ui.draw_children_space_pushed) - 1]
		ordered_remove(
			&state.ui.draw_children_space_pushed,
			len(state.ui.draw_children_space_pushed) - 1,
		)
		if ui_pass() == .Draw && pushed {
			draw_pop_space()
		}
	}

	ui_pop_scope()
}


/*
Runs a child builder inside a scoped layout node and style context.
*/
Children :: proc(
	child: proc(frame_state: $S),
	layout_id: UI_Id,
	config: Resolved_Widget_Config,
	state: S,
) {
	if layout_visibility_is_none(config.visibility) do return
	being_children(layout_id, config)
	if child != nil do child(state)

	end_children()
}
