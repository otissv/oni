package oni

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:time"
import sdl "vendor:sdl3"

@(private)
vector_vert_code := #load("shaders/vector.spv.vert")
@(private)
vector_solid_vert_code := #load("shaders/vector_solid.spv.vert")
@(private)
vector_frag_code := #load("shaders/vector.spv.frag")
@(private)
VECTOR_GPU_BUDGET :: u64(256 * 1024 * 1024)
@(private)
VECTOR_TARGET_POOL_BUDGET :: u64(64 * 1024 * 1024)
// One physical pixel of antialiasing padding around tight scene bounds.
@(private)
VECTOR_SCENE_AA_PAD :: f32(1)

@(private)
Vector_Target :: struct {
	colour, depth, resolved: ^sdl.GPUTexture,
	// World-space view rectangle in physical pixels (shader + blit origin).
	bounds: Rect,
	// Allocated texture size; MSAA roots grow to cover bounds, never shrink per slot.
	alloc_w, alloc_h: f32,
	bytes: u64,
	has_depth: bool,
	msaa: bool,
	in_use, used_this_encode: bool,
	atlas_refs: int,
}

@(private)
Vector_GPU_Record :: struct {
	content, mask: int,
	content_uv, mask_uv: Vec2,
}

@(private)
Vector_GPU_Frame :: struct {
	solid_instances: bool,
	index_snapshot: [dynamic]u32,
	index_snapshot_valid: bool,
	// Shared 4× MSAA scene target (vectors + UI).
	root: Vector_Target,
	pool: [dynamic]Vector_Target,
	pool_cursor: int,
	outputs: [dynamic]Vector_GPU_Record,
	buffers: [Vector_Buffer]^sdl.GPUBuffer,
	transfer: ^sdl.GPUTransferBuffer,
	buffer_bytes: u64,
	capacities: [Vector_Buffer]u64,
	transfer_capacity: u64,
	fence: ^sdl.GPUFence,
	root_view_origin: Vec2,
	root_view_origin_set: bool,
	ramp: ^sdl.GPUTexture,
	ramp_rows: int,
	ramp_bytes: u64,
}

@(private)
Vector_Buffer :: enum { Vertex, Index, Instance, Indirect }

@(private)
Vector_Stencil_Mode :: enum {
	Draw,
	Write,
	Pop,
}

@(private)
Vector_GPU :: struct {
	solid_pipelines: [2][5]^sdl.GPUGraphicsPipeline,
	pipeline, pipeline_depth: ^sdl.GPUGraphicsPipeline,
	pipeline_stencil_test, pipeline_stencil_write, pipeline_stencil_pop: ^sdl.GPUGraphicsPipeline,
	pipeline_ss, pipeline_ss_depth, pipeline_ss_stencil_test, pipeline_ss_stencil_write, pipeline_ss_stencil_pop: ^sdl.GPUGraphicsPipeline,
	ui_pipeline, ui_pipeline_depth, lcd_pipeline, lcd_pipeline_depth: ^sdl.GPUGraphicsPipeline,
	white: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	format, depth_format: sdl.GPUTextureFormat,
	frames: [2]Vector_GPU_Frame,
	frame_index: int,
	bytes, pool_bytes: u64,
	peak_bytes: u64,
	peak: [Vector_Resource_Category]u64,
	sample_work: u64,
	command_visits: u64,
	encode_attempts: int,
	geometry_epoch: u64,
	atlas_disabled: bool,
	// Last successful encode breakdown (milliseconds); for harness / diagnostics.
	encode_fence_ms, encode_upload_ms, encode_record_ms: f64,
	target_creates, target_reuses, target_releases: u64,
}

@(private)
vector_gpu_frame :: proc() -> ^Vector_GPU_Frame {
	return &state.vector.gpu.frames[state.vector.gpu.frame_index]
}

@(private)
vector_gpu_advance_frame :: proc() {
	if state == nil {
		return
	}

	state.vector.gpu.frame_index = (state.vector.gpu.frame_index + 1) % len(state.vector.gpu.frames)
}

@(private)
vector_target_release :: proc(target: ^Vector_Target, pooled: bool) {
	if target.colour != nil {
		state.vector.gpu.target_releases += 1
	}
	vector_target_release_textures(target.colour, target.depth, target.resolved)
	state.vector.gpu.bytes -= target.bytes
	if pooled {
		state.vector.gpu.pool_bytes -= target.bytes
	}
	target^ = {}
}

@(private)
vector_gpu_shutdown :: proc() {
	if state == nil {
		return
	}
	g := &state.vector.gpu
	for &frame in g.frames {
		if state.gpu != nil {
			if frame.fence != nil {
				_ = sdl.WaitForGPUFences(state.gpu, true, &frame.fence, 1)
				sdl.ReleaseGPUFence(state.gpu, frame.fence)
				frame.fence = nil
			}
			for &buffer in frame.buffers {
				if buffer != nil {
					sdl.ReleaseGPUBuffer(state.gpu, buffer)
					buffer = nil
				}
			}
			if frame.transfer != nil {
				sdl.ReleaseGPUTransferBuffer(state.gpu, frame.transfer)
				frame.transfer = nil
			}
			if frame.ramp != nil {
				sdl.ReleaseGPUTexture(state.gpu, frame.ramp)
				frame.ramp = nil
			}
		}
		state.vector.gpu.bytes -= frame.ramp_bytes
		frame.ramp_bytes = 0
		frame.ramp_rows = 0
		vector_target_release(&frame.root, false)
		for &target in frame.pool {
			vector_target_release(&target, true)
		}
		delete(frame.pool)
		delete(frame.outputs)
		delete(frame.index_snapshot)
		frame = {}
	}
	if state.gpu != nil {
		for &family in g.solid_pipelines {
			for &pipeline in family {
				if pipeline != nil { sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline); pipeline = nil }
			}
		}
		pipelines := [?]^^sdl.GPUGraphicsPipeline{
			&g.pipeline, &g.pipeline_depth,
			&g.pipeline_stencil_test, &g.pipeline_stencil_write, &g.pipeline_stencil_pop,
			&g.pipeline_ss, &g.pipeline_ss_depth, &g.pipeline_ss_stencil_test, &g.pipeline_ss_stencil_write, &g.pipeline_ss_stencil_pop,
			&g.ui_pipeline, &g.ui_pipeline_depth, &g.lcd_pipeline, &g.lcd_pipeline_depth,
		}
		for pipeline in pipelines {
			if pipeline^ != nil {
				sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline^)
				pipeline^ = nil
			}
		}
		if g.white != nil {
			sdl.ReleaseGPUTexture(state.gpu, g.white)
		}
		if g.sampler != nil {
			sdl.ReleaseGPUSampler(state.gpu, g.sampler)
		}
	}
	g^ = {}
}

