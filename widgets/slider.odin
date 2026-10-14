package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Slider root configuration.
*/
Slider_Config :: o.Widget_Config

/*
Slider track part configuration.
*/
Slider_Track_Config :: o.Widget_Config

/*
Slider range fill part configuration.
*/
Slider_Range_Config :: o.Widget_Config

/*
Slider thumb part configuration.
*/
Slider_Thumb_Config :: o.Widget_Config

/*
Slider per-frame state, including the active working values.
*/
Slider_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	values:            [o.SLIDER_MAX_THUMBS]f32,
	value_count:       int,
	active_thumb:      int,
	min:               f32,
	max:               f32,
	step:              f32,
	orientation:       o.Slider_Orientation,
	inverted:          bool,
}

/*
Per-thumb state passed to `Slider_Thumb.child`.

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
Slider thumb event snapshot.
*/
Slider_Thumb_Event :: o.Widget_Event(Slider_Thumb_State)

/*
Props for `Slider_Track`.
*/
Slider_Track_Props :: struct {
	config: Slider_Track_Config,
	child:  proc(frame_state: Slider_State),
}

/*
Props for `Slider_Range`.
*/
Slider_Range_Props :: struct {
	config: Slider_Range_Config,
}

/*
Props for `Slider_Thumb`.

`index` selects which thumb in `values` (`0 ..< value_count`) this part renders.
Optional `child` renders inside an absolutely positioned host matching the thumb
hit rect.
*/
Slider_Thumb_Props :: struct {
	config: Slider_Thumb_Config,
	index:  int,
	child:  proc(frame_state: Slider_Thumb_State),
}

