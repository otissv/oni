package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Context menu content configuration: Widget_Config plus floating placement.

`anchor_align` / `anchor_gap` / `viewport_margin` are placement relative to the
pointer (or trigger fallback) and viewport — not CSS box `align` / `gap_*` /
`margin`.
*/
Context_Menu_Content_Props_Config :: struct {
	using _:         o.Widget_Config,
	anchor_align:    Context_Menu_Align,
	anchor_gap:      f32,
	viewport_margin: f32,
}

/*
Context menu content per-frame state passed to the content child callback.
*/
Context_Menu_Content_Props_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
}

/*
Context menu content event snapshot.
*/
Context_Menu_Content_Props_Event :: o.Widget_Event(Context_Menu_Content_Props_State)

/*
Context menu content props: floating panel at the pointer while open.
*/
Context_Menu_Content_Props :: struct {
	config:                       Context_Menu_Content_Props_Config,
	child:                        proc(frame_state: Context_Menu_Content_Props_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Context_Menu_Content_Props_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Context_Menu_Content_Props_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Context_Menu_Content_Props_Event),
	on_blur:                      proc(event: Context_Menu_Content_Props_Event),
	on_mouse_enter:               proc(event: Context_Menu_Content_Props_Event),
	on_mouse_leave:               proc(event: Context_Menu_Content_Props_Event),
	on_mouse_pressed:             proc(event: Context_Menu_Content_Props_Event),
	on_mouse_down:                proc(event: Context_Menu_Content_Props_Event),
	on_mouse_released:            proc(event: Context_Menu_Content_Props_Event),
	on_mouse_move:                proc(event: Context_Menu_Content_Props_Event),
	on_click:                     proc(event: Context_Menu_Content_Props_Event),
	on_contextmenu:               proc(event: Context_Menu_Content_Props_Event),
	on_key_pressed:               proc(event: Context_Menu_Content_Props_Event),
	on_key_down:                  proc(event: Context_Menu_Content_Props_Event),
	on_key_released:              proc(event: Context_Menu_Content_Props_Event),
}

@(private)
context_menu_content_props_theme_base :: proc(
	frame_state: ^Context_Menu_Content_Props_State,
) -> Context_Menu_Content_Props_Config {
	_ = frame_state

	return Context_Menu_Content_Props_Config{kind = .CONTEXT_MENU_CONTENT}
}

@(private)
context_menu_content_panel_child :: proc(_: Popover_Content_State) {
	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()
	user := ctx.content_child

	if user != nil {
		user(ctx.content_frame)
	}
}

@(private)
context_menu_content_panel_mouse_enter :: proc(_: Popover_Content_Event) {
	context_menu_note_pointer()
}

@(private)
context_menu_content_is_open :: proc() -> bool {
	if !context_menu_ctx_ok() {
		return false
	}

	return context_menu_ctx_top().open
}

/*
Renders the floating context menu panel inside a `Context_Menu` root.

Skips layout and draw while closed. Outside a root the content is inert.
Anchors to the pointer from the opening contextmenu, or the trigger rect when
no pointer anchor was stored.
*/
Context_Menu_Content :: proc(props: Context_Menu_Content_Props) {
	if !context_menu_content_is_open() {
		return
	}

	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()
	context_menu_restore_anchor_into_ctx()

	gap := props.config.anchor_gap

	if gap < 0 {
		gap = CONTEXT_MENU_DEFAULT_GAP_PX
	}

	margin := props.config.viewport_margin

	if margin <= 0 {
		margin = CONTEXT_MENU_DEFAULT_VIEWPORT_MARGIN_PX
	}

	anchor: o.Vec2

	if ctx.has_anchor_point {
		anchor = ctx.anchor_point
	} else if ctx.has_trigger {
		anchor = {ctx.trigger_rect.x, ctx.trigger_rect.y + ctx.trigger_rect.h}
	} else {
		anchor = {o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	}

	cfg := context_menu_content_theme_for_anchor(anchor, gap)
	cfg = o.merge_widget_config(cfg, props.config)
	cfg.space = set.Space(.POPOVER)

	content_id := ctx.menu_key != "" ? fmt_context_menu_content_id(ctx.menu_key) : ""

	if content_id != "" {
		cfg.id = content_id
	}

	frame := Context_Menu_Content_Props_State {
		open = true,
	}
	event := widget_event(frame)
	base := context_menu_content_props_theme_base(&frame)
	frame.config = o.resolve_widget_config(base, props.config, &frame, event)
	ctx.content_frame = frame
	ctx.content_child = props.child

	panel_child := proc(fs: Popover_Content_State) {
		_ = fs
		context_menu_content_panel_child(fs)
	}

	panel_props := Popover_Content_Panel_Props {
		config         = cfg,
		child          = panel_child,
		on_mouse_enter = context_menu_content_panel_mouse_enter,
	}

	popover_panel(panel_props)

	content_layout_id := o.ui_id(content_id != "" ? content_id : o.element_key(cfg.id))

	if o.ui_pass() == .Layout {
		o.layout_anchor_popup_at_point(
			content_layout_id,
			anchor,
			gap,
			margin,
			props.config.anchor_align,
		)
	}

	if o.ui_pass() == .Draw {
		content_rect := o.ui_layout_rect(content_layout_id)

		if o.pointer_hits(content_layout_id, content_rect, .POPOVER) {
			context_menu_note_pointer()
		}
	}

	ctx.content_child = nil
}

@(private)
fmt_context_menu_content_id :: proc(menu_key: string) -> string {
	return fmt.tprintf("%s/__context_menu_content", menu_key)
}
