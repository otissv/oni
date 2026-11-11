#+test
package oni

import "core:testing"

@(test)
popup_side_anchors_flip_and_stay_inside_viewport :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		defer delete(layout.popup_anchors)
		state.dpi.logical_w = 300
		state.dpi.logical_h = 200
		anchor := layout_test_append_node(layout, -1, .RECT, {}, {40, 20})
		panel := layout_test_append_node(layout, -1, .RECT, {}, {100, 80})
		layout.nodes[anchor].rect = {250, 170, 40, 20}
		layout.nodes[panel].rect = {0, 0, 100, 80}
		layout.nodes[anchor].ui_id = 1
		layout.nodes[panel].ui_id = 2
		layout.id_to_node[1] = anchor
		layout.id_to_node[2] = panel
		append(&layout.popup_anchors, {anchor_id = 1, floating_id = 2, side = .RIGHT, gap = 4, margin = 8})
		layout_resolve_anchors()
		rect := layout.nodes[panel].rect
		testing.expect(t, rect.x + rect.w <= layout.nodes[anchor].rect.x)
		testing.expect(t, rect.x >= 8 && rect.y >= 8)
		testing.expect(t, rect.x + rect.w <= 292 && rect.y + rect.h <= 192)
	})
}

@(test)
popup_oversized_panel_is_clamped_without_inverted_bounds :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		defer delete(layout.popup_anchors)
		state.dpi.logical_w = 120
		state.dpi.logical_h = 100
		anchor := layout_test_append_node(layout, -1, .RECT, {}, {30, 20})
		panel := layout_test_append_node(layout, -1, .RECT, {}, {600, 400})
		layout.nodes[anchor].rect = {10, 10, 30, 20}
		layout.nodes[panel].rect = {0, 0, 600, 400}
		layout.nodes[anchor].ui_id = 1
		layout.nodes[panel].ui_id = 2
		layout.id_to_node[1] = anchor
		layout.id_to_node[2] = panel
		append(&layout.popup_anchors, {anchor_id = 1, floating_id = 2, margin = 8})
		layout_resolve_anchors()
		rect := layout.nodes[panel].rect
		testing.expect(t, rect.x >= 8 && rect.y >= 8)
		testing.expect(t, rect.x + rect.w <= 112 && rect.y + rect.h <= 92)
	})
}