@(private)
vector_gpu_init :: proc(format: sdl.GPUTextureFormat) -> bool {
	g := &state.vector.gpu
	if g.pipeline != nil && g.format == format {
		return true
	}
	vector_gpu_shutdown()
	depth_format, ok := gpu_vector_depth_format(state.gpu, format)
	if !ok {
		return false
	}
	g.format = format
	g.depth_format = depth_format
	success := false
	defer if !success {
		vector_gpu_shutdown()
	}

	// Colour-only and depth-compatible MSAA UI/LCD pairs match the root target.
	g.ui_pipeline = gpu_create_ui_layout_pipeline(state.gpu, format, frag_shader_code, gpu_blend_state(), sample_count = ._4)
	g.ui_pipeline_depth = gpu_create_ui_layout_pipeline(state.gpu, format, frag_shader_code, gpu_blend_state(), sample_count = ._4, depth_stencil_format = depth_format)
	g.lcd_pipeline = gpu_create_lcd_pipeline(state.gpu, format, sample_count = ._4)
	g.lcd_pipeline_depth = gpu_create_lcd_pipeline(state.gpu, format, sample_count = ._4, depth_stencil_format = depth_format)
	if g.ui_pipeline == nil || g.ui_pipeline_depth == nil || g.lcd_pipeline == nil || g.lcd_pipeline_depth == nil {
		return false
	}

	vert := gpu_load_shader(state.gpu, vector_vert_code, .VERTEX, 1, 0)
	solid_vert := gpu_load_shader(state.gpu, vector_solid_vert_code, .VERTEX, 1, 0)
	if test_hook_vector_fail_solid_shader && solid_vert != nil {
		sdl.ReleaseGPUShader(state.gpu, solid_vert)
		solid_vert = nil
	}
	frag := gpu_load_shader(state.gpu, vector_frag_code, .FRAGMENT, 1, 3)
	defer {
		if solid_vert != nil { sdl.ReleaseGPUShader(state.gpu, solid_vert) }
		if vert != nil {
			sdl.ReleaseGPUShader(state.gpu, vert)
		}
		if frag != nil {
			sdl.ReleaseGPUShader(state.gpu, frag)
		}
	}
	if vert == nil || solid_vert == nil || frag == nil {
		return false
	}
	stencil_keep := vector_gpu_stencil_state(.KEEP)
	stencil_inc := vector_gpu_stencil_state(.INCREMENT_AND_CLAMP)
	stencil_dec := vector_gpu_stencil_state(.DECREMENT_AND_CLAMP)
	g.pipeline = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._4, false, {}, true)
	g.pipeline_depth = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._4, true, {}, true)
	g.pipeline_stencil_test = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._4, true, stencil_keep, true)
	g.pipeline_stencil_write = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._4, true, stencil_inc, false)
	g.pipeline_stencil_pop = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._4, true, stencil_dec, false)
	g.pipeline_ss = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, false, {}, true)
	g.pipeline_ss_depth = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, {}, true)
	g.pipeline_ss_stencil_test = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_keep, true)
	g.pipeline_ss_stencil_write = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_inc, false)
	g.pipeline_ss_stencil_pop = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_dec, false)
	for &family, sample_index in g.solid_pipelines {
		for &pipeline, kind in family {
			stencil := kind == 2 ? stencil_keep : kind == 3 ? stencil_inc : kind == 4 ? stencil_dec : sdl.GPUDepthStencilState{}
			pipeline = vector_gpu_create_mesh_pipeline(solid_vert, frag, format, depth_format,
				sample_index == 0 ? ._4 : ._1, kind != 0, stencil, kind < 3, solid = true)
			if pipeline == nil { return false }
			if test_hook_vector_fail_solid_pipeline_after > 0 {
				test_hook_vector_fail_solid_pipeline_after -= 1
				if test_hook_vector_fail_solid_pipeline_after == 0 { return false }
			}
		}
	}
	g.white = gpu_create_white_texture(state.gpu)
	g.sampler = gpu_create_sampler(state.gpu)
	if g.pipeline == nil || g.pipeline_depth == nil ||
	   g.pipeline_stencil_test == nil || g.pipeline_stencil_write == nil || g.pipeline_stencil_pop == nil ||
	   g.pipeline_ss == nil || g.pipeline_ss_depth == nil || g.pipeline_ss_stencil_test == nil || g.pipeline_ss_stencil_write == nil || g.pipeline_ss_stencil_pop == nil ||
	   g.white == nil || g.sampler == nil {
		return false
	}
	success = true
	g.bytes += 4
	vector_gpu_note_peak(0, .Other_Textures)
	return true
}

@(private)
VECTOR_TARGET_SIZE_QUANTUM :: f32(8)

@(private)
vector_target_quantized_size :: proc(span: f32) -> f32 {
	if span <= 0 {
		return VECTOR_TARGET_SIZE_QUANTUM
	}

	return math.ceil(span / VECTOR_TARGET_SIZE_QUANTUM) * VECTOR_TARGET_SIZE_QUANTUM
}

@(private)
vector_gpu_limit :: proc(resource: string, consumed, allowed: u64) -> bool {
	state.vector.last_error = .Limit_Exceeded
	log_errorf("Vector %s consumed %d, allowed %d", resource, consumed, allowed)
	return false
}

@(private)
vector_target_release_textures :: proc(colour, depth, resolved: ^sdl.GPUTexture) {
	if state.gpu == nil {
		return
	}

	if colour != nil {
		sdl.ReleaseGPUTexture(state.gpu, colour)
	}
	if depth != nil {
		sdl.ReleaseGPUTexture(state.gpu, depth)
	}
	if resolved != nil && resolved != colour {
		sdl.ReleaseGPUTexture(state.gpu, resolved)
	}
}

@(private)
vector_gpu_stencil_state :: proc(op: sdl.GPUStencilOp) -> sdl.GPUDepthStencilState {
	face := sdl.GPUStencilOpState{
		fail_op = .KEEP,
		pass_op = op,
		depth_fail_op = .KEEP,
		compare_op = .EQUAL,
	}
	return {
		compare_op = .ALWAYS,
		back_stencil_state = face,
		front_stencil_state = face,
		compare_mask = 0xFF,
		write_mask = 0xFF,
		enable_depth_test = false,
		enable_depth_write = false,
		enable_stencil_test = true,
	}
}

@(private)
vector_gpu_create_mesh_pipeline :: proc(
	vert, frag: ^sdl.GPUShader,
	format, depth_format: sdl.GPUTextureFormat,
	sample_count: sdl.GPUSampleCount,
	with_depth: bool,
	stencil: sdl.GPUDepthStencilState,
	write_colour: bool,
	solid := false,
) -> ^sdl.GPUGraphicsPipeline {
	attributes := [9]sdl.GPUVertexAttribute{
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vector_Vertex, pos))},
		{location = 2, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, colour))},
		{location = 3, buffer_slot = 1, format = .FLOAT2, offset = u32(offset_of(Vector_Instance, origin))},
		{location = 4, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, morph_linear))},
		{location = 5, buffer_slot = 1, format = .FLOAT2, offset = u32(offset_of(Vector_Instance, morph_shift))},
		{location = 6, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, paint))},
		{location = 7, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, grad0))},
		{location = 8, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, combined_linear))},
		{location = 9, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Vector_Instance, combined_shift_focal))},
	}
	vertex_layout := [2]sdl.GPUVertexBufferDescription{
		{slot = 0, pitch = u32(size_of(Vector_Vertex))},
		{slot = 1, pitch = u32(solid ? size_of(Vector_Solid_Instance) : size_of(Vector_Instance)), input_rate = .INSTANCE},
	}
	blend := gpu_vector_blend_state()
	if !write_colour {
		blend.enable_color_write_mask = true
		blend.color_write_mask = {}
	}
	target := sdl.GPUColorTargetDescription{format = format, blend_state = blend}
	return sdl.CreateGPUGraphicsPipeline(state.gpu, {
		vertex_shader = vert,
		fragment_shader = frag,
		vertex_input_state = {
			vertex_buffer_descriptions = raw_data(vertex_layout[:]),
			num_vertex_buffers = 2,
			vertex_attributes = raw_data(attributes[:]),
			num_vertex_attributes = solid ? 5 : u32(len(attributes)),
		},
		primitive_type = .TRIANGLELIST,
		rasterizer_state = {cull_mode = .NONE},
		multisample_state = {sample_count = sample_count},
		depth_stencil_state = stencil,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &target,
			has_depth_stencil_target = with_depth,
			depth_stencil_format = depth_format,
		},
	})
}

