package oni_widgets

import o ".."
import set "../set"

/*
Author-time style overrides for auto-emitted and standalone scrollbars.

Unset Cfg fields keep the scrollbar theme defaults. `visible = false` suppresses
auto-emitted bars on a scrollport. `size` is track thickness in design pixels.
*/
Scroll_Bar_Style :: struct {
	size:       o.Cfg(o.Style_F32),
	background: o.Cfg(o.Colors),
	thumb:      o.Cfg(o.Colors),
	radius:     o.Cfg(o.Radius),
	opacity:    o.Cfg(o.Style_F32),
	min_thumb:  o.Cfg(o.Style_F32),
	visible:    o.Cfg(o.Style_Bool),
}

/*
Scrollbar widget configuration extending Widget_Config.
*/
Scroll_Bar_Config :: o.Widget_Config

/*
Scrollbar widget per-frame state merged with its resolved style config.
*/
Scroll_Bar_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Scrollbar widget event snapshot with frame_state and optional input metadata.
*/
Scroll_Bar_Event :: o.Widget_Event(Scroll_Bar_State)

/*
Scrollbar props: axis, parent scroll pointers, metrics, style, and handlers.

On thumb drag the bar writes the active axis into `parent_scroll_x` / `parent_scroll_y`
and invokes `on_scroll` with both parent scroll values.

`style` overrides track chrome (`background`, `radius`, `opacity`), thumb fill
(`thumb`), and geometry (`size` is unused here — callers set width/height; `min_thumb`
floors thumb length).
*/
Scroll_Bar_Props :: struct {
	config:                       Scroll_Bar_Config,
	style:                        Scroll_Bar_Style,
	axis:                         o.Scroll_Axis,
	parent_scroll_x:              ^f32,
	parent_scroll_y:              ^f32,
	viewport:                     f32,
	content:                      f32,
	child:                        proc(frame_state: Scroll_Bar_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Scroll_Bar_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Scroll_Bar_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Scroll_Bar_Event),
	on_blur:                      proc(event: Scroll_Bar_Event),
	on_mouse_enter:               proc(event: Scroll_Bar_Event),
	on_mouse_leave:               proc(event: Scroll_Bar_Event),
	on_mouse_pressed:             proc(event: Scroll_Bar_Event),
	on_mouse_down:                proc(event: Scroll_Bar_Event),
	on_mouse_released:            proc(event: Scroll_Bar_Event),
	on_mouse_move:                proc(event: Scroll_Bar_Event),
	on_click:                     proc(event: Scroll_Bar_Event),
	on_contextmenu:               proc(event: Scroll_Bar_Event),
	on_key_pressed:               proc(event: Scroll_Bar_Event),
	on_key_down:                  proc(event: Scroll_Bar_Event),
	on_key_released:              proc(event: Scroll_Bar_Event),
}

@(private)
scroll_bar_theme_base :: proc(frame_state: ^Scroll_Bar_State) -> Scroll_Bar_Config {
	_ = frame_state
	return Scroll_Bar_Config {
		kind = .SCROLL_BAR,
		background = set.Colors(o.Color.MUTED),
		radius = set.Radius(f32(4)),
	}
}

/*
Returns whether auto-emitted scrollbars should paint for this style.
Unset `visible` means shown.
*/
scroll_bar_style_visible :: proc(style: Scroll_Bar_Style) -> bool {
	if style.visible.mode == .UNSET do return true
	return o.cfg_style_bool(style.visible)
}

/*
Resolved track thickness from style, falling back to the engine default.
*/
scroll_bar_style_size :: proc(style: Scroll_Bar_Style) -> f32 {
	return o.cfg_style_f32(style.size, o.SCROLL_BAR_DEFAULT_SIZE)
}

/*
Resolved minimum thumb length from style, falling back to the engine default.
*/
scroll_bar_style_min_thumb :: proc(style: Scroll_Bar_Style) -> f32 {
	return o.cfg_style_f32(style.min_thumb, o.SCROLL_BAR_MIN_THUMB)
}

/*
Merges Scroll_Bar_Style chrome fields into a scrollbar config (track paint).
*/
scroll_bar_apply_style_config :: proc(config: ^Scroll_Bar_Config, style: Scroll_Bar_Style) {
	if config == nil do return
	if style.background.mode != .UNSET do config.background = style.background
	if style.radius.mode != .UNSET do config.radius = style.radius
	if style.opacity.mode != .UNSET do config.opacity = style.opacity
}

@(private)
scroll_bar_parent_scroll :: proc(props: Scroll_Bar_Props) -> f32 {
	switch props.axis {
	case .X:
		if props.parent_scroll_x != nil do return props.parent_scroll_x^
	case .Y:
		if props.parent_scroll_y != nil do return props.parent_scroll_y^
	}
	return 0
}

@(private)
scroll_bar_set_parent_scroll :: proc(props: Scroll_Bar_Props, value: f32) {
	switch props.axis {
	case .X:
		if props.parent_scroll_x != nil do props.parent_scroll_x^ = value
	case .Y:
		if props.parent_scroll_y != nil do props.parent_scroll_y^ = value
	}
	if props.on_scroll != nil {
		sx: f32
		sy: f32
		if props.parent_scroll_x != nil do sx = props.parent_scroll_x^
		if props.parent_scroll_y != nil do sy = props.parent_scroll_y^
		props.on_scroll(sx, sy)
	}
}

