package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Author-time style overrides for slider track, range fill, and thumbs.

Unset Cfg fields keep the slider theme defaults.
*/
Slider_Style :: struct {
	track:           o.Cfg(o.Colors),
	range:           o.Cfg(o.Colors),
	thumb:           o.Cfg(o.Colors),
	thumb_border:    o.Cfg(o.Colors),
	thumb_size:      o.Cfg(o.Style_F32),
	track_thickness: o.Cfg(o.Style_F32),
	radius:          o.Cfg(o.Radius),
}

/*
Slider configuration.
*/
Slider_Config :: o.Widget_Config

/*
Slider per-frame state, including the active working values.
*/
Slider_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	values:            [o.SLIDER_MAX_THUMBS]f32,
	value_count:       int,
	min:               f32,
	max:               f32,
	step:              f32,
	orientation:       o.Slider_Orientation,
	inverted:          bool,
}

/*
Per-thumb state passed to an optional custom `thumb` builder.

`index` is 0 for a single thumb, or 0/1 for a range. `is_active` is true for the
thumb currently targeted by pointer drag or keyboard stepping.
*/
Slider_Thumb_State :: struct {
	using slider: Slider_State,
	index:        int,
	value:        f32,
	is_active:    bool,
}

/*
Slider event snapshot.
*/
Slider_Event :: o.Widget_Event(Slider_State)

/*
Slider props.

`values` is owned by the caller and must be passed every frame with length 1
(single thumb) or 2 (range). Pointer and keyboard interaction report updates
through `on_value_change` only — the widget never mutates the caller's slice.
`on_value_commit` fires once when an active pointer drag ends.

When `thumb` is set it replaces the built-in thumb chrome for every thumb; the
callback runs once per thumb inside an absolutely positioned host matching the
thumb hit rect. Track and range fill still use the default painter.
*/
Slider_Props :: struct {
	config:                       Slider_Config,
	values:                       []f32,
	min:                          f32,
	max:                          f32,
	step:                         f32,
	min_steps_between_thumbs:     f32,
	orientation:                  o.Slider_Orientation,
	inverted:                     bool,
	disabled:                     bool,
	style:                        Slider_Style,
	thumb:                        proc(frame_state: Slider_Thumb_State),
	on_value_change:              proc(values: []f32),
	on_value_commit:              proc(values: []f32),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Slider_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Slider_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Slider_Event),
	on_blur:                      proc(event: Slider_Event),
	on_mouse_enter:               proc(event: Slider_Event),
	on_mouse_leave:               proc(event: Slider_Event),
	on_mouse_pressed:             proc(event: Slider_Event),
	on_mouse_down:                proc(event: Slider_Event),
	on_mouse_released:            proc(event: Slider_Event),
	on_mouse_move:                proc(event: Slider_Event),
	on_click:                     proc(event: Slider_Event),
	on_contextmenu:               proc(event: Slider_Event),
	on_key_pressed:               proc(event: Slider_Event),
	on_key_down:                  proc(event: Slider_Event),
	on_key_released:              proc(event: Slider_Event),
}

@(private)
Slider_Action_Context :: struct {
	active:                   bool,
	values:                   [o.SLIDER_MAX_THUMBS]f32,
	count:                    int,
	min:                      f32,
	max:                      f32,
	step:                     f32,
	min_steps_between_thumbs: f32,
	orientation:              o.Slider_Orientation,
	inverted:                 bool,
	layout_id:                o.UI_Id,
	parent_key:               string,
	thumb_size:               f32,
	track_thickness:          f32,
	active_thumb:             int,
	thumb:                    proc(frame_state: Slider_Thumb_State),
	on_value_change:          proc(values: []f32),
	on_value_commit:          proc(values: []f32),
	on_key_down:              proc(event: Slider_Event),
	on_key_pressed:           proc(event: Slider_Event),
	on_key_released:          proc(event: Slider_Event),
}

@(private)
slider_action_context: Slider_Action_Context

@(private)
slider_style_thumb_size :: proc(style: Slider_Style) -> f32 {
	return o.cfg_style_f32(style.thumb_size, o.SLIDER_DEFAULT_THUMB_SIZE)
}

