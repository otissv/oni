package oni_widgets

import o ".."
import set "../set"

/*
Context menu separator configuration.
*/
Context_Menu_Separator_Config :: o.Widget_Config

/*
Context menu separator per-frame state.
*/
Context_Menu_Separator_State :: o.Widget_Merged_State(
	o.Widget_Frame_State,
	o.Resolved_Widget_Config,
)

/*
Context menu separator event snapshot.
*/
Context_Menu_Separator_Event :: o.Widget_Event(Context_Menu_Separator_State)

/*
Context menu separator props: non-interactive divider between items.
*/
Context_Menu_Separator_Props :: struct {
	config:                       Context_Menu_Separator_Config,
	child:                        proc(frame_state: Context_Menu_Separator_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Context_Menu_Separator_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Context_Menu_Separator_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Context_Menu_Separator_Event),
	on_blur:                      proc(event: Context_Menu_Separator_Event),
	on_mouse_enter:               proc(event: Context_Menu_Separator_Event),
	on_mouse_leave:               proc(event: Context_Menu_Separator_Event),
	on_mouse_pressed:             proc(event: Context_Menu_Separator_Event),
	on_mouse_down:                proc(event: Context_Menu_Separator_Event),
	on_mouse_released:            proc(event: Context_Menu_Separator_Event),
	on_mouse_move:                proc(event: Context_Menu_Separator_Event),
	on_click:                     proc(event: Context_Menu_Separator_Event),
	on_contextmenu:               proc(event: Context_Menu_Separator_Event),
	on_key_pressed:               proc(event: Context_Menu_Separator_Event),
	on_key_down:                  proc(event: Context_Menu_Separator_Event),
	on_key_released:              proc(event: Context_Menu_Separator_Event),
}

@(private)
context_menu_separator_theme_base :: proc(
	frame_state: ^Context_Menu_Separator_State,
) -> Context_Menu_Separator_Config {
	_ = frame_state

	return Context_Menu_Separator_Config {
		kind = .CONTEXT_MENU_SEPARATOR,
		width = set.Width(.GROW),
		height = set.Height(f32(1)),
		margin = set.Margin(o.Mg_pos{x = 4, y = 4}),
		background = set.Background(o.Color.BORDER),
	}
}

/*
Renders a horizontal divider inside `Context_Menu_Content`.
*/
Context_Menu_Separator :: proc(props: Context_Menu_Separator_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Context_Menu_Separator_State {
		is_disabled = true,
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, context_menu_separator_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Context_Menu_Separator_State)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, context_menu_separator_theme_base)
			config = frame_state.config
		}

		if !skip_layout {
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

	rect := o.ui_layout_rect(layout_id)

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		context_menu_separator_theme_base,
		style_fp,
	)
	config = frame_state.config

	background: o.RGBA

	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		background = resolved_background
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
		props.config,
		props.on_scroll,
		frame_state.is_hovered,
	)
}
