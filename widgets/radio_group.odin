package oni_widgets

import o ".."
import set "../set"

/*
Arrow-key wrapping for a radio group.

`.ON` is the zero value: focus wraps from the last
enabled item to the first. `.OFF` stops at the ends.
*/
Radio_Loop :: enum {
	ON,
	OFF,
}

/*
Layout axis and arrow keys for a radio group.

`.VERTICAL` is the zero value: column layout, Up/Down change the selection.
`.HORIZONTAL`: row layout, Left/Right change the selection. Home and End jump
to the first and last enabled items on either axis.
*/
Radio_Orientation :: enum {
	VERTICAL,
	HORIZONTAL,
}

/*
Radio group configuration.
*/
Radio_Group_Config :: struct {
	using _:     o.Widget_Config,
	value:       string,
	name:        string,
	required:    bool,
	loop:        Radio_Loop,
	orientation: Radio_Orientation,
}

/*
Radio group per-frame state.

`value` is the caller-owned selection. `loop` is true when arrow keys wrap.
*/
Radio_Group_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	name:              string,
	required:          bool,
	loop:              bool,
	orientation:       Radio_Orientation,
}

/*
Radio group event snapshot.
*/
Radio_Group_Event :: o.Widget_Event(Radio_Group_State)

/*
Radio group props.

`value` is owned by the caller and must be passed every frame. Choosing an item
reports the next value through `on_value_change` only — the widget never writes
caller state. An empty `value` means nothing is selected. `loop` defaults to
wrapping. `name` and `required` are exposed on state for form owners; this
widget does not submit a form.
*/
Radio_Group_Props :: struct {
	config:                       Radio_Group_Config,
	on_value_change:              proc(value: string),
	child:                        proc(frame_state: Radio_Group_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Radio_Group_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Radio_Group_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Radio_Group_Event),
	on_blur:                      proc(event: Radio_Group_Event),
	on_mouse_enter:               proc(event: Radio_Group_Event),
	on_mouse_leave:               proc(event: Radio_Group_Event),
	on_mouse_pressed:             proc(event: Radio_Group_Event),
	on_mouse_down:                proc(event: Radio_Group_Event),
	on_mouse_released:            proc(event: Radio_Group_Event),
	on_mouse_move:                proc(event: Radio_Group_Event),
	on_click:                     proc(event: Radio_Group_Event),
	on_contextmenu:               proc(event: Radio_Group_Event),
	on_key_pressed:               proc(event: Radio_Group_Event),
	on_key_down:                  proc(event: Radio_Group_Event),
	on_key_released:              proc(event: Radio_Group_Event),
}

@(private)
RADIO_GROUP_MAX :: 8

@(private)
RADIO_ITEMS_MAX :: 128

@(private)
RADIO_DRAWN_MAX :: 256

@(private)
RADIO_GROUP_GAP :: u16(12)

/*
One radio registered with the enclosing group during layout.

`disabled` items stay in the set so they keep a stable index, and arrow keys
skip them. `on_focus` runs when arrow keys move onto this item.
*/
@(private)
Radio_Item_Entry :: struct {
	value:      string,
	element_id: string,
	disabled:   bool,
	auto_focus: bool,
	on_focus:   proc(event: Radio_Event),
}

@(private)
Radio_Ctx :: struct {
	key:             string,
	value:           string,
	name:            string,
	required:        bool,
	disabled:        bool,
	loop:            bool,
	orientation:     Radio_Orientation,
	on_value_change: proc(value: string),
	items:           [RADIO_ITEMS_MAX]Radio_Item_Entry,
	item_count:      int,
}

@(private)
Radio_Snapshot :: struct {
	key:   string,
	items: [RADIO_ITEMS_MAX]Radio_Item_Entry,
	count: int,
}

@(private)
Radio_Drawn :: struct {
	element_id: string,
	state:      Radio_State,
}

@(private)
Radio_Nav :: enum {
	NONE,
	NEXT,
	PREV,
	FIRST,
	LAST,
}

@(private)
radio_ctx_stack: [RADIO_GROUP_MAX]Radio_Ctx

@(private)
radio_ctx_depth: int

@(private)
radio_ctx_dummy: Radio_Ctx

@(private)
radio_snapshots: [RADIO_GROUP_MAX]Radio_Snapshot

@(private)
radio_snapshot_count: int

@(private)
radio_snapshot_frame: u64

