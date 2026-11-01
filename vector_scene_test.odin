#+test
package oni

import "core:testing"

@(test)
vector_scene_records_only_during_draw :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		nodes := [1]Vector_Node{{kind = .Mesh, mesh = {
			vertices = []Vec2{{0, 0}, {12, 0}, {0, 12}},
			indices = []u32{0, 1, 2},
		}, colour = {255, 0, 0, 255}}}
		state.ui.pass = .Layout
		testing.expect(t, draw_vector_scene({nodes = nodes[:]}) == .None)
		testing.expect_value(t, len(vector_frame().draws), 0)
		state.ui.pass = .Draw
		testing.expect(t, draw_vector_scene({nodes = nodes[:]}) == .None)
		testing.expect_value(t, len(vector_frame().draws), 1)
		testing.expect_value(t, len(vector_frame().vertices), 3)
	})
}

@(test)
vector_scene_rejects_invalid_mesh_without_partial_recording :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		nodes := [2]Vector_Node{
			{kind = .Mesh, mesh = {vertices = []Vec2{{0, 0}, {8, 0}, {0, 8}}, indices = []u32{0, 1, 2}}},
			{kind = .Mesh, mesh = {vertices = []Vec2{{0, 0}}, indices = []u32{0, 1, 2}}},
		}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:]}), Vector_Error.Invalid_Mesh)
		testing.expect_value(t, len(vector_frame().draws), 0)
		testing.expect_value(t, len(vector_frame().vertices), 0)
		testing.expect_value(t, len(batch_current().segments), 0)
	})
}

@(test)
vector_scene_rollback_drops_stale_geometry_and_segments :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		keep := [1]Vector_Node{{kind = .Mesh, mesh = {
			vertices = []Vec2{{0, 0}, {8, 0}, {0, 8}},
			indices = []u32{0, 1, 2},
		}, colour = {255, 0, 0, 255}, opacity = 1}}
		testing.expect_value(t, draw_vector_scene({nodes = keep[:], opacity = 1}), Vector_Error.None)
		f := vector_frame()
		saved_vertices := len(f.vertices)
		saved_indices := len(f.indices)
		saved_instances := len(f.instances)
		saved_commands := len(f.commands)
		saved_records := len(f.records)
		saved_draws := len(f.draws)
		saved_ramps := len(f.ramp_pixels)
		saved_ramp_rows := f.ramp_rows
		saved_revision := f.vertex_revision
		saved_segments := len(batch_current().segments)
		kept_geometry := len(f.geometry)
		f.geometry[0xdeadbeef] = {first_index = u32(saved_indices), index_count = 3}
		append(&f.vertices, Vector_Vertex{pos = {9, 9}})
		append(&f.indices, u32(0))
		append(&batch_current().segments, Batch_Segment{})
		vector_scene_rollback_recording(
			saved_vertices,
			saved_indices,
			saved_instances,
			saved_commands,
			saved_records,
			saved_draws,
			saved_ramps,
			saved_ramp_rows,
			saved_revision,
			saved_segments,
		)
		_, stale := f.geometry[0xdeadbeef]
		testing.expect(t, !stale)
		testing.expect_value(t, len(f.geometry), kept_geometry)
		testing.expect_value(t, len(f.vertices), saved_vertices)
		testing.expect_value(t, len(f.indices), saved_indices)
		testing.expect_value(t, len(batch_current().segments), saved_segments)
	})
}

@(test)
vector_scene_snapshots_mesh_data_before_application_mutation :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		vertices := [3]Vec2{{0, 0}, {8, 0}, {0, 8}}
		indices := [3]u32{0, 1, 2}
		nodes := [1]Vector_Node{{kind = .Mesh, mesh = {vertices = vertices[:], indices = indices[:]}}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:]}), Vector_Error.None)
		vertices[1] = {99, 99}
		indices[1] = 99
		testing.expect_value(t, vector_frame().vertices[1].pos, Vec2{8, 0})
		testing.expect_value(t, vector_frame().indices[1], u32(1))
	})
}

@(test)
vector_scene_orders_between_existing_ui_segments :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		batch_check_key(0)
		batch_push_indices(0)
		nodes := [1]Vector_Node{{kind = .Mesh, mesh = {
			vertices = []Vec2{{0, 0}, {8, 0}, {0, 8}}, indices = []u32{0, 1, 2},
		}}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:]}), Vector_Error.None)
		batch_check_key(0)
		batch_push_indices(0)
		batch_finalize_segments()
		testing.expect_value(t, len(batch_current().segments), 3)
		testing.expect(t, !batch_current().segments[0].vector)
		testing.expect(t, batch_current().segments[1].vector)
		testing.expect(t, !batch_current().segments[2].vector)
		testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
		testing.expect_value(t, batch_current().segments[2].index_count, u32(6))
	})
}
