package oni_widgets

import o ".."
import "core:strings"
import sdl "vendor:sdl3"

/*
Default hover delay before a tooltip opens (seconds).
*/
@(private)
TOOLTIP_DEFAULT_SHOW_DELAY_S :: f32(0.7)

/*
Horizontal alignment of tooltip content relative to the trigger.
*/
Tooltip_Align :: Popover_Align

@(private)
TOOLTIP_CTX_STACK_MAX :: 16

/*
Live compound context pushed by `Tooltip` for Trigger / Content parts.
*/
@(private)
Tooltip_Ctx :: struct {
	generation:         u64,
	tooltip_key:        string,
	open:               bool,
	disabled:           bool,
	show_delay:         f32,
	on_open_change:     proc(open: bool),
	trigger_key:        string,
	trigger_layout_id:  o.UI_Id,
	trigger_rect:       o.Rect,
	has_trigger:        bool,
	trigger_hovered:    bool,
	pointer_owned:      bool,
	trigger_user_enter: proc(event: Tooltip_Trigger_Event),
	trigger_user_leave: proc(event: Tooltip_Trigger_Event),
	content_child:      proc(frame_state: Tooltip_Content_Props_State),
	content_frame:      Tooltip_Content_Props_State,
}

@(private)
Tooltip_Owner :: struct {
	on_open_change: proc(open: bool),
	show_delay:     f32,
	disabled:       bool,
	trigger_id:     o.UI_Id,
	trigger_space:  o.Draw_Space,
}

@(private)
tooltip_ctx_stack: [TOOLTIP_CTX_STACK_MAX]Tooltip_Ctx

@(private)
tooltip_ctx_depth: int

@(private)
tooltip_ctx_generation: u64

@(private)
tooltip_registry: map[string]Tooltip_Owner

@(private)
tooltip_global_active: string

@(private)
tooltip_global_pending: string

@(private)
tooltip_global_pending_elapsed: f64

@(private)
tooltip_global_tick_frame: u64

@(private)
tooltip_tick_last_counter: u64

/*
Releases tooltip context stack, registry, and global hover state.

Called from widget `Shutdown`.
*/
tooltip_shutdown :: proc() {
	tooltip_ctx_depth = 0
	tooltip_ctx_stack = {}
	tooltip_ctx_generation = 0

	for key in tooltip_registry {
		delete(key)
	}

	delete(tooltip_registry)
	tooltip_registry = {}

	if tooltip_global_active != "" {
		delete(tooltip_global_active)
		tooltip_global_active = ""
	}

	tooltip_clear_pending()
	tooltip_global_tick_frame = 0
	tooltip_tick_last_counter = 0
}

@(private)
tooltip_clear_pending :: proc() {
	if tooltip_global_pending != "" {
		delete(tooltip_global_pending)
		tooltip_global_pending = ""
	}

	tooltip_global_pending_elapsed = 0
}

@(private)
tooltip_retain_key :: proc(key: string) -> string {
	if key == "" do return ""

	return strings.clone(key)
}

@(private)
tooltip_release_key :: proc(key: string) {
	if key != "" {
		delete(key)
	}
}

@(private)
tooltip_register_owner :: proc(key: string, owner: Tooltip_Owner) {
	if key == "" do return

	if tooltip_registry == nil {
		tooltip_registry = make(map[string]Tooltip_Owner)
	}

	stored, ok := tooltip_registry[key]
	if !ok {
		tooltip_registry[tooltip_retain_key(key)] = owner
		return
	}

	stored.on_open_change = owner.on_open_change
	stored.show_delay = owner.show_delay
	stored.disabled = owner.disabled
	tooltip_registry[key] = stored
}

@(private)
tooltip_owner_for :: proc(key: string) -> (Tooltip_Owner, bool) {
	if tooltip_registry == nil do return {}, false

	return tooltip_registry[key]
}

@(private)
tooltip_close_key :: proc(key: string) {
	if key == "" do return

	owner, ok := tooltip_owner_for(key)
	if ok && owner.on_open_change != nil {
		owner.on_open_change(false)
	}

	if tooltip_global_active == key {
		tooltip_release_key(tooltip_global_active)
		tooltip_global_active = ""
	}
}

@(private)
tooltip_open_key :: proc(key: string) {
	if key == "" do return
	if tooltip_global_active == key do return

	owner, ok := tooltip_owner_for(key)
	if !ok || owner.disabled do return

	if tooltip_global_active != "" && tooltip_global_active != key {
		tooltip_close_key(tooltip_global_active)
	}

	if owner.on_open_change != nil {
		owner.on_open_change(true)
	}

	if tooltip_global_active != "" && tooltip_global_active != key {
		tooltip_release_key(tooltip_global_active)
	}

	tooltip_global_active = tooltip_retain_key(key)
}

