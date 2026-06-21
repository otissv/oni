package widgets

import oni ".."
import set "../set"
import sdl "vendor:sdl3"

Text_Variant :: enum {
	DEFAULT,
	H1,
	H2,
	H3,
	H4,
	H5,
	H6,
}

Text_Size :: enum {
	Default,
	Small,
	Large,
	Icon,
}

Text_Config :: struct {
	using _: oni.Widget_Config,
	flags:   oni.Widget_Text_Flags,
	size:    Text_Size,
	text:    string,
	variant: Text_Variant,
}

Text_State :: struct {
	using _: oni.Widget_State,
}

Text_Merged_State :: struct {
	using state: Text_State,
	style:       oni.Resolved_Widget_Config,
	flags:       oni.Widget_Text_Flags,
	text:        string,
}

Text_Event :: oni.Widget_Event(Text_Merged_State)

Text_Props :: struct {
	using _:           Text_Config,
	on_focus:          proc(state: Text_State, event: Text_Event),
	on_blur:           proc(state: Text_State, event: Text_Event),
	on_mouse_enter:    proc(state: Text_State, event: Text_Event),
	on_mouse_leave:    proc(state: Text_State, event: Text_Event),
	on_mouse_pressed:  proc(state: Text_State, event: Text_Event),
	on_mouse_down:     proc(state: Text_State, event: Text_Event),
	on_mouse_released: proc(state: Text_State, event: Text_Event),
	on_mouse_move:     proc(state: Text_State, event: Text_Event),
	on_click:          proc(state: Text_State, event: Text_Event),
	on_contextmenu:    proc(state: Text_State, event: Text_Event),
	on_key_pressed:    proc(state: Text_State, event: Text_Event),
	on_key_down:       proc(state: Text_State, event: Text_Event),
	on_key_released:   proc(state: Text_State, event: Text_Event),
}

