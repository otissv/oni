package oni_widgets

@(private)
COLLAPSIBLE_CTX_STACK_MAX :: 16

/*
Live compound context pushed by `Collapsible` for Trigger / Content parts.
*/
@(private)
Collapsible_Ctx :: struct {
	open:               bool,
	disabled:           bool,
	on_open_change:     proc(open: bool),
	trigger_user_click: proc(event: Collapsible_Trigger_Event),
}

@(private)
collapsible_ctx_stack: [COLLAPSIBLE_CTX_STACK_MAX]Collapsible_Ctx

@(private)
collapsible_ctx_depth: int

/*
Releases collapsible context stack.

Called from widget `Shutdown`.
*/
collapsible_shutdown :: proc() {
	collapsible_ctx_depth = 0
	collapsible_ctx_stack = {}
}

@(private)
collapsible_ctx_push :: proc(ctx: Collapsible_Ctx) {
	assert(collapsible_ctx_depth < COLLAPSIBLE_CTX_STACK_MAX)
	collapsible_ctx_stack[collapsible_ctx_depth] = ctx
	collapsible_ctx_depth += 1
}

@(private)
collapsible_ctx_pop :: proc() {
	assert(collapsible_ctx_depth > 0)
	collapsible_ctx_depth -= 1
	collapsible_ctx_stack[collapsible_ctx_depth] = {}
}

@(private)
collapsible_ctx_ok :: proc() -> bool {
	return collapsible_ctx_depth > 0
}

@(private)
collapsible_ctx_top :: proc() -> ^Collapsible_Ctx {
	assert(collapsible_ctx_depth > 0)

	return &collapsible_ctx_stack[collapsible_ctx_depth - 1]
}

/*
Returns whether the active `Collapsible` root is open.
*/
Collapsible_Is_Open :: proc() -> bool {
	if !collapsible_ctx_ok() {
		return false
	}

	return collapsible_ctx_top().open
}

/*
Opens or closes the active `Collapsible` root.
*/
Collapsible_Set_Open :: proc(open: bool) {
	if !collapsible_ctx_ok() {
		return
	}

	collapsible_set_open(open)
}

@(private)
collapsible_set_open :: proc(open: bool) {
	ctx := collapsible_ctx_top()

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
