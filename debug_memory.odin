package oni

import "core:os"
import "core:strings"

// OS resident memory includes allocator retention, libraries and driver mappings.
Process_Memory_Stats :: struct {
	available, breakdown_available: bool,
	resident_bytes, peak_resident_bytes: u64,
	anonymous_bytes, file_bytes, shared_bytes: u64,
}

// Resource capacities overlap process RAM on some GPUs. They are not an RSS total.
Render_Memory_Stats :: struct {
	process: Process_Memory_Stats,
	layout_used_bytes, layout_capacity_bytes: u64,
	scratch_used_bytes, scratch_capacity_bytes: u64,
	texture_cpu_bytes, texture_gpu_bytes: u64,
	texture_count: int,
	batch_cpu_bytes, batch_gpu_bytes, batch_upload_bytes: u64,
	vector_gpu_bytes, vector_pool_bytes, vector_cache_bytes: u64,
}

@(private)
debug_memory_parse_kib :: proc(raw_value: string) -> (u64, bool) {
	value := strings.trim_space(raw_value)

	if !strings.has_suffix(value, "kB") {

		return 0, false
	}
	value = strings.trim_space(value[:len(value) - 2])

	if len(value) == 0 {

		return 0, false
	}
	result := u64(0)
	for ch in value {

		if ch < '0' || ch > '9' || result > ((~u64(0)) / 1024 - u64(ch - '0')) / 10 {

			return 0, false
		}
		result = result * 10 + u64(ch - '0')
	}

	return result * 1024, true
}

@(private)
debug_memory_parse_linux_status :: proc(text: string) -> (result: Process_Memory_Stats) {
	fields: bit_set[0 ..< 5]
	remaining := text
	for status_line in strings.split_lines_iterator(&remaining) {
		line := status_line
		key, _ := strings.split_iterator(&line, ":")
		index: int
		switch key {
		case "VmRSS": index = 0
		case "VmHWM": index = 1
		case "RssAnon": index = 2
		case "RssFile": index = 3
		case "RssShmem": index = 4
		case: continue
		}
		value, ok := debug_memory_parse_kib(line)

		if !ok {

			return {}
		}
		fields += {index}
		switch index {
		case 0: result.resident_bytes = value
		case 1: result.peak_resident_bytes = value
		case 2: result.anonymous_bytes = value
		case 3: result.file_bytes = value
		case 4: result.shared_bytes = value
		}
	}
	result.available = 0 in fields && 1 in fields
	result.breakdown_available = result.available && 2 in fields && 3 in fields && 4 in fields

	return
}

@(private)
debug_memory_process :: proc() -> Process_Memory_Stats {
	when ODIN_OS == .Linux {
		file, err := os.open("/proc/self/status")

		if err != nil {

			return {}
		}
		defer os.close(file)
		buffer: [8192]u8
		used := 0
		for used < len(buffer) {
			n, read_err := os.read(file, buffer[used:])
			used += n

			if read_err != nil && read_err != .EOF {

				return {}
			}

			if n == 0 || read_err == .EOF {

				return debug_memory_parse_linux_status(string(buffer[:used]))
			}
		}
	}

	return {}
}

@(private)
debug_memory_snapshot :: proc() -> (result: Render_Memory_Stats) {

	if state == nil {

		return
	}
	result.process = debug_memory_process()
	for &block in state.ui.layout.frame_arena.blocks {
		result.layout_used_bytes += u64(block.arena.offset)
		result.layout_capacity_bytes += u64(cap(block.backing))
	}
	for &block in state.ui.render_scratch.blocks {
		result.scratch_used_bytes += u64(block.arena.offset)
		result.scratch_capacity_bytes += u64(cap(block.backing))
	}
	for &record in state.textures.records {

		if record.surface != nil {
			result.texture_cpu_bytes += u64(max(record.surface.pitch, 0)) * u64(max(record.surface.h, 0))
		}

		if record.gpu != nil {
			result.texture_gpu_bytes += u64(max(record.w, 0)) * u64(max(record.h, 0)) * 4
		}

		if record.surface != nil || record.gpu != nil {
			result.texture_count += 1
		}
	}
	for &b in state.gpu_state.batches {
		result.batch_cpu_bytes += u64(cap(b.vertices) * size_of(UI_Vertex) + cap(b.indices) * size_of(u16) + cap(b.segments) * size_of(Batch_Segment))

		if b.vertex_buffer != nil {
			result.batch_gpu_bytes += u64(b.vertex_capacity) * size_of(UI_Vertex)
		}

		if b.index_buffer != nil {
			result.batch_gpu_bytes += u64(b.index_capacity) * size_of(u16)
		}

		if b.transfer != nil {
			result.batch_upload_bytes += u64(b.transfer_capacity)
		}
	}
	result.vector_gpu_bytes = state.vector.gpu.bytes
	result.vector_pool_bytes = state.vector.gpu.pool_bytes
	result.vector_cache_bytes = state.vector.path_cache_bytes + state.vector.svg_path_bytes

	return
}
