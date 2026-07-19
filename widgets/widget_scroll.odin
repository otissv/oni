package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

@(private)
WIDGET_SCROLL_STACK_MAX :: 16

@(private)
Widget_Scroll_Ctx :: struct {
	layout_id:  o.UI_Id,
	parent_id:  string,
	element_id: string,
	overflow_x: o.Overflow,
	overflow_y: o.Overflow,
	scroll:     ^o.Vec2,
	style:      Scroll_Bar_Style,
	hovered:    bool,
	on_scroll:  proc(scroll_x, scroll_y: f32),
	user_fn:    proc(data: rawptr),
	user_data:  rawptr,
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

.SCROLL always emits (when style allows). .AUTO emits only when content
overflows and the sticky hover-reveal flag is set (scrollport or bar hover,
or an active bar drag — updated during draw for the next frame).
*/
widget_scroll_overflow_shows_bar :: proc(
	overflow: o.Overflow,
	max_scroll: f32,
	auto_reveal: bool,
) -> bool {
	scroll: o.Overflow = .SCROLL
	auto: o.Overflow = .AUTO
	if overflow == scroll do return true
	if overflow == auto do return max_scroll > 0 && auto_reveal
	return false
}

@(private)
widget_scroll_bar_id :: proc(parent_id, suffix: string) -> string {
	if parent_id == "" do return ""
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

@(private)
widget_scroll_bar_hot_or_dragging :: proc(bar_id: string) -> bool {
	if bar_id == "" do return false
	if o.w_ctx != nil && o.w_ctx.element_was_hovered != nil {
		if o.w_ctx.element_was_hovered[bar_id] do return true
	}
	layout_id := o.ui_id(bar_id)
	if drag := o.scroll_bar_drag_entry(layout_id); drag != nil && drag.active {
		return true
	}
	return false
}

@(private)
widget_emit_scroll_bars :: proc(ctx: Widget_Scroll_Ctx) {
	if !o.style_is_scrollport(ctx.overflow_x, ctx.overflow_y) do return
	if ctx.scroll == nil do return
	if !scroll_bar_style_visible(ctx.style) do return

	metrics, _ := o.Scrollport_Metrics_Get(ctx.layout_id)
	auto_reveal := o.widget_scroll_auto_reveal_get(ctx.element_id)
	show_y := widget_scroll_overflow_shows_bar(
		ctx.overflow_y,
		metrics.max_scroll.y,
		auto_reveal,
	)
	show_x := widget_scroll_overflow_shows_bar(
		ctx.overflow_x,
		metrics.max_scroll.x,
		auto_reveal,
	)

	bar_size := scroll_bar_style_size(ctx.style)
	bar_y_id := widget_scroll_bar_id(ctx.parent_id, "scroll-bar-y")
	bar_x_id := widget_scroll_bar_id(ctx.parent_id, "scroll-bar-x")

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
		scroll_bar_apply_style_config(&bar_cfg, ctx.style)
		Scroll_Bar({
			config = bar_cfg,
			style = ctx.style,
			axis = .Y,
			parent_scroll_x = &ctx.scroll.x,
			parent_scroll_y = &ctx.scroll.y,
			viewport = metrics.viewport_size.y,
			content = metrics.content_size.y,
			on_scroll = widget_scroll_notify,
		})
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
		scroll_bar_apply_style_config(&bar_cfg, ctx.style)
		Scroll_Bar({
			config = bar_cfg,
			style = ctx.style,
			axis = .X,
			parent_scroll_x = &ctx.scroll.x,
			parent_scroll_y = &ctx.scroll.y,
			viewport = metrics.viewport_size.x,
			content = metrics.content_size.x,
			on_scroll = widget_scroll_notify,
		})
	}

	if o.ui_pass() == .Draw {
		ov_auto: o.Overflow = .AUTO
		needs_auto :=
			(ctx.overflow_y == ov_auto && metrics.max_scroll.y > 0) ||
			(ctx.overflow_x == ov_auto && metrics.max_scroll.x > 0)
		if needs_auto {
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
	if !hovered do return
	if !o.style_is_scrollport(config.overflow_x, config.overflow_y) do return
	if o.Shortcut_Wheel_Consumed() do return

	wheel_x := o.state.input.mouse_wheel_x
	wheel_y := o.state.input.mouse_wheel_y
	if wheel_x == 0 && wheel_y == 0 do return

	entry := o.widget_scroll_ensure(element_id)
	if entry == nil do return

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

`scroll_bar` customizes auto-emitted scrollbar chrome for this scrollport.
`hovered` drives AUTO overflow bar reveal (sticky into the next frame).
*/
widget_children :: proc(
	child: proc(frame_state: $S),
	layout_id: o.UI_Id,
	config: o.Resolved_Widget_Config,
	frame_state: S,
	element_id: string,
	author: o.Widget_Config,
	on_scroll: proc(scroll_x, scroll_y: f32) = nil,
	scroll_bar: Scroll_Bar_Style = {},
	hovered: bool = false,
) {
	resolved := config
	o.widget_scroll_apply(element_id, author, &resolved)

	Binder :: struct {
		child: proc(S),
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
			style = scroll_bar,
			hovered = hovered,
			on_scroll = on_scroll,
			user_fn = invoke,
			user_data = &binder,
		},
	)
	defer widget_scroll_pop()

	clipped := false
	if o.ui_pass() == .Draw {
		clipped = o.Draw_Push_Layout_Clip(layout_id)
	}
	defer if clipped do o.Draw_Pop_Clip()

	build :: proc(fs: S) {
		_ = fs
		ctx := widget_scroll_top()
		if ctx.user_fn != nil {
			ctx.user_fn(ctx.user_data)
		}
		widget_emit_scroll_bars(ctx^)
	}

	if o.style_is_scrollport(resolved.overflow_x, resolved.overflow_y) {
		o.Children(build, layout_id, resolved, frame_state)
	} else {
		o.Children(child, layout_id, resolved, frame_state)
	}
}
