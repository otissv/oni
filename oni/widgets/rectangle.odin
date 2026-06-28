package widgets

import oni ".."
import set "../set"
import sdl "vendor:sdl3"

/*
Rectangle widget configuration extending Widget_Config.
*/
Rectangle_Config :: oni.Widget_Config

/*
Rectangle widget per-frame interaction frame_state merged with its fully resolved style config.
*/
Rectangle_State :: oni.Widget_Merged_State(oni.Widget_Frame_State, oni.Resolved_Widget_Config)

/*
Rectangle widget event snapshot with frame_state and optional input metadata.
*/
Rectangle_Event :: oni.Widget_Event(Rectangle_State)

/*
Rectangle widget props: config, child callback, and input event handlers.
*/
Rectangle_Props :: struct {
	config:                       Rectangle_Config,
	child:                        proc(frame_state: Rectangle_State),
	unmount:                      bool,
	can_interactive_during_mount: bool, // default false
	on_mount:                     proc(frame_state: Rectangle_State) -> oni.Mount,
	on_unmount:                   proc(frame_state: Rectangle_State) -> oni.Mount,
	on_focus:                     proc(event: Rectangle_Event),
	on_blur:                      proc(event: Rectangle_Event),
	on_mouse_enter:               proc(event: Rectangle_Event),
	on_mouse_leave:               proc(event: Rectangle_Event),
	on_mouse_pressed:             proc(event: Rectangle_Event),
	on_mouse_down:                proc(event: Rectangle_Event),
	on_mouse_released:            proc(event: Rectangle_Event),
	on_mouse_move:                proc(event: Rectangle_Event),
	on_click:                     proc(event: Rectangle_Event),
	on_contextmenu:               proc(event: Rectangle_Event),
	on_key_pressed:               proc(event: Rectangle_Event),
	on_key_down:                  proc(event: Rectangle_Event),
	on_key_released:              proc(event: Rectangle_Event),
}

