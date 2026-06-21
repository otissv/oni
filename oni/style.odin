package oni

length_resolve :: proc(length: Length, parent: f32) -> f32 {
	switch length.kind {
	case .Auto:
		return 0
	case .Fixed:
		return length.value
	case .Percent:
		return parent * length.value * 0.01
	case .Inherit:
		return parent
	}
	return 0
}

length_is_definite :: proc(length: Length) -> bool {
	return length.kind != .Auto
}

@(private)
cfg_width_is_set :: proc(w: Width) -> bool {
	#partial switch _ in w {
	case struct{}:
		return false
	}
	return true
}

@(private)
cfg_height_is_set :: proc(h: Height) -> bool {
	#partial switch _ in h {
	case struct{}:
		return false
	}
	return true
}

@(private)
merge_cfg :: proc($T: typeid, dst: ^Cfg(T), src: Cfg(T)) {
	if src.mode != .Unset do dst^ = src
}

@(private)
resolve_cfg :: proc($T: typeid, field: Cfg(T), parent: T, theme_default: T) -> T {
	switch field.mode {
	case .Unset:
		return theme_default
	case .Inherit:
		return parent
	case .Value:
		return field.value
	}
	return theme_default
}

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
		return {kind = .Auto}
	case Width_Mode:
		switch v {
		case .Inherit:
			return {kind = .Inherit}
		case .Auto, .Fit_Content, .Min_Content, .Max_Content:
			return {kind = .Auto}
		}
	case f32:
		return {kind = .Fixed, value = v}
	case Dim_struct:
		if v.percent > 0 do return {kind = .Percent, value = v.percent}
		if v.min > 0 do return {kind = .Fixed, value = v.min}
		if v.max > 0 do return {kind = .Fixed, value = v.max}
		return {kind = .Auto}
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Width:
		return resolve_length_from_width(v(ui_state, ui_event), parent_w, state, event)
	}
	return {kind = .Auto}
}

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
		return {kind = .Auto}
	case Height_Mode:
		switch v {
		case .Inherit:
			return {kind = .Inherit}
		case .Auto, .Fit_Content, .Min_Content, .Max_Content:
			return {kind = .Auto}
		}
	case f32:
		return {kind = .Fixed, value = v}
	case Dim_struct:
		if v.percent > 0 do return {kind = .Percent, value = v.percent}
		if v.min > 0 do return {kind = .Fixed, value = v.min}
		if v.max > 0 do return {kind = .Fixed, value = v.max}
		return {kind = .Auto}
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Height:
		return resolve_length_from_height(v(ui_state, ui_event), parent_h, state, event)
	}
	return {kind = .Auto}
}

@(private)
resolve_cfg_gap :: proc(gap: Cfg(Gap), parent: u16, state: ^$S, event: Widget_Event(S)) -> u16 {
	switch gap.mode {
	case .Unset:
		if resolved, ok := resolve_gap_value(theme.gap); ok do return resolved
		return parent
	case .Inherit:
		return parent
	case .Value:
		if resolved, ok := resolve_child_gap(gap.value, state, event); ok do return resolved
		if resolved, ok := resolve_gap_value(gap.value); ok do return resolved
	}
	return parent
}

@(private)
resolve_cfg_direction :: proc(
	direction: Cfg(Widget_Direction),
	parent: Direction_Layout,
	state: ^$S,
	event: Widget_Event(S),
) -> Direction_Layout {
	switch direction.mode {
	case .Unset:
		if resolved, ok := resolve_direction_value(theme.direction); ok do return resolved
		return parent
	case .Inherit:
		return parent
	case .Value:
		if layout, layout_ok := resolve_direction_value(direction.value); layout_ok do return layout
		if dir, ok := resolve_direction(direction.value, state, event); ok {
			if layout, layout_ok := resolve_direction_value(dir); layout_ok do return layout
		}
	}
	return parent
}

@(private)
resolve_cfg_justify :: proc(
	justify: Cfg(Justify),
	parent: Justify_Pos,
	state: ^$S,
	event: Widget_Event(S),
) -> Justify_Pos {
	switch justify.mode {
	case .Unset:
		if resolved, ok := resolve_justify_value(theme.justify); ok do return resolved
		return parent
	case .Inherit:
		return parent
	case .Value:
		if resolved, ok := resolve_align(justify.value, state, event); ok do return resolved
		if resolved, ok := resolve_justify_value(justify.value); ok do return resolved
	}
	return parent
}

