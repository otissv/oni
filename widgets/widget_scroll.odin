package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

@(private)
WIDGET_SCROLL_STACK_MAX :: 16

@(private)
Widget_Scroll_Ctx :: struct {
	layout_id:           o.UI_Id,
	parent_id:           string,
	element_id:          string,
	overflow_x:          o.Overflow,
	overflow_y:          o.Overflow,
	scroll:              ^o.Vec2,
	hovered:             bool,
	content_clip_active: bool,
	on_scroll:           proc(scroll_x, scroll_y: f32),
	user_fn:             proc(data: rawptr),
	user_data:           rawptr,
}

@(private)
widget_scroll_stack: [WIDGET_SCROLL_STACK_MAX]Widget_Scroll_Ctx

@(private)
widget_scroll_depth: int

@(private)
widget_scroll_push :: proc(ctx: Widget_Scroll_Ctx) {
	assert(widget_scroll_depth < WIDGET_SCROLL_STACK_MAX)
	widget_scroll_stack[widget_scroll_depth] = ctx
	widget_scroll_depth += 1
}

@(private)
widget_scroll_pop :: proc() {
	assert(widget_scroll_depth > 0)
	widget_scroll_depth -= 1
	widget_scroll_stack[widget_scroll_depth] = {}
}

@(private)
widget_scroll_top :: proc() -> ^Widget_Scroll_Ctx {
	assert(widget_scroll_depth > 0)

	return &widget_scroll_stack[widget_scroll_depth - 1]
}

/*
Returns whether a scrollport axis should emit a scrollbar.

.SCROLL and .AUTO emit only when content overflows and the sticky hover-reveal
flag is set (scrollport or bar hover, or an active bar drag — updated during
draw for the next frame). Matches Chrome overlay scrollbar auto-hide.
*/
widget_scroll_overflow_shows_bar :: proc(
	overflow: o.Overflow,
	max_scroll: f32,
	auto_reveal: bool,
) -> bool {
	scroll: o.Overflow = .SCROLL
	auto: o.Overflow = .AUTO

	if overflow == scroll || overflow == auto {
		return max_scroll > 0 && auto_reveal
	}

	return false
}

@(private)
widget_scroll_bar_id :: proc(parent_id, suffix: string) -> string {
	if parent_id == "" {
		return ""
	}

	return fmt.tprintf("%s/%s", parent_id, suffix)
}

@(private)
widget_scroll_notify :: proc(scroll_x, scroll_y: f32) {
	ctx := widget_scroll_top()

	if ctx.scroll != nil {
		ctx.scroll^ = {scroll_x, scroll_y}
	}

	if ctx.on_scroll != nil {
		ctx.on_scroll(scroll_x, scroll_y)
	}
}

Widget_Scrollport_Frame :: struct {
	layout_id:  o.UI_Id,
	element_id: string,
	parent_id:  string,
	config:     o.Resolved_Widget_Config,
	hovered:    bool,
	on_scroll:  proc(scroll_x, scroll_y: f32),
}

@(private)
widget_scrollport_frame_begin :: proc(frame: Widget_Scrollport_Frame) -> bool {
	if !o.style_is_scrollport(frame.config.overflow_x, frame.config.overflow_y) {
		return false
	}

	entry := o.widget_scroll_ensure(frame.element_id)

	if entry == nil {
		return false
	}

	widget_scroll_push(
		{
			layout_id = frame.layout_id,
			parent_id = frame.parent_id,
			element_id = frame.element_id,
			overflow_x = frame.config.overflow_x,
			overflow_y = frame.config.overflow_y,
			scroll = entry,
			hovered = frame.hovered,
			on_scroll = frame.on_scroll,
		},
	)

	return true
}

@(private)
widget_scrollport_frame_end :: proc(active: bool, emit_bars: bool) {
	if !active {
		return
	}

	if emit_bars {
		widget_emit_scroll_bars(widget_scroll_top()^)
	}

	widget_scroll_pop()
}

