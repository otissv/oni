package oni_widgets

import o ".."
import set "../set"

Menubar_Radio_Group_Config :: struct {
	using _: o.Widget_Config,
	value: string,
}
Menubar_Radio_Group_State :: struct { value: string, disabled: bool }
Menubar_Radio_Group_Props :: struct {
	config: Menubar_Radio_Group_Config,
	child: proc(state: Menubar_Radio_Group_State),
	on_value_change: proc(value: string),
}

@(private)
Menubar_Radio_Ctx :: struct {
	value: string,
	disabled: bool,
	on_value_change: proc(value: string),
	child: proc(state: Menubar_Radio_Group_State),
}

@(private) menubar_radio_ctx: ^Menubar_Radio_Ctx

Menubar_Radio_Group :: proc(props: Menubar_Radio_Group_Props) {
	if menubar_ctx == nil || menubar_ctx.group == menubar_ctx.root do return
	ctx := Menubar_Radio_Ctx {
		value = props.config.value, disabled = o.cfg_style_bool(props.config.disabled),
		on_value_change = props.on_value_change,
		child = props.child,
	}
	previous := menubar_radio_ctx
	menubar_radio_ctx = &ctx
	defer menubar_radio_ctx = previous

	cfg := o.merge_widget_config(o.Widget_Config {
		kind = .MENUBAR_GROUP, width = set.Width(.GROW), height = set.Height(.FIT),
		direction = set.Direction(.VERTICAL), gap_y = set.Gap_Y(u16(2)),
		tabbable = set.Tabbable(false),
	}, props.config)
	Rectangle({config = cfg, child = menubar_radio_group_child})
}

@(private)
menubar_radio_group_child :: proc(state: Rectangle_State) {
	ctx := menubar_radio_ctx
	ctx.disabled ||= state.is_disabled

	if ctx.child != nil do ctx.child({value = ctx.value, disabled = ctx.disabled})
}

Menubar_Group_Config :: struct {
	using _: o.Widget_Config,
	unmount: bool,
	can_interactive_during_mount: bool,
}
Menubar_Group_State :: Rectangle_State
Menubar_Group_Props :: struct {
	config: Menubar_Group_Config,
	child:                        proc(frame_state: Menubar_Group_State),
	on_mount:                     proc(frame_state: Menubar_Group_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Menubar_Group_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Menubar_Group_Event),
	on_blur:                      proc(event: Menubar_Group_Event),
	on_mouse_enter:               proc(event: Menubar_Group_Event),
	on_mouse_leave:               proc(event: Menubar_Group_Event),
	on_mouse_pressed:             proc(event: Menubar_Group_Event),
	on_mouse_down:                proc(event: Menubar_Group_Event),
	on_mouse_released:            proc(event: Menubar_Group_Event),
	on_mouse_move:                proc(event: Menubar_Group_Event),
	on_click:                     proc(event: Menubar_Group_Event),
	on_contextmenu:               proc(event: Menubar_Group_Event),
	on_key_pressed:               proc(event: Menubar_Group_Event),
	on_key_down:                  proc(event: Menubar_Group_Event),
	on_key_released:              proc(event: Menubar_Group_Event),
}
Menubar_Group_Event :: Rectangle_Event

Menubar_Group :: proc(props: Menubar_Group_Props) {
	menubar_decoration_panel(props, .MENUBAR_GROUP)
}

@(private)
menubar_decoration_panel :: proc(props: Menubar_Group_Props, kind: o.Widget_Kind) {
	if menubar_ctx == nil || menubar_ctx.group == menubar_ctx.root do return
	cfg := o.Widget_Config {
		kind = kind, width = set.Width(.GROW), height = set.Height(.FIT),
		direction = set.Direction(.VERTICAL), gap_y = set.Gap_Y(u16(2)),
		tabbable = set.Tabbable(false),
	}
	if kind == .MENUBAR_SEPARATOR {
		cfg.height = set.Height(f32(1))
		cfg.margin = set.Margin(f32(4))
		cfg.background = set.Background(o.Color.BORDER)
	}
	cfg = o.merge_widget_config(cfg, props.config)
	Rectangle({
		config = cfg,
		unmount = props.config.unmount,
		can_interactive_during_mount = props.config.can_interactive_during_mount,
		child = props.child,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
		on_scroll = props.on_scroll,
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
	})
}

Menubar_Label_Config :: struct {
	using _: Text_Config,
	inset: bool,
	unmount: bool,
	can_interactive_during_mount: bool,
}
Menubar_Label_State :: Text_Merged_State
Menubar_Label_Event :: Text_Event
Menubar_Label_Props :: struct {
	config: Menubar_Label_Config,
	on_mount:                     proc(frame_state: Text_Merged_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Text_Merged_State) -> o.Mount,
	on_focus:                     proc(event: Text_Event),
	on_blur:                      proc(event: Text_Event),
	on_mouse_enter:               proc(event: Text_Event),
	on_mouse_leave:               proc(event: Text_Event),
	on_mouse_pressed:             proc(event: Text_Event),
	on_mouse_down:                proc(event: Text_Event),
	on_mouse_released:            proc(event: Text_Event),
	on_mouse_move:                proc(event: Text_Event),
	on_click:                     proc(event: Text_Event),
	on_contextmenu:               proc(event: Text_Event),
	on_key_pressed:               proc(event: Text_Event),
	on_key_down:                  proc(event: Text_Event),
	on_key_released:              proc(event: Text_Event),
}

Menubar_Label :: proc(props: Menubar_Label_Props) {
	menubar_decoration_text(props, false)
}

Menubar_Shortcut_Config :: Menubar_Label_Config
Menubar_Shortcut_State :: Text_Merged_State
Menubar_Shortcut_Event :: Text_Event
Menubar_Shortcut_Props :: Menubar_Label_Props

// A visual hint only; register actual commands through the engine shortcuts API.
Menubar_Shortcut :: proc(props: Menubar_Shortcut_Props) {
	menubar_decoration_text(props, true)
}

@(private)
menubar_decoration_text :: proc(props: Menubar_Label_Props, shortcut: bool) {
	cfg := props.config
	if shortcut {
		if cfg.width == nil do cfg.width = set.Width(.GROW)
		if cfg.align.mode == .UNSET do cfg.align = set.Align(menubar_ctx != nil && menubar_ctx.rtl ? .LEFT : .RIGHT)
		if cfg.color.mode == .UNSET do cfg.color = set.Color(o.Color.MUTED_FOREGROUND)
		if cfg.font_size.mode == .UNSET do cfg.font_size = set.Font_size(f32(12))
	} else {
		if cfg.padding.mode == .UNSET do cfg.padding = set.Padding(o.Pd_pos{x = cfg.inset ? 32 : 8, y = 6})
		if cfg.font_weight.mode == .UNSET do cfg.font_weight = set.Font_weight(f32(600))
	}
	text_cfg: Text_Config = cfg
	Text({
		config = text_cfg,
		unmount = cfg.unmount,
		can_interactive_during_mount = cfg.can_interactive_during_mount,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
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
	})
}

Menubar_Separator_Config :: Menubar_Group_Config
Menubar_Separator_State :: Menubar_Group_State
Menubar_Separator_Event :: Menubar_Group_Event
Menubar_Separator_Props :: Menubar_Group_Props

Menubar_Separator :: proc(props: Menubar_Separator_Props) {
	menubar_decoration_panel(props, .MENUBAR_SEPARATOR)
}
