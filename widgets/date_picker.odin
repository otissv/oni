package oni_widgets

import o ".."
import set "../set"

/*
Date picker root configuration (Popover + Calendar composition).
*/
Date_Picker_Config :: struct {
	using _:              o.Widget_Config,
	mode:                 Calendar_Mode,
	selected:             Calendar_Date,
	has_selected:         bool,
	selected_dates:       []Calendar_Date,
	selected_range:       Calendar_Range,
	open:                 bool,
	keep_open:            bool,
	month:                Calendar_Date,
	required:             bool,
	min:                  int,
	max:                  int,
	start_month:          Calendar_Date,
	end_month:            Calendar_Date,
	start_date:           Calendar_Date,
	end_date:             Calendar_Date,
	hide_outside_days:    bool,
	show_week_numbers:    bool,
	week_starts_on:       Calendar_Weekday,
	number_of_months:     int,
	today:                Calendar_Date,
	day_size:             o.Cfg(o.Style_F32),
	gap:                  o.Cfg(o.Style_F32),
}

/*
Date picker root per-frame state merged with resolved style and selection fields.
*/
Date_Picker_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	mode:              Calendar_Mode,
	open:              bool,
	selected:          Calendar_Date,
	has_selected:      bool,
	selected_dates:    []Calendar_Date,
	selected_range:    Calendar_Range,
	disabled:          bool,
	required:          bool,
}

/*
Date picker root event snapshot.
*/
Date_Picker_Event :: o.Widget_Event(Date_Picker_State)

/*
Date picker root props: caller-owned selection, open, and month; compound
Trigger / Value / Input children; optional calendar content panel.

Composition:
```
Date_Picker
└── Popover (internal)
    ├── child → Date_Picker_Trigger → Date_Picker_Value | Input
    └── Popover_Content → Calendar + Calendar_Default_Months
         (or custom `content`)
```

Selection, open, and month are caller-owned: pass them every frame and update
from `on_select` / `on_open_change` / `on_month_change`. The widget does not
keep open or month as runtime source of truth.

`mode` defaults to `.SINGLE` when `.NONE`. Single and completed range selections
close the popover unless `keep_open` is set. Multiple mode stays open.
*/
Date_Picker_Props :: struct {
	config:                       Date_Picker_Config,
	on_month_change:              proc(month: Calendar_Date),
	on_select:                    proc(selection: Calendar_Selection),
	on_day_click:                 proc(date: Calendar_Date),
	on_open_change:               proc(open: bool),
	disabled_matcher:             proc(date: Calendar_Date) -> bool,
	hidden_matcher:               proc(date: Calendar_Date) -> bool,
	day:                          proc(frame_state: Calendar_Day_State),
	format_month:                 proc(date: Calendar_Date) -> string,
	format_weekday:               proc(weekday: Calendar_Weekday) -> string,
	format_day:                   proc(date: Calendar_Date) -> string,
	format_value:                 proc(selection: Calendar_Selection) -> string,
	child:                        proc(frame_state: Date_Picker_State),
	content:                      proc(frame_state: Date_Picker_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Date_Picker_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Date_Picker_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Date_Picker_Event),
	on_blur:                      proc(event: Date_Picker_Event),
	on_mouse_enter:               proc(event: Date_Picker_Event),
	on_mouse_leave:               proc(event: Date_Picker_Event),
	on_mouse_pressed:             proc(event: Date_Picker_Event),
	on_mouse_down:                proc(event: Date_Picker_Event),
	on_mouse_released:            proc(event: Date_Picker_Event),
	on_mouse_move:                proc(event: Date_Picker_Event),
	on_click:                     proc(event: Date_Picker_Event),
	on_contextmenu:               proc(event: Date_Picker_Event),
	on_key_pressed:               proc(event: Date_Picker_Event),
	on_key_down:                  proc(event: Date_Picker_Event),
	on_key_released:              proc(event: Date_Picker_Event),
}

@(private)
date_picker_theme_base :: proc(frame_state: ^Date_Picker_State) -> Date_Picker_Config {
	_ = frame_state

	return Date_Picker_Config {
		kind = .DATE_PICKER,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
		background = set.Background(o.Color.TRANSPARENT),
	}
}