@(private)
widget_scroll_bar_hot_or_dragging :: proc(bar_id: string) -> bool {
	if bar_id == "" {
		return false
	}

	if o.w_ctx != nil && o.w_ctx.element_was_hovered != nil {
		if o.w_ctx.element_was_hovered[bar_id] {
			return true
		}
	}

	layout_id := o.ui_id(bar_id)

	if drag := o.scroll_bar_drag_entry(layout_id); drag != nil && drag.active {
		return true
	}

	return false
}

@(private)
widget_emit_scroll_bars :: proc(ctx: Widget_Scroll_Ctx) {
	if !o.style_is_scrollport(ctx.overflow_x, ctx.overflow_y) {
		return
	}

	if ctx.scroll == nil {
		return
	}

	metrics, _ := o.Scrollport_Metrics_Get(ctx.layout_id)
	auto_reveal := o.widget_scroll_auto_reveal_get(ctx.element_id)
	show_y := widget_scroll_overflow_shows_bar(ctx.overflow_y, metrics.max_scroll.y, auto_reveal)
	show_x := widget_scroll_overflow_shows_bar(ctx.overflow_x, metrics.max_scroll.x, auto_reveal)

	bar_size := o.SCROLL_BAR_DEFAULT_SIZE
	bar_y_id := widget_scroll_bar_id(ctx.parent_id, "scroll-bar-y")
	bar_x_id := widget_scroll_bar_id(ctx.parent_id, "scroll-bar-x")

	// `right = 0` + `width = bar_size` pins the bar's right edge to the padding
	// box (widget inner edge); the track extends left by bar_size into view.
	// Content-box overflow clip is popped before emit so padding does not hide it.
	if show_y {
		bottom_inset := show_x ? bar_size : f32(0)
		bar_cfg := Scroll_Bar_Config {
			id = bar_y_id,
			position = set.Position(.ABSOLUTE),
			right = set.Right(0),
			y = set.F32(0),
			bottom = set.Bottom(bottom_inset),
			width = set.Width(bar_size),
			z_index = set.Z_Index(f32(1)),
		}
		Scroll_Bar(
			{
				config = bar_cfg,
				axis = .Y,
				parent_scroll_x = &ctx.scroll.x,
				parent_scroll_y = &ctx.scroll.y,
				viewport = metrics.viewport_size.y,
				content = metrics.content_size.y,
				on_scroll = widget_scroll_notify,
			},
		)
	}

	if show_x {
		right_inset := show_y ? bar_size : f32(0)
		bar_cfg := Scroll_Bar_Config {
			id = bar_x_id,
			position = set.Position(.ABSOLUTE),
			x = set.F32(0),
			bottom = set.Bottom(0),
			right = set.Right(right_inset),
			height = set.Height(bar_size),
			z_index = set.Z_Index(f32(1)),
		}
		Scroll_Bar(
			{
				config = bar_cfg,
				axis = .X,
				parent_scroll_x = &ctx.scroll.x,
				parent_scroll_y = &ctx.scroll.y,
				viewport = metrics.viewport_size.x,
				content = metrics.content_size.x,
				on_scroll = widget_scroll_notify,
			},
		)
	}

	if o.ui_pass() == .Draw {
		needs_reveal :=
			(o.layout_node_scrolls_axis(ctx.overflow_y) && metrics.max_scroll.y > 0) ||
			(o.layout_node_scrolls_axis(ctx.overflow_x) && metrics.max_scroll.x > 0)

		if needs_reveal {
			bar_hot :=
				widget_scroll_bar_hot_or_dragging(bar_y_id) ||
				widget_scroll_bar_hot_or_dragging(bar_x_id)
			o.widget_scroll_auto_reveal_set(ctx.element_id, ctx.hovered || bar_hot)
		} else {
			o.widget_scroll_auto_reveal_set(ctx.element_id, false)
		}
	}
}