@(private)
radio_drawn: [RADIO_DRAWN_MAX]Radio_Drawn

@(private)
radio_drawn_count: int

@(private)
radio_arrow_group: string

@(private)
radio_arrow_target: string

@(private)
radio_arrow_handled: bool

@(private)
radio_arrow_blur: string

@(private)
radio_arrow_blur_group: string

@(private)
radio_items_warned: bool

@(private)
radio_groups_warned: bool

@(private)
radio_stack_warned: bool

/*
Releases radio-group frame tables.

Item strings are caller-owned and are not freed. Called from widget `Shutdown`
and from tests so a later frame cannot observe a stale group.
*/
radio_shutdown :: proc() {
	radio_ctx_depth = 0
	radio_ctx_stack = {}
	radio_ctx_dummy = {}
	radio_snapshot_count = 0
	radio_snapshot_frame = 0
	radio_snapshots = {}
	radio_drawn_count = 0
	radio_drawn = {}
	radio_arrow_group = ""
	radio_arrow_target = ""
	radio_arrow_handled = false
	radio_arrow_blur = ""
	radio_arrow_blur_group = ""
	radio_items_warned = false
	radio_groups_warned = false
	radio_stack_warned = false
	radio_action = {}
}

@(private)
radio_snapshots_begin_frame :: proc() {
	if o.state == nil {
		return
	}

	frame := o.state.ui.frame

	if radio_snapshot_frame == frame {
		return
	}

	radio_snapshot_count = 0
	radio_snapshot_frame = frame
	radio_drawn_count = 0
	radio_arrow_group = ""
	radio_arrow_target = ""
	radio_arrow_handled = false
	radio_arrow_blur = ""
	radio_arrow_blur_group = ""
}

