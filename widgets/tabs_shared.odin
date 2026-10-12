package oni_widgets

import o ".."

/*
Arrow-key wrapping for a tabs list.

`.ON` is the zero value and matches Base UI `loopFocus`: focus wraps from the
last enabled trigger to the first. `.OFF` stops at the ends.
*/
Tabs_Loop :: enum {
	ON,
	OFF,
}

/*
Layout axis and arrow keys for tabs.

`.HORIZONTAL` is the zero value: row list layout, Left/Right change focus.
`.VERTICAL`: column list layout, Up/Down change focus. Home and End jump to the
first and last enabled triggers on either axis.
*/
Tabs_Orientation :: enum {
	HORIZONTAL,
	VERTICAL,
}

/*
Visual style for `Tabs_List` and selected `Tabs_Trigger` chrome.

`.DEFAULT` is the zero value: muted pill list with a filled active trigger.
`.LINE`: transparent list with an underline on the active trigger.
*/
Tabs_List_Variant :: enum {
	DEFAULT,
	LINE,
}

@(private)
TABS_MAX :: 8

@(private)
TABS_TRIGGERS_MAX :: 128

@(private)
TABS_DRAWN_MAX :: 256


@(private)
Tabs_Trigger_Entry :: struct {
	value:      string,
	element_id: string,
	disabled:   bool,
	auto_focus: bool,
	on_focus:   proc(event: Tabs_Trigger_Event),
}

@(private)
Tabs_Ctx :: struct {
	key:               string,
	value:             string,
	disabled:          bool,
	loop:              bool,
	orientation:       Tabs_Orientation,
	activate_on_focus: bool,
	variant:           Tabs_List_Variant,
	in_list:           bool,
	on_value_change:   proc(value: string),
	triggers:          [TABS_TRIGGERS_MAX]Tabs_Trigger_Entry,
	trigger_count:     int,
}

@(private)
Tabs_Snapshot :: struct {
	key:               string,
	triggers:          [TABS_TRIGGERS_MAX]Tabs_Trigger_Entry,
	count:             int,
	activate_on_focus: bool,
	variant:           Tabs_List_Variant,
}

@(private)
Tabs_Drawn :: struct {
	element_id: string,
	state:      Tabs_Trigger_State,
}

@(private)
Tabs_Nav :: enum {
	NONE,
	NEXT,
	PREV,
	FIRST,
	LAST,
}

@(private)
tabs_ctx_stack: [TABS_MAX]Tabs_Ctx

@(private)
tabs_ctx_depth: int

@(private)
tabs_ctx_dummy: Tabs_Ctx

@(private)
tabs_snapshots: [TABS_MAX]Tabs_Snapshot

@(private)
tabs_snapshot_count: int

@(private)
tabs_snapshot_frame: u64

@(private)
tabs_drawn: [TABS_DRAWN_MAX]Tabs_Drawn

@(private)
tabs_drawn_count: int

@(private)
tabs_arrow_group: string

@(private)
tabs_arrow_target: string

@(private)
tabs_arrow_handled: bool

@(private)
tabs_arrow_blur: string

@(private)
tabs_arrow_blur_group: string

@(private)
tabs_triggers_warned: bool

@(private)
tabs_groups_warned: bool

@(private)
tabs_stack_warned: bool

/*
Releases tabs frame tables.

Trigger value strings are caller-owned and are not freed. Called from widget
`Shutdown` and from tests so a later frame cannot observe a stale root.
*/
tabs_shutdown :: proc() {
	tabs_ctx_depth = 0
	tabs_ctx_stack = {}
	tabs_ctx_dummy = {}
	tabs_snapshot_count = 0
	tabs_snapshot_frame = 0
	tabs_snapshots = {}
	tabs_drawn_count = 0
	tabs_drawn = {}
	tabs_arrow_group = ""
	tabs_arrow_target = ""
	tabs_arrow_handled = false
	tabs_arrow_blur = ""
	tabs_arrow_blur_group = ""
	tabs_triggers_warned = false
	tabs_groups_warned = false
	tabs_stack_warned = false
	tabs_trigger_action = {}
}

