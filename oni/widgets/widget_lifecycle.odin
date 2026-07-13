package widgets

import o ".."

/*
Lifecycle callback props shared by mountable widgets.
*/
Widget_Lifecycle_Handlers :: struct($S: typeid) {
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: S) -> o.Mount,
	on_unmount:                   proc(frame_state: S) -> o.Mount,
}

@(private)
lifecycle_frame_state :: proc(state: ^$S) -> ^o.Widget_Frame_State {
	return cast(^o.Widget_Frame_State)state
}

/*
Returns whether pointer and keyboard interaction should run for this widget frame.
*/
widget_can_interact :: proc(handlers: Widget_Lifecycle_Handlers($S), frame_state: ^S) -> bool {
	fs := lifecycle_frame_state(frame_state)
	if fs.is_disabled do return false
	if fs.unmounting == .RUNNING do return false
	if fs.mounting == .RUNNING && !handlers.can_interactive_during_mount do return false
	return true
}

/*
Runs mount and unmount callbacks during the layout pass.

Returns skip_layout when the widget should leave the layout tree, and ran_unmount
when on_unmount was invoked so callers can refresh merged state before measuring.
*/
widget_run_layout_lifecycle :: proc(
	handlers: Widget_Lifecycle_Handlers($S),
	layout_id: o.UI_Id,
	stable_id: bool,
	frame_state: ^S,
	visibility: o.Visibility = .VISIBLE,
) -> (
	skip_layout: bool,
	ran_unmount: bool,
) {
	entry := o.widget_lifecycle_entry(layout_id)
	fs := lifecycle_frame_state(frame_state)

	fs.mounting = entry.mounting
	fs.unmounting = entry.unmounting

	if o.layout_visibility_is_none(visibility) {
		if o.ui_was_laid_out_prev(layout_id) {
			if handlers.on_unmount != nil &&
			   (entry.unmounting == .RUNNING || entry.unmounting == .UNSET) {
				if entry.unmounting == .UNSET {
					entry.unmounting = .RUNNING
				}
				ran_unmount = true
				fs.unmounting = handlers.on_unmount(frame_state^)
				entry.unmounting = fs.unmounting
			}
			if entry.unmounting == .COMPLETED ||
			   entry.unmounting == .UNSET ||
			   handlers.on_unmount == nil {
				skip_layout = true
				o.widget_lifecycle_remove(layout_id)
			} else {
				skip_layout = true
			}
		} else {
			skip_layout = true
		}
		return
	}

	if handlers.on_mount != nil && stable_id {
		switch entry.mounting {
		case .UNSET:
			if !o.ui_was_laid_out_prev(layout_id) {
				entry.mounting = .RUNNING
				fs.mounting = handlers.on_mount(frame_state^)
				entry.mounting = fs.mounting
			}
		case .RUNNING:
			fs.mounting = handlers.on_mount(frame_state^)
			entry.mounting = fs.mounting
		case .COMPLETED:
			fs.mounting = .COMPLETED
		}
	}

	if handlers.on_unmount != nil &&
	   (handlers.unmount && (entry.unmounting == .RUNNING || entry.unmounting == .UNSET)) {
		if handlers.unmount && entry.unmounting == .UNSET {
			entry.unmounting = .RUNNING
		}

		ran_unmount = true
		fs.unmounting = handlers.on_unmount(frame_state^)
		entry.unmounting = fs.unmounting
	}

	if entry.unmounting == .COMPLETED || (handlers.unmount && entry.unmounting == .UNSET) {
		skip_layout = true
		o.widget_lifecycle_remove(layout_id)
	}

	return
}

/*
Syncs persisted mount/unmount phase from the layout tree into frame_state.

Returns false when the draw pass should skip this widget entirely.
*/
widget_prepare_draw :: proc(
	handlers: Widget_Lifecycle_Handlers($S),
	layout_id: o.UI_Id,
	frame_state: ^S,
) -> bool {
	if handlers.unmount && !o.ui_has_layout_node(layout_id) do return false

	entry := o.widget_lifecycle_entry(layout_id)
	fs := lifecycle_frame_state(frame_state)
	fs.mounting = entry.mounting
	fs.unmounting = entry.unmounting

	return o.ui_has_layout_node(layout_id)
}