@(private)
vector_target_ensure :: proc(target: ^Vector_Target, bounds: Rect, pooled: bool, with_depth: bool, msaa := true) -> bool {
	g := &state.vector.gpu
	if g.format == .INVALID || with_depth && g.depth_format == .INVALID { return false }
	if bounds.w <= 0 || bounds.h <= 0 {
		return false
	}

	// Root scenes grow-only so morphing AABBs do not thrash MSAA allocations.
	// Pooled group/mask targets reuse quantized size classes with grow-only slots.
	need_w := vector_target_quantized_size(math.ceil(bounds.w))
	need_h := vector_target_quantized_size(math.ceil(bounds.h))
	if !pooled {
		fb := vector_gpu_framebuffer_bounds()
		need_w = min(need_w, math.ceil(fb.w))
		need_h = min(need_h, math.ceil(fb.h))
	}
	if pooled {
		if target.colour != nil &&
		   target.has_depth == with_depth &&
		   target.msaa == msaa &&
		   target.alloc_w >= need_w &&
		   target.alloc_h >= need_h {
			target.bounds = bounds
			state.vector.gpu.target_reuses += 1

			return true
		}
	} else if target.colour != nil &&
	   target.has_depth == with_depth &&
	   target.msaa == msaa &&
	   target.alloc_w >= need_w &&
	   target.alloc_h >= need_h {
		target.bounds = bounds
		return true
	}

	alloc_w := pooled ? max(need_w, target.alloc_w) : max(need_w, target.alloc_w)
	alloc_h := pooled ? max(need_h, target.alloc_h) : max(need_h, target.alloc_h)
	colour_size := u64(sdl.GPUTextureFormatTexelBlockSize(g.format))
	depth_size := with_depth ? u64(sdl.GPUTextureFormatTexelBlockSize(g.depth_format)) : 0
	colour_samples := msaa ? u64(5) : u64(1)
	depth_samples := msaa ? u64(4) : u64(1)
	bytes := u64(alloc_w) * u64(alloc_h) * (colour_size * colour_samples + depth_size * (with_depth ? depth_samples : 0))
	// Old and replacement targets coexist until the new textures succeed — reserve peak.
	// Equal-size pooled replaces still allocate a second target before releasing the first.
	if g.bytes + bytes > VECTOR_GPU_BUDGET { return vector_gpu_limit("GPU bytes", g.bytes + bytes, VECTOR_GPU_BUDGET) }
	if pooled && g.pool_bytes + bytes > VECTOR_TARGET_POOL_BUDGET { return vector_gpu_limit("intermediate bytes", g.pool_bytes + bytes, VECTOR_TARGET_POOL_BUDGET) }

	sample_count: sdl.GPUSampleCount = msaa ? ._4 : ._1
	info := sdl.GPUTextureCreateInfo{
		type = .D2,
		format = g.format,
		usage = msaa ? {.COLOR_TARGET} : {.COLOR_TARGET, .SAMPLER},
		width = u32(alloc_w),
		height = u32(alloc_h),
		layer_count_or_depth = 1,
		num_levels = 1,
		sample_count = sample_count,
	}
	colour := sdl.CreateGPUTexture(state.gpu, info)
	depth: ^sdl.GPUTexture
	if with_depth {
		info.format = g.depth_format
		info.usage = {.DEPTH_STENCIL_TARGET}
		depth = sdl.CreateGPUTexture(state.gpu, info)
	}
	resolved: ^sdl.GPUTexture
	if msaa {
		info.format = g.format
		info.usage = {.COLOR_TARGET, .SAMPLER}
		info.sample_count = ._1
		resolved = sdl.CreateGPUTexture(state.gpu, info)
	} else {
		resolved = colour
	}
	if colour == nil || resolved == nil || (with_depth && depth == nil) {
		vector_target_release_textures(colour, depth, msaa ? resolved : nil)

		return false
	}

	state.vector.gpu.target_creates += 1
	vector_gpu_note_peak(bytes, pooled ? .Intermediate_Targets : .Scene_Targets)
	vector_target_release(target, pooled)
	if !pooled {
		frame := vector_gpu_frame()
		if &frame.root == target {
			frame.root_view_origin_set = false
		}
	}
	target.colour = colour
	target.depth = depth
	target.resolved = resolved
	target.bounds = bounds
	target.alloc_w = alloc_w
	target.alloc_h = alloc_h
	target.has_depth = with_depth
	target.msaa = msaa
	target.bytes = bytes
	g.bytes += bytes
	if pooled {
		g.pool_bytes += bytes
	}
	return true
}

@(private)
Vector_Index_Upload :: struct { offset, size: u64 }

@(private)
vector_gpu_index_upload_ranges :: proc(indices, previous: []u32, valid: bool) -> (ranges: [dynamic]Vector_Index_Upload, bytes: u64, ok: bool) {
	if len(indices) == 0 { return nil, 0, true }
	allocation_error: mem.Allocator_Error
	ranges, allocation_error = make([dynamic]Vector_Index_Upload, 0, 16, context.temp_allocator)
	if allocation_error != nil { return nil, 0, false }
	bytes = u64(len(indices)) * size_of(u32)
	if !valid || len(indices) != len(previous) {
		_, err := append(&ranges, Vector_Index_Upload{size = bytes})
		return ranges, bytes, err == nil
	}
	total := bytes
	bytes = 0
	for offset := u64(0); offset < total; offset += 4096 {
		size := min(u64(4096), total - offset)
		current := (cast([^]u8)raw_data(indices))[offset:]
		old := (cast([^]u8)raw_data(previous))[offset:]
		if mem.compare_byte_ptrs(current, old, int(size)) == 0 { continue }
		if len(ranges) > 0 && ranges[len(ranges) - 1].offset + ranges[len(ranges) - 1].size == offset {
			ranges[len(ranges) - 1].size += size
		} else if _, err := append(&ranges, Vector_Index_Upload{offset, size}); err != nil { return ranges, bytes, false }
		bytes += size
	}
	return ranges, bytes, true
}

