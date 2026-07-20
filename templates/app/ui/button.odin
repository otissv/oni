package ui

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"

Button_Variant :: enum {
	DEFAULT,
	SECONDARY,
	OUTLINE,
	GHOST,
	DESTRUCTIVE,
	LINK,
	ACTIVE,
}

Button_Size :: enum {
	DEFAULT,
	SMALL,
	LARGE,
	ICON,
}

Button_state :: w.Button_State
Button_Event :: w.Button_Event

Button_props :: struct {
	using _:           w.Button_Config,
	variant:           Button_Variant,
	size:              Button_Size,
	active:            bool,
	child:             proc(state: Button_state),
	on_focus:          proc(event: Button_Event),
	on_blur:           proc(event: Button_Event),
	on_mouse_enter:    proc(event: Button_Event),
	on_mouse_leave:    proc(event: Button_Event),
	on_mouse_pressed:  proc(event: Button_Event),
	on_mouse_down:     proc(event: Button_Event),
	on_mouse_released: proc(event: Button_Event),
	on_mouse_move:     proc(event: Button_Event),
	on_click:          proc(event: Button_Event),
	on_contextmenu:    proc(event: Button_Event),
	on_key_pressed:    proc(event: Button_Event),
	on_key_down:       proc(event: Button_Event),
	on_key_released:   proc(event: Button_Event),
}

@(private)
button_active_variant: Button_Variant

@(private)
button_border_fallback: o.Colors

@(private)
button_border_width_fallback: o.Border

@(private)
button_background :: proc(
	state: o.Widget_Frame_State,
	_: o.Widget_Event(o.Widget_Frame_State),
) -> o.Colors {
	switch button_active_variant {
	case .DEFAULT:
		if state.is_Pressed do return o.Color.PRIMARY_PRESSED
		if state.is_hovered do return o.Color.PRIMARY_HOVER
		return o.Color.PRIMARY

	case .SECONDARY:
		if state.is_Pressed do return o.RGBA{180, 180, 180, 255}
		if state.is_hovered do return o.RGBA{210, 210, 210, 255}
		return o.RGBA{235, 235, 235, 255}

	case .OUTLINE:
		if state.is_Pressed do return o.RGBA{210, 210, 210, 255}
		if state.is_hovered do return o.RGBA{245, 245, 245, 255}
		return o.RGBA{0, 0, 0, 0}

	case .GHOST:
		if state.is_Pressed do return o.RGBA{210, 210, 210, 255}
		if state.is_hovered do return o.RGBA{235, 235, 235, 255}
		return o.RGBA{0, 0, 0, 0}

	case .DESTRUCTIVE:
		if state.is_Pressed do return o.RGBA{120, 0, 0, 255}
		if state.is_hovered do return o.RGBA{180, 20, 20, 255}
		return o.RGBA{230, 40, 40, 255}

	case .LINK:
		if state.is_Pressed do return o.RGBA{235, 235, 235, 255}
		if state.is_hovered do return o.RGBA{245, 245, 245, 255}
		return o.RGBA{0, 0, 0, 0}

	case .ACTIVE:
		if state.is_Pressed do return o.Color.ACCENT_PRESSED
		if state.is_hovered do return o.Color.ACCENT_HOVER
		return o.Color.ACCENT
	}

	return o.Color.PRIMARY
}

@(private)
button_border_color :: proc(
	state: o.Widget_Frame_State,
	_: o.Widget_Event(o.Widget_Frame_State),
) -> o.Colors {
	if state.is_focused do return o.palette[.RING]

	return button_border_fallback
}

@(private)
button_border_width :: proc(
	state: o.Widget_Frame_State,
	_: o.Widget_Event(o.Widget_Frame_State),
) -> o.Border {
	if state.is_focused do return f32(1)

	return button_border_width_fallback
}

@(private)
button_apply_border_color :: proc(config: ^w.Button_Config) {
	if config.border_color.mode == .Value {
		button_border_fallback = config.border_color.value
	} else {
		button_border_fallback = o.palette[.TRANSPARENT]
	}

	if config.border.mode == .Value {
		button_border_width_fallback = config.border.value
	} else {
		button_border_width_fallback = f32(1)
	}

	config.border = set.Border(button_border_width)
	config.border_color = set.Colors(button_border_color)
}

@(private)
button_apply_variant :: proc(config: ^w.Button_Config, variant: Button_Variant) {
	config.font = set.Font(o.theme.font_heading)
	config.background = set.Colors(button_background)

	text_padding: f32 = 12
	radius: f32 = 8

	switch variant {
	case .DEFAULT:
	case .SECONDARY:
	case .ACTIVE:
	case .OUTLINE:
	case .GHOST:
	case .DESTRUCTIVE:
	case .LINK:
		radius = 0
		text_padding = 4
	}

	if config.padding.mode != .Value {
		config.padding = set.Padding(o.Pd_pos{x = text_padding, y = text_padding * 0.67})
	}
}


@(private)
button_apply_size :: proc(config: ^w.Button_Config, size: Button_Size) {
	current := o.cfg_style_f32(config.font_size)
	padding_x: f32 = 12
	padding_y: f32 = 8

	switch size {
	case .DEFAULT:
	case .SMALL:
		config.font_size = set.F32(
			current > 0 ? current * 0.875 : o.theme.font_body.size_px * 0.875,
		)
		padding_x = 10
		padding_y = 6

	case .LARGE:
		config.font_size = set.F32(current > 0 ? current * 1.25 : o.theme.font_body.size_px * 1.25)
		padding_x = 16
		padding_y = 10

	case .ICON:
		config.font_size = set.F32(14)
		padding_x = 8
		padding_y = 8
	}

	if size != .DEFAULT {
		config.padding = set.Padding(o.Pd_pos{x = padding_x, y = padding_y})
	}
}

Button :: proc(props: Button_props) {
	prev_variant := button_active_variant
	button_active_variant = props.variant
	defer button_active_variant = prev_variant

	prev_border := button_border_fallback
	defer button_border_fallback = prev_border

	prev_border_width := button_border_width_fallback
	defer button_border_width_fallback = prev_border_width

	base := w.Button_Config {
		width    = set.Width(.AUTO),
		justify  = set.Justify(o.Justify_Pos{x = .CENTER, y = .CENTER}),
		tabbable = set.Bool(true),
	}

	button_apply_variant(&base, props.variant)
	button_apply_size(&base, props.size)

	config := o.merge_widget_config(base, props)
	button_apply_border_color(&config)

	w.Button(
		{
			config = config,
			child = props.child,
			on_focus = props.on_focus,
			on_blur = props.on_blur,
			on_mouse_enter = props.on_mouse_enter,
			on_mouse_leave = props.on_mouse_leave,
			on_mouse_pressed = props.on_mouse_pressed,
			on_mouse_down = props.on_mouse_down,
			on_mouse_released = props.on_mouse_released,
			on_mouse_move = props.on_mouse_move,
			on_click = props.on_click,
			on_contextmenu = props.on_contextmenu,
			on_key_pressed = props.on_key_pressed,
			on_key_down = props.on_key_down,
			on_key_released = props.on_key_released,
		},
	)
}