/*
Builds a rectangle event carrying the current frame_state and optional input metadata.
*/
rect_event :: proc(
	frame_state: Rectangle_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Rectangle_Event {
	return {frame_state = frame_state, mouse_button = mouse_button, key = key}
}

/*
Returns the default rectangle theme config, muted when the widget is disabled.
*/
rect_theme_base :: proc(frame_state: ^Rectangle_State) -> Rectangle_Config {
	color := oni.Color.FOREGROUND

	if frame_state.is_disabled {
		color = oni.Color.MUTED
	}

	return Rectangle_Config {
		kind = .RECT,
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

/*
Merges theme defaults, prop overrides, and live frame_state into a resolved config.
*/
rect_config :: proc(
	props: Rectangle_Props,
	frame_state: ^Rectangle_State,
) -> oni.Resolved_Widget_Config {
	event := rect_event(frame_state^)

	base := rect_theme_base(frame_state)
	override := props.config
	return oni.resolve_widget_config(base, override, frame_state, event)
}

/*
Refreshes merged config on frame_state and returns a fresh rectangle event snapshot.
*/
@(private)
rect_refresh_merged :: proc(
	props: Rectangle_Props,
	frame_state: ^Rectangle_State,
) -> Rectangle_Event {
	frame_state.config = rect_config(props, frame_state)
	return rect_event(frame_state^)
}

/*
Renders a styled rectangle container with full pointer and keyboard interaction.

Runs layout on the layout pass and draws chrome plus children on the draw pass.
*/
Rectangle :: proc(props: Rectangle_Props) {
	// Layout pass
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)
	layout_rect := oni.ui_layout_rect(layout_id)
	rect := layout_rect

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus :=
		cfg.auto_focus.mode == .Value && cfg.auto_focus.value && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	frame_state := Rectangle_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	event := rect_refresh_merged(props, &frame_state)
	config := frame_state.config
	child := props.child

	if oni.ui_pass() == .Layout {
		// Layout pass

		if props.on_mount != nil &&
		   frame_state.mounting == .UNSET &&
		   frame_state.mounting != .COMPLETED {
			frame_state.mounting = props.on_mount(frame_state)
		} else if props.on_unmount != nil &&
		   (props.unmount || frame_state.unmounting == .RUNNING) {
			frame_state.unmounting = props.on_unmount(frame_state)
		}

		oni.Children(child, layout_id, config, frame_state)
		return
	} else {
		// Draw pass

		draw_widget_rectangle(
			{
				frame_state = &frame_state,
				event = event,
				rect = rect,
				child = child,
				layout_id = layout_id,
			},
		)

		oni.Children(child, layout_id, config, frame_state)

		// TODO: remove from layout tree
		return

	}

	// Draw pass
	if rect.w == 0 {
		if w := oni.length_resolve(config.width, 0); w > 0 do rect.w = w
	}
	if rect.h == 0 {
		if h := oni.length_resolve(config.height, 0); h > 0 do rect.h = h
	}

	frame_state.is_hovered = oni.pointer_over(rect, config.space)
	frame_state.is_left_clicked = frame_state.is_hovered && oni.w_ctx.left_mouse.pressed
	frame_state.is_right_clicked = frame_state.is_hovered && oni.w_ctx.right_mouse.pressed
	frame_state.is_middle_clicked = frame_state.is_hovered && oni.w_ctx.middle_mouse.pressed
	frame_state.is_left_released = frame_state.is_hovered && oni.w_ctx.left_mouse.released
	frame_state.is_right_released = frame_state.is_hovered && oni.w_ctx.right_mouse.released
	frame_state.is_Pressed = frame_state.is_hovered && oni.w_ctx.left_mouse.down

	got_focus := false
	lost_focus := false

	if !frame_state.is_disabled {
		if frame_state.is_hovered && oni.w_ctx.left_mouse.pressed && !frame_state.is_focused {
			oni.w_ctx.focused_id = key
			frame_state.is_focused = true
			got_focus = true
		}

		if was_focused && !frame_state.is_hovered && oni.w_ctx.left_mouse.pressed {
			oni.w_ctx.focused_id = {}
			frame_state.is_focused = false
			lost_focus = true
		}
	}

	event = rect_refresh_merged(props, &frame_state)

	if !frame_state.is_disabled {
		entered, left := oni.consume_hover_transition(key, frame_state.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(event)
		}

		if frame_state.is_hovered && oni.w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(event)
		}

		if frame_state.is_hovered && oni.w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(rect_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
		}

		if got_focus && props.on_focus != nil {
			props.on_focus(rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}

		if lost_focus && props.on_blur != nil {
			props.on_blur(rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}

		if frame_state.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(rect_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(rect_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if frame_state.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(rect_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(rect_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if frame_state.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(rect_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(rect_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := oni.consume_pointer_click(
			key,
			frame_state.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := rect_event(frame_state, mouse_button = sdl.BUTTON_LEFT)

		if frame_state.is_focused && props.on_click != nil {
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

		if frame_state.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key_frame_state := oni.w_ctx.keys[scancode]
				key_event := rect_event(frame_state, key = oni.Scancode(scancode))

				if props.on_key_pressed != nil && key_frame_state.pressed {
					props.on_key_pressed(key_event)
				}
				if props.on_key_down != nil && key_frame_state.down {
					props.on_key_down(key_event)
				}
				if props.on_key_released != nil && key_frame_state.released {
					props.on_key_released(key_event)
				}
			}
		}
	}

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(event)
	}

	config = frame_state.config

	draw_widget_rectangle(
		{
			frame_state = &frame_state,
			event = event,
			rect = rect,
			child = child,
			layout_id = layout_id,
		},
	)
}


@(private)
Draw_Widget_Rectangle :: struct {
	frame_state: ^Rectangle_State,
	event:       Rectangle_Event,
	rect:        oni.Rect,
	child:       proc(frame_state: Rectangle_State),
	layout_id:   oni.UI_Id,
}

@(private)
draw_widget_rectangle :: proc(props: Draw_Widget_Rectangle) {
	child := props.child
	event := props.event
	frame_state := props.frame_state
	layout_id := props.layout_id
	rect := props.rect

	config := frame_state.config

	background: oni.RGBA
	if resolved_background, background_ok := oni.to_rgba(config.background, frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: oni.Bd
	if resolved_border, border_ok := oni.resolve_border(config.border, frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: oni.RGBA
	if resolved_border_color, border_color_ok := oni.to_rgba(
		config.border_color,
		frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: oni.Radius_corners
	if resolved_radius, ok := oni.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	oni.Draw_Rectangle(rect, background, radius, border, border_color)

	oni.Children(child, layout_id, config, frame_state^)
}
