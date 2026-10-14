package oni_widgets

import o "../../oni"
import set "../set"

/*
Dialog action button configuration.

Renders via `Button`; does not dismiss the parent dialog.
*/
Dialog_Action_Config :: Button_Config

/*
Dialog action per-frame state (same as `Button_State`).
*/
Dialog_Action_State :: Button_State

/*
Dialog action event snapshot (same as `Button_Event`).
*/
Dialog_Action_Event :: Button_Event

/*
Dialog action props: identical to `Button_Props`.

Use `on_click` for the primary action; close the dialog from app state when done.
*/
Dialog_Action_Props :: Button_Props

/*
Dialog cancel button configuration.

Renders via `Button`. Default click closes the parent dialog; pass `on_click` to
replace that behavior entirely.
*/
Dialog_Cancel_Config :: Button_Config

/*
Dialog cancel per-frame state (same as `Button_State`).
*/
Dialog_Cancel_State :: Button_State

/*
Dialog cancel event snapshot (same as `Button_Event`).
*/
Dialog_Cancel_Event :: Button_Event

/*
Dialog cancel props: identical to `Button_Props`.

When `on_click` is nil, click closes the parent `Dialog`. A non-nil `on_click`
replaces the default close; the handler must update open state if dismiss is still wanted.
*/
Dialog_Cancel_Props :: Button_Props

@(private)
dialog_action_button_props :: proc(props: Button_Props) -> Button_Props {
	out := props
	out.config = o.merge_widget_config(Button_Config{width = set.Width(.FIT)}, props.config)

	if dialog_ctx_ok() && dialog_ctx_top().disabled {
		out.config.disabled = set.Disabled(true)
	}

	return out
}

@(private)
dialog_cancel_default_close :: proc(event: Button_Event) {
	_ = event

	if !dialog_ctx_ok() {
		return
	}

	dialog_set_open(false)
}

/*
Renders a primary action control inside a `Dialog`.

Must be used under `Dialog`. Wraps `Button` with dialog disabled inheritance.
*/
Dialog_Action :: proc(props: Dialog_Action_Props) {
	Button(dialog_action_button_props(props))
}

/*
Renders a cancel control that closes the parent `Dialog` by default.

Must be used under `Dialog`. Wraps `Button`. Pass `on_click` to override close.
*/
Dialog_Cancel :: proc(props: Dialog_Cancel_Props) {
	button_props := dialog_action_button_props(props)

	if button_props.on_click == nil {
		button_props.on_click = dialog_cancel_default_close
	}

	Button(button_props)
}