/*
Handles mouse-wheel scrolling for a hovered scrollport widget.

Persists the new offset in widget context and invokes `on_scroll` when it changes.
*/
widget_handle_scroll_wheel :: proc(
	layout_id: o.UI_Id,
	config: o.Resolved_Widget_Config,
	hovered: bool,
	element_id: string,
	on_scroll: proc(scroll_x, scroll_y: f32) = nil,
) {
	if !hovered {
		return
	}

	if !o.style_is_scrollport(config.overflow_x, config.overflow_y) {
		return
	}

	if o.Shortcut_Wheel_Consumed() {
		return
	}

	wheel_x := o.state.input.mouse_wheel_x
	wheel_y := o.state.input.mouse_wheel_y

	if wheel_x == 0 && wheel_y == 0 {
		return
	}

	entry := o.widget_scroll_ensure(element_id)

	if entry == nil {
		return
	}

	metrics, _ := o.Scrollport_Metrics_Get(layout_id)

	if o.scroll_apply_wheel(
		&entry.x,
		&entry.y,
		metrics.max_scroll,
		wheel_x,
		wheel_y,
		config.overflow_x,
		config.overflow_y,
	) {
		if on_scroll != nil {
			on_scroll(entry.x, entry.y)
		}

		o.Shortcut_Consume_Wheel()
		o.Stop_Propagation()
	}
}

/*
Runs Children with overflow clip and automatic Scroll_Bar chrome for scrollports.

Scroll position lives in widget context (keyed by element id). Optional
`author.scroll_x` / `scroll_y` overwrite context for that frame. Wheel and
scrollbar updates write context automatically; `on_scroll` is notification only.

`hovered` drives overlay bar reveal for .SCROLL/.AUTO (sticky into the next frame).
*/
widget_children :: proc(
	child: proc(frame_state: $S),
	layout_id: o.UI_Id,
	config: o.Resolved_Widget_Config,
	frame_state: S,
	element_id: string,
	author: o.Widget_Config,
	on_scroll: proc(scroll_x, scroll_y: f32) = nil,
	hovered: bool = false,
) {
	resolved := config
	o.widget_scroll_apply(element_id, author, &resolved)

	Binder :: struct {
		child: proc(_: S),
		state: S,
	}
	binder := Binder {
		child = child,
		state = frame_state,
	}

	invoke := proc(data: rawptr) {
		b := cast(^Binder)data

		if b.child != nil {
			b.child(b.state)
		}
	}

	entry: ^o.Vec2

	if o.style_is_scrollport(resolved.overflow_x, resolved.overflow_y) {
		entry = o.widget_scroll_ensure(element_id)
	}

	widget_scroll_push(
		{
			layout_id = layout_id,
			parent_id = resolved.id != "" ? resolved.id : element_id,
			element_id = element_id,
			overflow_x = resolved.overflow_x,
			overflow_y = resolved.overflow_y,
			scroll = entry,
			hovered = hovered,
			on_scroll = on_scroll,
			user_fn = invoke,
			user_data = rawptr(&binder),
		},
	)
	defer widget_scroll_pop()

	if !o.style_is_scrollport(resolved.overflow_x, resolved.overflow_y) {
		o.Children(child, layout_id, resolved, frame_state)

		return
	}

	// Content clips to the content box; overlay bars need the padding-box edge,
	// so pop that clip before emitting chrome (still inside Children).
	if o.ui_pass() == .Draw {
		widget_scroll_top().content_clip_active = o.Draw_Push_Layout_Clip(layout_id)
	}

	build :: proc(fs: S) {
		_ = fs
		ctx := widget_scroll_top()

		if ctx.user_fn != nil {
			ctx.user_fn(ctx.user_data)
		}

		if o.ui_pass() == .Draw && ctx.content_clip_active {
			o.Draw_Pop_Clip()
			ctx.content_clip_active = false
		}

		widget_emit_scroll_bars(ctx^)
	}

	o.Children(build, layout_id, resolved, frame_state)

	if widget_scroll_top().content_clip_active {
		o.Draw_Pop_Clip()
		widget_scroll_top().content_clip_active = false
	}
}
