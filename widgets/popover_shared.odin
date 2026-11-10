package oni_widgets

import o ".."
import set "../set"

/*
Horizontal alignment of popover content relative to the trigger.
*/
Popover_Align :: o.Layout_Popup_Align

@(private)
POPOVER_CTX_STACK_MAX :: 16

@(private)
POPOVER_DEFAULT_GAP_PX :: f32(4)

@(private)
POPOVER_DEFAULT_VIEWPORT_MARGIN_PX :: f32(8)

/*
Live compound context pushed by `Popover` for Trigger / Content parts.
*/
@(private)
Popover_Ctx :: struct {
	generation:          u64,
	dismiss_right_press: bool,
	popover_key:         string,
	open:                bool,
	disabled:            bool,
	on_open_change:      proc(handle: Popover_Handle, open: bool),
	user_on_open_change: proc(open: bool),
	trigger_key:         string,
	trigger_layout_id:   o.UI_Id,
	trigger_rect:        o.Rect,
	has_trigger:         bool,
	pointer_owned:       bool,
	trigger_user_click:  proc(event: Popover_Trigger_Event),
	content_child:       proc(frame_state: Popover_Content_Props_State),
	content_frame:       Popover_Content_Props_State,
}

@(private)
popover_ctx_stack: [POPOVER_CTX_STACK_MAX]Popover_Ctx

@(private)
popover_ctx_depth: int

@(private)
popover_ctx_generation: u64

/*
Scoped popup identity. Valid only inside its root callback, in the current pass.
Popped, replaced and shutdown handles are inert. Never retain across frames.
*/
Popover_Handle :: struct {
	slot:       int,
	generation: u64,
}

/*
Releases popover context stack.

Called from widget `Shutdown`.
*/
popover_shutdown :: proc() {
	popover_ctx_depth = 0
	popover_ctx_stack = {}
}

@(private)
popover_ctx_push :: proc(ctx: Popover_Ctx) -> Popover_Handle {
	assert(popover_ctx_depth < POPOVER_CTX_STACK_MAX)
	assert(popover_ctx_generation < max(u64))
	popover_ctx_generation += 1
	popover_ctx_stack[popover_ctx_depth] = ctx
	popover_ctx_stack[popover_ctx_depth].generation = popover_ctx_generation
	handle := Popover_Handle{slot = popover_ctx_depth, generation = popover_ctx_generation}
	popover_ctx_depth += 1
	return handle
}

@(private)
popover_ctx_pop :: proc() {
	assert(popover_ctx_depth > 0)
	popover_ctx_depth -= 1
	popover_ctx_stack[popover_ctx_depth] = {}
}

@(private)
popover_ctx_ok :: proc() -> bool {
	return popover_ctx_depth > 0
}

@(private)
popover_ctx_top :: proc() -> ^Popover_Ctx {
	assert(popover_ctx_depth > 0)

	return &popover_ctx_stack[popover_ctx_depth - 1]
}

@(private)
popover_current_handle :: proc() -> Popover_Handle {
	if !popover_ctx_ok() do return {}
	ctx := popover_ctx_top()
	return {slot = popover_ctx_depth - 1, generation = ctx.generation}
}

@(private)
popover_context :: proc(handle: Popover_Handle) -> ^Popover_Ctx {
	if handle.generation == 0 || handle.slot < 0 || handle.slot >= popover_ctx_depth {
		return nil
	}
	ctx := &popover_ctx_stack[handle.slot]
	if ctx.generation != handle.generation do return nil
	return ctx
}

/*
Reads the caller-owned open value for this live popup.
*/
Popover_Is_Open :: proc(handle: Popover_Handle) -> bool {
	ctx := popover_context(handle)
	return ctx != nil && ctx.open
}

/*
Requests a change once per transition. Disabled and expired handles are inert.
*/
Popover_Set_Open :: proc(handle: Popover_Handle, open: bool) {
	ctx := popover_context(handle)
	if ctx == nil || ctx.disabled || ctx.open == open do return
	ctx.open = open
	if ctx.on_open_change != nil {
		ctx.on_open_change(handle, open)
	}
}

