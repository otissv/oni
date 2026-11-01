#+test
package oni_vector

import "core:mem"
import "core:testing"

@(private)
Test_Failing_Allocator :: struct {
	backing: mem.Allocator,
	remaining: int,
	rejected: bool,
}

@(private)
test_failing_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	state := cast(^Test_Failing_Allocator)data
	if size > 0 && (mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed) {
		if state.remaining == 0 { state.rejected = true; return nil, .Out_Of_Memory }
		state.remaining -= 1
	}
	return state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

@(private)
test_tessellate_with_allocator :: proc(commands: []Command, allocator: mem.Allocator) -> (Mesh, Error) {
	context.allocator = allocator
	return Tessellate(commands, IDENTITY, .Even_Odd)
}

@(test)
tessellation_cleans_every_partial_allocation_on_failure :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	for kind in 0 ..< 3 {
		path: Path
		switch kind {
		case 0:
			_ = Polyline(&path, []Point{{0, -10}, {6, 8}, {-10, -3}, {10, -3}, {-6, 8}}, true)
			_ = Rectangle(&path, {-3, -3}, {6, 6})
		case 1: _ = Ellipse(&path, {0, 0}, {30, 10})
		case 2: _ = Polyline(&path, []Point{{0, 0}, {10, 0}, {10, 4}, {4, 4}, {4, 10}, {0, 10}}, true)
		}
		success := false
		for allowed in 0 ..< 128 {
			failing := Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), remaining = allowed}
			mesh, err := test_tessellate_with_allocator(path.commands[:], {procedure = test_failing_allocator_proc, data = &failing})
			Destroy_Mesh(&mesh)
			testing.expect_value(t, tracking.current_memory_allocated, i64(0))
			testing.expect_value(t, len(tracking.allocation_map), 0)
			testing.expect_value(t, err, failing.rejected ? Error.Allocation_Failed : Error.None)
			if !failing.rejected { success = true; break }
		}
		Destroy_Path(&path)
		testing.expect(t, success, "All allocation failure boundaries must be followed by a successful clean build")
	}
}

@(test)
scratch_blocks_preserve_alignment_resize_contents_and_bulk_cleanup :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	arena := Scratch_Arena{backing = mem.tracking_allocator(&tracking)}
	defer scratch_arena_destroy(&arena)
	allocator := mem.Allocator{procedure = scratch_allocator_proc, data = &arena}
	for alignment in ([6]int{1, 2, 8, 16, 64, 4096}) {
		data, err := allocator.procedure(allocator.data, .Alloc, 4097, alignment, nil, 0)
		testing.expect(t, err == nil)
		if err != nil { return }
		testing.expect_value(t, uintptr(raw_data(data)) % uintptr(alignment), uintptr(0))
		for value in data { testing.expect_value(t, value, u8(0)) }
		data[0], data[len(data) - 1] = 17, 29
		grown, growth_error := allocator.procedure(allocator.data, .Resize, 8193, alignment, raw_data(data), len(data))
		testing.expect(t, growth_error == nil)
		if growth_error != nil { return }
		testing.expect_value(t, grown[0], u8(17))
		testing.expect_value(t, grown[len(data) - 1], u8(29))
		for value in grown[len(data):] { testing.expect_value(t, value, u8(0)) }
	}
	scratch_arena_destroy(&arena)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
