package oni_vector

import "core:mem"

@(private)
Scratch_Block :: struct {
	next: ^Scratch_Block,
	capacity, used: int,
}

@(private)
Scratch_Arena :: struct {
	block: ^Scratch_Block,
	backing: mem.Allocator,
	limit, reserved: int,
	failed: bool,
	limit_exceeded: bool,
	requested: int,
}

// The ownership link lives inside each allocation. Acquiring a block never
// requires a second bookkeeping allocation that could fail and orphan it.
@(private)
scratch_arena_destroy :: proc(arena: ^Scratch_Arena) {
	block := arena.block
	for block != nil {
		next := block.next
		free(block, arena.backing)
		block = next
	}
	arena.block = nil
}

@(private)
scratch_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	arena := cast(^Scratch_Arena)data
	switch mode {
	case .Free: return nil, nil
	case .Free_All:
		scratch_arena_destroy(arena)
		return nil, nil
	case .Query_Features:
		if old_memory != nil {
			(cast(^mem.Allocator_Mode_Set)old_memory)^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Free_All, .Query_Features}
		}
		return nil, nil
	case .Query_Info: return nil, .Mode_Not_Implemented
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
	}
	if size == 0 { return nil, nil }
	if size < 0 || old_size < 0 || alignment <= 0 || alignment & (alignment - 1) != 0 ||
	   alignment > max(int) - size_of(Scratch_Block) || size > max(int) - size_of(Scratch_Block) - alignment {
		return nil, .Invalid_Argument
	}
	block := arena.block
	position := uintptr(0)
	if block != nil {
		position = mem.align_forward_uintptr(uintptr(block) + uintptr(block.used), uintptr(alignment))
	}
	if block == nil || position - uintptr(block) > uintptr(block.capacity) || uintptr(size) > uintptr(block.capacity) - (position - uintptr(block)) {
		capacity := max(4096, size_of(Scratch_Block) + alignment + size)
		arena.requested = size_of(Scratch_Block) + alignment + size
		if arena.limit > 0 {
			capacity = min(capacity, arena.limit - arena.reserved)
			if capacity < size_of(Scratch_Block) + alignment + size {
				arena.failed = true
				arena.limit_exceeded = true
				return nil, .Out_Of_Memory
			}
		}
		storage, err := arena.backing.procedure(arena.backing.data, .Alloc_Non_Zeroed, capacity, max(alignment, align_of(Scratch_Block)), nil, 0, loc)
		if err != nil { arena.failed = true; return nil, err }
		if len(storage) < capacity {
			if raw_data(storage) != nil { free(raw_data(storage), arena.backing) }
			return nil, .Out_Of_Memory
		}
		block = cast(^Scratch_Block)raw_data(storage)
		block^ = {next = arena.block, capacity = capacity, used = size_of(Scratch_Block)}
		arena.block = block
		arena.reserved += capacity
		position = mem.align_forward_uintptr(uintptr(block) + uintptr(block.used), uintptr(alignment))
	}
	block.used = int(position - uintptr(block)) + size
	result := (cast([^]byte)rawptr(position))[:size]
	copied := 0
	if (mode == .Resize || mode == .Resize_Non_Zeroed) && old_memory != nil {
		copied = min(size, old_size)
		mem.copy(raw_data(result), old_memory, copied)
	}
	if mode == .Alloc || mode == .Resize {
		mem.zero(raw_data(result[copied:]), size - copied)
	}
	return result, nil
}