@(private)
radio_loop_enabled :: proc(loop: Radio_Loop) -> bool {
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
radio_orientation_normalize :: proc(orientation: Radio_Orientation) -> Radio_Orientation {
	switch orientation {
	case .HORIZONTAL:
		return .HORIZONTAL
	case .VERTICAL:
		return .VERTICAL
	case:
		return .VERTICAL
	}
}

@(private)
radio_ctx_push :: proc(ctx: Radio_Ctx) -> bool {
	if radio_ctx_depth >= RADIO_GROUP_MAX {
		if !radio_stack_warned {
			radio_stack_warned = true
			o.Log_Warn("radio group context stack overflow")
		}

		return false
	}

	radio_ctx_stack[radio_ctx_depth] = ctx
	radio_ctx_depth += 1

	return true
}

@(private)
radio_ctx_pop :: proc() {
	if radio_ctx_depth <= 0 {
		return
	}

	radio_ctx_depth -= 1
	radio_ctx_stack[radio_ctx_depth] = {}
}

@(private)
radio_ctx_ok :: proc() -> bool {
	return radio_ctx_depth > 0
}

@(private)
radio_ctx_top :: proc() -> ^Radio_Ctx {
	if radio_ctx_depth <= 0 {
		return &radio_ctx_dummy
	}

	return &radio_ctx_stack[radio_ctx_depth - 1]
}

/*
Returns the active radio group's value.

`ok` is false outside a group. The string is the caller-owned value passed to
`Radio_Group` this frame, including a value committed earlier in the same draw
by a previous item.
*/
Radio_Group_Get_Value :: proc() -> (value: string, ok: bool) {
	if !radio_ctx_ok() {
		return "", false
	}

	return radio_ctx_top().value, true
}

@(private)
radio_snapshot_slot :: proc(key: string) -> int {
	if key == "" {
		return -1
	}

	for i in 0 ..< radio_snapshot_count {
		if radio_snapshots[i].key == key {
			return i
		}
	}

	return -1
}

@(private)
radio_snapshot_find :: proc(key: string) -> ^Radio_Snapshot {
	slot := radio_snapshot_slot(key)

	if slot < 0 {
		return nil
	}

	return &radio_snapshots[slot]
}

@(private)
radio_snapshot_save :: proc(ctx: ^Radio_Ctx) {
	if ctx.key == "" {
		return
	}

	slot := radio_snapshot_slot(ctx.key)

	if slot < 0 {
		if radio_snapshot_count >= RADIO_GROUP_MAX {
			if !radio_groups_warned {
				radio_groups_warned = true
				o.Log_Warn("radio group snapshot limit reached")
			}

			return
		}

		slot = radio_snapshot_count
		radio_snapshot_count += 1
	}

	radio_snapshots[slot].key = ctx.key
	radio_snapshots[slot].items = ctx.items
	radio_snapshots[slot].count = ctx.item_count
}

@(private)
radio_snapshot_remove :: proc(key: string) {
	slot := radio_snapshot_slot(key)

	if slot < 0 {
		return
	}

	last := radio_snapshot_count - 1
	radio_snapshots[slot] = radio_snapshots[last]
	radio_snapshots[last] = {}
	radio_snapshot_count = last
}

@(private)
radio_item_index :: proc(snap: ^Radio_Snapshot, element_id: string) -> int {
	if snap == nil || element_id == "" {
		return -1
	}

	for i in 0 ..< snap.count {
		if snap.items[i].element_id == element_id {
			return i
		}
	}

	return -1
}

@(private)
radio_tab_stop_index :: proc(items: []Radio_Item_Entry, value: string) -> int {
	fallback := -1

	for item, i in items {
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
radio_tab_order_has :: proc(id: string) -> bool {
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
radio_tab_order_remove :: proc(id: string) {
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
Keeps exactly one item from this group in the tab order: the checked enabled
item, or the first enabled item when nothing is selected.

Called as each item registers so the tab stop lands at that item's position.
A later checked item replaces an earlier provisional stop.
*/
@(private)
radio_sync_tab_stop :: proc(ctx: ^Radio_Ctx) {
	if o.state == nil || o.w_ctx == nil || o.ui_pass() != .Layout {
		return
	}

	wanted := radio_tab_stop_index(ctx.items[:ctx.item_count], ctx.value)
	wanted_id := ""

	if wanted >= 0 {
		wanted_id = ctx.items[wanted].element_id
	}

	for i in 0 ..< ctx.item_count {
		id := ctx.items[i].element_id

		if id == "" || id == wanted_id {
			continue
		}

		radio_tab_order_remove(id)
	}

	if wanted_id != "" && !radio_tab_order_has(wanted_id) {
		widget_register_tab_order(wanted_id, true, true)
	}
}

@(private)
radio_apply_auto_focus :: proc(ctx: ^Radio_Ctx, group_auto: bool) {
	if o.w_ctx == nil {
		return
	}

	idx := radio_tab_stop_index(ctx.items[:ctx.item_count], ctx.value)

	if idx < 0 {
		return
	}

	if !group_auto && !ctx.items[idx].auto_focus {
		return
	}

	id := ctx.items[idx].element_id

	if id == "" || o.w_ctx.auto_focused_id == id {
		return
	}

	widget_apply_auto_focus(id, true)
}

/*
Registers a radio with the current group. Empty values, duplicates, and items
past the cap are rejected and must not participate in selection.
*/
@(private)
radio_register_item :: proc(entry: Radio_Item_Entry) -> bool {
	if !radio_ctx_ok() {
		return false
	}

	if entry.value == "" || entry.element_id == "" {
		return false
	}

	ctx := radio_ctx_top()

	for i in 0 ..< ctx.item_count {
		if ctx.items[i].value == entry.value {
			return false
		}
	}

	if ctx.item_count >= RADIO_ITEMS_MAX {
		if !radio_items_warned {
			radio_items_warned = true
			o.Log_Warn("radio group item limit reached")
		}

		return false
	}

	ctx.items[ctx.item_count] = entry
	ctx.item_count += 1
	radio_sync_tab_stop(ctx)

	return true
}

@(private)
radio_first_enabled :: proc(snap: ^Radio_Snapshot) -> int {
	for i in 0 ..< snap.count {
		if !snap.items[i].disabled {
			return i
		}
	}

	return -1
}

@(private)
radio_last_enabled :: proc(snap: ^Radio_Snapshot) -> int {
	for i := snap.count - 1; i >= 0; i -= 1 {
		if !snap.items[i].disabled {
			return i
		}
	}

	return -1
}

@(private)
radio_step :: proc(snap: ^Radio_Snapshot, from: int, delta: int, loop: bool) -> int {
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

		if !snap.items[idx].disabled {
			return idx
		}
	}

	return -1
}

@(private)
radio_key_edge :: proc(code: o.Scancode) -> bool {
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
radio_consume :: proc(code: o.Scancode) {
	o.shortcut_consume_key(code)
}

@(private)
radio_nav_action :: proc(orientation: Radio_Orientation) -> (action: Radio_Nav, key: o.Scancode) {
	next_code := o.Scancode.DOWN
	prev_code := o.Scancode.UP

	if orientation == .HORIZONTAL {
		next_code = .RIGHT
		prev_code = .LEFT
	}

	home := radio_key_edge(.HOME)
	end := radio_key_edge(.END)
	next := radio_key_edge(next_code)
	prev := radio_key_edge(prev_code)
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
				radio_consume(.HOME)
			}

			if end {
				radio_consume(.END)
			}

			if next {
				radio_consume(next_code)
			}

			if prev {
				radio_consume(prev_code)
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
radio_commit_move :: proc(
	ctx: ^Radio_Ctx,
	snap: ^Radio_Snapshot,
	to: int,
	source_id: string,
) -> bool {
	if to < 0 || to >= snap.count {
		return false
	}

	dest := snap.items[to]

	if dest.disabled || dest.value == "" || dest.element_id == "" {
		return false
	}

	depth := radio_ctx_depth
	group_key := ctx.key
	next_value := dest.value

	if next_value != ctx.value && ctx.on_value_change != nil {
		ctx.on_value_change(next_value)
	}

	if radio_ctx_depth != depth || !radio_ctx_ok() {
		return true
	}

	live := radio_ctx_top()

	if live.key != group_key {
		return true
	}

	live.value = next_value
	o.widget_set_focused_id(dest.element_id)
	radio_arrow_group = group_key
	radio_arrow_target = dest.element_id
	radio_arrow_handled = false
	radio_arrow_blur = source_id
	radio_arrow_blur_group = group_key

	return true
}

/*
Arrow, Home, and End navigation for the focused radio.

Returns true when focus left this item. Navigation keys are consumed so parent
widgets do not see them. The cross-axis arrows are left alone.
*/
@(private)
radio_handle_keyboard :: proc(element_id: string) -> bool {
	if !radio_ctx_ok() || element_id == "" {
		return false
	}

	ctx := radio_ctx_top()

	if ctx.disabled {
		return false
	}

	snap := radio_snapshot_find(ctx.key)

	if snap == nil || snap.count == 0 {
		return false
	}

	from := radio_item_index(snap, element_id)

	if from < 0 || snap.items[from].disabled {
		return false
	}

	action, key := radio_nav_action(ctx.orientation)

	if action == .NONE {
		return false
	}

	radio_consume(key)
	to := -1

	switch action {
	case .NONE:
		return false
	case .NEXT:
		to = radio_step(snap, from, 1, ctx.loop)
	case .PREV:
		to = radio_step(snap, from, -1, ctx.loop)
	case .FIRST:
		to = radio_first_enabled(snap)
	case .LAST:
		to = radio_last_enabled(snap)
	}

	if to < 0 || to == from {
		return false
	}

	return radio_commit_move(ctx, snap, to, snap.items[from].element_id)
}

@(private)
radio_claim_arrow_focus :: proc(element_id, group_key: string) -> bool {
	if radio_arrow_target == "" || element_id == "" || radio_arrow_target != element_id {
		return false
	}

	if radio_arrow_group != group_key {
		return false
	}

	radio_arrow_target = ""
	radio_arrow_handled = true

	return true
}

@(private)
radio_take_arrow_blur :: proc(element_id, group_key: string) -> bool {
	if radio_arrow_blur == "" || element_id == "" || element_id != radio_arrow_blur {
		return false
	}

	if radio_arrow_blur_group != group_key {
		return false
	}

	radio_arrow_blur = ""
	radio_arrow_blur_group = ""

	return true
}

@(private)
radio_note_drawn :: proc(element_id: string, state: Radio_State) {
	if element_id == "" {
		return
	}

	for i in 0 ..< radio_drawn_count {
		if radio_drawn[i].element_id == element_id {
			radio_drawn[i].state = state

			return
		}
	}

	if radio_drawn_count >= RADIO_DRAWN_MAX {
		return
	}

	radio_drawn[radio_drawn_count] = {
		element_id = element_id,
		state      = state,
	}
	radio_drawn_count += 1
}

@(private)
radio_drawn_find :: proc(element_id: string) -> (state: Radio_State, ok: bool) {
	if element_id == "" {
		return {}, false
	}

	for i in 0 ..< radio_drawn_count {
		if radio_drawn[i].element_id == element_id {
			return radio_drawn[i].state, true
		}
	}

	return {}, false
}

/*
Fires `on_focus` for an arrow-key target that already finished drawing this
frame (moving backward). Forward targets claim focus themselves with a full event.
*/
@(private)
radio_flush_arrow_focus :: proc(group_key: string) {
	if radio_arrow_handled || radio_arrow_target == "" || radio_arrow_group != group_key {
		return
	}

	radio_arrow_handled = true
	target := radio_arrow_target
	radio_arrow_target = ""
	snap := radio_snapshot_find(group_key)

	if snap == nil {
		return
	}

	idx := radio_item_index(snap, target)

	if idx < 0 || snap.items[idx].on_focus == nil {
		return
	}

	state := Radio_State {
		is_focused  = true,
		is_disabled = snap.items[idx].disabled,
		value       = snap.items[idx].value,
		checked     = true,
	}

	if drawn, found := radio_drawn_find(target); found {
		state = drawn
		state.is_focused = true
		state.checked = true
	}

	snap.items[idx].on_focus({frame_state = state})
}

@(private)
radio_group_theme_base :: proc(frame_state: ^Radio_Group_State) -> Radio_Group_Config {
	direction := o.Direction_Layout.VERTICAL
	gap_x := u16(0)
	gap_y := RADIO_GROUP_GAP

	if frame_state.orientation == .HORIZONTAL {
		direction = .HORIZONTAL
		gap_x = RADIO_GROUP_GAP
		gap_y = 0
	}

	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	return Radio_Group_Config {
		kind = .RADIO_GROUP,
		tabbable = set.Tabbable(false),
		direction = set.Direction(direction),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		gap_x = set.Gap_X(gap_x),
		gap_y = set.Gap_Y(gap_y),
		opacity = set.F32(opacity),
	}
}

@(private)
radio_group_refresh_merged :: proc(
	props: Radio_Group_Props,
	frame_state: ^Radio_Group_State,
) -> Radio_Group_Event {
	event := widget_event(frame_state^)
	base := radio_group_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

/*
Renders a single-select radio group.

`Radio` items must be descendants of this group. Tab moves to the checked
enabled item, or the first enabled item when `value` matches none. Arrow keys
move focus and report the newly checked value. Space checks the focused item.
Enter does not. Clicking the checked item does not report a new value.
*/
Radio_Group :: proc(props: Radio_Group_Props) {
	radio_snapshots_begin_frame()

	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)
	orientation := radio_orientation_normalize(cfg.orientation)
	loop := radio_loop_enabled(cfg.loop)

	frame_state := Radio_Group_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		value       = cfg.value,
		name        = cfg.name,
		required    = cfg.required,
		loop        = loop,
		orientation = orientation,
	}

	resolved_props := props
	resolved_props.config = cfg
	event := radio_group_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Radio_Group_State)
	should_auto_focus := config.auto_focus
	pushed := radio_ctx_push(
		{
			key = key,
			value = cfg.value,
			name = cfg.name,
			required = cfg.required,
			disabled = disabled,
			loop = loop,
			orientation = orientation,
			on_value_change = props.on_value_change,
		},
	)

	defer {
		if pushed {
			radio_ctx_pop()
		}
	}

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = radio_group_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = config.auto_focus
		}

		if skip_layout {
			if pushed {
				radio_snapshot_remove(key)
			}

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)
		widget_register_tab_order(key, config.tabbable, can_interact)
		widget_children(
			props.child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			frame_state.is_hovered,
		)

		if pushed {
			ctx := radio_ctx_top()
			radio_snapshot_save(ctx)
			radio_sync_tab_stop(ctx)
			radio_apply_auto_focus(ctx, should_auto_focus && can_interact)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)
	widget_handle_interaction(
		resolved_props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = radio_group_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	// Move selection before items paint so an earlier sibling shows the new disc
	// in this frame. The item that lost focus reports blur while it draws.
	if pushed && o.w_ctx != nil {
		radio_handle_keyboard(o.w_ctx.focused_id)
	}

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_children(
		props.child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	if pushed {
		radio_flush_arrow_focus(key)

		if radio_arrow_blur_group == key {
			radio_arrow_blur = ""
			radio_arrow_blur_group = ""
		}
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)
	widget_dispatch_events(resolved_props, &frame_state, handlers, event, key, was_focused)
}