/*
Slider root props.

`values` is owned by the caller and must be passed every frame with length 1
(single thumb) or 2 (range). Pointer and keyboard interaction report updates
through `on_value_change` only — the widget never mutates the caller's slice.
`on_value_commit` fires once when an active pointer drag ends.

Compose chrome with `Slider_Track`, `Slider_Range`, and `Slider_Thumb` inside
`child`. When `child` is nil, `Slider_Default_Parts` renders track, range fill,
and one thumb per value using each part's theme defaults.

`thumb_size` and `track_thickness` are layout metrics (unset `Cfg` keeps
`SLIDER_DEFAULT_THUMB_SIZE` and `SLIDER_DEFAULT_TRACK_THICKNESS`).
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
	thumb_size:                   o.Cfg(o.Style_F32),
	track_thickness:              o.Cfg(o.Style_F32),
	child:                        proc(frame_state: Slider_State),
	on_value_change:              proc(values: []f32),
	on_value_commit:              proc(values: []f32),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Slider_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Slider_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
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
SLIDER_CTX_MAX :: 8

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
	frame_state:              Slider_State,
	track:                    o.Rect,
	range_rect:               o.Rect,
	thumbs:                   [o.SLIDER_MAX_THUMBS]o.Rect,
	rel_thumbs:               [o.SLIDER_MAX_THUMBS]o.Rect,
	pending_thumb_state:      Slider_Thumb_State,
	pending_thumb_child:      proc(frame_state: Slider_Thumb_State),
	on_value_change:          proc(values: []f32),
	on_value_commit:          proc(values: []f32),
	on_key_down:              proc(event: Slider_Event),
	on_key_pressed:           proc(event: Slider_Event),
	on_key_released:          proc(event: Slider_Event),
}

@(private)
slider_ctx_stack: [SLIDER_CTX_MAX]Slider_Action_Context

@(private)
slider_ctx_depth: int

@(private)
slider_ctx_dummy: Slider_Action_Context

@(private)
slider_ctx_ok :: proc() -> bool {
	return slider_ctx_depth > 0 && slider_ctx_stack[slider_ctx_depth - 1].active
}

@(private)
slider_ctx_top :: proc() -> ^Slider_Action_Context {
	if !slider_ctx_ok() {
		return &slider_ctx_dummy
	}

	return &slider_ctx_stack[slider_ctx_depth - 1]
}

@(private)
slider_ctx_push :: proc(ctx: Slider_Action_Context) -> bool {
	if slider_ctx_depth >= SLIDER_CTX_MAX {
		return false
	}

	slider_ctx_stack[slider_ctx_depth] = ctx
	slider_ctx_depth += 1

	return true
}

@(private)
slider_ctx_pop :: proc() {
	if slider_ctx_depth <= 0 {
		return
	}

	slider_ctx_depth -= 1
	slider_ctx_stack[slider_ctx_depth] = {}
}

@(private)
slider_resolve_thumb_size :: proc(props: Slider_Props) -> f32 {
	return o.cfg_style_f32(props.thumb_size, o.SLIDER_DEFAULT_THUMB_SIZE)
}

@(private)
slider_resolve_track_thickness :: proc(props: Slider_Props) -> f32 {
	return o.cfg_style_f32(props.track_thickness, o.SLIDER_DEFAULT_TRACK_THICKNESS)
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
slider_track_theme_base :: proc(
	frame_state: ^Slider_State,
	track_thickness: f32,
) -> Slider_Track_Config {
	_ = frame_state
	half := track_thickness * 0.5

	return Slider_Track_Config {
		kind = .RECT,
		background = set.Background(o.Color.MUTED),
		radius = set.Radius(half),
		tabbable = set.Tabbable(false),
	}
}

@(private)
slider_range_theme_base :: proc(
	frame_state: ^Slider_State,
	track_thickness: f32,
) -> Slider_Range_Config {
	_ = frame_state
	half := track_thickness * 0.5

	return Slider_Range_Config {
		kind = .RECT,
		background = set.Background(o.Color.PRIMARY),
		radius = set.Radius(half),
		tabbable = set.Tabbable(false),
	}
}

@(private)
slider_thumb_theme_base :: proc(
	frame_state: ^Slider_Thumb_State,
	thumb_size: f32,
) -> Slider_Thumb_Config {
	border_color := o.Colors(o.Color.PRIMARY)

	if frame_state.is_focused && frame_state.is_active {
		border_color = o.Color.RING
	}

	half := thumb_size * 0.5

	return Slider_Thumb_Config {
		kind = .RECT,
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border_color),
		radius = set.Radius(half),
		justify = set.Justify(o.Justify_Align.CENTER),
		tabbable = set.Tabbable(false),
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
	if !slider_ctx_ok() ||
	   frame_state == nil ||
	   !frame_state.is_focused ||
	   frame_state.is_disabled {
		return false
	}

	ctx := slider_ctx_top()

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
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()

	if ctx.on_key_down != nil {
		ctx.on_key_down(event)
	}
}

@(private)
slider_on_key_pressed :: proc(event: Slider_Event) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()

	if ctx.on_key_pressed != nil {
		ctx.on_key_pressed(event)
	}
}

@(private)
slider_on_key_released :: proc(event: Slider_Event) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()

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
	if !slider_ctx_ok() || frame_state == nil {
		return
	}

	ctx := slider_ctx_top()
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
		(o.w_ctx.left_mouse.released || (!o.w_ctx.left_mouse.down && !o.w_ctx.left_mouse.pressed))

	if ended {
		frame_state.values = ctx.values
		frame_state.value_count = ctx.count
		slider_emit_values(ctx, true)
		o.slider_drag_end(ctx.layout_id)
		o.Stop_Propagation()
	}
}

@(private)
slider_draw_part_box :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	config: o.Resolved_Widget_Config,
	frame_state: ^$S,
	event: o.Widget_Event(S),
) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	background: o.RGBA

	if resolved_bg, ok := o.style_background_rgba(config, frame_state, event); ok {
		background = resolved_bg
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_bc, ok := o.style_border_color_rgba(config, frame_state, event); ok {
		border_color = resolved_bc
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_draw_box_border(layout_id, rect, radius, border, border_color)
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
slider_part_id :: proc(parent_key, suffix: string) -> string {
	if parent_key == "" {
		return fmt.tprintf("slider-%s", suffix)
	}

	return fmt.tprintf("%s/%s", parent_key, suffix)
}

@(private)
slider_thumb_host_id :: proc(parent_key: string, index: int) -> string {
	if parent_key == "" {
		return fmt.tprintf("slider-thumb-%d", index)
	}

	return fmt.tprintf("%s/thumb-%d", parent_key, index)
}

@(private)
slider_thumb_host_child :: proc(_: Rectangle_State) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()

	if ctx.pending_thumb_child == nil {
		return
	}

	ctx.pending_thumb_child(ctx.pending_thumb_state)
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

/*
Track bar part for the enclosing `Slider`.

Paints the slider track using theme `Color.MUTED` and pill corners by default,
merged with `props.config`. Optional `child` runs inside the slider context
(for example to nest `Slider_Range`).
*/
Slider_Track :: proc(props: Slider_Track_Props) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = slider_part_id(ctx.parent_key, "track")
	}

	_ = o.element_key(cfg.id)

	if o.ui_pass() == .Layout {
		if props.child != nil {
			props.child(ctx.frame_state)
		}

		return
	}

	parent_state := ctx.frame_state
	event := widget_event(parent_state)
	base := slider_track_theme_base(&parent_state, ctx.track_thickness)
	resolved := o.resolve_widget_config(base, cfg, &parent_state, event)

	if !o.ui_layout_paint_skip(ctx.layout_id) && ctx.track.w > 0 && ctx.track.h > 0 {
		background: o.RGBA

		if resolved_bg, ok := o.style_background_rgba(resolved, &parent_state, event); ok {
			background = resolved_bg
		}

		border: o.Bd_px

		if resolved_border, ok := o.resolve_border(resolved.border, &parent_state, event); ok {
			border = resolved_border
		}

		border_color: o.RGBA

		if resolved_bc, ok := o.style_border_color_rgba(resolved, &parent_state, event); ok {
			border_color = resolved_bc
		}

		radius: o.Radius_px

		if resolved_radius, ok := o.resolve_radius(resolved.radius, &parent_state, event); ok {
			radius = resolved_radius
		}

		o.Draw_Push_Opacity(resolved.opacity)
		defer o.Draw_Pop_Opacity()

		widget_draw_box_background(ctx.layout_id, ctx.track, background, radius)

		if props.child != nil {
			props.child(parent_state)
		}

		widget_draw_box_border(ctx.layout_id, ctx.track, radius, border, border_color)

		return
	}

	if props.child != nil {
		props.child(parent_state)
	}
}