@(private)
popover_on_open_change :: proc(handle: Popover_Handle, open: bool) {
	ctx := popover_context(handle)
	if ctx != nil && ctx.user_on_open_change != nil {
		ctx.user_on_open_change(open)
	}
}

/*
Toggles the specified live popup through the same change callback.
*/
Popover_Toggle :: proc(handle: Popover_Handle) {
	Popover_Set_Open(handle, !Popover_Is_Open(handle))
}

/*
Marks a hit inside this popup and its enclosing popup roots. This prevents
an ancestor from treating a nested floating panel hit as an outside press.
*/
Popover_Claim_Pointer :: proc(handle: Popover_Handle) {
	if popover_context(handle) == nil do return
	for i in 0 ..= handle.slot {
		popover_ctx_stack[i].pointer_owned = true
	}
}

/*
Runs after children on Draw. Escape is consumed only by an enabled open popup;
outside presses use the same ownership path for all popup widgets.
*/
Popover_Process_Dismissal :: proc(handle: Popover_Handle) {
	ctx := popover_context(handle)
	if ctx == nil || !ctx.open || ctx.disabled do return

	for i in handle.slot + 1 ..< popover_ctx_depth {
		if popover_ctx_stack[i].open && !popover_ctx_stack[i].disabled do return
	}

	esc := o.w_ctx.keys[int(o.Scancode.ESCAPE)]
	if esc.pressed && !o.shortcut_key_consumed(.ESCAPE) {
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true
		Popover_Set_Open(handle, false)
		return
	}
	outside_press := o.w_ctx.left_mouse.pressed ||
	                 (ctx.dismiss_right_press && o.w_ctx.right_mouse.pressed)
	if outside_press && !ctx.pointer_owned {
		Popover_Set_Open(handle, false)
	}
}

@(private)
popover_set_trigger :: proc(handle: Popover_Handle, key: string, layout_id: o.UI_Id, rect: o.Rect) {
	ctx := popover_context(handle)
	if ctx == nil {
		return
	}

	ctx.trigger_key = key
	ctx.trigger_layout_id = layout_id
	ctx.trigger_rect = rect
	ctx.has_trigger = true
}

/*
Popover panel configuration (floating `.POPOVER` space container).

`space` is always forced to `.POPOVER`; user overrides are ignored.
*/
Popover_Content_Config :: o.Widget_Config

/*
Popover panel per-frame state merged with resolved style.
*/
Popover_Content_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Popover panel event snapshot.
*/
Popover_Content_Event :: o.Widget_Event(Popover_Content_State)

/*
Popover panel props: config, child callback, and input event handlers.
*/
Popover_Content_Panel_Props :: struct {
	config:                       Popover_Content_Config,
	child:                        proc(frame_state: Popover_Content_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Popover_Content_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Popover_Content_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Popover_Content_Event),
	on_blur:                      proc(event: Popover_Content_Event),
	on_mouse_enter:               proc(event: Popover_Content_Event),
	on_mouse_leave:               proc(event: Popover_Content_Event),
	on_mouse_pressed:             proc(event: Popover_Content_Event),
	on_mouse_down:                proc(event: Popover_Content_Event),
	on_mouse_released:            proc(event: Popover_Content_Event),
	on_mouse_move:                proc(event: Popover_Content_Event),
	on_click:                     proc(event: Popover_Content_Event),
	on_contextmenu:               proc(event: Popover_Content_Event),
	on_key_pressed:               proc(event: Popover_Content_Event),
	on_key_down:                  proc(event: Popover_Content_Event),
	on_key_released:              proc(event: Popover_Content_Event),
}

@(private)
popover_panel_theme_base :: proc(frame_state: ^Popover_Content_State) -> Popover_Content_Config {
	_ = frame_state

	return Popover_Content_Config{kind = .RECT, space = set.Space(.POPOVER)}
}

