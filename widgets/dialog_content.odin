package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Dialog content configuration (shadcn DialogContent).
*/
Dialog_Content_Props_Config :: o.Widget_Config

/*
Dialog content per-frame state passed to the content child callback.
*/
Dialog_Content_Props_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
}

/*
Dialog content event snapshot.
*/
Dialog_Content_Props_Event :: o.Widget_Event(Dialog_Content_Props_State)

/*
Dialog content props: centered modal panel in `.OVERLAY` space while open.
*/
Dialog_Content_Props :: struct {
	config:                       Dialog_Content_Props_Config,
	child:                        proc(frame_state: Dialog_Content_Props_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Dialog_Content_Props_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Dialog_Content_Props_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Dialog_Content_Props_Event),
	on_blur:                      proc(event: Dialog_Content_Props_Event),
	on_mouse_enter:               proc(event: Dialog_Content_Props_Event),
	on_mouse_leave:               proc(event: Dialog_Content_Props_Event),
	on_mouse_pressed:             proc(event: Dialog_Content_Props_Event),
	on_mouse_down:                proc(event: Dialog_Content_Props_Event),
	on_mouse_released:            proc(event: Dialog_Content_Props_Event),
	on_mouse_move:                proc(event: Dialog_Content_Props_Event),
	on_click:                     proc(event: Dialog_Content_Props_Event),
	on_contextmenu:               proc(event: Dialog_Content_Props_Event),
	on_key_pressed:               proc(event: Dialog_Content_Props_Event),
	on_key_down:                  proc(event: Dialog_Content_Props_Event),
	on_key_released:              proc(event: Dialog_Content_Props_Event),
}

/*
Overlay-space panel configuration used by `Dialog_Content` host/panel layers.

`space` is always forced to `.OVERLAY`; user overrides are ignored.
*/
@(private)
Dialog_Overlay_Panel_Config :: o.Widget_Config

@(private)
Dialog_Overlay_Panel_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

@(private)
Dialog_Overlay_Panel_Event :: o.Widget_Event(Dialog_Overlay_Panel_State)

@(private)
Dialog_Overlay_Panel_Props :: struct {
	config:                       Dialog_Overlay_Panel_Config,
	child:                        proc(frame_state: Dialog_Overlay_Panel_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Dialog_Overlay_Panel_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Dialog_Overlay_Panel_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Dialog_Overlay_Panel_Event),
	on_blur:                      proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_enter:               proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_leave:               proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_pressed:             proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_down:                proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_released:            proc(event: Dialog_Overlay_Panel_Event),
	on_mouse_move:                proc(event: Dialog_Overlay_Panel_Event),
	on_click:                     proc(event: Dialog_Overlay_Panel_Event),
	on_contextmenu:               proc(event: Dialog_Overlay_Panel_Event),
	on_key_pressed:               proc(event: Dialog_Overlay_Panel_Event),
	on_key_down:                  proc(event: Dialog_Overlay_Panel_Event),
	on_key_released:              proc(event: Dialog_Overlay_Panel_Event),
}

@(private)
DIALOG_DEFAULT_CONTENT_Z :: f32(50)

@(private)
dialog_content_props_theme_base :: proc(
	frame_state: ^Dialog_Content_Props_State,
) -> Dialog_Content_Props_Config {
	_ = frame_state

	return Dialog_Content_Props_Config{kind = .DIALOG_CONTENT}
}

@(private)
dialog_content_viewport_size :: proc() -> (w, h: f32) {
	w = f32(o.state.dpi.logical_w)
	h = f32(o.state.dpi.logical_h)

	return
}

@(private)
dialog_content_is_open :: proc() -> bool {
	if !dialog_ctx_ok() {
		return false
	}

	return dialog_ctx_top().open
}

@(private)
dialog_content_panel_theme_defaults :: proc() -> o.Widget_Config {
	return o.Widget_Config {
		kind = .DIALOG_CONTENT,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(8)),
		padding = set.Padding(f32(24)),
		max_w = set.Max_W(f32(480)),
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(f32(1)),
		border_color = set.Border_color(o.Color.BORDER),
		radius = set.Radius(f32(8)),
	}
}

@(private)
dialog_content_host_theme_defaults :: proc() -> o.Widget_Config {
	vw, vh := dialog_content_viewport_size()

	return o.Widget_Config {
		kind = .RECT,
		space = set.Space(.OVERLAY),
		position = set.Position(.FIXED),
		x = set.F32(0),
		y = set.F32(0),
		width = set.Width(vw),
		height = set.Height(vh),
		justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
		align = set.Align(.CENTER),
		background = set.Background(o.Color.TRANSPARENT),
		pointer_events = set.Pointer_Events(.NONE),
		z_index = set.Z_Index(DIALOG_DEFAULT_CONTENT_Z),
	}
}

@(private)
dialog_overlay_panel_theme_base :: proc(
	frame_state: ^Dialog_Overlay_Panel_State,
) -> Dialog_Overlay_Panel_Config {
	_ = frame_state

	return Dialog_Overlay_Panel_Config{kind = .RECT, space = set.Space(.OVERLAY)}
}

