package oni_widgets

import o ".."

@(private)
DIALOG_CTX_STACK_MAX :: 16

/*
Live compound context pushed by `Dialog` for Trigger / Scrim / Content parts.
*/
@(private)
Dialog_Ctx :: struct {
	dialog_key:           string,
	open:                 bool,
	disabled:             bool,
	on_open_change:       proc(open: bool),
	trigger_key:          string,
	trigger_layout_id:    o.UI_Id,
	trigger_rect:         o.Rect,
	has_trigger:          bool,
	pointer_owned:        bool,
	trigger_user_click:   proc(event: Dialog_Trigger_Event),
	content_child:        proc(frame_state: Dialog_Content_Props_State),
	content_frame:        Dialog_Content_Props_State,
	content_panel_author: o.Widget_Config,
}

@(private)
dialog_ctx_stack: [DIALOG_CTX_STACK_MAX]Dialog_Ctx

@(private)
dialog_ctx_depth: int

/*
Releases dialog context stack.

Called from widget `Shutdown`.
*/
dialog_shutdown :: proc() {
	dialog_ctx_depth = 0
	dialog_ctx_stack = {}
}

@(private)
dialog_ctx_push :: proc(ctx: Dialog_Ctx) {
	assert(dialog_ctx_depth < DIALOG_CTX_STACK_MAX)
	dialog_ctx_stack[dialog_ctx_depth] = ctx
	dialog_ctx_depth += 1
}

@(private)
dialog_ctx_pop :: proc() {
	assert(dialog_ctx_depth > 0)
	dialog_ctx_depth -= 1
	dialog_ctx_stack[dialog_ctx_depth] = {}
}

@(private)
dialog_ctx_ok :: proc() -> bool {
	return dialog_ctx_depth > 0
}

@(private)
dialog_ctx_top :: proc() -> ^Dialog_Ctx {
	assert(dialog_ctx_depth > 0)

	return &dialog_ctx_stack[dialog_ctx_depth - 1]
}

@(private)
dialog_set_open :: proc(open: bool) {
	ctx := dialog_ctx_top()

	if ctx.disabled {
		return
	}

	if ctx.open == open {
		return
	}

	ctx.open = open

	if ctx.on_open_change != nil {
		ctx.on_open_change(open)
	}
}

@(private)
dialog_note_pointer :: proc() {
	if !dialog_ctx_ok() {
		return
	}

	dialog_ctx_top().pointer_owned = true
}