@(private)
vector_gpu_upload :: proc(cmd: ^sdl.GPUCommandBuffer) -> bool {
	f := vector_frame()
	frame := vector_gpu_frame()
	solid := true
	for &instance in f.instances { if instance.paint[0] != 0 { solid = false; break } }
	vertex_count := len(f.vertices)
	index_count := len(f.indices)
	vertex_bytes := u64(vertex_count) * size_of(Vector_Vertex)
	index_bytes := u64(index_count) * size_of(u32)
	index_ranges, index_upload_bytes, index_ok := vector_gpu_index_upload_ranges(f.indices[:], frame.index_snapshot[:], frame.index_snapshot_valid && frame.buffers[.Index] != nil)
	if !index_ok || !vector_reserve(&frame.index_snapshot, index_count, VECTOR_MAX_FRAME_INDICES) { return false }
	sizes := [Vector_Buffer]u64{
		.Vertex = vertex_bytes,
		.Index = index_upload_bytes,
		.Instance = u64(len(f.instances)) * u64(solid ? size_of(Vector_Solid_Instance) : size_of(Vector_Instance)),
		.Indirect = u64(len(f.commands)) * size_of(sdl.GPUIndexedIndirectDrawCommand),
	}
	sources := [Vector_Buffer]rawptr{
		.Vertex = raw_data(f.vertices) if len(f.vertices) > 0 else nil,
		.Index = raw_data(f.indices) if len(f.indices) > 0 else nil,
		.Instance = raw_data(f.instances), .Indirect = raw_data(f.commands),
	}
	usages := [Vector_Buffer]sdl.GPUBufferUsageFlags{
		.Vertex = {.VERTEX}, .Index = {.INDEX}, .Instance = {.VERTEX}, .Indirect = {.INDIRECT},
	}
	bytes := u64(0)
	capacities := frame.capacities
	for kind in Vector_Buffer {
		bytes += sizes[kind]
		needed := index_bytes if kind == .Index else sizes[kind]
		capacities[kind] = max(capacities[kind], needed)
	}
	ramp_upload_bytes := u64(len(f.ramp_pixels))
	needed_ramp_rows := f.ramp_rows
	if bytes == 0 && ramp_upload_bytes == 0 {
		return true
	}
	allocated_ramp_rows := max(frame.ramp_rows, needed_ramp_rows)
	new_transfer_capacity := max(bytes + ramp_upload_bytes, frame.transfer_capacity)
	new_buffer_bytes := new_transfer_capacity
	for capacity in capacities { new_buffer_bytes += capacity }
	// Retained ramp textures never shrink; account for allocated height even when
	// this frame needs fewer (or zero) gradient rows.
	new_ramp_bytes := u64(0)
	if allocated_ramp_rows > 0 || frame.ramp != nil {
		rows := allocated_ramp_rows if allocated_ramp_rows > 0 else frame.ramp_rows
		new_ramp_bytes = u64(VECTOR_RAMP_WIDTH) * u64(rows) * 4
	}
	budget_delta := u64(0)
	for kind in Vector_Buffer { if sizes[kind] > frame.capacities[kind] { budget_delta += capacities[kind] } }
	if bytes + ramp_upload_bytes > frame.transfer_capacity { budget_delta += new_transfer_capacity }
	ramp_delta := needed_ramp_rows > 0 && (frame.ramp == nil || frame.ramp_rows < needed_ramp_rows) ? new_ramp_bytes : 0
	budget_delta += ramp_delta
	// Replacement buffers/ramps coexist with live ones until install succeeds.
	if state.vector.gpu.bytes + budget_delta > VECTOR_GPU_BUDGET {
		return vector_gpu_limit("GPU bytes", state.vector.gpu.bytes + budget_delta, VECTOR_GPU_BUDGET)
	}
	buffers := frame.buffers
	transfer := frame.transfer
	ramp_texture := frame.ramp
	success := false
	defer if !success {
		for kind in Vector_Buffer {
			if buffers[kind] != nil && buffers[kind] != frame.buffers[kind] { sdl.ReleaseGPUBuffer(state.gpu, buffers[kind]) }
		}
		if transfer != nil && transfer != frame.transfer { sdl.ReleaseGPUTransferBuffer(state.gpu, transfer) }
		if ramp_texture != nil && ramp_texture != frame.ramp { sdl.ReleaseGPUTexture(state.gpu, ramp_texture) }
	}
	for kind in Vector_Buffer {
		if sizes[kind] > frame.capacities[kind] {
			buffers[kind] = sdl.CreateGPUBuffer(state.gpu, {usage = usages[kind], size = u32(capacities[kind])})
			if buffers[kind] == nil { return false }
			if test_hook_vector_fail_buffer_after > 0 {
				test_hook_vector_fail_buffer_after -= 1
				if test_hook_vector_fail_buffer_after == 0 { return false }
			}
		}
	}
	need_transfer := bytes + ramp_upload_bytes
	if need_transfer > frame.transfer_capacity {
		transfer = sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = u32(new_transfer_capacity)})
		if transfer == nil { return false }
		if test_hook_vector_fail_transfer { return false }
	}
	if needed_ramp_rows > 0 && (frame.ramp == nil || frame.ramp_rows < needed_ramp_rows) {
		ramp_texture = sdl.CreateGPUTexture(state.gpu, {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(VECTOR_RAMP_WIDTH),
			height = u32(needed_ramp_rows),
			layer_count_or_depth = 1,
			num_levels = 1,
		})
		if ramp_texture == nil {
			return false
		}
		allocated_ramp_rows = needed_ramp_rows
		new_ramp_bytes = u64(VECTOR_RAMP_WIDTH) * u64(allocated_ramp_rows) * 4
	}
	// Map/copy before installing replacements so a failed upload leaves the
	// live frame buffers untouched and the defer releases only locals.
	if test_hook_vector_fail_map { return false }
	if need_transfer > 0 {
		// The slot fence has completed before upload, so its staging storage is reusable.
		data := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
		if data == nil {
			return false
		}
		// Tight pack only the buffers that upload this frame, in Vector_Buffer order.
		offset := u64(0)
		for kind in Vector_Buffer {
			if sizes[kind] == 0 {
				continue
			}
			dst := (cast([^]u8)data)[offset:]
			if kind == .Index {
				packed := u64(0)
				for region in index_ranges {
					mem.copy(dst[packed:], (cast([^]u8)sources[kind])[region.offset:], int(region.size))
					packed += region.size
				}
			} else if kind == .Instance && solid {
				instances := cast([^]Vector_Solid_Instance)dst
				for &instance, i in f.instances {
					instances[i] = {colour = instance.colour, origin = instance.origin, morph_linear = instance.morph_linear, morph_shift = instance.morph_shift}
				}
			} else if sources[kind] != nil { mem.copy(dst, sources[kind], int(sizes[kind])) }
			offset += sizes[kind]
		}
		if ramp_upload_bytes > 0 {
			mem.copy((cast([^]u8)data)[offset:], raw_data(f.ramp_pixels), int(ramp_upload_bytes))
		}
		sdl.UnmapGPUTransferBuffer(state.gpu, transfer)
		copy_pass := sdl.BeginGPUCopyPass(cmd)
		if copy_pass == nil {
			return false
		}
		offset = 0
		for kind in Vector_Buffer {
			if sizes[kind] > 0 {
				if kind == .Index {
					packed := offset
					for region in index_ranges {
						sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transfer, offset = u32(packed)}, {buffer = buffers[kind], offset = u32(region.offset), size = u32(region.size)}, false)
						packed += region.size
					}
				} else { sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transfer, offset = u32(offset)}, {buffer = buffers[kind], size = u32(sizes[kind])}, false) }
				offset += sizes[kind]
			}
		}
		if ramp_upload_bytes > 0 && ramp_texture != nil && needed_ramp_rows > 0 {
			sdl.UploadToGPUTexture(
				copy_pass,
				{transfer_buffer = transfer, offset = u32(offset)},
				{
					texture = ramp_texture,
					w = u32(VECTOR_RAMP_WIDTH),
					h = u32(needed_ramp_rows),
					d = 1,
				},
				false,
			)
		}
		sdl.EndGPUCopyPass(copy_pass)
	}
	for kind in Vector_Buffer {
		if frame.buffers[kind] != nil && buffers[kind] != frame.buffers[kind] { sdl.ReleaseGPUBuffer(state.gpu, frame.buffers[kind]) }
	}
	vector_gpu_note_peak(budget_delta - ramp_delta, .Buffers)
	vector_gpu_note_peak(ramp_delta, .Gradient_Ramps)
	state.vector.gpu.peak_bytes = max(state.vector.gpu.peak_bytes, state.vector.gpu.bytes + budget_delta)
	if frame.transfer != nil && transfer != frame.transfer { sdl.ReleaseGPUTransferBuffer(state.gpu, frame.transfer) }
	if frame.ramp != nil && ramp_texture != frame.ramp {
		sdl.ReleaseGPUTexture(state.gpu, frame.ramp)
	}
	state.vector.gpu.bytes -= frame.buffer_bytes + frame.ramp_bytes
	frame.buffers, frame.capacities = buffers, capacities
	frame.transfer, frame.transfer_capacity = transfer, new_transfer_capacity
	frame.buffer_bytes = new_buffer_bytes
	frame.ramp = ramp_texture
	if frame.ramp != nil {
		frame.ramp_rows = max(frame.ramp_rows, allocated_ramp_rows)
		frame.ramp_bytes = u64(VECTOR_RAMP_WIDTH) * u64(frame.ramp_rows) * 4
	} else {
		frame.ramp_rows = 0
		frame.ramp_bytes = 0
	}
	state.vector.gpu.bytes += frame.buffer_bytes + frame.ramp_bytes
	resize(&frame.index_snapshot, index_count)
	for region in index_ranges { mem.copy((cast([^]u8)raw_data(frame.index_snapshot))[region.offset:], (cast([^]u8)raw_data(f.indices))[region.offset:], int(region.size)) }
	frame.index_snapshot_valid = true
	frame.solid_instances = solid
	success = true

	return true
}

