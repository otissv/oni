package oni_widgets

import o ".."
import set "../set"
import "core:strings"

/*
Horizontal alignment of context menu content relative to the anchor point.
*/
Context_Menu_Align :: o.Layout_Popup_Align

@(private)
CONTEXT_MENU_CTX_STACK_MAX :: 16

@(private)
CONTEXT_MENU_DEFAULT_GAP_PX :: f32(0)

@(private)
CONTEXT_MENU_DEFAULT_VIEWPORT_MARGIN_PX :: f32(8)

/*
Live compound context pushed by `Context_Menu` for Trigger / Content parts.
*/
@(private)
Context_Menu_Ctx :: struct {
	menu_key:             string,
	open:                 bool,
	disabled:             bool,
	on_open_change:       proc(open: bool),
	trigger_key:          string,
	trigger_layout_id:    o.UI_Id,
	trigger_rect:         o.Rect,
	has_trigger:          bool,
	anchor_point:         o.Vec2,
	has_anchor_point:     bool,
	pointer_owned:        bool,
	trigger_user_context: proc(event: Context_Menu_Trigger_Event),
	trigger_user_click:   proc(event: Context_Menu_Trigger_Event),
	item_user_click:      proc(event: Context_Menu_Item_Event),
	content_child:        proc(frame_state: Context_Menu_Content_Props_State),
	content_frame:        Context_Menu_Content_Props_State,
}

@(private)
context_menu_ctx_stack: [CONTEXT_MENU_CTX_STACK_MAX]Context_Menu_Ctx

@(private)
context_menu_ctx_depth: int

/*
Cross-frame pointer anchors keyed by menu element key (ctx is rebuilt each frame).
*/
@(private)
context_menu_anchor_points: map[string]o.Vec2

/*
Releases context menu context stack and persisted anchors.

Called from widget `Shutdown`.
*/
context_menu_shutdown :: proc() {
	context_menu_ctx_depth = 0
	context_menu_ctx_stack = {}

	if context_menu_anchor_points != nil {
		for key in context_menu_anchor_points {
			delete(key)
		}

		delete(context_menu_anchor_points)
		context_menu_anchor_points = nil
	}
}

@(private)
context_menu_ctx_push :: proc(ctx: Context_Menu_Ctx) {
	assert(context_menu_ctx_depth < CONTEXT_MENU_CTX_STACK_MAX)
	context_menu_ctx_stack[context_menu_ctx_depth] = ctx
	context_menu_ctx_depth += 1
}

@(private)
context_menu_ctx_pop :: proc() {
	assert(context_menu_ctx_depth > 0)
	context_menu_ctx_depth -= 1
	context_menu_ctx_stack[context_menu_ctx_depth] = {}
}

@(private)
context_menu_ctx_ok :: proc() -> bool {
	return context_menu_ctx_depth > 0
}

@(private)
context_menu_ctx_top :: proc() -> ^Context_Menu_Ctx {
	assert(context_menu_ctx_depth > 0)

	return &context_menu_ctx_stack[context_menu_ctx_depth - 1]
}

/*
Returns whether the active `Context_Menu` root is open.
*/
Context_Menu_Is_Open :: proc() -> bool {
	if !context_menu_ctx_ok() {
		return false
	}

	return context_menu_ctx_top().open
}

/*
Opens or closes the active `Context_Menu` root.
*/
Context_Menu_Set_Open :: proc(open: bool) {
	if !context_menu_ctx_ok() {
		return
	}

	context_menu_set_open(open)
}

@(private)
context_menu_clear_anchor :: proc(menu_key: string) {
	if context_menu_anchor_points == nil || menu_key == "" {
		return
	}

	owned_key: string
	found := false

	for k in context_menu_anchor_points {
		if k == menu_key {
			owned_key = k
			found = true
			break
		}
	}

	if !found {
		return
	}

	delete_key(&context_menu_anchor_points, owned_key)
	delete(owned_key)
}

@(private)
context_menu_store_anchor :: proc(menu_key: string, point: o.Vec2) {
	if menu_key == "" {
		return
	}

	if context_menu_anchor_points == nil {
		context_menu_anchor_points = make(map[string]o.Vec2)
	}

	if _, ok := context_menu_anchor_points[menu_key]; ok {
		context_menu_anchor_points[menu_key] = point

		return
	}

	context_menu_anchor_points[strings.clone(menu_key)] = point
}

@(private)
context_menu_load_anchor :: proc(menu_key: string) -> (point: o.Vec2, ok: bool) {
	if context_menu_anchor_points == nil || menu_key == "" {
		return {}, false
	}

	return context_menu_anchor_points[menu_key]
}

@(private)
context_menu_set_open :: proc(open: bool) {
	ctx := context_menu_ctx_top()

	if ctx.disabled {
		return
	}

	if ctx.open == open {
		return
	}

	ctx.open = open

	if !open {
		ctx.has_anchor_point = false
		context_menu_clear_anchor(ctx.menu_key)
	}

	if ctx.on_open_change != nil {
		ctx.on_open_change(open)
	}
}

@(private)
context_menu_open_at_pointer :: proc() {
	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()

	if ctx.disabled {
		return
	}

	point := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	ctx.anchor_point = point
	ctx.has_anchor_point = true
	context_menu_store_anchor(ctx.menu_key, point)
	context_menu_set_open(true)
}

@(private)
context_menu_restore_anchor_into_ctx :: proc() {
	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()

	if point, ok := context_menu_load_anchor(ctx.menu_key); ok {
		ctx.anchor_point = point
		ctx.has_anchor_point = true
	}
}

@(private)
context_menu_set_trigger :: proc(key: string, layout_id: o.UI_Id, rect: o.Rect) {
	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()
	ctx.trigger_key = key
	ctx.trigger_layout_id = layout_id
	ctx.trigger_rect = rect
	ctx.has_trigger = true
}

@(private)
context_menu_note_pointer :: proc() {
	if !context_menu_ctx_ok() {
		return
	}

	context_menu_ctx_top().pointer_owned = true
}

@(private)
context_menu_handle_dismiss :: proc(root_key: string) {
	if !context_menu_ctx_ok() {
		return
	}

	ctx := context_menu_ctx_top()

	if !ctx.open {
		return
	}

	_ = root_key

	esc := o.w_ctx.keys[int(o.Scancode.ESCAPE)]

	if esc.pressed && !o.shortcut_key_consumed(.ESCAPE) {
		context_menu_set_open(false)
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true
	}

	outside_press :=
		(o.w_ctx.left_mouse.pressed || o.w_ctx.right_mouse.pressed) && !ctx.pointer_owned

	if outside_press {
		context_menu_set_open(false)
	}
}

@(private)
context_menu_content_theme_for_anchor :: proc(point: o.Vec2, gap: f32) -> o.Widget_Config {
	return o.Widget_Config {
		kind = .RECT,
		space = set.Space(.POPOVER),
		position = set.Position(.ABSOLUTE),
		x = set.F32(point.x),
		y = set.F32(point.y + gap),
		height = set.Height(o.Height_Mode.FIT),
		direction = set.Direction(.VERTICAL),
		padding = set.Padding(f32(4)),
		gap_y = set.Gap_Y(u16(2)),
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(1),
		border_color = set.Border_color(o.Color.BORDER),
		z_index = set.Z_Index(f32(50)),
		min_w = set.Min_W(f32(128)),
	}
}
