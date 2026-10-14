package oni_widgets

import o ".."
import set "../set"

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
Scrollbar thumb configuration extending Widget_Config.
*/
Scroll_Bar_Thumb_Config :: o.Widget_Config

/*
Scrollbar thumb part props.

Customizes thumb chrome (`background`, `radius`, `border`, `border_color`, `opacity`).
When `background` is unset, falls back to theme `FOREGROUND` at 0.45 alpha.
When `radius` is unset, inherits the parent `Scroll_Bar` track radius.
*/
Scroll_Bar_Thumb_Props :: struct {
	config: Scroll_Bar_Thumb_Config,
}

/*
Scrollbar props: axis, parent scroll pointers, metrics, minimum thumb length, and handlers.

On thumb drag the bar writes the active axis into `parent_scroll_x` / `parent_scroll_y`
and invokes `on_scroll` with both parent scroll values.

Track chrome (`background`, `radius`, `border`, `border_color`, `opacity`) comes from
`config`. When `child` is nil, `Scroll_Bar` renders `Scroll_Bar_Thumb({})` by default.
*/
Scroll_Bar_Props :: struct {
	config:                       Scroll_Bar_Config,
	min_thumb:                    o.Cfg(o.Style_F32),
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
SCROLL_BAR_CTX_MAX :: 16

@(private)
Scroll_Bar_Ctx :: struct {
	active:       bool,
	layout_id:    o.UI_Id,
	thumb_rect:   o.Rect,
	track_radius: o.Radius_px,
	frame_state:  Scroll_Bar_State,
	event:        Scroll_Bar_Event,
}

@(private)
scroll_bar_ctx_stack: [SCROLL_BAR_CTX_MAX]Scroll_Bar_Ctx

@(private)
scroll_bar_ctx_depth: int

@(private)
scroll_bar_ctx_push :: proc(ctx: Scroll_Bar_Ctx) {
	assert(scroll_bar_ctx_depth < SCROLL_BAR_CTX_MAX)
	scroll_bar_ctx_stack[scroll_bar_ctx_depth] = ctx
	scroll_bar_ctx_depth += 1
}

@(private)
scroll_bar_ctx_pop :: proc() {
	assert(scroll_bar_ctx_depth > 0)
	scroll_bar_ctx_depth -= 1
	scroll_bar_ctx_stack[scroll_bar_ctx_depth] = {}
}

@(private)
scroll_bar_ctx_ok :: proc() -> bool {
	return scroll_bar_ctx_depth > 0 && scroll_bar_ctx_stack[scroll_bar_ctx_depth - 1].active
}

@(private)
scroll_bar_ctx_top :: proc() -> ^Scroll_Bar_Ctx {
	assert(scroll_bar_ctx_depth > 0)

	return &scroll_bar_ctx_stack[scroll_bar_ctx_depth - 1]
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

@(private)
scroll_bar_resolve_min_thumb :: proc(props: Scroll_Bar_Props) -> f32 {
	return o.cfg_style_f32(props.min_thumb, o.SCROLL_BAR_MIN_THUMB)
}

@(private)
scroll_bar_parent_scroll :: proc(props: Scroll_Bar_Props) -> f32 {
	switch props.axis {
	case .X:
		if props.parent_scroll_x != nil {
			return props.parent_scroll_x^
		}
	case .Y:
		if props.parent_scroll_y != nil {
			return props.parent_scroll_y^
		}
	}

	return 0
}

@(private)
scroll_bar_set_parent_scroll :: proc(props: Scroll_Bar_Props, value: f32) {
	switch props.axis {
	case .X:
		if props.parent_scroll_x != nil {
			props.parent_scroll_x^ = value
		}
	case .Y:
		if props.parent_scroll_y != nil {
			props.parent_scroll_y^ = value
		}
	}

	if props.on_scroll != nil {
		sx: f32
		sy: f32

		if props.parent_scroll_x != nil {
			sx = props.parent_scroll_x^
		}

		if props.parent_scroll_y != nil {
			sy = props.parent_scroll_y^
		}

		props.on_scroll(sx, sy)
	}
}

@(private)
scroll_bar_bind_layout_chrome :: proc(
	layout_id: o.UI_Id,
	axis: o.Scroll_Axis,
	viewport, content, scroll, min_thumb: f32,
) {
	node, ok := o.layout_node_by_id(layout_id)

	if !ok {
		return
	}

	o.layout_set_scroll_bar(
		node,
		{
			axis = axis,
			viewport = viewport,
			content = content,
			scroll = scroll,
			min_thumb = min_thumb,
			active = true,
		},
	)
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

	if drag == nil {
		return
	}

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
	thumb_config: Scroll_Bar_Thumb_Config,
	frame_state: ^Scroll_Bar_State,
	event: Scroll_Bar_Event,
) -> o.RGBA {
	if thumb_config.background.mode != .UNSET {
		if rgba, ok := o.to_rgba(thumb_config.background.value, frame_state, event); ok {
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

@(private)
scroll_bar_default_child :: proc(_: Scroll_Bar_State) {
	Scroll_Bar_Thumb({})
}

/*
Renders the thumb inside a `Scroll_Bar`.

Must be used inside `Scroll_Bar` `child`. When `Scroll_Bar.child` is nil,
`Scroll_Bar` invokes `Scroll_Bar_Thumb({})` automatically.
*/
Scroll_Bar_Thumb :: proc(props: Scroll_Bar_Thumb_Props) {
	if !scroll_bar_ctx_ok() {
		return
	}

	if o.ui_pass() != .Draw {
		return
	}

	ctx := scroll_bar_ctx_top()

	if o.ui_layout_paint_skip(ctx.layout_id) {
		return
	}

	radius := ctx.track_radius

	if props.config.radius.mode != .UNSET {
		if resolved_radius, ok := o.resolve_radius(
			props.config.radius.value,
			&ctx.frame_state,
			ctx.event,
		); ok {
			radius = resolved_radius
		}
	}

	border: o.Bd_px

	if props.config.border.mode != .UNSET {
		if resolved_border, ok := o.resolve_border(
			props.config.border.value,
			&ctx.frame_state,
			ctx.event,
		); ok {
			border = resolved_border
		}
	}

	border_color: o.RGBA

	if props.config.border_color.mode != .UNSET {
		if resolved_bc, ok := o.to_rgba(
			props.config.border_color.value,
			&ctx.frame_state,
			ctx.event,
		); ok {
			border_color = resolved_bc
		}
	}

	thumb_bg := scroll_bar_resolve_thumb_rgba(props.config, &ctx.frame_state, ctx.event)

	has_opacity := props.config.opacity.mode != .UNSET

	if has_opacity {
		o.Draw_Push_Opacity(o.cfg_style_f32(props.config.opacity, 1))
	}

	defer if has_opacity {
		o.Draw_Pop_Opacity()
	}

	o.Draw_Rectangle(ctx.thumb_rect, thumb_bg, radius, border, border_color)
}

/*
Renders a scrollbar track and thumb that writes parent scroll_x / scroll_y on drag.

Layout pass registers the bar and binds thumb geometry inputs; draw paints from
the layout-owned track rect and maps the current scroll onto that track only.
*/
Scroll_Bar :: proc(props: Scroll_Bar_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Scroll_Bar_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, scroll_bar_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child != nil ? props.child : scroll_bar_default_child
	handlers := widget_lifecycle_handlers(props, Scroll_Bar_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	min_thumb := scroll_bar_resolve_min_thumb(props)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, scroll_bar_theme_base)
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

			scroll_bar_ctx_push(
				{
					active      = true,
					layout_id   = layout_id,
					frame_state = frame_state,
					event       = event,
				},
			)
			defer scroll_bar_ctx_pop()

			o.Children(child, layout_id, config, frame_state)
			scroll_bar_bind_layout_chrome(
				layout_id,
				props.axis,
				props.viewport,
				props.content,
				scroll_bar_parent_scroll(props),
				min_thumb,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props,
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
		props,
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
	// Paint/hit thumb from the layout-owned track + current scroll. Do not
	// re-finalize layout chrome during draw.
	thumb := o.layout_scroll_bar_thumb_rect(
		rect,
		props.axis,
		props.viewport,
		props.content,
		scroll,
		min_thumb,
	)

	if widget_can_interact(handlers, &frame_state) {
		scroll_bar_handle_drag(props, layout_id, rect, thumb, frame_state.is_hovered)
		scroll = scroll_bar_parent_scroll(props)
		thumb = o.layout_scroll_bar_thumb_rect(
			rect,
			props.axis,
			props.viewport,
			props.content,
			scroll,
			min_thumb,
		)
	}

	track_bg: o.RGBA

	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		track_bg = resolved_background
	}

	track_border: o.Bd_px

	if resolved_border, border_ok := o.resolve_border(config.border, &frame_state, event);
	   border_ok {
		track_border = resolved_border
	}

	track_border_color: o.RGBA

	if resolved_border_color, border_color_ok := o.style_border_color_rgba(
		config,
		&frame_state,
		event,
	); border_color_ok {
		track_border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	if !o.ui_layout_paint_skip(layout_id) {
		o.Draw_Rectangle(rect, track_bg, radius, track_border, track_border_color)
	}

	scroll_bar_ctx_push(
		{
			active       = true,
			layout_id    = layout_id,
			thumb_rect   = thumb,
			track_radius = radius,
			frame_state  = frame_state,
			event        = event,
		},
	)
	defer scroll_bar_ctx_pop()

	o.Children(child, layout_id, config, frame_state)

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}
