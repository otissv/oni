package oni_widgets

import o ".."
import set "../set"

/*
Dialog scrim configuration (shadcn DialogOverlay).

Viewport-fixed rectangle in `.OVERLAY` space; defaults to a semi-transparent fill.
*/
Dialog_Scrim_Config :: o.Widget_Config

/*
Dialog scrim per-frame state.
*/
Dialog_Scrim_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Dialog scrim event snapshot.
*/
Dialog_Scrim_Event :: o.Widget_Event(Dialog_Scrim_State)

/*
Dialog scrim props: full-viewport backdrop while the parent dialog is open.
*/
Dialog_Scrim_Props :: struct {
	config:                       Dialog_Scrim_Config,
	child:                        proc(frame_state: Dialog_Scrim_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Dialog_Scrim_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Dialog_Scrim_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Dialog_Scrim_Event),
	on_blur:                      proc(event: Dialog_Scrim_Event),
	on_mouse_enter:               proc(event: Dialog_Scrim_Event),
	on_mouse_leave:               proc(event: Dialog_Scrim_Event),
	on_mouse_pressed:             proc(event: Dialog_Scrim_Event),
	on_mouse_down:                proc(event: Dialog_Scrim_Event),
	on_mouse_released:            proc(event: Dialog_Scrim_Event),
	on_mouse_move:                proc(event: Dialog_Scrim_Event),
	on_click:                     proc(event: Dialog_Scrim_Event),
	on_contextmenu:               proc(event: Dialog_Scrim_Event),
	on_key_pressed:               proc(event: Dialog_Scrim_Event),
	on_key_down:                  proc(event: Dialog_Scrim_Event),
	on_key_released:              proc(event: Dialog_Scrim_Event),
}

@(private)
DIALOG_DEFAULT_SCRIM_Z :: f32(40)

@(private)
dialog_scrim_viewport_size :: proc() -> (w, h: f32) {
	w = f32(o.state.dpi.logical_w)
	h = f32(o.state.dpi.logical_h)

	return
}

@(private)
dialog_scrim_theme_defaults :: proc() -> o.Widget_Config {
	vw, vh := dialog_scrim_viewport_size()

	return o.Widget_Config {
		kind = .DIALOG_SCRIM,
		space = set.Space(.OVERLAY),
		position = set.Position(.FIXED),
		x = set.F32(0),
		y = set.F32(0),
		width = set.Width(vw),
		height = set.Height(vh),
		background = set.Background(o.RGBA{0, 0, 0, 128}),
		z_index = set.Z_Index(DIALOG_DEFAULT_SCRIM_Z),
	}
}

@(private)
dialog_scrim_active: Dialog_Scrim_Props

@(private)
dialog_scrim_state_from_rect :: proc(state: Rectangle_State) -> Dialog_Scrim_State {
	return Dialog_Scrim_State(state)
}

@(private)
dialog_scrim_event_from_rect :: proc(event: Rectangle_Event) -> Dialog_Scrim_Event {
	return Dialog_Scrim_Event(event)
}

@(private)
dialog_scrim_rect_theme_base :: proc(frame_state: ^Rectangle_State) -> Rectangle_Config {
	_ = frame_state

	return Rectangle_Config{kind = .DIALOG_SCRIM}
}

@(private)
dialog_scrim_rect_child :: proc(state: Rectangle_State) {
	if dialog_scrim_active.child != nil {
		dialog_scrim_active.child(dialog_scrim_state_from_rect(state))
	}
}

@(private)
dialog_scrim_rect_on_mount :: proc(state: Rectangle_State) -> o.Mount {
	if dialog_scrim_active.on_mount == nil {
		return {}
	}

	return dialog_scrim_active.on_mount(dialog_scrim_state_from_rect(state))
}

@(private)
dialog_scrim_rect_on_unmount :: proc(state: Rectangle_State) -> o.Mount {
	if dialog_scrim_active.on_unmount == nil {
		return {}
	}

	return dialog_scrim_active.on_unmount(dialog_scrim_state_from_rect(state))
}