@(private)
tabs_snapshots_begin_frame :: proc() {
	if o.state == nil {
		return
	}

	frame := o.state.ui.frame

	if tabs_snapshot_frame == frame {
		return
	}

	tabs_snapshot_count = 0
	tabs_snapshot_frame = frame
	tabs_drawn_count = 0
	tabs_arrow_group = ""
	tabs_arrow_target = ""
	tabs_arrow_handled = false
	tabs_arrow_blur = ""
	tabs_arrow_blur_group = ""
}

@(private)
tabs_loop_enabled :: proc(loop: Tabs_Loop) -> bool {
	switch loop {
	case .OFF:
		return false
	case .ON:
		return true
	case:
		return true
	}
}

@(private)
tabs_orientation_normalize :: proc(orientation: Tabs_Orientation) -> Tabs_Orientation {
	switch orientation {
	case .VERTICAL:
		return .VERTICAL
	case .HORIZONTAL:
		return .HORIZONTAL
	case:
		return .HORIZONTAL
	}
}

@(private)
tabs_variant_normalize :: proc(variant: Tabs_List_Variant) -> Tabs_List_Variant {
	switch variant {
	case .LINE:
		return .LINE
	case .DEFAULT:
		return .DEFAULT
	case:
		return .DEFAULT
	}
}

@(private)
tabs_ctx_push :: proc(ctx: Tabs_Ctx) -> bool {
	if tabs_ctx_depth >= TABS_MAX {
		if !tabs_stack_warned {
			tabs_stack_warned = true
			o.Log_Warn("tabs context stack overflow")
		}

		return false
	}

	tabs_ctx_stack[tabs_ctx_depth] = ctx
	tabs_ctx_depth += 1

	return true
}

@(private)
tabs_ctx_pop :: proc() {
	if tabs_ctx_depth <= 0 {
		return
	}

	tabs_ctx_depth -= 1
	tabs_ctx_stack[tabs_ctx_depth] = {}
}

@(private)
tabs_ctx_ok :: proc() -> bool {
	return tabs_ctx_depth > 0
}

@(private)
tabs_ctx_top :: proc() -> ^Tabs_Ctx {
	if tabs_ctx_depth <= 0 {
		return &tabs_ctx_dummy
	}

	return &tabs_ctx_stack[tabs_ctx_depth - 1]
}

/*
Returns the active tabs root value.

`ok` is false outside a `Tabs` root. The string is the caller-owned value
passed to `Tabs` this frame, including a value committed earlier in the same
draw by a previous trigger.
*/
Tabs_Get_Value :: proc() -> (value: string, ok: bool) {
	if !tabs_ctx_ok() {
		return "", false
	}

	return tabs_ctx_top().value, true
}

@(private)
tabs_snapshot_slot :: proc(key: string) -> int {
	if key == "" {
		return -1
	}

	for i in 0 ..< tabs_snapshot_count {
		if tabs_snapshots[i].key == key {
			return i
		}
	}

	return -1
}

@(private)
tabs_snapshot_find :: proc(key: string) -> ^Tabs_Snapshot {
	slot := tabs_snapshot_slot(key)

	if slot < 0 {
		return nil
	}

	return &tabs_snapshots[slot]
}

@(private)
tabs_snapshot_save :: proc(ctx: ^Tabs_Ctx) {
	if ctx.key == "" {
		return
	}

	slot := tabs_snapshot_slot(ctx.key)

	if slot < 0 {
		if tabs_snapshot_count >= TABS_MAX {
			if !tabs_groups_warned {
				tabs_groups_warned = true
				o.Log_Warn("tabs snapshot limit reached")
			}

			return
		}

		slot = tabs_snapshot_count
		tabs_snapshot_count += 1
	}

	tabs_snapshots[slot].key = ctx.key
	tabs_snapshots[slot].triggers = ctx.triggers
	tabs_snapshots[slot].count = ctx.trigger_count
	tabs_snapshots[slot].activate_on_focus = ctx.activate_on_focus
	tabs_snapshots[slot].variant = ctx.variant
}

@(private)
tabs_snapshot_remove :: proc(key: string) {
	slot := tabs_snapshot_slot(key)

	if slot < 0 {
		return
	}

	last := tabs_snapshot_count - 1
	tabs_snapshots[slot] = tabs_snapshots[last]
	tabs_snapshots[last] = {}
	tabs_snapshot_count = last
}

