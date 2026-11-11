package oni_widgets

import o ".."
import "core:fmt"

/*
Tooltip content configuration: Widget_Config plus floating placement.

`anchor_align` / `anchor_gap` / `viewport_margin` / `match_trigger_width` are
placement relative to the trigger and viewport — not CSS box `align` / `gap_*` /
`margin`.
*/
Tooltip_Content_Props_Config :: struct {
	using _:             o.Widget_Config,
	anchor_align:        Tooltip_Align,
	anchor_gap:          f32,
	viewport_margin:     f32,
	match_trigger_width: bool,
}

/*
Tooltip content per-frame state passed to the content child callback.
*/
Tooltip_Content_Props_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
}

/*
Tooltip content event snapshot.
*/
Tooltip_Content_Props_Event :: o.Widget_Event(Tooltip_Content_Props_State)

/*
Tooltip content props: floating panel anchored to the trigger while open.
*/
Tooltip_Content_Props :: struct {
	config:                       Tooltip_Content_Props_Config,
	child:                        proc(frame_state: Tooltip_Content_Props_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tooltip_Content_Props_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tooltip_Content_Props_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Tooltip_Content_Props_Event),
	on_blur:                      proc(event: Tooltip_Content_Props_Event),
	on_mouse_enter:               proc(event: Tooltip_Content_Props_Event),
	on_mouse_leave:               proc(event: Tooltip_Content_Props_Event),
	on_mouse_pressed:             proc(event: Tooltip_Content_Props_Event),
	on_mouse_down:                proc(event: Tooltip_Content_Props_Event),
	on_mouse_released:            proc(event: Tooltip_Content_Props_Event),
	on_mouse_move:                proc(event: Tooltip_Content_Props_Event),
	on_click:                     proc(event: Tooltip_Content_Props_Event),
	on_contextmenu:               proc(event: Tooltip_Content_Props_Event),
	on_key_pressed:               proc(event: Tooltip_Content_Props_Event),
	on_key_down:                  proc(event: Tooltip_Content_Props_Event),
	on_key_released:              proc(event: Tooltip_Content_Props_Event),
}

@(private)
tooltip_content_props_theme_base :: proc(
	frame_state: ^Tooltip_Content_Props_State,
) -> Tooltip_Content_Props_Config {
	_ = frame_state

	return Tooltip_Content_Props_Config{kind = .TOOLTIP_CONTENT}
}

@(private)
tooltip_content_panel_child :: proc(_: Popover_Content_State) {
	if !tooltip_ctx_ok() {
		return
	}

	ctx := tooltip_ctx_top()
	user := ctx.content_child

	if user != nil {
		user(ctx.content_frame)
	}
}

@(private)
tooltip_content_panel_mouse_enter :: proc(_: Popover_Content_Event) {
	tooltip_claim_pointer()
}

@(private)
tooltip_content_is_open :: proc() -> bool {
	if !tooltip_ctx_ok() {
		return false
	}

	return tooltip_ctx_top().open
}

/*
Renders the floating tooltip panel inside a `Tooltip` root.

Skips layout and draw while closed. Outside a root the content is inert.
*/
Tooltip_Content :: proc(props: Tooltip_Content_Props) {
	if !tooltip_content_is_open() {
		return
	}

	if !tooltip_ctx_ok() {
		return
	}

	ctx := tooltip_ctx_top()
	trigger_rect := ctx.trigger_rect

	if !ctx.has_trigger {
		trigger_rect = {}
	}

	gap := props.config.anchor_gap

	if gap <= 0 {
		gap = POPOVER_DEFAULT_GAP_PX
	}

	margin := props.config.viewport_margin

	if margin <= 0 {
		margin = POPOVER_DEFAULT_VIEWPORT_MARGIN_PX
	}

	cfg := popover_content_theme_for_trigger(trigger_rect, gap)
	cfg = o.merge_widget_config(cfg, props.config)

	content_id := ctx.tooltip_key != "" ? fmt_tooltip_content_id(ctx.tooltip_key) : ""

	if content_id != "" {
		cfg.id = content_id
	}

	frame := Tooltip_Content_Props_State {
		open = true,
	}
	event := widget_event(frame)
	base := tooltip_content_props_theme_base(&frame)
	frame.config = o.resolve_widget_config(base, props.config, &frame, event)
	ctx.content_frame = frame
	ctx.content_child = props.child

	panel_child := proc(fs: Popover_Content_State) {
		_ = fs
		tooltip_content_panel_child(fs)
	}

	popover_panel_anchored(
		{
			config = cfg,
			child = panel_child,
			anchor_id = ctx.trigger_layout_id,
			gap = gap,
			margin = margin,
			match_width = props.config.match_trigger_width,
			align = props.config.anchor_align,
			on_mouse_enter = tooltip_content_panel_mouse_enter,
			content_id = content_id,
		},
	)

	ctx.content_child = nil
}

@(private)
fmt_tooltip_content_id :: proc(tooltip_key: string) -> string {
	return fmt.tprintf("%s/__tooltip_content", tooltip_key)
}