@(private)
dialog_scrim_rect_on_focus :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_focus != nil {
		dialog_scrim_active.on_focus(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_blur :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_blur != nil {
		dialog_scrim_active.on_blur(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_enter :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_enter != nil {
		dialog_scrim_active.on_mouse_enter(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_leave :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_leave != nil {
		dialog_scrim_active.on_mouse_leave(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_pressed :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_pressed != nil {
		dialog_scrim_active.on_mouse_pressed(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_down :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_down != nil {
		dialog_scrim_active.on_mouse_down(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_released :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_released != nil {
		dialog_scrim_active.on_mouse_released(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_mouse_move :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_mouse_move != nil {
		dialog_scrim_active.on_mouse_move(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_click :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_click != nil {
		dialog_scrim_active.on_click(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_contextmenu :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_contextmenu != nil {
		dialog_scrim_active.on_contextmenu(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_key_pressed :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_key_pressed != nil {
		dialog_scrim_active.on_key_pressed(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_key_down :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_key_down != nil {
		dialog_scrim_active.on_key_down(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rect_on_key_released :: proc(event: Rectangle_Event) {
	if dialog_scrim_active.on_key_released != nil {
		dialog_scrim_active.on_key_released(dialog_scrim_event_from_rect(event))
	}
}

@(private)
dialog_scrim_rectangle_props :: proc(props: Dialog_Scrim_Props) -> Rectangle_Props {
	return Rectangle_Props {
		config = props.config,
		child = dialog_scrim_rect_child,
		unmount = props.unmount,
		can_interactive_during_mount = props.can_interactive_during_mount,
		on_mount = dialog_scrim_rect_on_mount,
		on_unmount = dialog_scrim_rect_on_unmount,
		on_scroll = props.on_scroll,
		scroll_bar = props.scroll_bar,
		on_focus = dialog_scrim_rect_on_focus,
		on_blur = dialog_scrim_rect_on_blur,
		on_mouse_enter = dialog_scrim_rect_on_mouse_enter,
		on_mouse_leave = dialog_scrim_rect_on_mouse_leave,
		on_mouse_pressed = dialog_scrim_rect_on_mouse_pressed,
		on_mouse_down = dialog_scrim_rect_on_mouse_down,
		on_mouse_released = dialog_scrim_rect_on_mouse_released,
		on_mouse_move = dialog_scrim_rect_on_mouse_move,
		on_click = dialog_scrim_rect_on_click,
		on_contextmenu = dialog_scrim_rect_on_contextmenu,
		on_key_pressed = dialog_scrim_rect_on_key_pressed,
		on_key_down = dialog_scrim_rect_on_key_down,
		on_key_released = dialog_scrim_rect_on_key_released,
	}
}

@(private)
dialog_scrim_is_open :: proc() -> bool {
	if !dialog_ctx_ok() {
		return false
	}

	return dialog_ctx_top().open
}

/*
Renders the modal scrim inside a `Dialog` root.

Skips layout and draw while closed. Delegates to `Rectangle` with forced
`.OVERLAY` draw space and `position = .FIXED` relative to the viewport.
*/
Dialog_Scrim :: proc(props: Dialog_Scrim_Props) {
	if !dialog_scrim_is_open() {
		return
	}

	if !dialog_ctx_ok() {
		return
	}

	cfg := o.merge_widget_config(dialog_scrim_theme_defaults(), props.config)
	cfg.space = set.Space(.OVERLAY)
	cfg.position = set.Position(.FIXED)


	props_merged := props
	props_merged.config = cfg

	dialog_scrim_active = props_merged
	defer dialog_scrim_active = {}

	o.Begin_Overlay()
	defer o.End_Overlay()

	rectangle_with_theme(dialog_scrim_rectangle_props(props_merged), dialog_scrim_rect_theme_base)


}
