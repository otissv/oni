package oni_widgets

import o ".."
import set "../set"
import "core:sync"
import "core:testing"

@(private)
widget_test_guard: sync.Mutex

@(private)
expect_close :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expectf(t, abs(got - want) < 1e-4, "got=%v want=%v", got, want, loc = loc)
}

@(private)
drain_style_stack :: proc() {
	for len(o.state.ui.style_stack) > 0 {
		o.ui_pop_style()
	}
}

/*
Runs body with a bound engine state, theme, and UI maps ready for widget layout/draw.
*/
@(private)
with_widget_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&widget_test_guard)
	defer sync.mutex_unlock(&widget_test_guard)

	test_state: o.State
	test_theme := o.Theme {
		palette      = o.palette,
		border       = 0,
		border_color = .BLACK,
		background   = .TRANSPARENT,
		gap_x        = u16(0),
		gap_y        = u16(0),
		color        = .FOREGROUND,
		direction    = o.Direction_Layout.VERTICAL,
	}

	saved_state := o.state
	saved_theme := o.theme
	saved_w_ctx := o.w_ctx
	defer {
		o.state = saved_state
		o.theme = saved_theme
		o.w_ctx = saved_w_ctx
	}

	o.state = &test_state
	o.theme = &test_theme
	o.w_ctx = &o.state.widget
	o.state.widget = {}
	o.state.dpi = {
		logical_w = 800,
		logical_h = 600,
		scale     = 1,
	}
	o.state.view = o.view_default()
	// Allow draw_rect batching without a GPU device.
	o.batch_current().vertex_capacity = 64 * 1024
	o.batch_current().index_capacity = 64 * 1024 * 6

	o.ui_init()
	defer {
		drain_style_stack()
		o.ui_shutdown()
		o.batch_delete_cpu_arrays(&o.state.gpu_state)
	}

	// Root style required by resolve_widget_config / theme merges.
	o.ui_push_style(o.style_root(.SCREEN, {0, 0, 800, 600}))

	body(t)
}

@(private)
widget_test_begin_layout :: proc() {
	o.ui_begin_frame()
	// ui_begin_frame clears style stack; restore the root context.
	o.ui_push_style(o.style_root(.SCREEN, {0, 0, 800, 600}))
	o.layout_begin_space(.SCREEN)
}

@(private)
widget_test_finish_layout :: proc() {
	o.layout_end_space()
}

@(private)
widget_test_begin_draw :: proc() {
	o.ui_end_layout_pass()
}

@(private)
widget_test_end_frame :: proc() {
	o.ui_end_frame()
	o.batch_delete_cpu_arrays(&o.state.gpu_state)
	o.batch_current().has_current_key = false
}

@(private)
widget_test_layout_node :: proc(id: string) -> (^o.Layout_Node, bool) {
	layout_id := o.ui_id(id)
	idx, ok := o.state.ui.layout.id_to_node[layout_id]
	if !ok do return nil, false
	return &o.state.ui.layout.nodes[idx], true
}

@(private)
expect_layout_kind :: proc(
	t: ^testing.T,
	id: string,
	kind: o.Widget_Kind,
	loc := #caller_location,
) {
	node, ok := widget_test_layout_node(id)
	testing.expectf(t, ok, "missing layout node for id=%v", id, loc = loc)
	if !ok do return
	testing.expectf(t, node.kind == kind, "id=%v kind=%v want=%v", id, node.kind, kind, loc = loc)
}

@(private)
expect_registered_id :: proc(t: ^testing.T, id: string, loc := #caller_location) {
	_, ok := GetElementById(id)
	testing.expectf(t, ok, "id %v not registered", id, loc = loc)
}

@(private)
expect_in_tab_order :: proc(t: ^testing.T, id: string, want: bool, loc := #caller_location) {
	key, ok := GetElementById(id)
	testing.expect(t, ok, loc = loc)
	if !ok do return

	found := false
	for tab_id in o.w_ctx.tab_order {
		if tab_id == key {
			found = true
			break
		}
	}
	testing.expectf(t, found == want, "id=%v in_tab_order=%v want=%v", id, found, want, loc = loc)
}

@(private)
len_fixed :: proc(v: f32) -> o.Length {
	return {kind = .FIXED, value = v}
}

@(private)
set_bool :: proc(v: bool) -> o.Cfg(o.Style_Bool) {
	return set.Bool(v)
}

/*
Finds a root layout node and one of its direct children by parent links.

Used when scoped `ui_id` lookups cannot resolve nested widget nodes after layout.
*/
@(private)
widget_test_find_parent_child_nodes :: proc(
) -> (
	parent: ^o.Layout_Node,
	child: ^o.Layout_Node,
	ok: bool,
) {
	nodes := o.state.ui.layout.nodes[:]
	parent_i := -1
	for i in 0 ..< len(nodes) {
		if nodes[i].parent < 0 {
			parent_i = i
			break
		}
	}
	if parent_i < 0 do return nil, nil, false

	for i in 0 ..< len(nodes) {
		if nodes[i].parent == parent_i {
			return &nodes[parent_i], &nodes[i], true
		}
	}
	return &nodes[parent_i], nil, false
}