@(private)
scroll_bar_thumb_rect :: proc(
	track: o.Rect,
	axis: o.Scroll_Axis,
	viewport, content, scroll, min_thumb: f32,
) -> o.Rect {
	switch axis {
	case .X:
		thumb_w, thumb_x := o.scroll_bar_thumb_geometry(
			track.w,
			viewport,
			content,
			scroll,
			min_thumb,
		)
		return {x = track.x + thumb_x, y = track.y, w = thumb_w, h = track.h}
	case .Y:
		thumb_h, thumb_y := o.scroll_bar_thumb_geometry(
			track.h,
			viewport,
			content,
			scroll,
			min_thumb,
		)
		return {x = track.x, y = track.y + thumb_y, w = track.w, h = thumb_h}
	}
	return {}
}

@(private)
scroll_bar_handle_drag :: proc(
	props: Scroll_Bar_Props,
	layout_id: o.UI_Id,
	track: o.Rect,
	thumb: o.Rect,
	hovered: bool,
) {
	drag := o.scroll_bar_drag_entry(layout_id)
	if drag == nil do return

	max_scroll := max(0, props.content - props.viewport)
	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}

	if o.w_ctx.left_mouse.pressed && hovered {
		on_thumb :=
			mouse.x >= thumb.x &&
			mouse.x < thumb.x + thumb.w &&
			mouse.y >= thumb.y &&
			mouse.y < thumb.y + thumb.h
		drag.active = true
		if props.axis == .X {
			if on_thumb {
				drag.grab_offset = mouse.x - thumb.x
			} else {
				drag.grab_offset = thumb.w * 0.5
				next := o.scroll_bar_scroll_from_pointer(
					mouse.x,
					track.x,
					track.w,
					thumb.w,
					drag.grab_offset,
					max_scroll,
				)
				scroll_bar_set_parent_scroll(props, next)
			}
		} else {
			if on_thumb {
				drag.grab_offset = mouse.y - thumb.y
			} else {
				drag.grab_offset = thumb.h * 0.5
				next := o.scroll_bar_scroll_from_pointer(
					mouse.y,
					track.y,
					track.h,
					thumb.h,
					drag.grab_offset,
					max_scroll,
				)
				scroll_bar_set_parent_scroll(props, next)
			}
		}
		o.Stop_Propagation()
	}

	if drag.active && o.w_ctx.left_mouse.down {
		next: f32
		if props.axis == .X {
			next = o.scroll_bar_scroll_from_pointer(
				mouse.x,
				track.x,
				track.w,
				thumb.w,
				drag.grab_offset,
				max_scroll,
			)
		} else {
			next = o.scroll_bar_scroll_from_pointer(
				mouse.y,
				track.y,
				track.h,
				thumb.h,
				drag.grab_offset,
				max_scroll,
			)
		}
		if next != scroll_bar_parent_scroll(props) {
			scroll_bar_set_parent_scroll(props, next)
		}
		o.Stop_Propagation()
	}

	if drag.active && o.w_ctx.left_mouse.released {
		o.scroll_bar_drag_clear(layout_id)
		o.Stop_Propagation()
	}
}

@(private)
scroll_bar_resolve_thumb_rgba :: proc(
	style: Scroll_Bar_Style,
	frame_state: ^Scroll_Bar_State,
	event: Scroll_Bar_Event,
) -> o.RGBA {
	if style.thumb.mode != .UNSET {
		if rgba, ok := o.to_rgba(style.thumb.value, frame_state, event); ok {
			return rgba
		}
	}
	thumb_bg: o.RGBA
	if rgba, ok := o.to_rgba(o.Color.FOREGROUND, frame_state, event); ok {
		thumb_bg = rgba
		thumb_bg.a = u8(f32(thumb_bg.a) * 0.45)
	}
	return thumb_bg
}

/*
Renders a scrollbar track and thumb that writes parent scroll_x / scroll_y on drag.

Layout pass registers the bar; draw pass paints chrome and handles thumb interaction.
*/
Scroll_Bar :: proc(props: Scroll_Bar_Props) {
	cfg := props.config
	scroll_bar_apply_style_config(&cfg, props.style)
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Scroll_Bar_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	merged_props := props
	merged_props.config = cfg
	event := widget_refresh_merged(merged_props, &frame_state, scroll_bar_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(merged_props, Scroll_Bar_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	min_thumb := scroll_bar_style_min_thumb(props.style)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(merged_props, &frame_state, scroll_bar_theme_base)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if !skip_layout {
			can_interact := widget_can_interact(handlers, &frame_state)
			if can_interact && should_auto_focus {
				widget_apply_auto_focus(key, true)
				frame_state.is_focused = true
			}
			widget_register_tab_order(key, config.tabbable, can_interact)
			o.Children(child, layout_id, config, frame_state)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	got_focus, lost_focus := widget_handle_interaction(
		merged_props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)

	event, _ = widget_refresh_merged_if_interaction_changed(
		merged_props,
		&frame_state,
		scroll_bar_theme_base,
		style_fp,
	)
	config = frame_state.config

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}
		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	scroll := scroll_bar_parent_scroll(props)
	thumb := scroll_bar_thumb_rect(
		rect,
		props.axis,
		props.viewport,
		props.content,
		scroll,
		min_thumb,
	)

	if widget_can_interact(handlers, &frame_state) {
		scroll_bar_handle_drag(props, layout_id, rect, thumb, frame_state.is_hovered)
	}

	track_bg: o.RGBA
	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		track_bg = resolved_background
	}

	radius: o.Radius_px
	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	thumb_bg := scroll_bar_resolve_thumb_rgba(props.style, &frame_state, event)

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	if !o.ui_layout_paint_skip(layout_id) {
		o.Draw_Rectangle(rect, track_bg, radius, {}, {})
		o.Draw_Rectangle(thumb, thumb_bg, radius, {}, {})
	}

	o.Children(child, layout_id, config, frame_state)

	widget_dispatch_events(merged_props, &frame_state, handlers, event, key, got_focus, lost_focus)
}
