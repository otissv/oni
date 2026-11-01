#+test
package oni

import "core:testing"

@(test)
vector_scene_clip_requires_rect_or_mesh :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		child := [1]Vector_Node{vector_test_rect({0, 0, 8, 8}, {255, 0, 0, 255})}
		empty := [1]Vector_Node{{kind = .Clip, opacity = 1, children = child[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = empty[:], opacity = 1}), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().draws), 0)
	})
}

@(test)
vector_scene_records_geometric_clip_mesh :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		content := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {255, 0, 0, 255})}
		clip_mesh := vector_test_triangle({0, 32}, {16, 0}, {32, 32})
		nodes := [1]Vector_Node{{kind = .Clip, opacity = 1, mesh = clip_mesh.mesh, children = content[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().draws), 1)
		root := vector_frame().records[vector_frame().draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Clip)
		testing.expect(t, root.geometric)
		testing.expect(t, root.bounds.w > 0 && root.bounds.h > 0)
	})
}

@(test)
vector_scene_rejects_geometric_clip_depth_over_sixty_four :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		leaf := vector_test_rect({0, 0, 4, 4}, {255, 0, 0, 255})
		// 65 geometric clips + leaf content.
		children := make([][]Vector_Node, 66, context.temp_allocator)
		for i in 0 ..< 66 {
			children[i] = make([]Vector_Node, 1, context.temp_allocator)
		}
		children[65][0] = leaf
		for i := 64; i >= 0; i -= 1 {
			tri := vector_test_triangle({0, 4}, {2, 0}, {4, 4})
			children[i][0] = {
				kind = .Clip,
				opacity = 1,
				mesh = tri.mesh,
				children = children[i + 1],
			}
		}
		nodes := [1]Vector_Node{children[0][0]}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, len(vector_frame().draws), 0)
	})
}

@(test)
vector_scene_mask_object_bounding_box_maps_content_units :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		content := [1]Vector_Node{vector_test_rect({10, 20, 40, 20}, {255, 0, 0, 255})}
		// Unit-square left half in objectBoundingBox space → device [10,20]–[30,40].
		mask := [1]Vector_Node{vector_test_rect({0, 0, 0.5, 1}, {255, 255, 255, 255})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = mask[:],
			mask_kind = .Alpha,
			mask_content_units = .Object_Bounding_Box,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		root := vector_frame().records[vector_frame().draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Mask)
		mask_index := root.first_mask
		testing.expect(t, mask_index >= 0)
		mask_record := vector_frame().records[mask_index]
		testing.expect(t, abs(mask_record.bounds.x - 10) < 0.01)
		testing.expect(t, abs(mask_record.bounds.y - 20) < 0.01)
		testing.expect(t, abs(mask_record.bounds.w - 20) < 0.01)
		testing.expect(t, abs(mask_record.bounds.h - 20) < 0.01)
	})
}

@(test)
vector_scene_mask_region_object_bounding_box_is_stored :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		content := [1]Vector_Node{vector_test_rect({0, 0, 40, 20}, {255, 0, 0, 255})}
		mask := [1]Vector_Node{vector_test_rect({0, 0, 40, 20}, {255, 255, 255, 255})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = mask[:],
			mask_kind = .Luminance,
			mask_units = .Object_Bounding_Box,
			mask_region = {0.25, 0, 0.5, 1},
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		root := vector_frame().records[vector_frame().draws[0].first]
		testing.expect(t, abs(root.clip.x - 10) < 0.01)
		testing.expect(t, abs(root.clip.y - 0) < 0.01)
		testing.expect(t, abs(root.clip.w - 20) < 0.01)
		testing.expect(t, abs(root.clip.h - 20) < 0.01)
	})
}

@(private)
vector_test_triangle :: proc(a, b, c: Vec2) -> Vector_Node {
	points := make([]Vec2, 3, context.temp_allocator)
	points[0] = a
	points[1] = b
	points[2] = c
	indices := make([]u32, 3, context.temp_allocator)
	indices[0] = 0
	indices[1] = 1
	indices[2] = 2
	return {kind = .Mesh, mesh = {vertices = points, indices = indices}, colour = {255, 255, 255, 255}, opacity = 1}
}
