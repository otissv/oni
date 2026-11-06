#+test
package oni

import "core:mem"
import "core:testing"

@(test)
layout_frame_arena_grows_tail_in_place_and_clears_new_bytes :: proc(t: ^testing.T) {
	layout := layout_test_begin_small_frame_arena()
	defer layout_test_end(&layout)
	allocator := layout_frame_allocator_for(&layout)
	first, err := mem.alloc_bytes(64, 16, allocator)
	testing.expect(t, err == nil)
	for &value in first { value = 0xa5 }
	grown, resize_error := mem.resize_bytes(first, 128, 16, allocator)
	testing.expect(t, resize_error == nil)
	testing.expect_value(t, raw_data(grown), raw_data(first))
	for value in grown[:64] { testing.expect_value(t, value, u8(0xa5)) }
	for value in grown[64:] { testing.expect_value(t, value, u8(0)) }
}

@(test)
layout_frame_arena_resize_preserves_other_live_allocations :: proc(t: ^testing.T) {
	layout := layout_test_begin_small_frame_arena()
	defer layout_test_end(&layout)
	allocator := layout_frame_allocator_for(&layout)
	first, a := mem.alloc_bytes(64, 16, allocator)
	second, b := mem.alloc_bytes(64, 16, allocator)
	testing.expect(t, a == nil && b == nil)
	for &value in first { value = 0xa5 }
	for &value in second { value = 0x5a }
	grown, err := mem.resize_bytes(first, 8192, 64, allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, uintptr(raw_data(grown)) % 64, uintptr(0))
	for value in grown[:64] { testing.expect_value(t, value, u8(0xa5)) }
	for value in grown[64:] { testing.expect_value(t, value, u8(0)) }
	for value in second { testing.expect_value(t, value, u8(0x5a)) }
}

@(test)
layout_frame_arena_resize_honors_stricter_alignment :: proc(t: ^testing.T) {
	layout := layout_test_begin_small_frame_arena()
	defer layout_test_end(&layout)
	allocator := layout_frame_allocator_for(&layout)
	_, _ = mem.alloc_bytes(3, 1, allocator)
	first, err := mem.alloc_bytes(5, 1, allocator)
	testing.expect(t, err == nil)
	for &value in first { value = 0x5a }
	grown, resize_error := mem.resize_bytes(first, 32, 64, allocator)
	testing.expect(t, resize_error == nil)
	testing.expect_value(t, uintptr(raw_data(grown)) % 64, uintptr(0))
	for value in grown[:5] { testing.expect_value(t, value, u8(0x5a)) }
	for value in grown[5:] { testing.expect_value(t, value, u8(0)) }
}

@(test)
layout_frame_arena_mixed_resizes_preserve_all_live_buffers :: proc(t: ^testing.T) {
	layout := layout_test_begin_small_frame_arena()
	defer layout_test_end(&layout)
	allocator := layout_frame_allocator_for(&layout)
	buffers: [16][]byte
	seed := u64(137)
	for iteration in 0 ..< 256 {
		seed = seed * 6364136223846793005 + 1442695040888963407
		slot := int(seed >> 32) % len(buffers)
		size := 1 + int(seed >> 16) % 2048
		alignment := 1 << uint(seed % 7)
		mode := mem.Allocator_Mode.Resize
		if iteration % 2 == 0 { mode = .Resize_Non_Zeroed }
		old := buffers[slot]
		resized, err := allocator.procedure(allocator.data, mode, size, alignment, raw_data(old), len(old))
		testing.expect(t, err == nil)
		testing.expect_value(t, len(resized), size)
		testing.expect_value(t, uintptr(raw_data(resized)) % uintptr(alignment), uintptr(0))
		for value in resized[:min(len(old), size)] { testing.expect_value(t, value, u8(slot + 1)) }
		if mode == .Resize && size > len(old) {
			for value in resized[len(old):] { testing.expect_value(t, value, u8(0)) }
		}
		for &value in resized { value = u8(slot + 1) }
		buffers[slot] = resized
		for buffer, i in buffers {
			for value in buffer { testing.expect_value(t, value, u8(i + 1)) }
		}
	}
}

@(test)
layout_frame_arena_rejects_invalid_sizes_and_alignments :: proc(t: ^testing.T) {
	layout := layout_test_begin_small_frame_arena()
	defer layout_test_end(&layout)
	allocator := layout_frame_allocator_for(&layout)
	for request in ([5][2]int{{-1, 8}, {8, 0}, {8, 3}, {max(int), 16}, {8, -1}}) {
		_, err := allocator.procedure(allocator.data, .Alloc, request[0], request[1], nil, 0)
		testing.expect_value(t, err, mem.Allocator_Error.Invalid_Argument)
	}
}
