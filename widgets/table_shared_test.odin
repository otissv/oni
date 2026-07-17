package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
table_shared_build_heading_row :: proc(frame_state: Table_Row_State) {
	_ = frame_state
	Table_Heading(
		{config = {id = "th1", width = set.Width(f32(100)), height = set.Height(f32(30))}},
	)
	Table_Heading(
		{config = {id = "th2", width = set.Width(f32(100)), height = set.Height(f32(30))}},
	)
}

@(private)
table_shared_build_head :: proc(frame_state: Table_Head_State) {
	_ = frame_state
	Table_Row({config = {id = "hrow"}, child = table_shared_build_heading_row})
}

@(private)
table_shared_build_body_row :: proc(frame_state: Table_Row_State) {
	_ = frame_state
	Table_Cell({config = {id = "td1", width = set.Width(f32(100)), height = set.Height(f32(24))}})
	Table_Cell({config = {id = "td2", width = set.Width(f32(100)), height = set.Height(f32(24))}})
}

@(private)
table_shared_build_body :: proc(frame_state: Table_Body_State) {
	_ = frame_state
	Table_Row({config = {id = "brow"}, child = table_shared_build_body_row})
}

@(private)
table_shared_build_table :: proc(frame_state: Table_State) {
	_ = frame_state
	Table_Caption({config = {id = "cap"}})
	Table_Head({config = {id = "head"}, child = table_shared_build_head})
	Table_Body({config = {id = "body"}, child = table_shared_build_body})
	Table_Foot({config = {id = "foot"}})
}

@(private)
find_child_kind :: proc(layout: ^o.Layout_State, parent: int, kind: o.Widget_Kind) -> (int, bool) {
	if parent < 0 || parent >= len(layout.nodes) do return -1, false
	for child_index in layout.nodes[parent].child_indices {
		if layout.nodes[child_index].kind == kind do return child_index, true
	}
	return -1, false
}

@(test)
table_nested_layout_builds_full_structure :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Table({config = {id = "tbl", width = set.Width(f32(300)), height = set.Height(f32(200))}, child = table_shared_build_table})
		widget_test_finish_layout()

		expect_layout_kind(t, "tbl", .TABLE)
		expect_registered_id(t, "cap")
		expect_registered_id(t, "head")
		expect_registered_id(t, "th1")
		expect_registered_id(t, "td1")
		expect_registered_id(t, "foot")

		layout := &o.state.ui.layout
		table, table_ok := widget_test_layout_node("tbl")
		testing.expect(t, table_ok)
		if !table_ok do return

		table_index := -1
		for &node, i in layout.nodes {
			if &node == table {
				table_index = i
				break
			}
		}
		testing.expect(t, table_index >= 0)
		testing.expect(t, len(table.child_indices) >= 4)

		cap, cap_ok := find_child_kind(layout, table_index, .TABLE_CAPTION)
		head, head_ok := find_child_kind(layout, table_index, .TABLE_HEAD)
		body, body_ok := find_child_kind(layout, table_index, .TABLE_BODY)
		foot, foot_ok := find_child_kind(layout, table_index, .TABLE_FOOT)
		testing.expect(t, cap_ok && head_ok && body_ok && foot_ok)

		hrow, hrow_ok := find_child_kind(layout, head, .TABLE_ROW)
		testing.expect(t, hrow_ok)
		th1, th1_ok := find_child_kind(layout, hrow, .TABLE_HEADING)
		testing.expect(t, th1_ok)
		testing.expect(t, layout.nodes[th1].kind == .TABLE_HEADING)

		brow, brow_ok := find_child_kind(layout, body, .TABLE_ROW)
		testing.expect(t, brow_ok)
		td1, td1_ok := find_child_kind(layout, brow, .TABLE_CELL)
		testing.expect(t, td1_ok)
		testing.expect(t, layout.nodes[td1].kind == .TABLE_CELL)
		_ = cap
		_ = foot
	})
}