@(private)
vector_gpu_pool_target :: proc(bounds: Rect, msaa, with_depth: bool) -> (index: int, ok: bool) {
	frame := vector_gpu_frame()
	need_w := vector_target_quantized_size(math.ceil(bounds.w))
	need_h := vector_target_quantized_size(math.ceil(bounds.h))
	index = -1
	best_waste: f32 = max(f32)
	for target, i in frame.pool {
		if target.in_use || target.msaa != msaa || target.has_depth != with_depth {

			continue
		}

		if target.alloc_w >= need_w && target.alloc_h >= need_h {
			waste := (target.alloc_w - need_w) + (target.alloc_h - need_h)
			if waste < best_waste {
				best_waste = waste
				index = i
			}
		}
	}
	if index < 0 {
		for target, i in frame.pool {
			if !target.in_use && !target.used_this_encode {
				index = i

				break
			}
		}
	}
	if index < 0 { index = len(frame.pool) }
	if index == len(frame.pool) {
		if _, err := append(&frame.pool, Vector_Target{}); err != nil {
			return -1, false
		}
	}
	if !vector_target_ensure(&frame.pool[index], bounds, true, with_depth, msaa) {
		return -1, false
	}
	frame.pool_cursor += 1
	frame.pool[index].in_use, frame.pool[index].used_this_encode = true, true
	return index, true
}

@(private)
vector_gpu_select_pipeline :: proc(
	msaa: bool,
	with_depth: bool,
	stencil_depth: u8,
	mode: Vector_Stencil_Mode,
) -> ^sdl.GPUGraphicsPipeline {
	g := &state.vector.gpu
	if vector_gpu_frame().solid_instances {
		kind := mode == .Write ? 3 : mode == .Pop ? 4 : stencil_depth > 0 ? 2 : with_depth ? 1 : 0
		return g.solid_pipelines[msaa ? 0 : 1][kind]
	}
	if !msaa {
		switch mode {
		case .Write:
			return g.pipeline_ss_stencil_write
		case .Pop:
			return g.pipeline_ss_stencil_pop
		case .Draw:
			if stencil_depth > 0 {
				return g.pipeline_ss_stencil_test
			}
			if with_depth { return g.pipeline_ss_depth }
			return g.pipeline_ss
		}
	}
	switch mode {
	case .Write:
		return g.pipeline_stencil_write
	case .Pop:
		return g.pipeline_stencil_pop
	case .Draw:
		if stencil_depth > 0 {
			return g.pipeline_stencil_test
		}
		if with_depth {
			return g.pipeline_depth
		}
		return g.pipeline
	}
	return g.pipeline
}

@(private)
vector_gpu_bind_mesh :: proc(
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	bounds: Rect,
	msaa: bool,
	with_depth: bool,
	stencil_depth: u8,
	mode: Vector_Stencil_Mode = .Draw,
) {
	pipeline := vector_gpu_select_pipeline(msaa, with_depth, stencil_depth, mode)
	sdl.BindGPUGraphicsPipeline(pass, pipeline)
	if mode != .Draw || stencil_depth > 0 {
		sdl.SetGPUStencilReference(pass, stencil_depth)
	}
	bindings := [2]sdl.GPUBufferBinding{
		{buffer = vector_gpu_frame().buffers[.Vertex]}, {buffer = vector_gpu_frame().buffers[.Instance]},
	}
	sdl.BindGPUVertexBuffers(pass, 0, raw_data(bindings[:]), 2)
	sdl.BindGPUIndexBuffer(pass, {buffer = vector_gpu_frame().buffers[.Index]}, ._32BIT)
	view := [4]f32{bounds.x, bounds.y, bounds.w, bounds.h}
	sdl.PushGPUVertexUniformData(cmd, 0, &view, u32(size_of(view)))
}

@(private)
vector_gpu_draw_clip_mesh :: proc(
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	record: Vector_Record,
	bounds, clip: Rect,
	msaa: bool,
	stencil_depth: u8,
	mode: Vector_Stencil_Mode,
	viewport_origin: Vec2 = {},
) {
	visible := rect_intersect(clip, bounds)
	left := max(f32(0), math.floor(visible.x - bounds.x))
	top := max(f32(0), math.floor(visible.y - bounds.y))
	right := min(bounds.w, math.ceil(visible.x + visible.w - bounds.x))
	bottom := min(bounds.h, math.ceil(visible.y + visible.h - bounds.y))
	if right <= left || bottom <= top {
		return
	}

	ref := mode == .Write ? stencil_depth : stencil_depth + 1
	vector_gpu_bind_mesh(cmd, pass, bounds, msaa, true, ref, mode)
	sdl.SetGPUScissor(pass, {x = i32(left + viewport_origin.x), y = i32(top + viewport_origin.y), w = i32(right - left), h = i32(bottom - top)})
	g := &state.vector.gpu
	frame := vector_gpu_frame()
	ramp := frame.ramp != nil ? frame.ramp : g.white
	bindings := [3]sdl.GPUTextureSamplerBinding{
		{texture = g.white, sampler = g.sampler},
		{texture = g.white, sampler = g.sampler},
		{texture = ramp, sampler = g.sampler},
	}
	sdl.BindGPUFragmentSamplers(pass, 0, raw_data(bindings[:]), 3)
	paint := [12]f32{}
	sdl.PushGPUFragmentUniformData(cmd, 0, &paint, u32(size_of(paint)))
	sdl.DrawGPUIndexedPrimitivesIndirect(
		pass,
		frame.buffers[.Indirect],
		record.command * u32(size_of(sdl.GPUIndexedIndirectDrawCommand)),
		1,
	)
}