@(private)
tabs_trigger_index :: proc(snap: ^Tabs_Snapshot, element_id: string) -> int {
	if snap == nil || element_id == "" {
		return -1
	}

	for i in 0 ..< snap.count {
		if snap.triggers[i].element_id == element_id {
			return i
		}
	}

	return -1
}

@(private)
tabs_tab_stop_index :: proc(triggers: []Tabs_Trigger_Entry, value: string) -> int {
	fallback := -1

	for item, i in triggers {
		if item.disabled {
			continue
		}

		if value != "" && item.value == value {
			return i
		}

		if fallback < 0 {
			fallback = i
		}
	}

	return fallback
}

@(private)
tabs_tab_order_has :: proc(id: string) -> bool {
	if o.w_ctx == nil || o.w_ctx.tab_order == nil || id == "" {
		return false
	}

	for tab_id in o.w_ctx.tab_order {
		if tab_id == id {
			return true
		}
	}

	return false
}

@(private)
tabs_tab_order_remove :: proc(id: string) {
	if o.w_ctx == nil || o.w_ctx.tab_order == nil || id == "" {
		return
	}

	for i := 0; i < len(o.w_ctx.tab_order); i += 1 {
		if o.w_ctx.tab_order[i] == id {
			ordered_remove(&o.w_ctx.tab_order, i)

			return
		}
	}
}

/*
Keeps exactly one trigger from this root in the tab order: the active enabled
trigger, or the first enabled trigger when nothing is selected.
*/
@(private)
tabs_sync_tab_stop :: proc(ctx: ^Tabs_Ctx) {
	if o.state == nil || o.w_ctx == nil || o.ui_pass() != .Layout {
		return
	}

	wanted := tabs_tab_stop_index(ctx.triggers[:ctx.trigger_count], ctx.value)
	wanted_id := ""

	if wanted >= 0 {
		wanted_id = ctx.triggers[wanted].element_id
	}

	for i in 0 ..< ctx.trigger_count {
		id := ctx.triggers[i].element_id

		if id == "" || id == wanted_id {
			continue
		}

		tabs_tab_order_remove(id)
	}

	if wanted_id != "" && !tabs_tab_order_has(wanted_id) {
		widget_register_tab_order(wanted_id, true, true)
	}
}

@(private)
tabs_apply_auto_focus :: proc(ctx: ^Tabs_Ctx, root_auto: bool) {
	if o.w_ctx == nil {
		return
	}

	idx := tabs_tab_stop_index(ctx.triggers[:ctx.trigger_count], ctx.value)

	if idx < 0 {
		return
	}

	if !root_auto && !ctx.triggers[idx].auto_focus {
		return
	}

	id := ctx.triggers[idx].element_id

	if id == "" || o.w_ctx.auto_focused_id == id {
		return
	}

	widget_apply_auto_focus(id, true)
}

/*
Registers a trigger with the current tabs root. Empty values, duplicates, and
items past the cap are rejected and must not participate in selection.
*/
@(private)
tabs_register_trigger :: proc(entry: Tabs_Trigger_Entry) -> bool {
	if !tabs_ctx_ok() {
		return false
	}

	if entry.value == "" || entry.element_id == "" {
		return false
	}

	ctx := tabs_ctx_top()

	for i in 0 ..< ctx.trigger_count {
		if ctx.triggers[i].value == entry.value {
			return false
		}
	}

	if ctx.trigger_count >= TABS_TRIGGERS_MAX {
		if !tabs_triggers_warned {
			tabs_triggers_warned = true
			o.Log_Warn("tabs trigger limit reached")
		}

		return false
	}

	ctx.triggers[ctx.trigger_count] = entry
	ctx.trigger_count += 1
	tabs_sync_tab_stop(ctx)

	return true
}

@(private)
tabs_first_enabled :: proc(snap: ^Tabs_Snapshot) -> int {
	for i in 0 ..< snap.count {
		if !snap.triggers[i].disabled {
			return i
		}
	}

	return -1
}