@(private)
resolve_cfg_colors :: proc(
	field: Cfg(Colors),
	parent: Colors,
	state: ^$S,
	event: Widget_Event(S),
) -> Colors {
	switch field.mode {
	case .Unset:
		return parent
	case .Inherit:
		return parent
	case .Value:
		#partial switch v in field.value {
		case Color:
			if v == .Inherit do return parent
		}
		if rgba, ok := to_rgba(field.value, state, event); ok do return rgba
		return field.value
	}
	return parent
}

@(private)
theme_widget_style :: proc() -> Resolved_Widget_Style {
	gap: u16
	if resolved_gap, ok := resolve_gap_value(theme.gap); ok {
		gap = resolved_gap
	}

	justify := Justify_Pos {
		x = .Start,
		y = .Start,
	}
	if resolved_justify, ok := resolve_justify_value(theme.justify); ok {
		justify = resolved_justify
	}

	direction := Direction_Layout.Horizontal
	if resolved_direction, ok := resolve_direction_value(theme.direction); ok {
		direction = resolved_direction
	}

	return Resolved_Widget_Style {
		font = theme.font_body,
		font_size = theme.font_body.size_px,
		color = theme.palette[.Text],
		background = theme.background,
		border = theme.border,
		border_color = theme.border_color,
		padding = theme.padding,
		radius = theme.radius,
		gap = gap,
		direction = direction,
		justify = justify,
		line_height = 1,
		text_direction = .LTR,
		space = .Screen,
	}
}

@(private)
merge_widget_decl :: proc(base, override: Widget_config) -> Widget_config {
	result := base

	if override.id != "" do result.id = override.id
	merge_cfg(Text_Align, &result.align, override.align)
	merge_cfg(Aspect_Ratio, &result.aspect_ratio, override.aspect_ratio)
	merge_cfg(bool, &result.auto_focus, override.auto_focus)
	merge_cfg(Colors, &result.background, override.background)
	merge_cfg(Border, &result.border, override.border)
	merge_cfg(Colors, &result.border_color, override.border_color)
	merge_cfg(Colors, &result.color, override.color)
	merge_cfg(Widget_Direction, &result.direction, override.direction)
	merge_cfg(bool, &result.disabled, override.disabled)
	merge_cfg(f32, &result.flex, override.flex)
	merge_cfg(Font_Handle, &result.font, override.font)
	merge_cfg(f32, &result.font_size, override.font_size)
	merge_cfg(Gap, &result.gap, override.gap)
	if cfg_height_is_set(override.height) do result.height = override.height
	merge_cfg(Justify, &result.justify, override.justify)
	merge_cfg(f32, &result.letter_spacing, override.letter_spacing)
	merge_cfg(f32, &result.line_height, override.line_height)
	merge_cfg(f32, &result.max_h, override.max_h)
	merge_cfg(f32, &result.max_w, override.max_w)
	merge_cfg(f32, &result.min_h, override.min_h)
	merge_cfg(f32, &result.min_w, override.min_w)
	merge_cfg(Padding, &result.padding, override.padding)
	merge_cfg(Radius, &result.radius, override.radius)
	merge_cfg(Draw_Space, &result.space, override.space)
	merge_cfg(Text_Direction, &result.text_direction, override.text_direction)
	if cfg_width_is_set(override.width) do result.width = override.width
	merge_cfg(Text_Warp, &result.wrap, override.wrap)
	merge_cfg(f32, &result.x, override.x)
	merge_cfg(f32, &result.y, override.y)
	merge_cfg(Overflow, &result.overflow, override.overflow)
	merge_cfg(Overflow, &result.overflow_x, override.overflow_x)
	merge_cfg(Overflow, &result.overflow_y, override.overflow_y)
	merge_cfg(Visibility, &result.visibility, override.visibility)
	merge_cfg(f32, &result.z_index, override.z_index)
	merge_cfg(Position, &result.position, override.position)

	return result
}