@(private)
vector_gpu_draw_list :: proc(
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	first: int,
	bounds, clip: Rect,
	merged_commands: u32 = 0,
	msaa := true,
	with_depth := false,
	stencil_depth: u8 = 0,
	viewport_origin: Vec2 = {},
) {
	g := &state.vector.gpu
	frame := vector_gpu_frame()
	index := first
	for index >= 0 {
		record := vector_frame().records[index]
		if record.opacity > 0 && record.bounds.w > 0 && record.bounds.h > 0 {
			if record.kind == .Clip {
				child_clip := rect_intersect(clip, record.bounds)
				if record.geometric {
					if stencil_depth >= u8(VECTOR_MAX_CLIP_DEPTH) {
						index = record.next
						continue
					}
					vector_gpu_draw_clip_mesh(cmd, pass, record, bounds, child_clip, msaa, stencil_depth, .Write, viewport_origin)
					vector_gpu_draw_list(
						cmd,
						pass,
						record.first_child,
						bounds,
						child_clip,
						msaa = msaa,
						with_depth = true,
						stencil_depth = stencil_depth + 1,
						viewport_origin = viewport_origin,
					)
					vector_gpu_draw_clip_mesh(cmd, pass, record, bounds, child_clip, msaa, stencil_depth, .Pop, viewport_origin)
				} else {
					vector_gpu_draw_list(
						cmd,
						pass,
						record.first_child,
						bounds,
						child_clip,
						msaa = msaa,
						with_depth = with_depth,
						stencil_depth = stencil_depth,
						viewport_origin = viewport_origin,
					)
				}
			} else {
				paint := [12]f32{4 = 1, 5 = 1, 6 = 1, 7 = 1}
				content, mask := g.white, g.white
				draw_clip := clip
				if record.kind == .Group || record.kind == .Mask {
					output := frame.outputs[index]
					if output.content < 0 {
						index = record.next
						continue
					}
					content = frame.pool[output.content].resolved
					content_target := frame.pool[output.content]
					paint[4], paint[5] = record.bounds.w / content_target.alloc_w, record.bounds.h / content_target.alloc_h
					paint[8], paint[9] = output.content_uv.x, output.content_uv.y
					paint[0] = 1
					if record.kind == .Mask {
						mask = frame.pool[output.mask].resolved
						mask_target := frame.pool[output.mask]
						paint[6], paint[7] = record.bounds.w / mask_target.alloc_w, record.bounds.h / mask_target.alloc_h
						paint[10], paint[11] = output.mask_uv.x, output.mask_uv.y
						paint[1] = record.mask_kind == .Alpha ? 1 : 2
						if record.clip.w > 0 && record.clip.h > 0 {
							draw_clip = rect_intersect(draw_clip, record.clip)
						}
					}
				}
				visible := rect_intersect(draw_clip, bounds)
				left := max(f32(0), math.floor(visible.x - bounds.x))
				top := max(f32(0), math.floor(visible.y - bounds.y))
				right := min(bounds.w, math.ceil(visible.x + visible.w - bounds.x))
				bottom := min(bounds.h, math.ceil(visible.y + visible.h - bounds.y))
				if right > left && bottom > top {
					vector_gpu_bind_mesh(cmd, pass, bounds, msaa, with_depth || stencil_depth > 0, stencil_depth, .Draw)
					sdl.SetGPUScissor(pass, {x = i32(left + viewport_origin.x), y = i32(top + viewport_origin.y), w = i32(right - left), h = i32(bottom - top)})
					ramp := frame.ramp != nil ? frame.ramp : g.white
					bindings := [3]sdl.GPUTextureSamplerBinding{
						{texture = content, sampler = g.sampler},
						{texture = mask, sampler = g.sampler},
						{texture = ramp, sampler = g.sampler},
					}
					sdl.BindGPUFragmentSamplers(pass, 0, raw_data(bindings[:]), 3)
					sdl.PushGPUFragmentUniformData(cmd, 0, &paint, u32(size_of(paint)))
					count := merged_commands > 0 ? merged_commands : 1
					sdl.DrawGPUIndexedPrimitivesIndirect(pass, frame.buffers[.Indirect], record.command * u32(size_of(sdl.GPUIndexedIndirectDrawCommand)), count)
				}
			}
		}
		index = record.next
	}
}

@(private)
vector_gpu_render_target :: proc(cmd: ^sdl.GPUCommandBuffer, target_index, first: int, scissor: Rect = {}) -> bool {
	if test_hook_vector_fail_pass_after > 0 {
		test_hook_vector_fail_pass_after -= 1
		if test_hook_vector_fail_pass_after == 0 {
			return false
		}
	}
	target := vector_gpu_frame().pool[target_index]
	samples := target.msaa ? u64(4) : u64(1)
	work := u64(target.alloc_w) * u64(target.alloc_h) * samples
	if work > VECTOR_MAX_SAMPLE_WORK - min(state.vector.gpu.sample_work, VECTOR_MAX_SAMPLE_WORK) {
		return vector_gpu_limit("sample-pixels", state.vector.gpu.sample_work + work, VECTOR_MAX_SAMPLE_WORK)
	}
	state.vector.gpu.sample_work += work
	state.vector.gpu.command_visits += 1
	if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS {
		return false
	}

	colour := sdl.GPUColorTargetInfo{
		texture = target.colour,
		load_op = .CLEAR,
		store_op = target.msaa ? .RESOLVE : .STORE,
		resolve_texture = target.msaa ? target.resolved : nil,
	}
	depth := sdl.GPUDepthStencilTargetInfo{
		texture = target.depth,
		load_op = .CLEAR,
		store_op = .DONT_CARE,
		stencil_load_op = .CLEAR,
		stencil_store_op = .DONT_CARE,
	}
	pass := sdl.BeginGPURenderPass(cmd, &colour, 1, target.has_depth ? &depth : nil)
	if pass == nil {
		return false
	}
	clip := target.bounds
	if scissor.w > 0 && scissor.h > 0 {
		clip = rect_intersect(clip, scissor)
	}
	view := Rect{target.bounds.x, target.bounds.y, target.alloc_w, target.alloc_h}
	vector_gpu_draw_list(cmd, pass, first, view, clip, msaa = target.msaa, with_depth = target.has_depth)
	sdl.EndGPURenderPass(pass)
	return true
}

@(private)
vector_gpu_prepare_list :: proc(cmd: ^sdl.GPUCommandBuffer, first: int) -> bool {
	index := first
	for index >= 0 {
		record := vector_frame().records[index]
		if record.opacity > 0 && record.bounds.w > 0 && record.bounds.h > 0 {
			if !vector_gpu_prepare_list(cmd, record.first_child) || !vector_gpu_prepare_list(cmd, record.first_mask) {
				return false
			}
			if record.kind == .Group || record.kind == .Mask {
				composite_work := u64(record.bounds.w) * u64(record.bounds.h) * 4
				if composite_work > VECTOR_MAX_SAMPLE_WORK - min(state.vector.gpu.sample_work, VECTOR_MAX_SAMPLE_WORK) {
					return false
				}
				state.vector.gpu.sample_work += composite_work
				state.vector.gpu.command_visits += 1
				if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS {
					return false
				}
				content_msaa := vector_gpu_list_needs_msaa(record.first_child)
				content, ok := vector_gpu_pool_target(record.bounds, content_msaa, vector_gpu_list_needs_stencil(record.first_child))
				if !ok || !vector_gpu_render_target(cmd, content, record.first_child) {
					return false
				}
				vector_gpu_release_list_outputs(record.first_child)
				vector_gpu_frame().outputs[index] = {content = content, mask = -1}
				if record.kind == .Mask {
					// Masks keep 4× MSAA so curved boundaries retain coverage quality.
					mask, mask_ok := vector_gpu_pool_target(record.bounds, true, vector_gpu_list_needs_stencil(record.first_mask))
					mask_scissor := record.clip
					if !mask_ok || !vector_gpu_render_target(cmd, mask, record.first_mask, mask_scissor) {
						return false
					}
					vector_gpu_release_list_outputs(record.first_mask)
					vector_gpu_frame().outputs[index].mask = mask
				}
			}
		}
		index = record.next
	}
	return true
}

@(private)
vector_gpu_draw_submission :: proc(index: int) {
	draw := vector_frame().draws[index]
	if draw.failed {
		return
	}
	clip := draw.clip
	clip = {clip.x * state.dpi.scale, clip.y * state.dpi.scale, clip.w * state.dpi.scale, clip.h * state.dpi.scale}
	root := vector_gpu_frame().root
	vector_gpu_draw_list(
		batch_current().cmd,
		batch_current().pass,
		draw.first,
		root.bounds,
		clip,
		draw.merged_commands,
		msaa = true,
		with_depth = root.has_depth,
	)
}

/*
True when the recorded frame needs a cleared depth/stencil attachment.

Mesh-only scenes use rectangular scissor clips and do not sample depth; skipping
the MSAA depth clear removes a full-target write on the hot path. Groups, masks
and geometric clips keep the cleared attachment for stencil nesting.
*/
@(private)
vector_gpu_frame_needs_depth_clear :: proc() -> bool {
	for draw in vector_frame().draws { if !draw.failed && vector_gpu_list_needs_stencil(draw.first) { return true } }

	return false
}

@(private)
vector_gpu_list_needs_msaa :: proc(first: int) -> bool {
	for index := first; index >= 0; index = vector_frame().records[index].next {
		record := vector_frame().records[index]
		if record.kind == .Mesh || record.kind == .Path { return true }
		if record.kind == .Clip && (record.geometric || vector_gpu_list_needs_msaa(record.first_child)) { return true }
	}
	return false
}

