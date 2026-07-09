package widgets

import o ".."


Image_Config :: o.Widget_Config
Image_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)
Image_Event :: o.Widget_Event(Image_State)

/*
Image widget props: source rect, tint, fit/pos overrides, and event handlers.
*/
Image_Props :: struct {
	config:                       Image_Config,
	texture:                      o.Texture_Handle,
	src, dst:                     o.Rect,
	tint:                         o.Colors,
	alt:                          string,
	texture_fit:                  o.Cfg(o.Style_Image_Fit),
	texture_pos:                  o.Cfg(o.Style_Image_Pos),
	child:                        proc(frame_state: Image_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Image_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Image_State) -> o.Mount,
	on_focus:                     proc(event: Image_Event),
	on_blur:                      proc(event: Image_Event),
	on_mouse_enter:               proc(event: Image_Event),
	on_mouse_leave:               proc(event: Image_Event),
	on_mouse_pressed:             proc(event: Image_Event),
	on_mouse_down:                proc(event: Image_Event),
	on_mouse_released:            proc(event: Image_Event),
	on_mouse_move:                proc(event: Image_Event),
	on_click:                     proc(event: Image_Event),
	on_contextmenu:               proc(event: Image_Event),
	on_key_pressed:               proc(event: Image_Event),
	on_key_down:                  proc(event: Image_Event),
	on_key_released:              proc(event: Image_Event),
}

/*
Returns the default texture widget theme config, muted when the widget is disabled.
*/
image_theme_base :: proc(frame_state: ^Image_State) -> Image_Config {
	color := o.Color.FOREGROUND

	if frame_state.is_disabled {
		color = o.Color.MUTED
	}

	return Image_Config{kind = .RECT}
}

/*
Merges theme defaults, prop overrides, and live frame_state into a resolved config.

Applies explicit texture_fit and texture_pos props when they are set.
*/
image_config :: proc(props: Image_Props, frame_state: ^Image_State) -> o.Resolved_Widget_Config {
	event := widget_event(frame_state^)

	base := image_theme_base(frame_state)
	override := props.config

	if props.texture_fit.mode != .UNSET do override.texture_fit = props.texture_fit
	if props.texture_pos.mode != .UNSET do override.texture_pos = props.texture_pos

	return o.resolve_widget_config(base, override, frame_state, event)
}

/*
Refreshes merged config on frame_state and returns a fresh texture event snapshot.
*/
@(private)
image_refresh_merged :: proc(props: Image_Props, frame_state: ^Image_State) -> Image_Event {
	frame_state.config = image_config(props, frame_state)
	return widget_event(frame_state^)
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
	config: o.Resolved_Widget_Config,
	frame_state: ^Image_State,
	event: Image_Event,
) -> o.Vec2 {
	src_w, src_h := texture_src_size(props)
	if src_w <= 0 || src_h <= 0 do return {}

	width_auto := !o.length_is_definite(config.width)
	height_auto := !o.length_is_definite(config.height)
	if !width_auto && !height_auto do return {}

	fit := o.Image_Fit.FILL
	if resolved_fit, fit_ok := o.resolve_texture_fit(config.texture_fit, frame_state, event);
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

	padding, _ := o.resolve_padding_value(config.padding)
	border, _ := o.resolve_border_value(config.border)
	inset_w := padding.l + padding.r + border.l + border.r
	inset_h := padding.t + padding.b + border.t + border.b

	measure: o.Vec2
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
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Image_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = was_focused,
	}

	event := image_refresh_merged(props, &frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Image_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if o.ui_pass() == .Layout {
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

		o.ui_push_scope(layout_id)
		node := o.layout_push_node(layout_id, config)

		if measure := texture_measure_size(props, config, &frame_state, event);
		   measure.x > 0 || measure.y > 0 {
			o.layout_set_measure_size(node, measure)
		}

		o.ui_push_style(o.style_child_context(config))

		if child != nil do child(frame_state)

		o.ui_pop_style()
		o.layout_pop_node()
		o.ui_pop_scope()

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := o.ui_layout_rect(layout_id)
	rect := widget_resolve_hit_rect(layout_rect, config)

	got_focus, lost_focus := widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		rect,
		config,
	)

	event = image_refresh_merged(props, &frame_state)
	config = frame_state.config

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	widget_dispatch_events(props, &frame_state, handlers, event, key, got_focus, lost_focus)

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	config = frame_state.config

	background: o.RGBA
	if resolved_background, background_ok := o.to_rgba(config.background, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd
	if resolved_border, border_ok := o.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	padding: o.Pd
	if resolved_padding, padding_ok := o.resolve_padding(config.padding, &frame_state, event);
	   padding_ok {
		padding = resolved_padding
	}

	border_color: o.RGBA
	if resolved_border_color, border_color_ok := o.to_rgba(
		config.border_color,
		&frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_corners
	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	src := props.src
	if src.w == 0 && src.h == 0 {
		src_w, src_h := texture_src_size(props)
		if src_w > 0 && src_h > 0 {
			src = {0, 0, src_w, src_h}
		}
	}

	content := o.layout_inner_rect(rect, border, padding)
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

	fit := o.Image_Fit.FILL
	if resolved_fit, fit_ok := o.resolve_texture_fit(config.texture_fit, &frame_state, event);
	   fit_ok {
		fit = resolved_fit
	}

	pos := o.Resolved_Image_Pos{0.5, 0.5, 0, 0}
	if resolved_pos, pos_ok := o.resolve_texture_pos(config.texture_pos, &frame_state, event);
	   pos_ok {
		pos = resolved_pos
	}

	dst := container
	src, dst = o.texture_fit_rects(src, container, fit, pos)

	tint := o.RGBA{255, 255, 255, 255}
	if resolved_tint, tint_ok := o.to_rgba(props.tint, &frame_state, event); tint_ok {
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
		o.Draw_Rectangle(rect, background, radius, border, border_color)
	}

	o.draw_texture_fitted(props.texture, src, content, dst, tint, radius)

	o.Children(child, layout_id, config, frame_state)
}
