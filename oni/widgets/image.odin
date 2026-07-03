package widgets

import oni ".."
import set "../set"
import sdl "vendor:sdl3"


Image_Config :: oni.Widget_Config
Image_State :: oni.Widget_Merged_State(oni.Widget_Frame_State, oni.Resolved_Widget_Config)
Image_Event :: oni.Widget_Event(Image_State)

/*
Image widget props: source rect, tint, fit/pos overrides, and event handlers.
*/
Image_Props :: struct {
	config:                       Image_Config,
	texture:                      oni.Texture_Handle,
	src, dst:                     oni.Rect,
	tint:                         oni.Colors,
	alt:                          string,
	texture_fit:                  oni.Cfg(oni.Style_Image_Fit),
	texture_pos:                  oni.Cfg(oni.Style_Image_Pos),
	child:                        proc(frame_state: Image_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Image_State) -> oni.Mount,
	on_unmount:                   proc(frame_state: Image_State) -> oni.Mount,
	on_focus:                     proc(event: Image_Event),
	on_blur:           proc(event: Image_Event),
	on_mouse_enter:    proc(event: Image_Event),
	on_mouse_leave:    proc(event: Image_Event),
	on_mouse_pressed:  proc(event: Image_Event),
	on_mouse_down:     proc(event: Image_Event),
	on_mouse_released: proc(event: Image_Event),
	on_mouse_move:     proc(event: Image_Event),
	on_click:          proc(event: Image_Event),
	on_contextmenu:    proc(event: Image_Event),
	on_key_pressed:    proc(event: Image_Event),
	on_key_down:       proc(event: Image_Event),
	on_key_released:   proc(event: Image_Event),
}

