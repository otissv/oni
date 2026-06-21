package widgets

import oni ".."
import set "../set"
import sdl "vendor:sdl3"

Button_Variant :: enum {
	DEFAULT,
	DESTRUCTIVE,
	OUTLINE,
	SECONDARY,
	GHOST,
	LINK,
}

Button_Size :: enum {
	Default,
	Small,
	Large,
	Icon,
}


Button_Config :: struct {
	using _: oni.Widget_Config,
	flags:   oni.Widget_Text_Flags,
	size:    Button_Size,
	text:    string,
	variant: Button_Variant,
}

Button_State :: oni.Widget_Merged_State(oni.Widget_State, oni.Resolved_Widget_Config)
Button_Event :: oni.Widget_Event(Button_State)


Button_Props :: struct {
	config:            Button_Config,
	child:             proc(state: Button_State),
	on_focus:          proc(event: Button_Event),
	on_blur:           proc(event: Button_Event),
	on_mouse_enter:    proc(event: Button_Event),
	on_mouse_leave:    proc(event: Button_Event),
	on_mouse_pressed:  proc(event: Button_Event),
	on_mouse_down:     proc(event: Button_Event),
	on_mouse_released: proc(event: Button_Event),
	on_mouse_move:     proc(event: Button_Event),
	on_click:          proc(event: Button_Event),
	on_contextmenu:    proc(event: Button_Event),
	on_key_pressed:    proc(event: Button_Event),
	on_key_down:       proc(event: Button_Event),
	on_key_released:   proc(event: Button_Event),
}

@(private)
button_event :: proc(
	state: Button_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Button_Event {
	return {state = state, mouse_button = mouse_button, key = key}
}

@(private)
button_props_override :: proc(props: Button_Props) -> Button_Config {
	return props.config
}

@(private)
button_apply_variant :: proc(config: ^Button_Config, state: ^Button_State) {
	if config.variant == .DEFAULT do return

	config.font = set.Font(oni.theme.font_heading)
	bg := oni.RGBA{0, 0, 0, 0}
	border: oni.Border
	border_color: oni.RGBA
	text_padding: f32 = 12
	radius: f32 = 8

	#partial switch config.variant {
	case .DEFAULT:
		if state.is_Pressed do bg = {20, 20, 20, 255}
		else if state.is_hovered do bg = {50, 50, 50, 255}
		else do bg = {30, 30, 30, 255}

	case .SECONDARY:
		if state.is_Pressed do bg = {180, 180, 180, 255}
		else if state.is_hovered do bg = {210, 210, 210, 255}
		else do bg = {235, 235, 235, 255}

	case .OUTLINE:
		border = 1
		border_color = oni.RGBA{80, 80, 80, 255}

		if state.is_Pressed do bg = {210, 210, 210, 255}
		else if state.is_hovered do bg = {245, 245, 245, 255}
		else do bg = {0, 0, 0, 0}

	case .GHOST:
		if state.is_Pressed do bg = {210, 210, 210, 255}
		else if state.is_hovered do bg = {235, 235, 235, 255}
		else do bg = {0, 0, 0, 0}

	case .DESTRUCTIVE:
		if state.is_Pressed do bg = {120, 0, 0, 255}
		else if state.is_hovered do bg = {180, 20, 20, 255}
		else do bg = {230, 40, 40, 255}

	case .LINK:
		radius = {}
		text_padding = 4
		if state.is_Pressed do bg = {235, 235, 235, 255}
		else if state.is_hovered do bg = {245, 245, 245, 255}
		else do bg = {0, 0, 0, 0}
	}
}

