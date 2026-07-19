package oni_widgets

import o ".."

/*
Registers a widget in this frame's tab order when it is tabbable and interactive.
*/
widget_register_tab_order :: proc(element_id: o.Widget_ID, tabbable: bool, can_interact: bool) {
	if !tabbable || !can_interact do return
	o.register_tabbable(element_id)
}

/*
Returns whether auto_focus should run for a resolved widget config.
*/
widget_should_auto_focus :: proc(
	config: o.Resolved_Widget_Config,
	element_id: o.Widget_ID,
) -> bool {
	return config.auto_focus && config.tabbable && o.w_ctx.auto_focused_id != element_id
}

/*
Applies auto_focus for the current frame when requested.
*/
widget_apply_auto_focus :: proc(element_id: o.Widget_ID, should: bool) {
	if !should do return
	o.widget_set_focused_id(element_id)
	o.widget_set_auto_focused_id(element_id)
}

/*
Returns whether the given element currently has keyboard focus.
*/
widget_is_focused :: proc(element_id: o.Widget_ID) -> bool {
	return o.w_ctx.focused_id == element_id
}

/*
Updates focus from a pointer press using CSS-like hover.

Any tabbable hovered ancestor of the hit may claim focus; deeper widgets run
later and overwrite, so the deepest tabbable under the pointer wins. Non-tabbable
children (e.g. button labels) therefore still focus their tabbable parent.

Returns got_focus when this element gained focus and lost_focus when it was cleared.
*/
widget_handle_pointer_focus :: proc(
	element_id: o.Widget_ID,
	tabbable: bool,
	was_focused: bool,
	is_hovered: bool,
	is_focused: ^bool,
) -> (
	got_focus: bool,
	lost_focus: bool,
) {
	if !tabbable do return

	if !o.w_ctx.left_mouse.pressed do return

	if is_hovered {
		o.widget_set_focused_id(element_id)
		is_focused^ = true

		if !was_focused {
			got_focus = true
		}
	} else if was_focused {
		o.widget_set_focused_id("")
		is_focused^ = false
		lost_focus = true
	}

	return
}

/*
Returns whether this element gained focus from Tab navigation this frame.
*/
widget_got_tab_focus :: proc(element_id: o.Widget_ID) -> bool {
	return o.w_ctx.tab_focus_changed && o.w_ctx.focused_id == element_id
}

/*
Returns whether this element lost focus from Tab navigation this frame.
*/
widget_lost_tab_focus :: proc(element_id: o.Widget_ID) -> bool {
	return o.w_ctx.tab_focus_changed && o.w_ctx.tab_focus_previous_id == element_id
}
