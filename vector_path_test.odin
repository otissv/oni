#+test
package oni

import "core:testing"
import "core:mem"

@(test)
vector_path_handles_reject_released_generation :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := [4]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.Invalid_Handle)
	})
}

@(test)
vector_path_translation_reuses_geometry_and_snapshots_before_update :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		translation := Vector_Identity
		translation[4] = 23.25
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 255, 0, 255}, translation), Vector_Error.None)
		testing.expect_value(t, len(state.vector.paths[handle.index - 1].cache), 1)
		before := vector_frame().vertices[0]
		commands[1].points[0] = {20, 0}
		testing.expect_value(t, Vector_Update_Path(handle, commands[:]), Vector_Error.None)
		testing.expect_value(t, vector_frame().vertices[0], before)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		testing.expect_value(t, vector_frame().vertices[0], before)
	})
}

@(test)
vector_path_frame_work_limit_recovers_after_reset :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		vector_frame().new_segments = VECTOR_MAX_NEW_SEGMENTS
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, len(vector_frame().draws), 0)
		vector_scene_reset()
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		testing.expect(t, vector_frame().new_segments > 0)
	})
}

@(test)
vector_path_repeated_lifecycle_releases_cache_and_rejects_stale_handles :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		stale: Vector_Path_Handle
		for cycle in 0 ..< 100 {
			vector_scene_reset()
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			if cycle > 0 {
				testing.expect_value(t, Vector_Update_Path(stale, commands[:]), Vector_Error.Invalid_Handle)
			}
			testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
			testing.expect(t, state.vector.path_cache_bytes > 0)
			testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
			testing.expect_value(t, state.vector.path_cache_bytes, u64(0))
			stale = handle
		}
		testing.expect_value(t, len(state.vector.paths), 1)
	})
}

@(test)
vector_path_eviction_preserves_a_moved_protected_cache_and_recordings :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		for scale in 1 ..= 3 {
			transform := Vector_Transform{f64(scale), 0, 0, f64(scale), 0, 0}
			testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}, transform), Vector_Error.None)
			state.vector.paths[handle.index - 1].cache[scale - 1].last_used = u64(scale)
		}
		before := vector_frame().vertices[0]
		protected := 2
		testing.expect(t, !vector_path_evict_cache(VECTOR_CPU_CACHE_BUDGET, int(handle.index - 1), &protected))
		testing.expect_value(t, protected, 0)
		entry := vector_path_entry(handle)
		testing.expect_value(t, len(entry.cache), 1)
		testing.expect_value(t, entry.cache[protected].linear[0], f64(3))
		testing.expect_value(t, vector_frame().vertices[0], before)
		testing.expect_value(t, state.vector.path_cache_bytes, u64(cap(entry.cache)) * size_of(Vector_Path_Cache) + vector_path_cache_bytes(entry.cache[0].mesh))
	})
}

@(test)
vector_path_instances_share_snapshot_geometry_until_the_source_changes :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		transform := Vector_Identity
		transform[4] = 12.375
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 255, 0, 255}, transform, opacity = 0.5), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().vertices), 3)
		testing.expect_value(t, len(vector_frame().indices), 3)
		testing.expect_value(t, len(vector_frame().instances), 2)
		testing.expect_value(t, len(vector_frame().commands), 2)
		testing.expect_value(t, vector_frame().commands[0].first_index, vector_frame().commands[1].first_index)
		testing.expect_value(t, vector_frame().instances[1].origin.x, f32(12.375))
		testing.expect_value(t, vector_frame().instances[1].colour, [4]f32{0, 1, 0, 0.5})
		commands[1].points[0].x = 20
		testing.expect_value(t, Vector_Update_Path(handle, commands[:]), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}), Vector_Error.None)
		// Affine-compatible edits keep basis geometry and apply a GPU morph.
		testing.expect_value(t, len(vector_frame().vertices), 3)
		testing.expect_value(t, vector_frame().vertices[1].pos.x, f32(10))
		testing.expect_value(t, len(vector_frame().instances), 3)
		testing.expect(t, vector_frame().instances[2].morph_linear != [4]f32{1, 0, 0, 1})
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().commands), 3)
	})
}