@(private)
button_apply_size :: proc(config: ^Button_Config) {
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
button_theme_base :: proc(state: ^Button_State) -> Button_Config {
	color := oni.Color.Text

	if state.is_disabled {
		color = oni.Color.Text_muted
	}

	return Button_Config {
		kind = .BUTTON,
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
button_config :: proc(props: Button_Props, state: ^Button_State) -> oni.Resolved_Widget_Config {
	event := button_event(state^)

	base := button_theme_base(state)
	override := button_props_override(props)
	button_apply_variant(&override, state)
	button_apply_size(&override)

	return oni.resolve_widget_config(base, override, state, event)
}

@(private)
button_refresh_merged :: proc(props: Button_Props, state: ^Button_State) -> Button_Event {
	state.config = button_config(props, state)
	return button_event(state^)
}

Button :: proc(props: Button_Props) {
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus :=
		cfg.auto_focus.mode == .Value && cfg.auto_focus.value && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	state := Button_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	event := button_refresh_merged(props, &state)
	config := state.config
	child := props.child

	if oni.ui_pass() == .Layout {
		oni.Children(child, layout_id, config, state)
		return
	}

	layout_rect := oni.ui_layout_rect(layout_id)
	rect := layout_rect
	if rect.w == 0 {
		if w := oni.length_resolve(config.width, 0); w > 0 do rect.w = w
	}
	if rect.h == 0 {
		if h := oni.length_resolve(config.height, 0); h > 0 do rect.h = h
	}

	state.is_hovered = oni.pointer_over(rect, config.space)
	state.is_left_clicked = state.is_hovered && oni.w_ctx.left_mouse.pressed
	state.is_right_clicked = state.is_hovered && oni.w_ctx.right_mouse.pressed
	state.is_middle_clicked = state.is_hovered && oni.w_ctx.middle_mouse.pressed
	state.is_left_released = state.is_hovered && oni.w_ctx.left_mouse.released
	state.is_right_released = state.is_hovered && oni.w_ctx.right_mouse.released
	state.is_Pressed = state.is_hovered && oni.w_ctx.left_mouse.down

	got_focus := false
	lost_focus := false

	if !state.is_disabled {
		if state.is_hovered && oni.w_ctx.left_mouse.pressed && !state.is_focused {
			oni.w_ctx.focused_id = key
			state.is_focused = true
			got_focus = true
		}

		if was_focused && !state.is_hovered && oni.w_ctx.left_mouse.pressed {
			oni.w_ctx.focused_id = {}
			state.is_focused = false
			lost_focus = true
		}
	}

	event = button_refresh_merged(props, &state)

	if !state.is_disabled {
		entered, left := oni.consume_hover_transition(key, state.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(event)
		}

		if state.is_hovered && oni.w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(event)
		}

		if state.is_hovered && oni.w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(button_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}

		if got_focus && props.on_focus != nil {
			props.on_focus(button_event(state, mouse_button = sdl.BUTTON_LEFT))
		}

		if lost_focus && props.on_blur != nil {
			props.on_blur(button_event(state, mouse_button = sdl.BUTTON_LEFT))
		}

		if state.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(button_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(button_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(button_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(button_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(button_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(button_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(button_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(button_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(button_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := oni.consume_pointer_click(
			key,
			state.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := button_event(state, mouse_button = sdl.BUTTON_LEFT)

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
			props.on_click(click_event)
		}

		if state.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key_state := oni.w_ctx.keys[scancode]
				key_event := button_event(state, key = oni.Scancode(scancode))

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

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(event)
	}

	background: oni.RGBA
	if resolved_background, background_ok := oni.to_rgba(config.background, &state, event);
	   background_ok {
		background = resolved_background
	}

	border: oni.Bd
	if resolved_border, border_ok := oni.resolve_border(config.border, &state, event); border_ok {
		border = resolved_border
	}

	border_color: oni.RGBA
	if resolved_border_color, border_color_ok := oni.to_rgba(config.border_color, &state, event);
	   border_color_ok {
		border_color = resolved_border_color
	}

	radius: oni.Radius_corners
	if resolved_radius, ok := oni.resolve_radius(config.radius, &state, event); ok {
		radius = resolved_radius
	}

	oni.Draw_rectangle(rect, background, radius, border, border_color)

	oni.Children(child, layout_id, config, state)
}
