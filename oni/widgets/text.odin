package widgets

import oni ".."
import sdl "vendor:sdl3"


Widget_Text_Flag :: enum {
	Uncached,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag;i32]

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
	using config: oni.Widget_config,
	flags:        Widget_Text_Flags,
	max_w:        f32,
	size:         Text_Size,
	text:         string,
	variant:      Text_Variant,
}

Text_State :: struct {
	using _: oni.Widget_State,
}

Text_Merged_State :: oni.Widget_Merged_State(Text_State, Text_Config)

Text_Event :: oni.Widget_Event(Text_Merged_State)

Text_Props :: struct {
	using _:           Text_Config,
	on_focus:          proc(event: Text_Event),
	on_blur:           proc(event: Text_Event),
	on_mouse_enter:    proc(event: Text_Event),
	on_mouse_leave:    proc(event: Text_Event),
	on_mouse_pressed:  proc(event: Text_Event),
	on_mouse_down:     proc(event: Text_Event),
	on_mouse_released: proc(event: Text_Event),
	on_mouse_move:     proc(event: Text_Event),
	on_click:          proc(event: Text_Event),
	on_contextmenu:    proc(event: Text_Event),
	on_key_pressed:    proc(event: Text_Event),
	on_key_down:       proc(event: Text_Event),
	on_key_released:   proc(event: Text_Event),
}