/*
Active range fill part for the enclosing `Slider`.

Paints the filled span along the track using theme `Color.PRIMARY` and pill
corners by default, merged with `props.config`.
*/
Slider_Range :: proc(props: Slider_Range_Props) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = slider_part_id(ctx.parent_key, "range")
	}

	_ = o.element_key(cfg.id)

	if o.ui_pass() == .Layout {
		return
	}

	parent_state := ctx.frame_state
	event := widget_event(parent_state)
	base := slider_range_theme_base(&parent_state, ctx.track_thickness)
	resolved := o.resolve_widget_config(base, cfg, &parent_state, event)

	slider_draw_part_box(ctx.layout_id, ctx.range_rect, resolved, &parent_state, event)
}

/*
Thumb handle part for one value index (`0 ..< value_count`) of the enclosing `Slider`.

Paints the thumb using `Color.BACKGROUND` fill, `Color.PRIMARY` border (`Color.RING`
when focused and active), and circular radius by default, merged with
`props.config`. When `child` is provided, it runs inside an absolutely
positioned host matching the thumb hit rect.
*/
Slider_Thumb :: proc(props: Slider_Thumb_Props) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()
	i := props.index

	if i < 0 || i >= ctx.count {
		return
	}

	cfg := props.config

	if cfg.id == "" {
		cfg.id = slider_thumb_host_id(ctx.parent_key, i)
	}

	thumb_state := Slider_Thumb_State {
		slider    = ctx.frame_state,
		index     = i,
		value     = ctx.values[i],
		is_active = i == ctx.active_thumb,
	}
	thumb_state.values = ctx.values
	thumb_state.value_count = ctx.count
	thumb_state.active_thumb = ctx.active_thumb
	thumb_state.min = ctx.min
	thumb_state.max = ctx.max
	thumb_state.step = ctx.step
	thumb_state.orientation = ctx.orientation
	thumb_state.inverted = ctx.inverted

	if o.ui_pass() == .Draw {
		mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}

		if !thumb_state.is_disabled && slider_point_in_rect(mouse, ctx.thumbs[i]) {
			thumb_state.is_hovered = true
		}
	}

	event := widget_event(thumb_state)
	base := slider_thumb_theme_base(&thumb_state, ctx.thumb_size)
	resolved := o.resolve_widget_config(base, cfg, &thumb_state, event)
	thumb_state.config = resolved

	if o.ui_pass() == .Layout {
		if props.child == nil {
			return
		}

		rel_rect := ctx.rel_thumbs[i]
		prev_state := ctx.pending_thumb_state
		prev_child := ctx.pending_thumb_child
		ctx.pending_thumb_state = thumb_state
		ctx.pending_thumb_child = props.child
		defer {
			ctx.pending_thumb_state = prev_state
			ctx.pending_thumb_child = prev_child
		}

		Rectangle(
			{
				config = {
					id = cfg.id,
					position = set.Position(.ABSOLUTE),
					x = set.F32(rel_rect.x),
					y = set.F32(rel_rect.y),
					width = set.Width(rel_rect.w),
					height = set.Height(rel_rect.h),
					justify = set.Justify(resolved.justify),
					background = set.Background(o.Color.TRANSPARENT),
					border_color = set.Border_color(o.Color.TRANSPARENT),
					tabbable = set.Tabbable(false),
				},
				child = slider_thumb_host_child,
			},
		)

		return
	}

	thumb_rect := ctx.thumbs[i]

	if props.child == nil {
		slider_draw_part_box(ctx.layout_id, thumb_rect, resolved, &thumb_state, event)

		return
	}

	background: o.RGBA

	if resolved_bg, ok := o.style_background_rgba(resolved, &thumb_state, event); ok {
		background = resolved_bg
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(resolved.border, &thumb_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_bc, ok := o.style_border_color_rgba(resolved, &thumb_state, event); ok {
		border_color = resolved_bc
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(resolved.radius, &thumb_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(resolved.opacity)
	defer o.Draw_Pop_Opacity()

	if thumb_rect.w > 0 && thumb_rect.h > 0 {
		widget_draw_box_background(ctx.layout_id, thumb_rect, background, radius)
	}

	rel_rect := ctx.rel_thumbs[i]
	prev_state := ctx.pending_thumb_state
	prev_child := ctx.pending_thumb_child
	ctx.pending_thumb_state = thumb_state
	ctx.pending_thumb_child = props.child
	defer {
		ctx.pending_thumb_state = prev_state
		ctx.pending_thumb_child = prev_child
	}

	Rectangle(
		{
			config = {
				id = cfg.id,
				position = set.Position(.ABSOLUTE),
				x = set.F32(rel_rect.x),
				y = set.F32(rel_rect.y),
				width = set.Width(rel_rect.w),
				height = set.Height(rel_rect.h),
				justify = set.Justify(resolved.justify),
				background = set.Background(o.Color.TRANSPARENT),
				border_color = set.Border_color(o.Color.TRANSPARENT),
				tabbable = set.Tabbable(false),
			},
			child = slider_thumb_host_child,
		},
	)

	if thumb_rect.w > 0 && thumb_rect.h > 0 {
		widget_draw_box_border(ctx.layout_id, thumb_rect, radius, border, border_color)
	}
}

/*
Default slider composition: track, range fill, and one thumb per value.

Used when `Slider.child` is nil.
*/
Slider_Default_Parts :: proc(frame_state: Slider_State) {
	if !slider_ctx_ok() {
		return
	}

	ctx := slider_ctx_top()

	Slider_Track({config = {id = slider_part_id(ctx.parent_key, "track")}})
	Slider_Range({config = {id = slider_part_id(ctx.parent_key, "range")}})

	for i in 0 ..< frame_state.value_count {
		Slider_Thumb({config = {id = slider_thumb_host_id(ctx.parent_key, i)}, index = i})
	}
}

/*
Renders a composable slider.

Layout binds and finalizes track/thumb geometry; draw maps current values onto
the layout-owned track and delegates chrome rendering to `child` (or
`Slider_Default_Parts` when `child` is nil).

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

	active_thumb := 0

	if drag := o.slider_drag_get(layout_id); drag != nil {
		if drag.thumb_index >= 0 && drag.thumb_index < count {
			active_thumb = drag.thumb_index
		}
	}

	frame_state := Slider_State {
		is_disabled  = disabled,
		is_focused   = was_focused,
		values       = working,
		value_count  = count,
		active_thumb = active_thumb,
		min          = min_v,
		max          = max_v,
		step         = step,
		orientation  = props.orientation,
		inverted     = props.inverted,
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
	thumb_size := slider_resolve_thumb_size(props)
	track_thickness := slider_resolve_track_thickness(props)
	child := props.child

	if child == nil {
		child = Slider_Default_Parts
	}

	root_w, root_h := slider_root_size_for_thumbs(layout_id, config, props.orientation)
	provisional_root := o.Rect {
		w = root_w,
		h = root_h,
	}
	rel_track := o.layout_slider_track_rect(provisional_root, props.orientation, track_thickness)
	rel_thumbs, _ := slider_paint_thumbs_from_track(
		rel_track,
		props.orientation,
		working,
		count,
		min_v,
		max_v,
		props.inverted,
		thumb_size,
	)

	pushed := slider_ctx_push(
		{
			active = true,
			values = working,
			count = count,
			min = min_v,
			max = max_v,
			step = step,
			min_steps_between_thumbs = props.min_steps_between_thumbs,
			orientation = props.orientation,
			inverted = props.inverted,
			layout_id = layout_id,
			parent_key = key,
			thumb_size = thumb_size,
			track_thickness = track_thickness,
			active_thumb = active_thumb,
			frame_state = frame_state,
			rel_thumbs = rel_thumbs,
			on_value_change = props.on_value_change,
			on_value_commit = props.on_value_commit,
			on_key_down = props.on_key_down,
			on_key_pressed = props.on_key_pressed,
			on_key_released = props.on_key_released,
		},
	)
	defer if pushed {
		slider_ctx_pop()
	}

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

		if pushed {
			slider_ctx_top().frame_state = frame_state
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

		if pushed {
			ctx := slider_ctx_top()
			ctx.values = frame_state.values
			ctx.count = frame_state.value_count
		}
	}

	// Map values onto the layout-owned track for hit-test and paint. Do not
	// re-finalize layout chrome during draw.
	if chrome != nil && pushed {
		ctx := slider_ctx_top()
		thumbs, range_rect = slider_paint_thumbs_from_track(
			track,
			props.orientation,
			ctx.values,
			ctx.count,
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

	if chrome != nil && pushed {
		ctx := slider_ctx_top()
		thumbs, range_rect = slider_paint_thumbs_from_track(
			track,
			props.orientation,
			ctx.values,
			ctx.count,
			min_v,
			max_v,
			props.inverted,
			thumb_size,
		)
	}

	if drag := o.slider_drag_get(layout_id); drag != nil {
		if drag.thumb_index >= 0 && drag.thumb_index < frame_state.value_count {
			active_thumb = drag.thumb_index
		}
	}

	frame_state.active_thumb = active_thumb

	if pushed {
		ctx := slider_ctx_top()
		ctx.values = frame_state.values
		ctx.count = frame_state.value_count
		ctx.active_thumb = active_thumb
		ctx.frame_state = frame_state
		ctx.track = track
		ctx.range_rect = range_rect
		ctx.thumbs = thumbs
	}

	o.slider_root_rect_store(layout_id, rect)

	background: o.RGBA

	if resolved_bg, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_bg
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_bc, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_bc
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_with_keys, &frame_state, handlers, event, key, was_focused)
}