@(private)
tabs_last_enabled :: proc(snap: ^Tabs_Snapshot) -> int {
	for i := snap.count - 1; i >= 0; i -= 1 {
		if !snap.triggers[i].disabled {
			return i
		}
	}

	return -1
}

@(private)
tabs_step :: proc(snap: ^Tabs_Snapshot, from: int, delta: int, loop: bool) -> int {
	if snap.count == 0 || delta == 0 {
		return -1
	}

	idx := from

	for _ in 0 ..< snap.count {
		idx += delta

		if idx < 0 || idx >= snap.count {
			if !loop {
				return -1
			}

			if idx < 0 {
				idx = snap.count - 1
			} else {
				idx = 0
			}
		}

		if !snap.triggers[idx].disabled {
			return idx
		}
	}

	return -1
}

@(private)
tabs_key_edge :: proc(code: o.Scancode) -> bool {
	if o.w_ctx == nil || o.shortcut_key_consumed(code) {
		return false
	}

	idx := int(code)

	if idx < 0 || idx >= len(o.w_ctx.keys) {
		return false
	}

	key := o.w_ctx.keys[idx]

	return key.pressed || key.repeat
}

@(private)
tabs_consume :: proc(code: o.Scancode) {
	o.shortcut_consume_key(code)
}

@(private)
tabs_nav_action :: proc(orientation: Tabs_Orientation) -> (action: Tabs_Nav, key: o.Scancode) {
	next_code := o.Scancode.RIGHT
	prev_code := o.Scancode.LEFT

	if orientation == .VERTICAL {
		next_code = .DOWN
		prev_code = .UP
	}

	home := tabs_key_edge(.HOME)
	end := tabs_key_edge(.END)
	next := tabs_key_edge(next_code)
	prev := tabs_key_edge(prev_code)
	count := 0

	if home {
		count += 1
	}

	if end {
		count += 1
	}

	if next {
		count += 1
	}

	if prev {
		count += 1
	}

	if count != 1 {
		if count > 1 {
			if home {
				tabs_consume(.HOME)
			}

			if end {
				tabs_consume(.END)
			}

			if next {
				tabs_consume(next_code)
			}

			if prev {
				tabs_consume(prev_code)
			}
		}

		return .NONE, {}
	}

	if home {
		return .FIRST, .HOME
	}

	if end {
		return .LAST, .END
	}

	if next {
		return .NEXT, next_code
	}

	return .PREV, prev_code
}

@(private)
tabs_commit_move :: proc(
	ctx: ^Tabs_Ctx,
	snap: ^Tabs_Snapshot,
	to: int,
	source_id: string,
	activate: bool,
) -> bool {
	if to < 0 || to >= snap.count {
		return false
	}

	dest := snap.triggers[to]

	if dest.disabled || dest.value == "" || dest.element_id == "" {
		return false
	}

	depth := tabs_ctx_depth
	group_key := ctx.key
	next_value := dest.value

	if activate && next_value != ctx.value && ctx.on_value_change != nil {
		ctx.on_value_change(next_value)
	}

	if tabs_ctx_depth != depth || !tabs_ctx_ok() {
		return true
	}

	live := tabs_ctx_top()

	if live.key != group_key {
		return true
	}

	if activate {
		live.value = next_value
	}

	o.widget_set_focused_id(dest.element_id)
	tabs_arrow_group = group_key
	tabs_arrow_target = dest.element_id
	tabs_arrow_handled = false
	tabs_arrow_blur = source_id
	tabs_arrow_blur_group = group_key

	return true
}

/*
Arrow, Home, and End navigation for the focused trigger.

Returns true when focus left this trigger. Navigation keys are consumed so
parent widgets do not see them. The cross-axis arrows are left alone.
When `activate_on_focus` is set, moving focus also reports a new value.
*/
@(private)
tabs_handle_keyboard :: proc(element_id: string) -> bool {
	if !tabs_ctx_ok() || element_id == "" {
		return false
	}

	ctx := tabs_ctx_top()

	if ctx.disabled {
		return false
	}

	snap := tabs_snapshot_find(ctx.key)

	if snap == nil || snap.count == 0 {
		return false
	}

	from := tabs_trigger_index(snap, element_id)

	if from < 0 || snap.triggers[from].disabled {
		return false
	}

	action, key := tabs_nav_action(ctx.orientation)

	if action == .NONE {
		return false
	}

	tabs_consume(key)
	to := -1

	switch action {
	case .NONE:
		return false
	case .NEXT:
		to = tabs_step(snap, from, 1, ctx.loop)
	case .PREV:
		to = tabs_step(snap, from, -1, ctx.loop)
	case .FIRST:
		to = tabs_first_enabled(snap)
	case .LAST:
		to = tabs_last_enabled(snap)
	}

	if to < 0 || to == from {
		return false
	}

	return tabs_commit_move(ctx, snap, to, snap.triggers[from].element_id, ctx.activate_on_focus)
}

