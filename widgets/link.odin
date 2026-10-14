package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

/*
Modifier required for pointer activation of a Link.

`.NONE` matches HTML `<a>`: a plain click activates. `.PRIMARY` is Ctrl on
Windows/Linux and Super/Cmd on macOS. Other values require that specific
modifier to be held during the pointer click.
*/
Link_Mod :: enum u8 {
	NONE,
	CTRL,
	SHIFT,
	ALT,
	SUPER,
	PRIMARY,
}

/*
Link configuration.
*/
Link_Config :: o.Widget_Config

/*
Link per-frame state including destination and activation modifier.
*/
Link_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	href:              string,
	mod:               Link_Mod,
	text:              string,
}

/*
Link event snapshot.
*/
Link_Event :: o.Widget_Event(Link_State)

/*
Link props.

Behaves like HTML `<a>`: `href` is the destination, activation reports through
`on_navigate` / `on_click`, and allowlisted absolute URLs are opened via the OS
unless `suppress_open_url` is set. Enter activates when focused; Space never
activates. When `mod` is not `.NONE`, pointer activation requires that
modifier; keyboard Enter still activates without it.
*/
Link_Props :: struct {
	config:                       Link_Config,
	href:                         string,
	text:                         string,
	mod:                          Link_Mod,
	suppress_open_url:            bool,
	disabled:                     bool,
	child:                        proc(frame_state: Link_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Link_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Link_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Link_Event),
	on_blur:                      proc(event: Link_Event),
	on_mouse_enter:               proc(event: Link_Event),
	on_mouse_leave:               proc(event: Link_Event),
	on_mouse_pressed:             proc(event: Link_Event),
	on_mouse_down:                proc(event: Link_Event),
	on_mouse_released:            proc(event: Link_Event),
	on_mouse_move:                proc(event: Link_Event),
	on_click:                     proc(event: Link_Event),
	on_navigate:                  proc(event: Link_Event),
	on_contextmenu:               proc(event: Link_Event),
	on_key_pressed:               proc(event: Link_Event),
	on_key_down:                  proc(event: Link_Event),
	on_key_released:              proc(event: Link_Event),
}

@(private)
Link_Action_Context :: struct {
	active:            bool,
	text:              string,
	mod:               Link_Mod,
	suppress_open_url: bool,
	child:             proc(frame_state: Link_State),
	on_click:          proc(event: Link_Event),
	on_navigate:       proc(event: Link_Event),
	label_id:          string,
}

@(private)
link_action_context: Link_Action_Context

/*
Returns whether the current input modifiers satisfy `mod` for pointer activation.
*/
Link_Mod_Satisfied :: proc(mod: Link_Mod) -> bool {
	if mod == .NONE {
		return true
	}

	if o.state == nil {
		return false
	}

	mods := o.state.input.modifiers

	switch mod {
	case .NONE:
		return true
	case .CTRL:
		return mods.ctrl
	case .SHIFT:
		return mods.shift
	case .ALT:
		return mods.alt
	case .SUPER:
		return mods.super
	case .PRIMARY:
		when ODIN_OS == .Darwin {
			return mods.super
		} else {
			return mods.ctrl
		}
	}

	return false
}

@(private)
link_mod_normalize :: proc(mod: Link_Mod) -> Link_Mod {
	switch mod {
	case .NONE, .CTRL, .SHIFT, .ALT, .SUPER, .PRIMARY:
		return mod
	case:
		return .NONE
	}
}

@(private)
link_theme_base :: proc(frame_state: ^Link_State) -> Link_Config {
	color := o.Color.PRIMARY

	if frame_state.is_disabled {
		color = o.Color.MUTED
	} else if frame_state.is_Pressed {
		color = o.Color.PRIMARY_PRESSED
	} else if frame_state.is_hovered {
		color = o.Color.PRIMARY_HOVER
	}

	border_color := o.Color.TRANSPARENT

	if frame_state.is_focused {
		border_color = o.Color.RING
	}

	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	return Link_Config {
		kind = .LINK,
		tabbable = set.Tabbable(true),
		direction = set.Direction(.HORIZONTAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		line_height = set.F32(1),
		color = set.Colors(color),
		text_decoration = set.Text_decoration(o.Text_Decoration_Lines{.UNDERLINE}),
		background = set.Background(o.Color.TRANSPARENT),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border_color),
		opacity = set.F32(opacity),
	}
}

@(private)
link_refresh_merged :: proc(props: Link_Props, frame_state: ^Link_State) -> Link_Event {
	event := widget_event(frame_state^)
	base := link_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
link_label_child :: proc(frame_state: Link_State) {
	ctx := &link_action_context

	if !ctx.active {
		return
	}

	if ctx.child != nil {
		ctx.child(frame_state)

		return
	}

	if ctx.text == "" {
		return
	}

	Text(
		{
			config = {
				id = ctx.label_id,
				text = ctx.text,
				color = set.Colors(o.Color.INHERIT),
				text_decoration = set.Text_decoration(o.Text_Decoration_Lines{.UNDERLINE}),
			},
		},
	)
}

@(private)
link_on_click :: proc(event: Link_Event) {
	ctx := &link_action_context

	if !ctx.active {
		return
	}

	if event.key == .SPACE {
		return
	}

	keyboard := event.key == .RETURN

	if !keyboard && !Link_Mod_Satisfied(ctx.mod) {
		return
	}

	if ctx.on_navigate != nil {
		ctx.on_navigate(event)
	}

	if !ctx.suppress_open_url && o.url_is_openable(event.frame_state.href) {
		_ = o.open_url(event.frame_state.href)
	}

	if ctx.on_click != nil {
		ctx.on_click(event)
	}
}

/*
Renders an HTML `<a>`-style link.

`href` is caller-owned and must be passed every frame. Allowlisted absolute URLs
(`http`, `https`, `mailto`) are opened via the OS on activation unless
`suppress_open_url` is set. Pointer activation respects `mod`; Enter activates
whenever the link is focused and interactive.
*/
Link :: proc(props: Link_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)
	mod := link_mod_normalize(props.mod)
	href := props.href
	text := props.text

	frame_state := Link_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		href        = href,
		mod         = mod,
		text        = text,
	}

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg
	resolved_props.mod = mod

	event := link_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Link_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	label_id: string

	if cfg.id != "" {
		label_id = fmt.tprintf("%s-label", cfg.id)
	} else {
		label_id = fmt.tprintf("%s-label", key)
	}

	previous_action_context := link_action_context
	link_action_context = {
		active            = true,
		text              = text,
		mod               = mod,
		suppress_open_url = props.suppress_open_url,
		child             = props.child,
		on_click          = props.on_click,
		on_navigate       = props.on_navigate,
		label_id          = label_id,
	}
	defer link_action_context = previous_action_context

	props_with_activate := resolved_props
	props_with_activate.on_click = link_on_click

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = link_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		widget_children(
			link_label_child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			frame_state.is_hovered,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_with_activate,
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
		event = link_refresh_merged(resolved_props, &frame_state)
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

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		link_label_child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(
		props_with_activate,
		&frame_state,
		handlers,
		event,
		key,
		was_focused,
	)
}