/*
Builds a texture event carrying the current frame_state and optional input metadata.
*/
image_event :: proc(
	frame_state: Image_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Image_Event {
	return {frame_state = frame_state, mouse_button = mouse_button, key = key}
}

/*
Returns the default texture widget theme config, muted when the widget is disabled.
*/
image_theme_base :: proc(frame_state: ^Image_State) -> Image_Config {
	color := oni.Color.FOREGROUND

	if frame_state.is_disabled {
		color = oni.Color.MUTED
	}

	return Image_Config {
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

Applies explicit texture_fit and texture_pos props when they are set.
*/
image_config :: proc(props: Image_Props, frame_state: ^Image_State) -> oni.Resolved_Widget_Config {
	event := image_event(frame_state^)

	base := image_theme_base(frame_state)
	override := props.config
	if props.texture_fit.mode != .UNSET do override.texture_fit = props.texture_fit
	if props.texture_pos.mode != .UNSET do override.texture_pos = props.texture_pos
	return oni.resolve_widget_config(base, override, frame_state, event)
}

/*
Refreshes merged config on frame_state and returns a fresh texture event snapshot.
*/
@(private)
image_refresh_merged :: proc(props: Image_Props, frame_state: ^Image_State) -> Image_Event {
	frame_state.config = image_config(props, frame_state)
	return image_event(frame_state^)
}

@(private)
image_lifecycle_handlers :: proc(props: Image_Props) -> Widget_Lifecycle_Handlers(Image_State) {
	return {
		unmount = props.unmount,
		can_interactive_during_mount = props.can_interactive_during_mount,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
	}
}

/*
Resolves the intrinsic source size from props.src or the loaded texture handle.
*/
@(private)
texture_src_size :: proc(props: Image_Props) -> (w, h: f32) {
	src := props.src
	if src.w > 0 || src.h > 0 {
		return src.w, src.h
	}
	if props.texture.w > 0 && props.texture.h > 0 {
		return props.texture.w, props.texture.h
	}
	return 0, 0
}

/*
Computes intrinsic layout size for auto-sized texture widgets.

Accounts for fit mode, padding, and border when width or height is indefinite.
*/
@(private)
texture_measure_size :: proc(
	props: Image_Props,
	config: oni.Resolved_Widget_Config,
	frame_state: ^Image_State,
	event: Image_Event,
) -> oni.Vec2 {
	src_w, src_h := texture_src_size(props)
	if src_w <= 0 || src_h <= 0 do return {}

	width_auto := !oni.length_is_definite(config.width)
	height_auto := !oni.length_is_definite(config.height)
	if !width_auto && !height_auto do return {}

	fit := oni.Image_Fit.FILL
	if resolved_fit, fit_ok := oni.resolve_texture_fit(config.texture_fit, frame_state, event);
	   fit_ok {
		fit = resolved_fit
	}

	needs_intrinsic := false
	switch fit {
	case .NONE, .SCALE_DOWN:
		needs_intrinsic = true
	case .FILL, .CONTAIN, .COVER:
		needs_intrinsic = width_auto || height_auto
	}
	if !needs_intrinsic do return {}

	padding, _ := oni.resolve_padding_value(config.padding)
	border, _ := oni.resolve_border_value(config.border)
	inset_w := padding.l + padding.r + border.l + border.r
	inset_h := padding.t + padding.b + border.t + border.b

	measure: oni.Vec2
	if width_auto do measure.x = src_w + inset_w
	if height_auto do measure.y = src_h + inset_h
	return measure
}

/*
Renders a fitted texture inside styled chrome with full pointer interaction.

Runs layout on the layout pass and draws background, border, and image on draw.
*/
Image :: proc(props: Image_Props) {
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Image_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = was_focused,
	}

	event := image_refresh_merged(props, &frame_state)
	config := frame_state.config
	child := props.child
	handlers := image_lifecycle_handlers(props)
	should_auto_focus := widget_should_auto_focus(config, key)

	if oni.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
		)
		if ran_unmount {
			event = image_refresh_merged(props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}
		if skip_layout do return

		can_interact := widget_can_interact(handlers, &frame_state)
		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}
		widget_register_tab_order(key, config.tabbable, can_interact)

		oni.ui_push_scope(layout_id)
		node := oni.layout_push_node(layout_id, config)
		if measure := texture_measure_size(props, config, &frame_state, event);
		   measure.x > 0 || measure.y > 0 {
			oni.layout_set_measure_size(node, measure)
		}
		oni.ui_push_style(oni.style_child_context(config))
		if child != nil do child(frame_state)
		oni.ui_pop_style()
		oni.layout_pop_node()
		oni.ui_pop_scope()
		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := oni.ui_layout_rect(layout_id)
	rect := layout_rect
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

	if widget_can_interact(handlers, &frame_state) {
		got_focus, lost_focus := widget_handle_pointer_focus(
			key,
			config.tabbable,
			was_focused,
			frame_state.is_hovered,
			&frame_state.is_focused,
		)

		event = image_refresh_merged(props, &frame_state)
		config = frame_state.config

		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}
		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}

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
			props.on_contextmenu(image_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
		}

		if got_focus && props.on_focus != nil {
			props.on_focus(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}

		if lost_focus && props.on_blur != nil {
			props.on_blur(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
		}

		if frame_state.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(image_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(image_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if frame_state.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(image_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(image_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if frame_state.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(image_event(frame_state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(image_event(frame_state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(image_event(frame_state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := oni.consume_pointer_click(
			key,
			frame_state.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := image_event(frame_state, mouse_button = sdl.BUTTON_LEFT)

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
				key_event := image_event(frame_state, key = oni.Scancode(scancode))

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

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	config = frame_state.config

	background: oni.RGBA
	if resolved_background, background_ok := oni.to_rgba(config.background, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: oni.Bd
	if resolved_border, border_ok := oni.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	padding: oni.Pd
	if resolved_padding, padding_ok := oni.resolve_padding(config.padding, &frame_state, event);
	   padding_ok {
		padding = resolved_padding
	}

	border_color: oni.RGBA
	if resolved_border_color, border_color_ok := oni.to_rgba(
		config.border_color,
		&frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: oni.Radius_corners
	if resolved_radius, ok := oni.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	src := props.src
	if src.w == 0 && src.h == 0 {
		src_w, src_h := texture_src_size(props)
		if src_w > 0 && src_h > 0 {
			src = {0, 0, src_w, src_h}
		}
	}

	content := oni.layout_inner_rect(rect, border, padding)
	container := content
	if props.dst.w > 0 || props.dst.h > 0 {
		container = props.dst
		if container.w == 0 do container.w = content.w
		if container.h == 0 do container.h = content.h
		if container.x == 0 && container.y == 0 {
			container.x = content.x
			container.y = content.y
		}
	}

	fit := oni.Image_Fit.FILL
	if resolved_fit, fit_ok := oni.resolve_texture_fit(config.texture_fit, &frame_state, event);
	   fit_ok {
		fit = resolved_fit
	}

	pos := oni.Resolved_Image_Pos{0.5, 0.5, 0, 0}
	if resolved_pos, pos_ok := oni.resolve_texture_pos(config.texture_pos, &frame_state, event);
	   pos_ok {
		pos = resolved_pos
	}

	dst := container
	src, dst = oni.texture_fit_rects(src, container, fit, pos)

	tint := oni.RGBA{255, 255, 255, 255}
	if resolved_tint, tint_ok := oni.to_rgba(props.tint, &frame_state, event); tint_ok {
		tint = resolved_tint
	}

	has_chrome :=
		background.a > 0 ||
		border_color.a > 0 && (border.t > 0 || border.b > 0 || border.l > 0 || border.r > 0) ||
		radius.tl > 0 ||
		radius.tr > 0 ||
		radius.bl > 0 ||
		radius.br > 0

	if has_chrome {
		oni.Draw_Rectangle(rect, background, radius, border, border_color)
	}
	oni.draw_texture_fitted(props.texture, src, content, dst, tint, radius)

	oni.Children(child, layout_id, config, frame_state)
}