@(private)
slider_style_track_thickness :: proc(style: Slider_Style) -> f32 {
	return o.cfg_style_f32(style.track_thickness, o.SLIDER_DEFAULT_TRACK_THICKNESS)
}

@(private)
slider_resolve_bounds :: proc(props: Slider_Props) -> (min_v, max_v, step: f32) {
	min_v = props.min
	max_v = props.max
	step = props.step

	if min_v == 0 && max_v == 0 {
		min_v = o.SLIDER_DEFAULT_MIN
		max_v = o.SLIDER_DEFAULT_MAX
	}

	if step == 0 && props.step == 0 && props.min == 0 && props.max == 0 {
		step = o.SLIDER_DEFAULT_STEP
	}

	min_v, max_v = o.slider_normalize_bounds(min_v, max_v)

	return min_v, max_v, step
}

@(private)
slider_theme_base :: proc(frame_state: ^Slider_State) -> Slider_Config {
	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	width := set.Width(o.SLIDER_DEFAULT_WIDTH)
	height := set.Height(o.SLIDER_DEFAULT_HEIGHT)

	if frame_state.orientation == .VERTICAL {
		width = set.Width(o.SLIDER_DEFAULT_HEIGHT)
		height = set.Height(o.SLIDER_DEFAULT_WIDTH)
	}

	return Slider_Config {
		kind = .SLIDER,
		tabbable = set.Tabbable(true),
		width = width,
		height = height,
		justify = set.Justify(o.Justify_Align.CENTER),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
slider_refresh_merged :: proc(props: Slider_Props, frame_state: ^Slider_State) -> Slider_Event {
	event := widget_event(frame_state^)
	base := slider_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
slider_emit_values :: proc(ctx: ^Slider_Action_Context, commit: bool) {
	if ctx == nil || ctx.count <= 0 {
		return
	}

	slice := ctx.values[:ctx.count]

	if ctx.on_value_change != nil {
		ctx.on_value_change(slice)
	}

	if commit && ctx.on_value_commit != nil {
		ctx.on_value_commit(slice)
	}
}

@(private)
slider_key_edge :: proc(code: o.Scancode) -> bool {
	if o.w_ctx == nil || o.shortcut_key_consumed(code) {
		return false
	}

	idx := int(code)

	if idx < 0 || idx >= len(o.w_ctx.keys) {
		return false
	}

	key := o.w_ctx.keys[idx]

	return key.pressed || key.repeat
}

@(private)
slider_consume_key :: proc(code: o.Scancode) {
	o.shortcut_consume_key(code)
}

@(private)
slider_handle_keyboard :: proc(frame_state: ^Slider_State) -> bool {
	ctx := &slider_action_context

	if !ctx.active || frame_state == nil || !frame_state.is_focused || frame_state.is_disabled {
		return false
	}

	if ctx.count <= 0 {
		return false
	}

	drag := o.slider_drag_entry(ctx.layout_id)

	if drag == nil {
		return false
	}

	thumb := drag.thumb_index

	if thumb < 0 || thumb >= ctx.count {
		thumb = 0
		drag.thumb_index = 0
	}

	unit := o.slider_effective_step(ctx.min, ctx.max, ctx.step)
	page := o.slider_page_delta(ctx.min, ctx.max, ctx.step)
	shift := o.state != nil && o.state.input.modifiers.shift
	delta: f32
	handled := false
	code: o.Scancode

	inc_code := o.Scancode.RIGHT
	dec_code := o.Scancode.LEFT
	alt_inc := o.Scancode.UP
	alt_dec := o.Scancode.DOWN

	if ctx.orientation == .VERTICAL {
		inc_code = .UP
		dec_code = .DOWN
		alt_inc = .RIGHT
		alt_dec = .LEFT
	}

	if ctx.inverted {
		inc_code, dec_code = dec_code, inc_code
		alt_inc, alt_dec = alt_dec, alt_inc
	}

	if slider_key_edge(.HOME) {
		code = .HOME
		handled = o.slider_set_thumb_value(
			&ctx.values,
			ctx.count,
			thumb,
			ctx.min,
			ctx.min,
			ctx.max,
			ctx.step,
			ctx.min_steps_between_thumbs,
		)
		slider_consume_key(.HOME)
	} else if slider_key_edge(.END) {
		code = .END
		handled = o.slider_set_thumb_value(
			&ctx.values,
			ctx.count,
			thumb,
			ctx.max,
			ctx.min,
			ctx.max,
			ctx.step,
			ctx.min_steps_between_thumbs,
		)
		slider_consume_key(.END)
	} else if slider_key_edge(.PAGEUP) {
		code = .PAGEUP
		delta = page
		slider_consume_key(.PAGEUP)
	} else if slider_key_edge(.PAGEDOWN) {
		code = .PAGEDOWN
		delta = -page
		slider_consume_key(.PAGEDOWN)
	} else if slider_key_edge(inc_code) {
		code = inc_code
		delta = shift ? unit * 10 : unit
		slider_consume_key(inc_code)
	} else if slider_key_edge(dec_code) {
		code = dec_code
		delta = shift ? -(unit * 10) : -unit
		slider_consume_key(dec_code)
	} else if slider_key_edge(alt_inc) {
		code = alt_inc
		delta = shift ? unit * 10 : unit
		slider_consume_key(alt_inc)
	} else if slider_key_edge(alt_dec) {
		code = alt_dec
		delta = shift ? -(unit * 10) : -unit
		slider_consume_key(alt_dec)
	}

	if delta != 0 {
		handled = o.slider_set_thumb_value(
			&ctx.values,
			ctx.count,
			thumb,
			ctx.values[thumb] + delta,
			ctx.min,
			ctx.max,
			ctx.step,
			ctx.min_steps_between_thumbs,
		)
	}

	if handled {
		frame_state.values = ctx.values
		frame_state.value_count = ctx.count
		slider_emit_values(ctx, false)
	}

	_ = code

	return handled
}

@(private)
slider_on_key_down :: proc(event: Slider_Event) {
	ctx := &slider_action_context

	if !ctx.active {
		return
	}

	if ctx.on_key_down != nil {
		ctx.on_key_down(event)
	}
}

@(private)
slider_on_key_pressed :: proc(event: Slider_Event) {
	ctx := &slider_action_context

	if !ctx.active {
		return
	}

	if ctx.on_key_pressed != nil {
		ctx.on_key_pressed(event)
	}
}

@(private)
slider_on_key_released :: proc(event: Slider_Event) {
	ctx := &slider_action_context

	if !ctx.active {
		return
	}

	if ctx.on_key_released != nil {
		ctx.on_key_released(event)
	}
}

@(private)
slider_point_in_rect :: proc(p: o.Vec2, r: o.Rect) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

@(private)
slider_bind_layout_chrome :: proc(
	layout_id: o.UI_Id,
	orientation: o.Slider_Orientation,
	values: [o.SLIDER_MAX_THUMBS]f32,
	count: int,
	min_v, max_v: f32,
	inverted: bool,
	thumb_size: f32,
	track_thickness: f32,
) {
	node, ok := o.layout_node_by_id(layout_id)

	if !ok {
		return
	}

	o.layout_set_slider(
		node,
		{
			orientation = orientation,
			values = values,
			count = count,
			min = min_v,
			max = max_v,
			inverted = inverted,
			thumb_size = thumb_size,
			track_thickness = track_thickness,
			active = true,
		},
	)
}

@(private)
slider_handle_drag :: proc(
	frame_state: ^Slider_State,
	track: o.Rect,
	thumbs: [o.SLIDER_MAX_THUMBS]o.Rect,
	thumb_size: f32,
	hovered: bool,
	interactive: bool,
) {
	ctx := &slider_action_context

	if !ctx.active || frame_state == nil {
		return
	}

	drag := o.slider_drag_get(ctx.layout_id)

	if drag != nil && drag.active && (frame_state.is_disabled || ctx.count <= 0 || !interactive) {
		frame_state.values = ctx.values
		frame_state.value_count = ctx.count
		slider_emit_values(ctx, true)
		o.slider_drag_end(ctx.layout_id)
		o.Stop_Propagation()

		return
	}

	if !interactive || frame_state.is_disabled || ctx.count <= 0 {
		return
	}

	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	axis_pointer := mouse.x
	track_origin := track.x
	track_len := track.w

	if ctx.orientation == .VERTICAL {
		axis_pointer = mouse.y
		track_origin = track.y
		track_len = track.h
	}

	if o.w_ctx.left_mouse.pressed && hovered {
		drag = o.slider_drag_entry(ctx.layout_id)

		if drag == nil {
			return
		}

		thumb_hit := -1

		for i in 0 ..< ctx.count {
			if slider_point_in_rect(mouse, thumbs[i]) {
				thumb_hit = i
				break
			}
		}

		drag.active = true

		if thumb_hit >= 0 {
			drag.thumb_index = thumb_hit

			if ctx.orientation == .VERTICAL {
				drag.grab_offset = mouse.y - thumbs[thumb_hit].y
			} else {
				drag.grab_offset = mouse.x - thumbs[thumb_hit].x
			}
		} else {
			t := o.slider_t_from_pointer(
				axis_pointer,
				track_origin,
				track_len,
				thumb_size,
				thumb_size * 0.5,
			)
			drag.thumb_index = o.slider_nearest_thumb(
				ctx.values,
				ctx.count,
				t,
				ctx.min,
				ctx.max,
				ctx.inverted,
			)
			drag.grab_offset = thumb_size * 0.5
			raw := o.slider_value_from_t(t, ctx.min, ctx.max, ctx.inverted)

			if o.slider_set_thumb_value(
				&ctx.values,
				ctx.count,
				drag.thumb_index,
				raw,
				ctx.min,
				ctx.max,
				ctx.step,
				ctx.min_steps_between_thumbs,
			) {
				frame_state.values = ctx.values
				frame_state.value_count = ctx.count
				slider_emit_values(ctx, false)
			}
		}

		o.Stop_Propagation()
	}

	if drag == nil {
		return
	}

	if drag.active && o.w_ctx.left_mouse.down {
		t := o.slider_t_from_pointer(
			axis_pointer,
			track_origin,
			track_len,
			thumb_size,
			drag.grab_offset,
		)
		raw := o.slider_value_from_t(t, ctx.min, ctx.max, ctx.inverted)

		if o.slider_set_thumb_value(
			&ctx.values,
			ctx.count,
			drag.thumb_index,
			raw,
			ctx.min,
			ctx.max,
			ctx.step,
			ctx.min_steps_between_thumbs,
		) {
			frame_state.values = ctx.values
			frame_state.value_count = ctx.count
			slider_emit_values(ctx, false)
		}

		o.Stop_Propagation()
	}

	ended :=
		drag.active &&
		(o.w_ctx.left_mouse.released ||
			(!o.w_ctx.left_mouse.down && !o.w_ctx.left_mouse.pressed))

	if ended {
		frame_state.values = ctx.values
		frame_state.value_count = ctx.count
		slider_emit_values(ctx, true)
		o.slider_drag_end(ctx.layout_id)
		o.Stop_Propagation()
	}
}

@(private)
slider_resolve_color :: proc(
	cfg: o.Cfg(o.Colors),
	fallback: o.Colors,
	frame_state: ^Slider_State,
	event: Slider_Event,
) -> o.RGBA {
	if cfg.mode != .UNSET {
		if rgba, ok := o.to_rgba(cfg.value, frame_state, event); ok {
			return rgba
		}
	}

	rgba: o.RGBA

	if resolved, ok := o.to_rgba(fallback, frame_state, event); ok {
		rgba = resolved
	}

	return rgba
}

@(private)
slider_draw_chrome :: proc(
	layout_id: o.UI_Id,
	track: o.Rect,
	range_rect: o.Rect,
	thumbs: [o.SLIDER_MAX_THUMBS]o.Rect,
	count: int,
	active_thumb: int,
	style: Slider_Style,
	frame_state: ^Slider_State,
	event: Slider_Event,
	radius: o.Radius_px,
	paint_default_thumbs: bool,
) {
	if o.ui_layout_paint_skip(layout_id) {
		return
	}

	track_bg := slider_resolve_color(style.track, o.Color.MUTED, frame_state, event)
	range_bg := slider_resolve_color(style.range, o.Color.PRIMARY, frame_state, event)

	o.Draw_Rectangle(track, track_bg, radius, {}, {})

	if range_rect.w > 0 && range_rect.h > 0 {
		o.Draw_Rectangle(range_rect, range_bg, radius, {}, {})
	}

	if !paint_default_thumbs {
		return
	}

	thumb_bg := slider_resolve_color(style.thumb, o.Color.BACKGROUND, frame_state, event)
	thumb_border := slider_resolve_color(style.thumb_border, o.Color.PRIMARY, frame_state, event)

	if frame_state.is_focused {
		thumb_border = slider_resolve_color(style.thumb_border, o.Color.RING, frame_state, event)
	}

	border := o.Bd_px {
		t = 1,
		b = 1,
		l = 1,
		r = 1,
	}

	for i in 0 ..< count {
		border_color := thumb_border

		if frame_state.is_focused && i == active_thumb {
			border_color = slider_resolve_color(
				style.thumb_border,
				o.Color.RING,
				frame_state,
				event,
			)
		} else if !frame_state.is_focused {
			border_color = slider_resolve_color(
				style.thumb_border,
				o.Color.PRIMARY,
				frame_state,
				event,
			)
		}

		thumb_radius := radius

		if style.radius.mode == .UNSET {
			half := min(thumbs[i].w, thumbs[i].h) * 0.5
			thumb_radius = {tl = half, tr = half, bl = half, br = half}
		}

		o.Draw_Rectangle(thumbs[i], thumb_bg, thumb_radius, border, border_color)
	}
}

@(private)
slider_root_size_for_thumbs :: proc(
	layout_id: o.UI_Id,
	config: o.Resolved_Widget_Config,
	orientation: o.Slider_Orientation,
) -> (
	w, h: f32,
) {
	// Layout-only provisional size for absolute thumb hosts before the root rect
	// is solved. Draw must use layout_slider_result track geometry instead.
	if cached, ok := o.slider_root_rect_get(layout_id); ok && cached.w > 0 && cached.h > 0 {
		return cached.w, cached.h
	}

	w = o.SLIDER_DEFAULT_WIDTH
	h = o.SLIDER_DEFAULT_HEIGHT

	if orientation == .VERTICAL {
		w = o.SLIDER_DEFAULT_HEIGHT
		h = o.SLIDER_DEFAULT_WIDTH
	}

	if config.width.kind == .FIXED && config.width.value > 0 {
		w = config.width.value
	}

	if config.height.kind == .FIXED && config.height.value > 0 {
		h = config.height.value
	}

	return w, h
}

@(private)
slider_thumb_build_index: int

@(private)
slider_thumb_build_parent: Slider_State

@(private)
slider_thumb_host_id :: proc(parent_key: string, index: int) -> string {
	if parent_key == "" {
		return fmt.tprintf("slider-thumb-%d", index)
	}

	return fmt.tprintf("%s/thumb-%d", parent_key, index)
}

@(private)
slider_thumb_host_child :: proc(_: Rectangle_State) {
	ctx := &slider_action_context

	if !ctx.active || ctx.thumb == nil {
		return
	}

	i := slider_thumb_build_index

	if i < 0 || i >= ctx.count {
		return
	}

	thumb_state := Slider_Thumb_State {
		slider    = slider_thumb_build_parent,
		index     = i,
		value     = ctx.values[i],
		is_active = i == ctx.active_thumb,
	}
	thumb_state.values = ctx.values
	thumb_state.value_count = ctx.count
	thumb_state.min = ctx.min
	thumb_state.max = ctx.max
	thumb_state.step = ctx.step
	thumb_state.orientation = ctx.orientation
	thumb_state.inverted = ctx.inverted

	ctx.thumb(thumb_state)
}

@(private)
slider_paint_thumbs_from_track :: proc(
	track: o.Rect,
	orientation: o.Slider_Orientation,
	values: [o.SLIDER_MAX_THUMBS]f32,
	count: int,
	min_v, max_v: f32,
	inverted: bool,
	thumb_size: f32,
) -> (
	thumbs: [o.SLIDER_MAX_THUMBS]o.Rect,
	range_rect: o.Rect,
) {
	n := clamp(count, 0, o.SLIDER_MAX_THUMBS)

	for i in 0 ..< n {
		thumbs[i] = o.layout_slider_thumb_rect(
			track,
			orientation,
			values[i],
			min_v,
			max_v,
			inverted,
			thumb_size,
		)
	}

	range_rect = o.layout_slider_range_rect(
		track,
		orientation,
		values,
		n,
		min_v,
		max_v,
		inverted,
		thumb_size,
	)

	return thumbs, range_rect
}

@(private)
slider_emit_custom_thumbs :: proc(frame_state: Slider_State) {
	ctx := &slider_action_context

	if !ctx.active || ctx.thumb == nil || ctx.count <= 0 {
		return
	}

	track: o.Rect

	if o.ui_pass() == .Draw {
		// Draw hosts paint from the layout-owned track; map current values only.
		chrome := o.layout_slider_result(ctx.layout_id)

		if chrome == nil {
			return
		}

		track = chrome.track
	} else {
		root_w, root_h := slider_root_size_for_thumbs(
			ctx.layout_id,
			frame_state.config,
			ctx.orientation,
		)
		root := o.Rect {
			w = root_w,
			h = root_h,
		}
		track = o.layout_slider_track_rect(root, ctx.orientation, ctx.track_thickness)
	}

	thumbs, _ := slider_paint_thumbs_from_track(
		track,
		ctx.orientation,
		ctx.values,
		ctx.count,
		ctx.min,
		ctx.max,
		ctx.inverted,
		ctx.thumb_size,
	)
	previous_parent := slider_thumb_build_parent
	previous_index := slider_thumb_build_index
	slider_thumb_build_parent = frame_state
	defer {
		slider_thumb_build_parent = previous_parent
		slider_thumb_build_index = previous_index
	}

	for i in 0 ..< ctx.count {
		thumb_rect := thumbs[i]
		slider_thumb_build_index = i
		Rectangle({
			config = {
				id = slider_thumb_host_id(ctx.parent_key, i),
				position = set.Position(.ABSOLUTE),
				x = set.F32(thumb_rect.x),
				y = set.F32(thumb_rect.y),
				width = set.Width(thumb_rect.w),
				height = set.Height(thumb_rect.h),
				justify = set.Justify(o.Justify_Align.CENTER),
				tabbable = set.Tabbable(false),
			},
			child = slider_thumb_host_child,
		})
	}
}

@(private)
slider_children_body :: proc(frame_state: Slider_State) {
	slider_emit_custom_thumbs(frame_state)
}

/*
Renders a production Radix/shadcn-style slider.

Layout binds and finalizes track/thumb chrome; draw paints from the
layout-owned track and maps current values onto that track only.

`values` is caller-owned (length 1 or 2). Pointer drag, track press, and
keyboard arrows / Home / End / PageUp / PageDown report updates via
`on_value_change`. Drag release also fires `on_value_commit`.
*/
Slider :: proc(props: Slider_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	min_v, max_v, step := slider_resolve_bounds(props)
	was_focused := widget_is_focused(key)
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)

	working: [o.SLIDER_MAX_THUMBS]f32
	count := o.slider_copy_values(props.values, &working)
	count = o.slider_normalize_values(
		&working,
		count,
		min_v,
		max_v,
		step,
		props.min_steps_between_thumbs,
	)

	frame_state := Slider_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		values      = working,
		value_count = count,
		min         = min_v,
		max         = max_v,
		step        = step,
		orientation = props.orientation,
		inverted    = props.inverted,
	}

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg

	event := slider_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Slider_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	thumb_size := slider_style_thumb_size(props.style)
	track_thickness := slider_style_track_thickness(props.style)
	child: proc(frame_state: Slider_State)

	if props.thumb != nil {
		child = slider_children_body
	}

	active_thumb := 0

	if drag := o.slider_drag_get(layout_id); drag != nil {
		if drag.thumb_index >= 0 && drag.thumb_index < count {
			active_thumb = drag.thumb_index
		}
	}

	previous_action_context := slider_action_context
	slider_action_context = {
		active                   = true,
		values                   = working,
		count                    = count,
		min                      = min_v,
		max                      = max_v,
		step                     = step,
		min_steps_between_thumbs = props.min_steps_between_thumbs,
		orientation              = props.orientation,
		inverted                 = props.inverted,
		layout_id                = layout_id,
		parent_key               = key,
		thumb_size               = thumb_size,
		track_thickness          = track_thickness,
		active_thumb             = active_thumb,
		thumb                    = props.thumb,
		on_value_change          = props.on_value_change,
		on_value_commit          = props.on_value_commit,
		on_key_down              = props.on_key_down,
		on_key_pressed           = props.on_key_pressed,
		on_key_released          = props.on_key_released,
	}
	defer slider_action_context = previous_action_context

	props_with_keys := resolved_props
	props_with_keys.on_key_down = slider_on_key_down
	props_with_keys.on_key_pressed = slider_on_key_pressed
	props_with_keys.on_key_released = slider_on_key_released

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = slider_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			o.slider_root_rect_clear(layout_id)
			o.slider_drag_clear(layout_id)

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state) && count > 0

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		widget_children(
			child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			props.scroll_bar,
			frame_state.is_hovered,
		)
		slider_bind_layout_chrome(
			layout_id,
			props.orientation,
			working,
			count,
			min_v,
			max_v,
			props.inverted,
			thumb_size,
			track_thickness,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_with_keys,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = slider_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

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

	chrome := o.layout_slider_result(layout_id)
	track: o.Rect
	thumbs: [o.SLIDER_MAX_THUMBS]o.Rect
	range_rect: o.Rect

	if chrome != nil {
		track = chrome.track
		thumbs = chrome.thumbs
		range_rect = chrome.range
	}

	can_interact := widget_can_interact(handlers, &frame_state) && count > 0

	if can_interact {
		slider_handle_keyboard(&frame_state)
		slider_action_context.values = frame_state.values
		slider_action_context.count = frame_state.value_count
	}

	// Map values onto the layout-owned track for hit-test and paint. Do not
	// re-finalize layout chrome during draw.
	if chrome != nil {
		thumbs, range_rect = slider_paint_thumbs_from_track(
			track,
			props.orientation,
			slider_action_context.values,
			slider_action_context.count,
			min_v,
			max_v,
			props.inverted,
			thumb_size,
		)
	}

	// Always run drag handling so a latch can commit when interaction ends
	// (disable / empty values / pointer up), not only while interactive.
	slider_handle_drag(
		&frame_state,
		track,
		thumbs,
		thumb_size,
		frame_state.is_hovered,
		can_interact,
	)

	if chrome != nil {
		thumbs, range_rect = slider_paint_thumbs_from_track(
			track,
			props.orientation,
			slider_action_context.values,
			slider_action_context.count,
			min_v,
			max_v,
			props.inverted,
			thumb_size,
		)
	}

	radius: o.Radius_px

	if props.style.radius.mode != .UNSET {
		if resolved_radius, ok := o.resolve_radius(props.style.radius.value, &frame_state, event);
		   ok {
			radius = resolved_radius
		}
	} else {
		half := track_thickness * 0.5
		radius = {tl = half, tr = half, bl = half, br = half}
	}

	if drag := o.slider_drag_get(layout_id); drag != nil {
		if drag.thumb_index >= 0 && drag.thumb_index < frame_state.value_count {
			active_thumb = drag.thumb_index
			slider_action_context.active_thumb = active_thumb
		}
	}

	slider_action_context.values = frame_state.values
	slider_action_context.count = frame_state.value_count
	o.slider_root_rect_store(layout_id, rect)

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	slider_draw_chrome(
		layout_id,
		track,
		range_rect,
		thumbs,
		frame_state.value_count,
		active_thumb,
		props.style,
		&frame_state,
		event,
		radius,
		props.thumb == nil,
	)

	widget_children(
		child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		props.scroll_bar,
		frame_state.is_hovered,
	)

	widget_dispatch_events(
		props_with_keys,
		&frame_state,
		handlers,
		event,
		key,
		was_focused,
	)
}