@(private)
finalize_resolved_procs :: proc(
	config: ^Resolved_Widget_config,
	state: ^$S,
	event: Widget_Event(S),
) {
	if padding, padding_ok := resolve_padding(config.padding, state, event); padding_ok {
		config.padding = padding
	}
	if radius, radius_ok := resolve_radius(config.radius, state, event); radius_ok {
		config.radius = radius
	}
	if border, border_ok := resolve_border(config.border, state, event); border_ok {
		config.border = border
	}
	if color, color_ok := to_rgba(config.border_color, state, event); color_ok {
		config.border_color = color
	}
	if background, bg_ok := to_rgba(config.background, state, event); bg_ok {
		config.background = background
	}
	if color, color_ok := to_rgba(config.color, state, event); color_ok {
		config.color = color
	}
	if align, align_ok := resolve_text_align(config.align, state, event); align_ok {
		config.align = align
	}
	if aspect_ratio, aspect_ok := resolve_aspect_ratio(config.aspect_ratio, state, event);
	   aspect_ok {
		config.aspect_ratio = aspect_ratio
	}
	if wrap, wrap_ok := resolve_text_warp(config.wrap, state, event); wrap_ok {
		config.wrap = wrap
	}
	if overflow, overflow_ok := resolve_overflow(config.overflow, state, event); overflow_ok {
		config.overflow = overflow
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
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Align:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_align(v(ui_state, ui_event), state, event)
	}
	#partial switch _ in align {
	case struct{}:
		return {}, false
	}
	return align, true
}

@(private)
resolve_aspect_ratio :: proc(
	aspect_ratio: Aspect_Ratio,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Aspect_Ratio,
	bool,
) {
	#partial switch v in aspect_ratio {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Aspect_Ratio:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_aspect_ratio(v(ui_state, ui_event), state, event)
	}
	#partial switch _ in aspect_ratio {
	case struct{}:
		return {}, false
	}
	return aspect_ratio, true
}

@(private)
resolve_text_warp :: proc(
	wrap: Text_Warp,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	Text_Warp,
	bool,
) {
	#partial switch v in wrap {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Warp:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_text_warp(v(ui_state, ui_event), state, event)
	}
	#partial switch _ in wrap {
	case struct{}:
		return {}, false
	}
	return wrap, true
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Overflow:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_overflow(v(ui_state, ui_event), state, event)
	}
	return overflow, true
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Visibility:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_visibility(v(ui_state, ui_event), state, event)
	}
	return visibility, true
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Position:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_position(v(ui_state, ui_event), state, event)
	}
	return position, true
}