@(private)
dialog_content_inner_panel_theme_base :: proc(
	frame_state: ^Dialog_Overlay_Panel_State,
) -> Dialog_Overlay_Panel_Config {
	_ = frame_state

	cfg := dialog_content_panel_theme_defaults()
	cfg.space = set.Space(.OVERLAY)

	return cfg
}

@(private)
Draw_Dialog_Overlay_Panel :: struct {
	frame_state: ^Dialog_Overlay_Panel_State,
	event:       Dialog_Overlay_Panel_Event,
	rect:        o.Rect,
	child:       proc(frame_state: Dialog_Overlay_Panel_State),
	layout_id:   o.UI_Id,
	element_id:  string,
	author:      o.Widget_Config,
	on_scroll:   proc(scroll_x, scroll_y: f32),
	scroll_bar:  Scroll_Bar_Style,
}

@(private)
dialog_overlay_draw_panel :: proc(props: Draw_Dialog_Overlay_Panel) {
	child := props.child
	event := props.event
	frame_state := props.frame_state
	layout_id := props.layout_id
	rect := props.rect

	config := frame_state.config

	background: o.RGBA

	if resolved_background, background_ok := o.style_background_rgba(config, frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, border_ok := o.resolve_border(config.border, frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, border_color_ok := o.style_border_color_rgba(
		config,
		frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		child,
		layout_id,
		config,
		frame_state^,
		props.element_id,
		props.author,
		props.on_scroll,
		props.scroll_bar,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)
}

@(private)
dialog_overlay_panel_with_theme :: proc(
	props: Dialog_Overlay_Panel_Props,
	theme_base: proc(frame_state: ^Dialog_Overlay_Panel_State) -> Dialog_Overlay_Panel_Config,
) {
	props := props
	props.config.space = set.Space(.OVERLAY)
	cfg := props.config
	key := o.element_key(cfg.id)

	was_focused := widget_is_focused(key)

	frame_state := Dialog_Overlay_Panel_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Dialog_Overlay_Panel_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	layout_rect := o.ui_layout_rect(layout_id)
	rect := layout_rect

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, theme_base)
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
			widget_children(
				child,
				layout_id,
				config,
				frame_state,
				key,
				props.config,
				props.on_scroll,
				props.scroll_bar,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

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

	// pointer_owned resets each layout pass; note while hovered (trigger does the same).
	if frame_state.is_hovered {
		dialog_note_pointer()
	}

	widget_handle_scroll_wheel(
		layout_id,
		config,
		frame_state.is_hovered,
		key,
		props.on_scroll,
	)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		theme_base,
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

	dialog_overlay_draw_panel(
		{
			frame_state = &frame_state,
			event = event,
			rect = rect,
			child = child,
			layout_id = layout_id,
			element_id = key,
			author = props.config,
			on_scroll = props.on_scroll,
			scroll_bar = props.scroll_bar,
		},
	)

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}

@(private)
dialog_overlay_panel :: proc(props: Dialog_Overlay_Panel_Props) {
	dialog_overlay_panel_with_theme(props, dialog_overlay_panel_theme_base)
}

@(private)
dialog_content_panel_child :: proc(_: Dialog_Overlay_Panel_State) {
	if !dialog_ctx_ok() {
		return
	}

	ctx := dialog_ctx_top()
	user := ctx.content_child

	if user != nil {
		user(ctx.content_frame)
	}
}

@(private)
dialog_content_panel_mouse_enter :: proc(_: Dialog_Overlay_Panel_Event) {
	dialog_note_pointer()
}

@(private)
dialog_content_host_child :: proc(_: Dialog_Overlay_Panel_State) {
	if !dialog_ctx_ok() {
		return
	}

	ctx := dialog_ctx_top()

	dialog_overlay_panel_with_theme(
		{
			config = ctx.content_panel_author,
			child = dialog_content_panel_child,
			on_mouse_enter = dialog_content_panel_mouse_enter,
		},
		dialog_content_inner_panel_theme_base,
	)
}

/*
Renders the centered dialog panel inside a `Dialog` root.

Skips layout and draw while closed. Outside a root the content is inert.
*/
Dialog_Content :: proc(props: Dialog_Content_Props) {
	if !dialog_content_is_open() {
		return
	}

	if !dialog_ctx_ok() {
		return
	}

	ctx := dialog_ctx_top()

	host_cfg := dialog_content_host_theme_defaults()
	panel_cfg := o.merge_widget_config(dialog_content_panel_theme_defaults(), props.config)

	content_id := ctx.dialog_key != "" ? fmt_dialog_content_id(ctx.dialog_key) : ""

	if content_id != "" {
		panel_cfg.id = content_id
	}

	frame := Dialog_Content_Props_State {
		open = true,
	}
	event := widget_event(frame)
	base := dialog_content_props_theme_base(&frame)
	frame.config = o.resolve_widget_config(base, props.config, &frame, event)
	ctx.content_frame = frame
	ctx.content_child = props.child
	ctx.content_panel_author = panel_cfg

	o.Begin_Overlay()
	defer o.End_Overlay()

	dialog_overlay_panel(
		{
			config = host_cfg,
			child = dialog_content_host_child,
		},
	)

	ctx.content_child = nil
	ctx.content_panel_author = {}
}

@(private)
fmt_dialog_content_id :: proc(dialog_key: string) -> string {
	return fmt.tprintf("%s/__dialog_content", dialog_key)
}