@(private)
vector_gpu_list_needs_stencil :: proc(first: int) -> bool {
	for index := first; index >= 0; index = vector_frame().records[index].next {
		record := vector_frame().records[index]
		if record.kind == .Clip && (record.geometric || vector_gpu_list_needs_stencil(record.first_child)) { return true }
	}
	return false
}

// A parent's completed render pass has consumed these resolved child images.
// Reuse exact-sized textures in later passes; never replace an image already
// referenced by this command buffer, so allocation accounting stays fence-safe.
@(private)
vector_gpu_release_list_outputs :: proc(first: int) {
	frame := vector_gpu_frame()
	for index := first; index >= 0; index = vector_frame().records[index].next {
		record := vector_frame().records[index]
		if record.kind == .Group || record.kind == .Mask {
			output := frame.outputs[index]
			for target in ([2]int{output.content, output.mask}) {
				if target < 0 { continue }
				if frame.pool[target].atlas_refs > 0 { frame.pool[target].atlas_refs -= 1 }
				if frame.pool[target].atlas_refs == 0 { frame.pool[target].in_use = false }
			}
			frame.outputs[index] = {content = -1, mask = -1}
		} else if record.kind == .Clip { vector_gpu_release_list_outputs(record.first_child) }
	}
}

/*
Framebuffer rectangle in physical pixels for the current DPI.
*/
@(private)
vector_gpu_framebuffer_bounds :: proc() -> Rect {
	scale := state.dpi.scale
	if scale <= 0 {
		scale = 1
	}

	return {0, 0, f32(state.dpi.logical_w) * scale, f32(state.dpi.logical_h) * scale}
}

@(private)
vector_gpu_expand_rect :: proc(r: Rect, bounds: ^Rect, has: ^bool) {
	if r.w <= 0 || r.h <= 0 {
		return
	}

	if !has^ {
		bounds^ = r
		has^ = true
		return
	}

	bounds^ = rect_union(bounds^, r)
}

@(private)
vector_gpu_expand_point :: proc(px, py: f32, bounds: ^Rect, has: ^bool) {
	if !has^ {
		bounds^ = {px, py, 0, 0}
		has^ = true
		return
	}

	x0 := min(bounds.x, px)
	y0 := min(bounds.y, py)
	x1 := max(bounds.x + bounds.w, px)
	y1 := max(bounds.y + bounds.h, py)
	bounds^ = {x0, y0, x1 - x0, y1 - y0}
}

@(private)
vector_gpu_snap_pad_clamp_bounds :: proc(bounds: Rect) -> Rect {
	fb := vector_gpu_framebuffer_bounds()
	padded := bounds
	padded.x -= VECTOR_SCENE_AA_PAD
	padded.y -= VECTOR_SCENE_AA_PAD
	padded.w += 2 * VECTOR_SCENE_AA_PAD
	padded.h += 2 * VECTOR_SCENE_AA_PAD
	x0 := math.floor(padded.x)
	y0 := math.floor(padded.y)
	x1 := math.ceil(padded.x + padded.w)
	y1 := math.ceil(padded.y + padded.h)
	padded = {x0, y0, max(f32(1), x1 - x0), max(f32(1), y1 - y0)}
	clipped := rect_intersect(padded, fb)
	if clipped.w <= 0 || clipped.h <= 0 {
		return fb
	}

	return clipped
}

/*
Content-bounded MSAA root covering recorded vectors and UI vertices, plus AA pad,
snapped and clamped to the framebuffer. Empty content uses the full framebuffer.
*/
@(private)
vector_gpu_compute_composite_bounds :: proc() -> Rect {
	fb := vector_gpu_framebuffer_bounds()
	scale := state.dpi.scale
	if scale <= 0 {
		scale = 1
	}

	bounds: Rect
	has := false
	for record in vector_frame().records {
		if record.opacity > 0 {
			vector_gpu_expand_rect(record.bounds, &bounds, &has)
		}
	}
	for vertex in batch_current().vertices {
		vector_gpu_expand_point(vertex.pos[0] * scale, vertex.pos[1] * scale, &bounds, &has)
	}
	if !has {
		return fb
	}

	return vector_gpu_snap_pad_clamp_bounds(bounds)
}

@(private)
vector_gpu_place_view :: proc(
	content: Rect,
	alloc_w, alloc_h: f32,
	origin: ^Vec2,
	origin_set: ^bool,
) -> Rect {
	fb := vector_gpu_framebuffer_bounds()
	view_x := origin.x
	view_y := origin.y
	fits := origin_set^ &&
		content.x >= view_x &&
		content.y >= view_y &&
		content.x + content.w <= view_x + alloc_w &&
		content.y + content.h <= view_y + alloc_h
	if !fits {
		view_x = min(max(content.x, 0), max(f32(0), fb.w - alloc_w))
		view_y = min(max(content.y, 0), max(f32(0), fb.h - alloc_h))
		origin^ = {view_x, view_y}
		origin_set^ = true
	}

	return {view_x, view_y, alloc_w, alloc_h}
}

@(private)
vector_gpu_set_ortho_for_bounds :: proc(bounds: Rect) {
	scale := state.dpi.scale
	if scale <= 0 {
		scale = 1
	}

	lx := bounds.x / scale
	ly := bounds.y / scale
	lw := bounds.w / scale
	lh := bounds.h / scale
	state.gpu_state.proj_mat = linalg.matrix_ortho3d_f32(lx, lx + lw, ly + lh, ly, -1, 1)
}

/*
Blocks until the current GPU frame slot's fence completes and releases it.
*/
@(private)
vector_gpu_wait_slot_fence :: proc(frame: ^Vector_GPU_Frame) -> bool {
	if frame.fence == nil {
		return true
	}

	if !sdl.WaitForGPUFences(state.gpu, true, &frame.fence, 1) {
		return false
	}

	sdl.ReleaseGPUFence(state.gpu, frame.fence)
	frame.fence = nil
	return true
}