@(test)
vector_path_commands_keep_their_allocator_across_update_and_shutdown :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		backing := context.allocator
		owner, other: mem.Tracking_Allocator
		mem.tracking_allocator_init(&owner, backing)
		mem.tracking_allocator_init(&other, backing)
		owner.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
		other.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
		defer {
			// Also clean up a failing regression run without freeing through the
			// allocator whose ownership check rejected the original free.
			for pointer in owner.allocation_map { free(pointer, owner.backing) }
			for pointer in other.allocation_map { free(pointer, other.backing) }
			mem.tracking_allocator_destroy(&owner)
			mem.tracking_allocator_destroy(&other)
		}
		defer vector_scene_shutdown()
		commands := [5]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{10, 10}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		context.allocator = mem.tracking_allocator(&owner)
		handle, created := Vector_Create_Path(commands[:4])
		context.allocator = mem.tracking_allocator(&other)
		updated := Vector_Update_Path(handle, commands[:])
		state.ui.pass = .Draw
		drawn := Draw_Vector_Path(handle, {255, 0, 0, 255})
		destroyed := Vector_Destroy_Path(handle)
		_, second := Vector_Create_Path(commands[:])
		context.allocator = backing
		vector_scene_shutdown()
		batch_delete_cpu_arrays(&state.gpu_state)
		testing.expect_value(t, created, Vector_Error.None)
		testing.expect_value(t, updated, Vector_Error.None)
		testing.expect_value(t, drawn, Vector_Error.None)
		testing.expect_value(t, destroyed, Vector_Error.None)
		testing.expect_value(t, second, Vector_Error.None)
		testing.expect_value(t, len(owner.allocation_map), 0)
		testing.expect_value(t, len(other.allocation_map), 0)
		for _, allocation in other.allocation_map { testing.expectf(t, false, "unreleased vector allocation: %v", allocation.location) }
		testing.expect_value(t, len(owner.bad_free_array), 0)
		testing.expect_value(t, len(other.bad_free_array), 0)
	})
}

@(private)
Test_Vector_Failing_Allocator :: struct {
	backing: mem.Allocator,
	remaining: int,
	rejected: bool,
}

@(private)
test_vector_failing_allocator :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	fault := cast(^Test_Vector_Failing_Allocator)data
	if size > 0 && (mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed) {
		if fault.remaining == 0 { fault.rejected = true; return nil, .Out_Of_Memory }
		fault.remaining -= 1
	}
	return fault.backing.procedure(fault.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

@(test)
vector_path_partial_allocations_are_released_at_every_failure_boundary :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		backing := context.allocator
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, backing)
		defer mem.tracking_allocator_destroy(&tracking)
		commands := [5]Vector_Path_Command{
			{kind = .Move},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{10, 10}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}},
			{kind = .Close},
		}
		state.ui.pass = .Draw
		success := false
		for allowed in 0 ..< 128 {
			fault := Test_Vector_Failing_Allocator{backing = mem.tracking_allocator(&tracking), remaining = allowed}
			context.allocator = {procedure = test_vector_failing_allocator, data = &fault}
			handle, created := Vector_Create_Path(commands[:4])
			drawn, updated, destroyed: Vector_Error
			if created == .None {
				drawn = Draw_Vector_Path(handle, {255, 0, 0, 255})
				updated = Vector_Update_Path(handle, commands[:])
				if drawn == .None && updated == .None { drawn = Draw_Vector_Path(handle, {0, 255, 0, 255}) }
				destroyed = Vector_Destroy_Path(handle)
			}
			context.allocator = backing
			vector_scene_shutdown()
			batch_delete_cpu_arrays(&state.gpu_state)
			testing.expect(t, created == .None || created == .Allocation_Failed)
			testing.expect(t, drawn == .None || drawn == .Allocation_Failed)
			testing.expect(t, updated == .None || updated == .Allocation_Failed)
			testing.expect_value(t, destroyed, Vector_Error.None)
			testing.expect_value(t, tracking.current_memory_allocated, i64(0))
			testing.expect_value(t, len(tracking.allocation_map), 0)
			if !fault.rejected { success = true; break }
		}
		testing.expect(t, success)
	})
}