@(private)
text_event :: proc(
	merged: Text_Merged_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Text_Event {
	return {state = merged, mouse_button = mouse_button, key = key}
}

@(private)
text_apply_variant :: proc(config: ^Text_Config) {
	if config.variant == .DEFAULT do return

	config.font = oni.theme.font_heading
	switch config.variant {
	case .DEFAULT:
	case .H1:
		config.font_size = 32
	case .H2:
		config.font_size = 28
	case .H3:
		config.font_size = 24
	case .H4:
		config.font_size = 20
	case .H5:
		config.font_size = 18
	case .H6:
		config.font_size = 16
	}
}

@(private)
text_apply_size :: proc(config: ^Text_Config) {
	switch config.size {
	case .Default:
	case .Small:
		config.font_size =
			config.font_size != 0 ? config.font_size * 0.875 : oni.theme.font_body.size_px * 0.875
	case .Large:
		config.font_size =
			config.font_size != 0 ? config.font_size * 1.25 : oni.theme.font_body.size_px * 1.25
	case .Icon:
		config.font_size = 14
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
text_theme_base :: proc(merged: ^Text_Merged_State) -> Text_Config {
	color := oni.Color.Text

	if merged.is_disabled {
		color = oni.Color.Text_muted
	}

	return Text_Config {
		kind = .TEXT,
		font = oni.theme.font_body,
		font_size = oni.theme.font_body.size_px,
		color = color,
		line_height = 1,
		text_direction = .LTR,
		space = .Screen,
		justify = oni.theme.justify,
		gap = oni.theme.gap,
	}
}

@(private)
text_config :: proc(props: Text_Props, merged: ^Text_Merged_State) -> Text_Config {
	event := text_event(merged^)

	base := text_theme_base(merged)
	override := text_props_override(props)
	text_apply_variant(&override)
	text_apply_size(&override)

	resolved := merge_element_declaration(base, override, merged, event)

	override.color = resolved.color
	override.background = resolved.background
	override.border_color = resolved.border_color
	override.padding = resolved.padding
	override.radius = resolved.radius
	override.border = resolved.border
	override.gap = resolved.gap
	override.justify = resolved.justify
	override.direction = resolved.direction
	override.font = resolved.font
	override.font_size = resolved.font_size
	override.space = resolved.space
	override.line_height = resolved.line_height
	return override
}

@(private)
text_refresh_merged :: proc(props: Text_Props, merged: ^Text_Merged_State) -> Text_Event {
	merged.config = text_config(props, merged)
	return text_event(merged^)
}

Text :: proc(props: Text_Props) -> oni.Vec2 {
	key := element_key(props.id)

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus := props.auto_focus && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	merged := Text_Merged_State {
		is_disabled = props.disabled,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	rect := oni.Rect {
		x = props.x,
		y = props.y,
		w = props.width,
		h = props.height,
	}

	merged.is_hovered = pointer_over(rect, props.space)
	merged.is_left_clicked = merged.is_hovered && oni.w_ctx.left_mouse.pressed
	merged.is_right_clicked = merged.is_hovered && oni.w_ctx.right_mouse.pressed
	merged.is_middle_clicked = merged.is_hovered && oni.w_ctx.middle_mouse.pressed
	merged.is_left_released = merged.is_hovered && oni.w_ctx.left_mouse.released
	merged.is_right_released = merged.is_hovered && oni.w_ctx.right_mouse.released
	merged.is_Pressed = merged.is_hovered && oni.w_ctx.left_mouse.down

	event := text_refresh_merged(props, &merged)

	if !merged.is_disabled {
		entered, left := consume_hover_transition(key, merged.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(event)
		}

		if merged.is_hovered && oni.w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(event)
		}

		if merged.is_hovered && oni.w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(text_event(merged, mouse_button = sdl.BUTTON_RIGHT))
		}

		if merged.is_hovered && oni.w_ctx.left_mouse.pressed && !merged.is_focused {
			oni.w_ctx.focused_id = key
			merged.is_focused = true
			event = text_refresh_merged(props, &merged)

			if props.on_focus != nil {
				props.on_focus(text_event(merged, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		if was_focused && !merged.is_hovered && oni.w_ctx.left_mouse.pressed {
			oni.w_ctx.focused_id = {}
			merged.is_focused = false
			event = text_refresh_merged(props, &merged)

			if props.on_blur != nil {
				props.on_blur(text_event(merged, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		merged.is_focused = oni.w_ctx.focused_id == key
		event = text_refresh_merged(props, &merged)

		if merged.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(text_event(merged, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(text_event(merged, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(text_event(merged, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if merged.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(text_event(merged, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(text_event(merged, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(text_event(merged, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if merged.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(text_event(merged, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(text_event(merged, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(text_event(merged, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := consume_pointer_click(
			key,
			merged.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := text_event(merged, mouse_button = sdl.BUTTON_LEFT)

		if merged.is_focused && props.on_click != nil {
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
			props.on_click(click_event)
		}

		if merged.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key_state := oni.w_ctx.keys[scancode]
				key_event := text_event(merged, key = oni.Scancode(scancode))

				if props.on_key_pressed != nil && key_state.pressed {
					props.on_key_pressed(key_event)
				}
				if props.on_key_down != nil && key_state.down {
					props.on_key_down(key_event)
				}
				if props.on_key_released != nil && key_state.released {
					props.on_key_released(key_event)
				}
			}
		}
	}

	event = text_refresh_merged(props, &merged)

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(event)
	}

	config := merged.config

	rgbaColor, color_ok := oni.to_rgba(config.color, &merged, event)
	if !color_ok do return {}

	resolved_font, layout_scale, ok := oni.font_resolve(
		config.font,
		config.font_size,
		config.space,
	)
	if !ok do return {}

	face := oni.font_face_from_handle(resolved_font)
	if face == nil || len(config.text) == 0 do return {}

	pos := oni.Vec2{config.x, config.y}
	max_w := config.max_w != 0 ? config.max_w : config.width
	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

	if .Uncached in config.flags {
		lines := oni.font_shape_line_build(face, config.text, shape_max_w, config.text_direction)
		if len(lines) == 0 do return {}
		defer oni.font_destroy_shaped_lines(lines)
		return oni.font_draw_shaped_lines(
			resolved_font,
			face,
			lines,
			pos,
			rgbaColor,
			max_w,
			config.font_size * config.line_height,
			layout_scale,
		)
	}

	cache_id := props.id != "" ? props.id : key
	cache := widget_shaped(cache_id)
	lines := oni.shaped_text_ensure(
		cache,
		resolved_font.id,
		face,
		config.text,
		shape_max_w,
		config.text_direction,
	)
	if len(lines) == 0 do return {}
	return oni.font_draw_shaped_lines(
		resolved_font,
		face,
		lines,
		pos,
		rgbaColor,
		max_w,
		config.font_size * config.line_height,
		layout_scale,
	)
}