resolve_widget_config :: proc(
	base: Widget_config,
	override: Widget_config,
	state: ^$S,
	event: Widget_Event(S),
) -> Resolved_Widget_config {
	parent_ctx := ui_style_current()
	parent := parent_ctx.style
	theme := theme_widget_style()
	decl := merge_widget_decl(base, override)

	style := Resolved_Widget_Style {
		align          = resolve_cfg(Text_Align, decl.align, parent.align, theme.align),
		aspect_ratio   = resolve_cfg(
			Aspect_Ratio,
			decl.aspect_ratio,
			parent.aspect_ratio,
			theme.aspect_ratio,
		),
		auto_focus     = resolve_cfg(bool, decl.auto_focus, parent.auto_focus, theme.auto_focus),
		background     = resolve_cfg_colors(decl.background, parent.background, state, event),
		border         = resolve_cfg(Border, decl.border, parent.border, theme.border),
		border_color   = resolve_cfg_colors(decl.border_color, parent.border_color, state, event),
		color          = resolve_cfg_colors(decl.color, parent.color, state, event),
		direction      = resolve_cfg_direction(decl.direction, parent.direction, state, event),
		disabled       = resolve_cfg(bool, decl.disabled, parent.disabled, theme.disabled),
		flex           = resolve_cfg(f32, decl.flex, parent.flex, theme.flex),
		font           = resolve_cfg(Font_Handle, decl.font, parent.font, theme.font),
		font_size      = resolve_cfg(f32, decl.font_size, parent.font_size, theme.font_size),
		gap            = resolve_cfg_gap(decl.gap, parent.gap, state, event),
		height         = resolve_length_from_height(
			decl.height,
			parent_ctx.content_h,
			state,
			event,
		),
		justify        = resolve_cfg_justify(decl.justify, parent.justify, state, event),
		letter_spacing = resolve_cfg(
			f32,
			decl.letter_spacing,
			parent.letter_spacing,
			theme.letter_spacing,
		),
		line_height    = resolve_cfg(f32, decl.line_height, parent.line_height, theme.line_height),
		max_h          = resolve_cfg(f32, decl.max_h, parent.max_h, theme.max_h),
		max_w          = resolve_cfg(f32, decl.max_w, parent.max_w, theme.max_w),
		min_h          = resolve_cfg(f32, decl.min_h, parent.min_h, theme.min_h),
		min_w          = resolve_cfg(f32, decl.min_w, parent.min_w, theme.min_w),
		padding        = resolve_cfg(Padding, decl.padding, parent.padding, theme.padding),
		radius         = resolve_cfg(Radius, decl.radius, parent.radius, theme.radius),
		space          = resolve_cfg(Draw_Space, decl.space, parent.space, theme.space),
		text_direction = resolve_cfg(
			Text_Direction,
			decl.text_direction,
			parent.text_direction,
			theme.text_direction,
		),
		width          = resolve_length_from_width(decl.width, parent_ctx.content_w, state, event),
		wrap           = resolve_cfg(Text_Warp, decl.wrap, parent.wrap, theme.wrap),
		x              = resolve_cfg(f32, decl.x, parent.x, theme.x),
		y              = resolve_cfg(f32, decl.y, parent.y, theme.y),
		overflow       = resolve_cfg(Overflow, decl.overflow, parent.overflow, theme.overflow),
		overflow_x     = resolve_cfg(
			Overflow,
			decl.overflow_x,
			parent.overflow_x,
			theme.overflow_x,
		),
		overflow_y     = resolve_cfg(
			Overflow,
			decl.overflow_y,
			parent.overflow_y,
			theme.overflow_y,
		),
		visibility     = resolve_cfg(
			Visibility,
			decl.visibility,
			parent.visibility,
			theme.visibility,
		),
		z_index        = resolve_cfg(f32, decl.z_index, parent.z_index, theme.z_index),
		position       = resolve_cfg(Position, decl.position, parent.position, theme.position),
	}

	resolved := Resolved_Widget_config {
		id    = decl.id,
		kind  = decl.kind,
		style = style,
	}
	finalize_resolved_procs(&resolved, state, event)
	return resolved
}

style_root :: proc(space: Draw_Space, bounds: Rect) -> Style_Context {
	style := theme_widget_style()
	style.space = space
	return Style_Context{style = style, content_w = bounds.w, content_h = bounds.h}
}

style_child_context :: proc(config: Resolved_Widget_config) -> Style_Context {
	parent := ui_style_current()

	padding, _ := resolve_padding_value(config.padding)
	border, _ := resolve_border_value(config.border)

	inset_w := padding.l + padding.r + border.l + border.r
	inset_h := padding.t + padding.b + border.t + border.b

	return Style_Context {
		style = config.style,
		content_w = max(0, parent.content_w - inset_w),
		content_h = max(0, parent.content_h - inset_h),
	}
}

ui_style_current :: proc() -> ^Style_Context {
	assert(
		len(state.ui.style_stack) > 0,
		"style stack is empty — push a root style before building widgets",
	)
	return &state.ui.style_stack[len(state.ui.style_stack) - 1]
}

ui_push_style :: proc(ctx: Style_Context) {
	append(&state.ui.style_stack, ctx)
}

ui_pop_style :: proc() {
	assert(len(state.ui.style_stack) > 0, "style stack underflow")
	ordered_remove(&state.ui.style_stack, len(state.ui.style_stack) - 1)
}

being_children :: proc(layout_id: UI_Id, config: Resolved_Widget_config) {
	ui_push_scope(layout_id)
	if ui_pass() == .Layout {
		layout_push_node(layout_id, config)
	}
	ui_push_style(style_child_context(config))
}

end_children :: proc() {
	ui_pop_style()
	if ui_pass() == .Layout {
		layout_pop_node()
	}
	ui_pop_scope()
}