/*
Renders a styled container in `.POPOVER` space (internal panel primitive).
*/
@(private)
popover_panel :: proc(props: Popover_Content_Panel_Props) {
	props := props
	props.config.space = set.Space(.POPOVER)
	cfg := props.config
	key := o.element_key(cfg.id)

	was_focused := widget_is_focused(key)

	frame_state := Popover_Content_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, popover_panel_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Popover_Content_State)
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
			event = widget_refresh_merged(props, &frame_state, popover_panel_theme_base)
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
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		popover_panel_theme_base,
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

	popover_draw_panel(
		{
			frame_state = &frame_state,
			event = event,
			rect = rect,
			child = child,
			layout_id = layout_id,
			element_id = key,
			author = props.config,
			on_scroll = props.on_scroll,
		},
	)

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}

@(private)
Draw_Popover_Panel :: struct {
	frame_state: ^Popover_Content_State,
	event:       Popover_Content_Event,
	rect:        o.Rect,
	child:       proc(frame_state: Popover_Content_State),
	layout_id:   o.UI_Id,
	element_id:  string,
	author:      o.Widget_Config,
	on_scroll:   proc(scroll_x, scroll_y: f32),
}

@(private)
popover_draw_panel :: proc(props: Draw_Popover_Panel) {
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

	// Chrome must record in `.POPOVER`. `being_children` only pushes layer space
	// around the child callback — background/border drawn outside that would use
	// the parent SCREEN batch with this node's high stack_index and cover page UI.
	o.Draw_Push_Space(.POPOVER)
	defer o.Draw_Pop_Space()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		child,
		layout_id,
		config,
		frame_state^,
		props.element_id,
		props.author,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)
}

/*
Parameters for anchoring a popover panel beside a trigger (Select, Date_Picker, etc.).
*/
@(private)
Popover_Panel_Anchored_Params :: struct {
	config:         o.Widget_Config,
	child:          proc(frame_state: Popover_Content_State),
	anchor_id:      o.UI_Id,
	gap:            f32,
	margin:         f32,
	match_width:    bool,
	align:          Popover_Align,
	on_mouse_enter: proc(event: Popover_Content_Event),
	content_id:     string,
}

/*
Lays out and draws a popover panel anchored to a trigger with viewport flipping.
*/
@(private)
popover_panel_anchored :: proc(params: Popover_Panel_Anchored_Params) {
	cfg := params.config
	cfg.space = set.Space(.POPOVER)

	if params.content_id != "" {
		cfg.id = params.content_id
	}

	panel_props := Popover_Content_Panel_Props {
		config         = cfg,
		child          = params.child,
		on_mouse_enter = params.on_mouse_enter,
	}

	popover_panel(panel_props)

	if o.ui_pass() == .Layout && params.anchor_id != 0 {
		content_layout_id := o.ui_id(
			params.content_id != "" ? params.content_id : o.element_key(cfg.id),
		)
		o.layout_anchor_popup(
			params.anchor_id,
			content_layout_id,
			params.gap,
			params.margin,
			params.match_width,
			params.align,
		)
	}

	if o.ui_pass() == .Draw {
		content_layout_id := o.ui_id(
			params.content_id != "" ? params.content_id : o.element_key(cfg.id),
		)
		content_rect := o.ui_layout_rect(content_layout_id)

		if o.pointer_hits(content_layout_id, content_rect, .POPOVER) &&
		   params.on_mouse_enter != nil {
			params.on_mouse_enter({})
		}
	}
}

@(private)
popover_content_theme_for_trigger :: proc(trigger_rect: o.Rect, gap: f32) -> o.Widget_Config {
	return o.Widget_Config {
		kind = .RECT,
		space = set.Space(.POPOVER),
		position = set.Position(.ABSOLUTE),
		x = set.F32(trigger_rect.x),
		y = set.F32(trigger_rect.y + trigger_rect.h + gap),
		height = set.Height(o.Height_Mode.FIT),
		direction = set.Direction(.VERTICAL),
		padding = set.Padding(f32(12)),
		background = set.Background(o.Color.BACKGROUND),
		z_index = set.Z_Index(f32(50)),
	}
}
