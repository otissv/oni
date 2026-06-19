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
	using _: oni.Widget_config,
	flags:   Widget_Text_Flags,
	max_w:   f32,
	size:    Text_Size,
	text:    string,
	variant: Text_Variant,
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
	state: Text_State,
	config: Text_Config,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Text_Event {
	return merge_state_event(state, config, mouse_button, key)
}

text_config :: proc(props: Text_Props, state: ^Text_State) -> oni.Widget_config {

	color := oni.Color{}

	if state.is_disabled && color == {} {
		color = oni.Color.Text_muted
	}

	decl := Text_Config {
		bg = 0,
		pd = 0,
		rd = 0,
		bd = 0,
		alignChild = oni.Align_Pos{x = .Left, y = .Top},
		color = color,
	}

	style_event := oni.Widget_Event(Text_State) {
		state = state^,
	}
	decl = merge_element_declaration(
		decl,
		oni.Widget_config {
			bdColor = props.bdColor,
			bg = props.bg,
			pd = props.pd,
			rd = props.rd,
			bd = props.bd,
			aspectRatio = props.aspectRatio,
			gap = props.gap,
			alignChild = props.alignChild,
			direction = props.direction,
		},
		state,
		style_event,
	)


	return decl
}


Text :: proc(props: Text_Props) -> oni.Vec2 {
	key := element_key(props.id)

	// event := Text_Event {
	// 	state = state,
	// }

	was_focused := w_ctx.focused_id == key
	should_auto_focus := props.auto_focus && w_ctx.auto_focused_id != key

	if should_auto_focus {
		w_ctx.focused_id = key
		w_ctx.auto_focused_id = key
	}


	state := Text_Merged_State {
		state = Text_State{is_disabled = props.disabled, is_focused = w_ctx.focused_id == key},
	}

	// Dynamic style callbacks are resolved while building the declaration,
	// so populate the interaction snapshot before configuring the text element.
	state.is_hovered = PointerOver(key)
	state.is_left_clicked = state.is_hovered && w_ctx.left_mouse.pressed
	state.is_right_clicked = state.is_hovered && w_ctx.right_mouse.pressed
	state.is_middle_clicked = state.is_hovered && w_ctx.middle_mouse.pressed
	state.is_left_released = state.is_hovered && w_ctx.left_mouse.released
	state.is_right_released = state.is_hovered && w_ctx.right_mouse.released
	state.is_Pressed = state.is_hovered && w_ctx.left_mouse.down


	config := text_config(props, &state)
	event := text_event(state, config)

	if !state.is_disabled {
		entered, left := consume_hover_transition(key, state.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(event)
		}

		if state.is_hovered && w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(event)
		}

		if state.is_hovered && w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(text_event(state, config, mouse_button = sdl.BUTTON_RIGHT))
		}

		if state.is_hovered && w_ctx.left_mouse.pressed && !state.is_focused {
			w_ctx.focused_id = key
			state.is_focused = true

			if props.on_focus != nil {
				props.on_focus(text_event(state, config, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		if was_focused && !state.is_hovered && w_ctx.left_mouse.pressed {
			w_ctx.focused_id = {}
			state.is_focused = false

			if props.on_blur != nil {
				props.on_blur(text_event(state, config, mouse_button = sdl.BUTTON_LEFT))
			}
		}

		state.is_focused = w_ctx.focused_id == key

		if state.is_hovered && props.on_mouse_pressed != nil {
			if w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(text_event(state, config, mouse_button = sdl.BUTTON_LEFT))
			}
			if w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(text_event(state, config, mouse_button = sdl.BUTTON_RIGHT))
			}
			if w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(text_event(state, config, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_down != nil {
			if w_ctx.left_mouse.down {
				props.on_mouse_down(text_event(state, config, mouse_button = sdl.BUTTON_LEFT))
			}
			if w_ctx.right_mouse.down {
				props.on_mouse_down(text_event(state, config, mouse_button = sdl.BUTTON_RIGHT))
			}
			if w_ctx.middle_mouse.down {
				props.on_mouse_down(text_event(state, config, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_released != nil {
			if w_ctx.left_mouse.released {
				props.on_mouse_released(text_event(state, config, mouse_button = sdl.BUTTON_LEFT))
			}
			if w_ctx.right_mouse.released {
				props.on_mouse_released(text_event(state, config, mouse_button = sdl.BUTTON_RIGHT))
			}
			if w_ctx.middle_mouse.released {
				props.on_mouse_released(
					text_event(state, config, mouse_button = sdl.BUTTON_MIDDLE),
				)
			}
		}

		clicked := consume_pointer_click(
			key,
			state.is_hovered,
			w_ctx.left_mouse.pressed,
			w_ctx.left_mouse.released,
		)
		click_event := text_event(state, config, mouse_button = sdl.BUTTON_LEFT)

		if state.is_focused && props.on_click != nil {
			enter_key := w_ctx.keys[int(sdl.Scancode.RETURN)]
			space_key := w_ctx.keys[int(sdl.Scancode.SPACE)]

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

		if state.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key := w_ctx.keys[scancode]
				event := text_event(state, config, key = oni.Scancode(scancode))

				if props.on_key_pressed != nil && key.pressed {
					props.on_key_pressed(event)
				}
				if props.on_key_down != nil && key.down {
					props.on_key_down(event)
				}
				if props.on_key_released != nil && key.released {
					props.on_key_released(event)
				}
			}
		}
	}

	config := text_config(props, &state)

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(text_event(state, config))
	}


	font := props.font != {} ? props.font : oni.theme.font_body
	rect := props.rect
	text := props.text
	font_size := props.font_size != 0 ? props.font_size : 16

	color := props.color
	max_w := props.max_w

	rgbaColor: oni.RGBA
	has_color := false

	#partial switch c in color {
	case oni.Color:
		if c == .Invalid {
			rgbaColor = oni.theme.palette[.Text]
			has_color = true
		}
	case:
		if color == {} {
			if state.is_disabled {
				rgbaColor = oni.theme.palette[.Text_muted]
				has_color = true
			}
		}
	}

	if !has_color {
		if resolved, ok := oni.resolve_color(color, &state, event); ok {
			rgbaColor = resolved
		}
	}

	resolved_font, layout_scale, ok := oni.font_resolve(font, font_size, props.space)
	if !ok do return {}

	face := oni.font_face_from_handle(resolved_font)
	if face == nil || len(text) == 0 do return {}

	pos := oni.Vec2{rect.x, rect.y}
	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

	if .Uncached in props.flags {
		lines := oni.font_shape_line_build(face, text, shape_max_w, props.direction)
		if len(lines) == 0 do return {}
		defer oni.font_destroy_shaped_lines(lines)
		return oni.font_draw_shaped_lines(
			resolved_font,
			face,
			lines,
			pos,
			rgbaColor,
			max_w,
			font_size * props.line_height,
			layout_scale,
		)
	}

	cache := oni.widget_shaped(props.id)
	lines := oni.shaped_text_ensure(
		cache,
		resolved_font.id,
		face,
		text,
		shape_max_w,
		props.direction,
	)
	if len(lines) == 0 do return {}
	return oni.font_draw_shaped_lines(
		resolved_font,
		face,
		lines,
		pos,
		rgbaColor,
		max_w,
		font_size * props.line_height,
		layout_scale,
	)
}


// ui_text_layout :: proc(
// 	id: oni.UI_Id,
// 	text: string,
// 	font: oni.Font_Handle,
// 	max_w: f32,
// 	direction: oni.Text_Direction = .LTR,
// 	font_size: f32 = 0,
// 	line_height: f32 = 0,
// 	space: oni.Draw_Space = .Screen,
// 	flags: Widget_Text_Flags = {},
// ) -> oni.Vec2 {
// 	resolved, layout_scale, ok := oni.font_resolve(font, font_size, space)
// 	if !ok do return {}

// 	face := oni.font_face_from_handle(resolved)
// 	if face == nil || len(text) == 0 do return {}

// 	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

// 	if .Uncached in flags {
// 		lines := oni.font_shape_line_build(face, text, shape_max_w, direction)
// 		if len(lines) == 0 do return {}
// 		defer oni.font_destroy_shaped_lines(lines)
// 		return oni.font_measure_lines(face, lines, line_height, layout_scale)
// 	}

// 	cache := oni.ui_widget_shaped(id)
// 	lines := oni.shaped_text_ensure(cache, resolved.id, face, text, shape_max_w, direction)
// 	if len(lines) == 0 do return {}
// 	return oni.font_measure_lines(face, lines, line_height, layout_scale)
// }
