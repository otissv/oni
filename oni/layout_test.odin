package oni

import "core:testing"

expect_close :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expectf(
		t,
		abs(got - want) < 1e-4,
		"got=%v want=%v",
		got,
		want,
		loc = loc,
	)
}

@(test)
justify_align_is_content_detects_max_and_min :: proc(t: ^testing.T) {
	testing.expect(t, justify_align_is_content(.MAX_CONTENT))
	testing.expect(t, justify_align_is_content(.MIN_CONTENT))
	testing.expect(t, !justify_align_is_content(.START))
	testing.expect(t, !justify_align_is_content(.STRETCH))
}

@(test)
justify_align_position_offset_content_align_starts_at_zero :: proc(t: ^testing.T) {
	expect_close(t, justify_align_position_offset(100, 40, .MAX_CONTENT), 0)
	expect_close(t, justify_align_position_offset(100, 40, .MIN_CONTENT), 0)
}

@(test)
layout_content_align_target_returns_extrema :: proc(t: ^testing.T) {
	target, ok := layout_content_align_target(.MAX_CONTENT, 120, 30)
	testing.expect(t, ok)
	expect_close(t, target, 120)

	target, ok = layout_content_align_target(.MIN_CONTENT, 120, 30)
	testing.expect(t, ok)
	expect_close(t, target, 30)

	_, ok = layout_content_align_target(.START, 120, 30)
	testing.expect(t, !ok)
}

@(test)
layout_sibling_axis_extrema_finds_bounds :: proc(t: ^testing.T) {
	max_v, min_v, ok := layout_sibling_axis_extrema([]f32{50, 120, 80})
	testing.expect(t, ok)
	expect_close(t, max_v, 120)
	expect_close(t, min_v, 50)

	_, _, ok = layout_sibling_axis_extrema([]f32{})
	testing.expect(t, !ok)
}

@(test)
layout_apply_content_align_axis_uses_align_mode :: proc(t: ^testing.T) {
	expect_close(t, layout_apply_content_align_axis(.MAX_CONTENT, 50, 120, 30), 120)
	expect_close(t, layout_apply_content_align_axis(.MIN_CONTENT, 50, 120, 30), 30)
	expect_close(t, layout_apply_content_align_axis(.START, 50, 120, 30), 50)
}

@(test)
layout_apply_content_align_sizes_indices_max_width :: proc(t: ^testing.T) {
	children: [4]Layout_Node
	child_ptrs: [4]^Layout_Node
	for i in 0 ..< 4 {
		child_ptrs[i] = &children[i]
	}

	child_sizes := [4]Vec2{{50, 20}, {100, 20}, {75, 20}, {80, 20}}
	children[3].config.width = {kind = .FIXED, value = 80}

	justify := Justify_Pos{x = .MAX_CONTENT, y = .START}
	indices := []int{0, 1, 2, 3}
	layout_apply_content_align_sizes_indices(justify, child_ptrs[:], child_sizes[:], indices)

	expect_close(t, child_sizes[0].x, 100)
	expect_close(t, child_sizes[1].x, 100)
	expect_close(t, child_sizes[2].x, 100)
	expect_close(t, child_sizes[3].x, 80)
}

@(test)
layout_apply_content_align_sizes_indices_min_height :: proc(t: ^testing.T) {
	children: [3]Layout_Node
	child_ptrs: [3]^Layout_Node
	for i in 0 ..< 3 {
		child_ptrs[i] = &children[i]
	}

	child_sizes := [3]Vec2{{40, 80}, {40, 40}, {40, 60}}
	children[1].config.height = {kind = .FIXED, value = 40}

	justify := Justify_Pos{x = .START, y = .MIN_CONTENT}
	indices := []int{0, 1, 2}
	layout_apply_content_align_sizes_indices(justify, child_ptrs[:], child_sizes[:], indices)

	expect_close(t, child_sizes[0].y, 40)
	expect_close(t, child_sizes[1].y, 40)
	expect_close(t, child_sizes[2].y, 40)
}

@(test)
layout_apply_content_align_sizes_applies_to_all_children :: proc(t: ^testing.T) {
	children: [2]Layout_Node
	child_ptrs: [2]^Layout_Node
	for i in 0 ..< 2 {
		child_ptrs[i] = &children[i]
	}

	child_sizes := [2]Vec2{{60, 30}, {90, 30}}
	justify := Justify_Pos{x = .MAX_CONTENT, y = .START}
	layout_apply_content_align_sizes(justify, child_ptrs[:], child_sizes[:])

	expect_close(t, child_sizes[0].x, 90)
	expect_close(t, child_sizes[1].x, 90)
}