@(private)
text_event :: proc(
	state: Text_Merged_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Text_Event {
	return {state = state, mouse_button = mouse_button, key = key}
}

@(private)
text_decl_font_size :: proc(field: oni.Cfg(f32)) -> f32 {
	if field.mode == .Value do return field.value
	return 0
}

@(private)
text_set_font_size :: proc(field: ^oni.Cfg(f32), size: f32) {
	field^ = set.F32(size)
}

@(private)
text_apply_variant :: proc(config: ^Text_Config) {
	if config.variant == .DEFAULT do return

	config.font = set.Font(oni.theme.font_heading)
	switch config.variant {
	case .DEFAULT:
	case .H1:
		text_set_font_size(&config.font_size, 32)
	case .H2:
		text_set_font_size(&config.font_size, 28)
	case .H3:
		text_set_font_size(&config.font_size, 24)
	case .H4:
		text_set_font_size(&config.font_size, 20)
	case .H5:
		text_set_font_size(&config.font_size, 18)
	case .H6:
		text_set_font_size(&config.font_size, 16)
	}
}

@(private)
text_apply_size :: proc(config: ^Text_Config) {
	current := text_decl_font_size(config.font_size)
	switch config.size {
	case .Default:
	case .Small:
		text_set_font_size(
			&config.font_size,
			current > 0 ? current * 0.875 : oni.theme.font_body.size_px * 0.875,
		)
	case .Large:
		text_set_font_size(
			&config.font_size,
			current > 0 ? current * 1.25 : oni.theme.font_body.size_px * 1.25,
		)
	case .Icon:
		text_set_font_size(&config.font_size, 14)
	}
}

@(private)
text_props_override :: proc(props: Text_Props) -> Text_Config {
	return Text_Config {
		id = props.id,
		x = props.x,
		y = props.y,
		width = props.width,
		height = props.height,
		text = props.text,
		flags = props.flags,
		max_w = props.max_w,
		size = props.size,
		variant = props.variant,
		align = props.align,
		justify = props.justify,
		aspect_ratio = props.aspect_ratio,
		auto_focus = props.auto_focus,
		border = props.border,
		border_color = props.border_color,
		background = props.background,
		gap = props.gap,
		color = props.color,
		text_direction = props.text_direction,
		direction = props.direction,
		disabled = props.disabled,
		font = props.font,
		font_size = props.font_size,
		letter_spacing = props.letter_spacing,
		line_height = props.line_height,
		padding = props.padding,
		radius = props.radius,
		space = props.space,
		wrap = props.wrap,
	}
}

@(private)
text_widget_decl :: proc(state: ^Text_Merged_State) -> Text_Config {
	color := oni.Color.Text

	if state.is_disabled {
		color = oni.Color.Text_muted
	}

	return Text_Config {
		kind = .TEXT,
		font = set.Font(oni.theme.font_body),
		font_size = set.F32(oni.theme.font_body.size_px),
		color = set.Colors(color),
		line_height = set.F32(1),
		text_direction = set.Text_Direction(.LTR),
		space = set.Inherit_Space(),
		justify = set.Justify(oni.theme.justify),
		gap = set.Gap(oni.theme.gap),
	}
}

@(private)
text_refresh_merged :: proc(props: Text_Props, state: ^Text_Merged_State) -> Text_Event {
	event := text_event(state^)

	base := text_widget_decl(state)
	override := text_props_override(props)
	text_apply_variant(&override)
	text_apply_size(&override)

	state.style = oni.resolve_widget_config(base, override, state, event)
	state.flags = override.flags
	state.text = override.text
	return text_event(state^)
}

Text :: proc(props: Text_Props) -> oni.Vec2 {
	key := oni.element_key(props.id)
	layout_label := props.id != "" ? props.id : key
	layout_id := oni.ui_id(layout_label)

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus :=
		props.auto_focus.mode == .Value &&
		props.auto_focus.value &&
		oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}


	state := Text_Merged_State {
		is_disabled = props.disabled.mode == .Value && props.disabled.value,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	event := text_refresh_merged(props, &state)
	style := state.style

	if oni.ui_pass() == .Layout {
		node := oni.layout_push_node(layout_id, style)
		max_w: f32
		if props.max_w.mode == .Value do max_w = props.max_w.value
		if max_w <= 0 && style.width.kind == .Fixed do max_w = style.width.value
		oni.layout_set_measure_text(node, state.text, max_w)
		oni.layout_pop_node()
		return {}
	}

	rect := oni.widget_hit_rect(layout_id, style)

	state.is_hovered = oni.pointer_over(rect, style.space)
	state.is_left_clicked = state.is_hovered && oni.w_ctx.left_mouse.pressed
	state.is_right_clicked = state.is_hovered && oni.w_ctx.right_mouse.pressed
	state.is_middle_clicked = state.is_hovered && oni.w_ctx.middle_mouse.pressed
	state.is_left_released = state.is_hovered && oni.w_ctx.left_mouse.released
	state.is_right_released = state.is_hovered && oni.w_ctx.right_mouse.released
	state.is_Pressed = state.is_hovered && oni.w_ctx.left_mouse.down

	if !state.is_disabled {
		entered, left := oni.consume_hover_transition(key, state.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(state, event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(state, event)
		}

		if state.is_hovered && oni.w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(state, event)
		}

		if state.is_hovered && oni.w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(state, text_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}

		if state.is_hovered && oni.w_ctx.left_mouse.pressed && !state.is_focused {
			oni.w_ctx.focused_id = key
			state.is_focused = true
			event = text_refresh_merged(props, &state)

			if props.on_focus != nil {
				props.on_focus(state, text_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		if was_focused && !state.is_hovered && oni.w_ctx.left_mouse.pressed {
			oni.w_ctx.focused_id = {}
			state.is_focused = false
			event = text_refresh_merged(props, &state)

			if props.on_blur != nil {
				props.on_blur(state, text_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		state.is_focused = oni.w_ctx.focused_id == key
		event = text_refresh_merged(props, &state)
		style = state.style

		if state.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(state, text_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(state, text_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(state, text_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(state, text_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(state, text_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(state, text_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(state, text_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(state, text_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(state, text_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := oni.consume_pointer_click(
			key,
			state.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := text_event(state, mouse_button = sdl.BUTTON_LEFT)

		if state.is_focused && props.on_click != nil {
			enter_key := oni.w_ctx.keys[int(sdl.Scancode.RETURN)]
			space_key := oni.w_ctx.keys[int(sdl.Scancode.SPACE)]

			if enter_key.pressed {
				clicked = true
				click_event.key = oni.Scancode(sdl.Scancode.RETURN)
			} else if space_key.pressed {
				clicked = true
				click_event.key = oni.Scancode(sdl.Scancode.SPACE)
			}
		}

		if clicked && props.on_click != nil {
			props.on_click(state, click_event)
		}

		if state.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key_state := oni.w_ctx.keys[scancode]
				key_event := text_event(state, key = oni.Scancode(scancode))

				if props.on_key_pressed != nil && key_state.pressed {
					props.on_key_pressed(state, key_event)
				}
				if props.on_key_down != nil && key_state.down {
					props.on_key_down(state, key_event)
				}
				if props.on_key_released != nil && key_state.released {
					props.on_key_released(state, key_event)
				}
			}
		}
	}

	event = text_refresh_merged(props, &state)
	style = state.style

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(state, event)
	}

	rgbaColor, color_ok := oni.to_rgba(style.color, &state, event)
	if !color_ok do return {}

	resolved_font, layout_scale, ok := oni.font_resolve(style.font, style.font_size, style.space)
	if !ok do return {}

	face := oni.font_face_from_handle(resolved_font)
	if face == nil || len(state.text) == 0 do return {}

	pos := oni.Vec2{rect.x, rect.y}
	max_w := style.max_w != 0 ? style.max_w : rect.w
	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

	if .Uncached in state.flags {
		lines := oni.font_shape_line_build(face, state.text, shape_max_w, style.text_direction)
		if len(lines) == 0 do return {}
		defer oni.font_destroy_shaped_lines(lines)
		return oni.font_draw_shaped_lines(
			resolved_font,
			face,
			lines,
			pos,
			rgbaColor,
			max_w,
			style.font_size * style.line_height,
			layout_scale,
		)
	}

	cache_id := props.id != "" ? props.id : key
	cache := oni.widget_shaped(cache_id)
	lines := oni.shaped_text_ensure(
		cache,
		resolved_font.id,
		face,
		state.text,
		shape_max_w,
		style.text_direction,
	)
	if len(lines) == 0 do return {}
	return oni.font_draw_shaped_lines(
		resolved_font,
		face,
		lines,
		pos,
		rgbaColor,
		max_w,
		style.font_size * style.line_height,
		layout_scale,
	)
}