@(private)
tabs_claim_arrow_focus :: proc(element_id, group_key: string) -> bool {
	if tabs_arrow_target == "" || element_id == "" || tabs_arrow_target != element_id {
		return false
	}

	if tabs_arrow_group != group_key {
		return false
	}

	tabs_arrow_target = ""
	tabs_arrow_handled = true

	return true
}

@(private)
tabs_take_arrow_blur :: proc(element_id, group_key: string) -> bool {
	if tabs_arrow_blur == "" || element_id == "" || element_id != tabs_arrow_blur {
		return false
	}

	if tabs_arrow_blur_group != group_key {
		return false
	}

	tabs_arrow_blur = ""
	tabs_arrow_blur_group = ""

	return true
}

@(private)
tabs_note_drawn :: proc(element_id: string, state: Tabs_Trigger_State) {
	if element_id == "" {
		return
	}

	for i in 0 ..< tabs_drawn_count {
		if tabs_drawn[i].element_id == element_id {
			tabs_drawn[i].state = state

			return
		}
	}

	if tabs_drawn_count >= TABS_DRAWN_MAX {
		return
	}

	tabs_drawn[tabs_drawn_count] = {
		element_id = element_id,
		state      = state,
	}
	tabs_drawn_count += 1
}

@(private)
tabs_drawn_find :: proc(element_id: string) -> (state: Tabs_Trigger_State, ok: bool) {
	if element_id == "" {
		return {}, false
	}

	for i in 0 ..< tabs_drawn_count {
		if tabs_drawn[i].element_id == element_id {
			return tabs_drawn[i].state, true
		}
	}

	return {}, false
}

/*
Fires `on_focus` for an arrow-key target that already finished drawing this
frame (moving backward). Forward targets claim focus themselves with a full event.
*/
@(private)
tabs_flush_arrow_focus :: proc(group_key: string) {
	if tabs_arrow_handled || tabs_arrow_target == "" || tabs_arrow_group != group_key {
		return
	}

	tabs_arrow_handled = true
	target := tabs_arrow_target
	tabs_arrow_target = ""
	snap := tabs_snapshot_find(group_key)

	if snap == nil {
		return
	}

	idx := tabs_trigger_index(snap, target)

	if idx < 0 || snap.triggers[idx].on_focus == nil {
		return
	}

	state := Tabs_Trigger_State {
		is_focused  = true,
		is_disabled = snap.triggers[idx].disabled,
		value       = snap.triggers[idx].value,
		active      = true,
	}

	if drawn, found := tabs_drawn_find(target); found {
		state = drawn
		state.is_focused = true
	}

	snap.triggers[idx].on_focus({frame_state = state})
}

@(private)
tabs_lookup_registered :: proc(group_key, element_id: string) -> bool {
	snap := tabs_snapshot_find(group_key)

	return tabs_trigger_index(snap, element_id) >= 0
}

/*
Applies list policy captured during layout so draw-pass keyboard navigation
sees `activate_on_focus` / variant before `Tabs_List` runs again.
*/
@(private)
tabs_ctx_apply_snapshot_policy :: proc(ctx: ^Tabs_Ctx) {
	snap := tabs_snapshot_find(ctx.key)

	if snap == nil {
		return
	}

	ctx.activate_on_focus = snap.activate_on_focus
	ctx.variant = snap.variant
}

@(private)
tabs_active_now :: proc(value: string, registered: bool) -> bool {
	if !registered || !tabs_ctx_ok() || value == "" {
		return false
	}

	current := tabs_ctx_top().value

	return current != "" && current == value
}