// Encodes a complete scene before swapchain acquisition. Group targets are
// produced before the shared MSAA pass, keeping submissions atomic there.
@(private)
vector_gpu_encode_frame :: proc(cmd: ^sdl.GPUCommandBuffer, format: sdl.GPUTextureFormat, background: sdl.FColor, failed_submission: ^int = nil) -> bool {
	if failed_submission != nil {
		failed_submission^ = -1
	}
	if !vector_gpu_init(format) {
		return false
	}
	frame := vector_gpu_frame()
	fence_start := time.tick_now()
	if !vector_gpu_wait_slot_fence(frame) {
		return false
	}
	fence_ms := time.duration_milliseconds(time.tick_since(fence_start))

	frame.pool_cursor = 0
	for &target in frame.pool { target.in_use, target.used_this_encode, target.atlas_refs = false, false, 0 }
	content := vector_gpu_compute_composite_bounds()
	needs_depth_clear := vector_gpu_frame_needs_depth_clear()
	// Geometric clips need root stencil; other composition uses pooled targets.
	if !vector_target_ensure(&frame.root, content, false, needs_depth_clear) {
		return false
	}
	frame.root.bounds = vector_gpu_place_view(
		content,
		frame.root.alloc_w,
		frame.root.alloc_h,
		&frame.root_view_origin,
		&frame.root_view_origin_set,
	)
	bounds := frame.root.bounds
	root_samples := u64(frame.root.alloc_w) * u64(frame.root.alloc_h) * 4
	if root_samples > VECTOR_MAX_SAMPLE_WORK - min(state.vector.gpu.sample_work, VECTOR_MAX_SAMPLE_WORK) {
		return vector_gpu_limit("sample-pixels", state.vector.gpu.sample_work + root_samples, VECTOR_MAX_SAMPLE_WORK)
	}
	state.vector.gpu.sample_work += root_samples
	state.vector.gpu.command_visits += 1
	if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS {
		return false
	}

	// Every ordered batch entry is visited on every replay, including UI.
	visits := u64(len(batch_current().segments))
	if visits > VECTOR_MAX_COMMAND_VISITS - state.vector.gpu.command_visits { return false }
	state.vector.gpu.command_visits += visits

	clear(&frame.outputs)
	if resize(&frame.outputs, len(vector_frame().records)) != nil {
		return false
	}
	for &output in frame.outputs {
		output = {content = -1, mask = -1}
	}

	upload_start := time.tick_now()
	if !batch_upload(cmd) || !vector_gpu_upload(cmd) {
		return false
	}
	upload_ms := time.duration_milliseconds(time.tick_since(upload_start))

	record_start := time.tick_now()
	if len(vector_frame().draws) >= 8 && !state.vector.gpu.atlas_disabled {
		for begin := 0; begin < len(vector_frame().draws); begin += 32 {
			failed := -1
			if !vector_gpu_prepare_atlas_batch(cmd, begin, min(begin + 32, len(vector_frame().draws)), &failed) {
				// Retry the complete immutable frame through individual targets if
				// atlas packing, allocation or encoding cannot complete.
				state.vector.gpu.atlas_disabled = true
				if failed_submission != nil { failed_submission^ = -2 }
				return false
			}
		}
	} else {
		for &draw, draw_index in vector_frame().draws {
			if !draw.failed && !vector_gpu_prepare_list(cmd, draw.first) {
				if failed_submission != nil { failed_submission^ = draw_index }
				return false
			}
		}
	}

	colour := sdl.GPUColorTargetInfo{
		texture = frame.root.colour,
		load_op = .CLEAR,
		clear_color = background,
		store_op = .RESOLVE,
		resolve_texture = frame.root.resolved,
	}
	pass: ^sdl.GPURenderPass
	if frame.root.has_depth {
		depth_info := sdl.GPUDepthStencilTargetInfo{
			texture = frame.root.depth,
			load_op = .CLEAR,
			store_op = .DONT_CARE,
			stencil_load_op = .CLEAR,
			stencil_store_op = .DONT_CARE,
		}
		pass = sdl.BeginGPURenderPass(cmd, &colour, 1, &depth_info)
	} else {
		pass = sdl.BeginGPURenderPass(cmd, &colour, 1, nil)
	}
	if pass == nil {
		return false
	}

	saved_proj := state.gpu_state.proj_mat
	vector_gpu_set_ortho_for_bounds(bounds)
	draw_begin(cmd, pass, state.dpi)
	batch_flush_draws()
	batch_current().cmd = nil
	batch_current().pass = nil
	sdl.EndGPURenderPass(pass)
	state.gpu_state.proj_mat = saved_proj
	record_ms := time.duration_milliseconds(time.tick_since(record_start))

	state.vector.gpu.encode_fence_ms = fence_ms
	state.vector.gpu.encode_upload_ms = upload_ms
	state.vector.gpu.encode_record_ms = record_ms
	return true
}

/*
Releases pooled targets after a cancelled encode. A retry uploads the immutable
frame buffers again and rebuilds intermediate images from the remaining draws.
*/
@(private)
vector_gpu_reset_after_cancelled_encode :: proc() {
	frame := vector_gpu_frame()
	frame.index_snapshot_valid = false
	for &target in frame.pool {
		vector_target_release(&target, true)
		target = {}
	}

	frame.pool_cursor = 0
	clear(&frame.outputs)
}

@(private)
vector_gpu_prepare_frame :: proc(format: sdl.GPUTextureFormat, background: sdl.FColor) -> ^sdl.GPUCommandBuffer {
	// Always allow up to VECTOR_MAX_ENCODE_ATTEMPTS replays — never draws+1.
	attempts := VECTOR_MAX_ENCODE_ATTEMPTS
	state.vector.gpu.sample_work = 0
	state.vector.gpu.command_visits = 0
	state.vector.gpu.encode_attempts = 0
	state.vector.gpu.atlas_disabled = false
	for _ in 0 ..< attempts {
		state.vector.gpu.encode_attempts += 1
		cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
		if cmd == nil {
			state.vector.last_error = .GPU_Failed
			return nil
		}

		failed := -1
		if vector_gpu_encode_frame(cmd, format, background, &failed) {
			return cmd
		}

		cancelled := sdl.CancelGPUCommandBuffer(cmd)
		if cancelled && failed == -2 {
			vector_gpu_reset_after_cancelled_encode()
			// The slot fence was waited before encoding. Its cancelled command
			// buffer is the only borrower of these atlas pages.
			for &target in vector_gpu_frame().pool { vector_target_release(&target, true) }
			clear(&vector_gpu_frame().pool)
			continue
		}
		if !cancelled || failed < 0 {
			state.vector.last_error = .GPU_Failed
			vector_gpu_reset_after_cancelled_encode()
			return nil
		}

		vector_frame().draws[failed].failed = true
		state.vector.last_error = .GPU_Failed
		log_errorf(
			"Vector submission %d failed; replaying frame without it (sample_work=%v/%v visits=%v/%v)",
			failed,
			state.vector.gpu.sample_work,
			VECTOR_MAX_SAMPLE_WORK,
			state.vector.gpu.command_visits,
			VECTOR_MAX_COMMAND_VISITS,
		)
		vector_gpu_reset_after_cancelled_encode()
	}

	state.vector.last_error = .GPU_Failed
	return nil
}

@(private)
vector_gpu_present :: proc() -> bool {
	format := sdl.GetGPUSwapchainTextureFormat(state.gpu, state.window)
	background := sdl.FColor(color_to_f32(theme.background))
	cmd := vector_gpu_prepare_frame(format, background)
	if cmd == nil {
		log_errorf("Vector frame encoding failed: %s", sdl.GetError())
		if state.vector.gpu.command_visits >= VECTOR_MAX_COMMAND_VISITS || state.vector.gpu.encode_attempts >= VECTOR_MAX_ENCODE_ATTEMPTS { return true }
		return false
	}
	target: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, state.window, &target, nil, nil) || target == nil {
		_ = sdl.CancelGPUCommandBuffer(cmd)
		vector_gpu_reset_after_cancelled_encode()
		return true
	}

	// Clear the full swapchain, then blit the resolved MSAA root to its origin.
	clear_target := sdl.GPUColorTargetInfo{
		texture = target,
		load_op = .CLEAR,
		clear_color = background,
		store_op = .STORE,
	}
	clear_pass := sdl.BeginGPURenderPass(cmd, &clear_target, 1, nil)
	if clear_pass == nil {
		log_errorf("Vector swapchain clear failed: %s", sdl.GetError())
		vector_gpu_submit_frame(cmd)
		return true
	}
	sdl.EndGPURenderPass(clear_pass)

	bounds := vector_gpu_frame().root.bounds
	sdl.BlitGPUTexture(cmd, {
		source = {texture = vector_gpu_frame().root.resolved, w = u32(bounds.w), h = u32(bounds.h)},
		destination = {
			texture = target,
			x = u32(max(bounds.x, 0)),
			y = u32(max(bounds.y, 0)),
			w = u32(bounds.w),
			h = u32(bounds.h),
		},
		load_op = .LOAD,
		filter = .NEAREST,
	})
	vector_gpu_submit_frame(cmd)
	return true
}

@(private)
vector_gpu_submit_frame :: proc(cmd: ^sdl.GPUCommandBuffer) {
	frame := vector_gpu_frame()
	frame.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if frame.fence == nil {
		log_errorf("Vector frame submission failed: %s", sdl.GetError())
		_ = sdl.WaitForGPUIdle(state.gpu)
		state.vector.last_error = .GPU_Failed
		vector_gpu_shutdown()
		state.can_render = false

		return
	}

	vector_gpu_advance_frame()
}