@(private)
date_picker_refresh_merged :: proc(
	props: Date_Picker_Props,
	frame_state: ^Date_Picker_State,
) -> Date_Picker_Event {
	event := widget_event(frame_state^)
	base := date_picker_theme_base(frame_state)
	override := props.config
	frame_state.config = o.resolve_widget_config(base, override, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
date_picker_refresh_merged_if_interaction_changed :: proc(
	props: Date_Picker_Props,
	frame_state: ^Date_Picker_State,
	prev_fp: u8,
) -> (
	event: Date_Picker_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return date_picker_refresh_merged(props, frame_state), fp
}

/*
Renders a composable date picker root (nested Popover + Calendar).

Push compound context for Trigger / Value / Input parts. When open, `content`
(or a default Calendar) is shown via composable `Popover` / `Popover_Content`
beside the trigger. Dropdown dismiss (Escape / outside press) is owned by the
nested Popover.
*/
Date_Picker :: proc(props: Date_Picker_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open := cfg.open
	mode := date_picker_effective_mode(cfg.mode)
	disabled := o.cfg_style_bool(cfg.disabled)

	frame_state := Date_Picker_State {
		is_disabled    = disabled,
		is_focused     = was_focused,
		mode           = mode,
		open           = open,
		selected       = cfg.selected,
		has_selected   = cfg.has_selected,
		selected_dates = cfg.selected_dates,
		selected_range = cfg.selected_range,
		disabled       = disabled,
		required       = cfg.required,
	}

	props_resolved := props
	props_resolved.config = cfg
	props_resolved.config.mode = mode

	event := date_picker_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Date_Picker_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	date_picker_ctx_push(
		{
			picker_key = key,
			mode = mode,
			open = open,
			disabled = disabled,
			required = cfg.required,
			keep_open = cfg.keep_open,
			selected = cfg.selected,
			has_selected = cfg.has_selected,
			selected_dates = cfg.selected_dates,
			selected_range = cfg.selected_range,
			month = cfg.month,
			on_month_change = props.on_month_change,
			on_select = props.on_select,
			on_day_click = props.on_day_click,
			on_open_change = props.on_open_change,
			min = cfg.min,
			max = cfg.max,
			start_month = cfg.start_month,
			end_month = cfg.end_month,
			start_date = cfg.start_date,
			end_date = cfg.end_date,
			disabled_matcher = props.disabled_matcher,
			hidden_matcher = props.hidden_matcher,
			hide_outside_days = cfg.hide_outside_days,
			show_week_numbers = cfg.show_week_numbers,
			week_starts_on = cfg.week_starts_on,
			number_of_months = cfg.number_of_months,
			today = cfg.today,
			day_size = cfg.day_size,
			gap = cfg.gap,
			day = props.day,
			format_month = props.format_month,
			format_weekday = props.format_weekday,
			format_day = props.format_day,
			format_value = props.format_value,
			user_child = props.child,
			user_content = props.content,
		},
	)
	defer date_picker_ctx_pop()

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = date_picker_refresh_merged(props_resolved, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			date_picker_runtime_clear(key)

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)
		widget_children(
			date_picker_compound_child,
			layout_id,
			config,
			frame_state,
			key,
			props_resolved.config,
			props.on_scroll,
			frame_state.is_hovered,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_resolved,
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

	event, _ = date_picker_refresh_merged_if_interaction_changed(
		props_resolved,
		&frame_state,
		style_fp,
	)
	config = frame_state.config
	frame_state.open = date_picker_ctx_top().open
	frame_state.selected = date_picker_ctx_top().selected
	frame_state.has_selected = date_picker_ctx_top().has_selected
	frame_state.selected_dates = date_picker_ctx_top().selected_dates
	frame_state.selected_range = date_picker_ctx_top().selected_range

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

	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, border_ok := o.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, border_color_ok := o.style_border_color_rgba(
		config,
		&frame_state,
		event,
	); border_color_ok {
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
		date_picker_compound_child,
		layout_id,
		config,
		frame_state,
		key,
		props_resolved.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	trigger_focused := false

	if popover_ctx_ok() {
		tkey := popover_ctx_top().trigger_key
		trigger_focused = tkey != "" && widget_is_focused(tkey)
	}

	if trigger_focused || widget_is_focused(key) {
		date_picker_handle_keys()
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