@(private)
tooltip_global_tick :: proc(dt: f64) {
	if tooltip_global_pending == "" do return

	owner, ok := tooltip_owner_for(tooltip_global_pending)
	if !ok || owner.disabled {
		tooltip_clear_pending()
		return
	}

	tooltip_global_pending_elapsed += dt
	delay := f64(owner.show_delay)

	if delay <= 0 {
		delay = f64(TOOLTIP_DEFAULT_SHOW_DELAY_S)
	}

	if tooltip_global_pending_elapsed < delay do return

	pending := tooltip_global_pending
	tooltip_global_pending = ""
	tooltip_global_pending_elapsed = 0
	defer tooltip_release_key(pending)
	tooltip_open_key(pending)
}

@(private)
tooltip_frame_tick :: proc() {
	if o.state == nil do return

	frame := o.state.ui.frame

	if tooltip_global_tick_frame == frame do return

	tooltip_global_tick_frame = frame

	now := sdl.GetPerformanceCounter()
	dt: f64 = 0

	if tooltip_tick_last_counter != 0 && o.state.perf_frequency > 0 {
		dt = f64(now - tooltip_tick_last_counter) / f64(o.state.perf_frequency)
	}

	tooltip_tick_last_counter = now

	if tooltip_global_pending != "" {
		owner, registered := tooltip_owner_for(tooltip_global_pending)
		node_index, laid_out := o.state.ui.layout.id_to_node[owner.trigger_id]

		if !registered || !laid_out {
			tooltip_clear_pending()
			return
		}

		node := &o.state.ui.layout.nodes[node_index]

		if node.config.disabled || !o.pointer_hits(owner.trigger_id, node.rect, owner.trigger_space) {
			tooltip_clear_pending()
			return
		}
	}

	tooltip_global_tick(dt)
}

@(private)
tooltip_test_advance_pending :: proc(seconds: f64) {
	tooltip_global_tick(seconds)
}

@(private)
tooltip_on_trigger_enter :: proc(key: string) {
	if key == "" do return
	if tooltip_global_active == key do return

	owner, ok := tooltip_owner_for(key)
	if !ok || owner.disabled do return

	if tooltip_global_pending == key do return

	tooltip_clear_pending()
	tooltip_global_pending = tooltip_retain_key(key)
	tooltip_global_pending_elapsed = 0

	if tooltip_global_active != "" && tooltip_global_active != key {
		tooltip_close_key(tooltip_global_active)
	}
}

@(private)
tooltip_on_trigger_leave :: proc(key: string) {
	if key == "" do return

	if tooltip_global_pending == key {
		tooltip_clear_pending()
	}
}

@(private)
tooltip_note_app_open :: proc(key: string, open: bool) {
	if open {
		if tooltip_global_pending == key {
			tooltip_clear_pending()
		}

		if tooltip_global_active != "" && tooltip_global_active != key {
			tooltip_release_key(tooltip_global_active)
		}

		if tooltip_global_active == "" {
			tooltip_global_active = tooltip_retain_key(key)
		}

		return
	}

	if tooltip_global_active == key {
		tooltip_release_key(tooltip_global_active)
		tooltip_global_active = ""

		if tooltip_global_pending == key {
			tooltip_clear_pending()
		}
	}
}

@(private)
tooltip_ctx_push :: proc(ctx: Tooltip_Ctx) -> int {
	assert(tooltip_ctx_depth < TOOLTIP_CTX_STACK_MAX)
	assert(tooltip_ctx_generation < max(u64))
	tooltip_ctx_generation += 1
	tooltip_ctx_stack[tooltip_ctx_depth] = ctx
	tooltip_ctx_stack[tooltip_ctx_depth].generation = tooltip_ctx_generation
	slot := tooltip_ctx_depth
	tooltip_ctx_depth += 1

	return slot
}

@(private)
tooltip_ctx_pop :: proc() {
	assert(tooltip_ctx_depth > 0)
	tooltip_ctx_depth -= 1
	tooltip_ctx_stack[tooltip_ctx_depth] = {}
}

@(private)
tooltip_ctx_ok :: proc() -> bool {
	return tooltip_ctx_depth > 0
}

@(private)
tooltip_ctx_top :: proc() -> ^Tooltip_Ctx {
	assert(tooltip_ctx_depth > 0)

	return &tooltip_ctx_stack[tooltip_ctx_depth - 1]
}

@(private)
tooltip_set_trigger :: proc(key: string, layout_id: o.UI_Id, rect: o.Rect, space: o.Draw_Space) {
	ctx := tooltip_ctx_top()
	ctx.trigger_key = key
	ctx.trigger_layout_id = layout_id
	ctx.trigger_rect = rect
	ctx.has_trigger = true

	if owner, ok := tooltip_owner_for(ctx.tooltip_key); ok {
		owner.trigger_id = layout_id
		owner.trigger_space = space
		tooltip_registry[ctx.tooltip_key] = owner
	}
}

@(private)
tooltip_claim_pointer :: proc() {
	if !tooltip_ctx_ok() do return

	tooltip_ctx_top().pointer_owned = true
}

/*
After children run on Draw: close when open and pointer is not on trigger or content.
*/
@(private)
Tooltip_Process_Hover :: proc() {
	if !tooltip_ctx_ok() do return

	ctx := tooltip_ctx_top()

	if !ctx.open || ctx.disabled do return

	if ctx.trigger_hovered || ctx.pointer_owned do return

	tooltip_close_key(ctx.tooltip_key)
}
