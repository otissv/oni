#+test
package oni

import "core:testing"
import v "./vector"

@(test)
vector_scene_accepts_sixty_four_geometric_clips :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		leaf := vector_test_rect({0, 0, 4, 4}, {255, 0, 0, 255})
		children := make([][]Vector_Node, 64, context.temp_allocator)
		for i in 0 ..< 64 {
			children[i] = make([]Vector_Node, 1, context.temp_allocator)
		}
		children[63][0] = leaf
		for i := 62; i >= 0; i -= 1 {
			tri := vector_test_triangle({0, 4}, {2, 0}, {4, 4})
			children[i][0] = {
				kind = .Clip,
				opacity = 1,
				mesh = tri.mesh,
				children = children[i + 1],
			}
		}
		root_clip := vector_test_triangle({0, 4}, {2, 0}, {4, 4})
		nodes := [1]Vector_Node{{
			kind = .Clip,
			opacity = 1,
			mesh = root_clip.mesh,
			children = children[0],
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().draws), 1)
	})
}

@(test)
vector_scene_mask_obb_uses_unpadded_geometry_bounds :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		content_mesh := [1]Vector_Node{vector_test_rect({10, 20, 40, 20}, {255, 0, 0, 255})}
		grouped := [1]Vector_Node{{kind = .Group, opacity = 1, children = content_mesh[:]}}
		mask := [1]Vector_Node{vector_test_rect({0, 0, 0.5, 1}, {255, 255, 255, 255})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = grouped[:],
			mask = mask[:],
			mask_kind = .Alpha,
			mask_content_units = .Object_Bounding_Box,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		root := vector_frame().records[vector_frame().draws[0].first]
		mask_record := vector_frame().records[root.first_mask]
		testing.expect(t, abs(mask_record.bounds.x - 10) < 0.01)
		testing.expect(t, abs(mask_record.bounds.y - 20) < 0.01)
		testing.expect(t, abs(mask_record.bounds.w - 20) < 0.01)
		testing.expect(t, abs(mask_record.bounds.h - 20) < 0.01)
	})
}

@(test)
vector_scene_rejects_obb_mapped_coordinates_beyond_limit :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		huge := f32(1 << 20)
		content := [1]Vector_Node{vector_test_rect({0, 0, huge, huge}, {255, 0, 0, 255})}
		// Unit corner maps to (huge, huge) which is at the limit; 1.1 exceeds it.
		mask := [1]Vector_Node{vector_test_rect({1.1, 1.1, 0.1, 0.1}, {255, 255, 255, 255})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = mask[:],
			mask_kind = .Alpha,
			mask_content_units = .Object_Bounding_Box,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().draws), 0)
	})
}

@(test)
vector_scene_path_nodes_record_inside_groups :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {20, 20}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stops := [2]Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
		child := [1]Vector_Node{{
			kind = .Path,
			opacity = 1,
			path = {
				handle = handle,
				paint = Linear_Paint({x1 = 0, y1 = 0, x2 = 20, y2 = 0, stops = stops[:]}),
				transform = {1, 0, 0, 1, 4, 4},
				rule = .Nonzero,
				opacity = 1,
			},
		}}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = child[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().draws), 1)
		root := vector_frame().records[vector_frame().draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Group)
		testing.expect(t, root.first_child >= 0)
		testing.expect_value(t, vector_frame().records[root.first_child].kind, Vector_Node_Kind.Path)
		testing.expect(t, vector_frame().ramp_rows > 0)
	})
}

@(test)
vector_frame_vertex_revision_advances_on_scene_geometry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		a := [1]Vector_Node{vector_test_rect({0, 0, 8, 8}, {255, 0, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = a[:], opacity = 1}), Vector_Error.None)
		rev1 := vector_frame().vertex_revision
		testing.expect(t, rev1 > 0)
		vector_scene_reset()
		batch_reset()
		b := [1]Vector_Node{vector_test_rect({1, 1, 8, 8}, {0, 255, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = b[:], opacity = 1}), Vector_Error.None)
		testing.expect(t, vector_frame().vertex_revision > rev1)
		testing.expect_value(t, len(vector_frame().vertices), 4)
		testing.expect(t, vector_frame().vertices[0].pos != Vec2{0, 0} || true)
		testing.expect_value(t, vector_frame().vertices[0].pos, Vec2{1, 1})
	})
}
