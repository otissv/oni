#+test
package oni

import "core:testing"

@(test)
vector_opacity_groups_fuse_at_mask_boundaries :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		content := [2]Vector_Node{vector_test_rect({0, 0, 20, 20}, {255, 0, 0, 255}), vector_test_rect({10, 0, 20, 20}, {0, 255, 0, 255})}
		inner := [1]Vector_Node{{kind = .Group, opacity = .5, children = content[:]}}
		mask := [1]Vector_Node{vector_test_rect({0, 0, 30, 20}, {255, 255, 255, 255})}
		masked := [1]Vector_Node{{kind = .Mask, opacity = .5, children = inner[:], mask = mask[:]}}
		outer := [1]Vector_Node{{kind = .Group, opacity = .5, children = masked[:]}}
		testing.expect_value(t, Draw_Vector_Scene({nodes = outer[:], opacity = 1}), Vector_Error.None)
		f := vector_frame()
		root := f.records[f.draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Mask)
		testing.expect_value(t, root.opacity, f32(.125))
		testing.expect_value(t, f.instances[f.commands[root.command].first_instance].colour[3], f32(.125))
		testing.expect_value(t, f.records[root.first_child].kind, Vector_Node_Kind.Mesh)
		testing.expect(t, f.records[root.first_child].next >= 0)
		testing.expect_value(t, inner[0].opacity, f32(.5))
	})
}
