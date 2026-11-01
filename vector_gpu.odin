package oni

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:time"
import sdl "vendor:sdl3"

@(private)
vector_vert_code := #load("shaders/vector.spv.vert")
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
}

@(private)
Vector_GPU_Record :: struct {
	content, mask: int,
}

@(private)
Vector_GPU_Frame :: struct {
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
	uploaded_geometry_epoch: u64,
	uploaded_vertex_revision: u64,
	uploaded_vertex_bytes, uploaded_index_bytes: u64,
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
	pipeline, pipeline_depth: ^sdl.GPUGraphicsPipeline,
	pipeline_stencil_test, pipeline_stencil_write, pipeline_stencil_pop: ^sdl.GPUGraphicsPipeline,
	pipeline_ss, pipeline_ss_stencil_test, pipeline_ss_stencil_write, pipeline_ss_stencil_pop: ^sdl.GPUGraphicsPipeline,
	ui_pipeline, ui_pipeline_depth, lcd_pipeline, lcd_pipeline_depth: ^sdl.GPUGraphicsPipeline,
	white: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	format, depth_format: sdl.GPUTextureFormat,
	// Five colour-only MSAA root slots hide UHD fence latency within the 256 MiB
	// budget when roots stay content-bounded; group targets keep depth in the pool.
	frames: [5]Vector_GPU_Frame,
	frame_index: int,
	bytes, pool_bytes: u64,
	sample_work: u64,
	command_visits: u64,
	geometry_epoch: u64,
	// Last successful encode breakdown (milliseconds); for harness / diagnostics.
	encode_fence_ms, encode_upload_ms, encode_record_ms: f64,
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
		frame = {}
	}
	if state.gpu != nil {
		pipelines := [?]^^sdl.GPUGraphicsPipeline{
			&g.pipeline, &g.pipeline_depth,
			&g.pipeline_stencil_test, &g.pipeline_stencil_write, &g.pipeline_stencil_pop,
			&g.pipeline_ss, &g.pipeline_ss_stencil_test, &g.pipeline_ss_stencil_write, &g.pipeline_ss_stencil_pop,
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
	frag := gpu_load_shader(state.gpu, vector_frag_code, .FRAGMENT, 1, 3)
	defer {
		if vert != nil {
			sdl.ReleaseGPUShader(state.gpu, vert)
		}
		if frag != nil {
			sdl.ReleaseGPUShader(state.gpu, frag)
		}
	}
	if vert == nil || frag == nil {
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
	g.pipeline_ss = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, {}, true)
	g.pipeline_ss_stencil_test = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_keep, true)
	g.pipeline_ss_stencil_write = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_inc, false)
	g.pipeline_ss_stencil_pop = vector_gpu_create_mesh_pipeline(vert, frag, format, depth_format, ._1, true, stencil_dec, false)
	g.white = gpu_create_white_texture(state.gpu)
	g.sampler = gpu_create_sampler(state.gpu)
	if g.pipeline == nil || g.pipeline_depth == nil ||
	   g.pipeline_stencil_test == nil || g.pipeline_stencil_write == nil || g.pipeline_stencil_pop == nil ||
	   g.pipeline_ss == nil || g.pipeline_ss_stencil_test == nil || g.pipeline_ss_stencil_write == nil || g.pipeline_ss_stencil_pop == nil ||
	   g.white == nil || g.sampler == nil {
		return false
	}
	success = true
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
) -> ^sdl.GPUGraphicsPipeline {
	attributes := [10]sdl.GPUVertexAttribute{
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vector_Vertex, pos))},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vector_Vertex, uv))},
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
		{slot = 1, pitch = u32(size_of(Vector_Instance)), input_rate = .INSTANCE},
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
			num_vertex_attributes = 10,
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
	if bounds.w <= 0 || bounds.h <= 0 {
		return false
	}

	// Root scenes grow-only so morphing AABBs do not thrash MSAA allocations.
	// Pooled group/mask targets stay exact so sampling UVs match.
	need_w := math.ceil(bounds.w)
	need_h := math.ceil(bounds.h)
	if !pooled {
		need_w = vector_target_quantized_size(need_w)
		need_h = vector_target_quantized_size(need_h)
		fb := vector_gpu_framebuffer_bounds()
		need_w = min(need_w, math.ceil(fb.w))
		need_h = min(need_h, math.ceil(fb.h))
	}
	if pooled {
		if target.colour != nil &&
		   target.has_depth == with_depth &&
		   target.msaa == msaa &&
		   target.alloc_w == need_w &&
		   target.alloc_h == need_h {
			target.bounds = bounds
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

	alloc_w := pooled ? need_w : max(need_w, target.alloc_w)
	alloc_h := pooled ? need_h : max(need_h, target.alloc_h)
	colour_size := u64(sdl.GPUTextureFormatTexelBlockSize(g.format))
	depth_size := with_depth ? u64(sdl.GPUTextureFormatTexelBlockSize(g.depth_format)) : 0
	colour_samples := msaa ? u64(5) : u64(1)
	depth_samples := msaa ? u64(4) : u64(1)
	bytes := u64(alloc_w) * u64(alloc_h) * (colour_size * colour_samples + depth_size * (with_depth ? depth_samples : 0))
	// Old and replacement targets coexist until the new textures succeed — reserve peak.
	// Equal-size pooled replaces still allocate a second target before releasing the first.
	if g.bytes + bytes > VECTOR_GPU_BUDGET ||
	   (pooled && g.pool_bytes + bytes > VECTOR_TARGET_POOL_BUDGET) {
		return false
	}

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
vector_gpu_upload :: proc(cmd: ^sdl.GPUCommandBuffer) -> bool {
	f := vector_frame()
	frame := vector_gpu_frame()
	sizes := [Vector_Buffer]u64{
		.Vertex = u64(len(f.vertices)) * size_of(Vector_Vertex),
		.Index = u64(len(f.indices)) * size_of(u32),
		.Instance = u64(len(f.instances)) * size_of(Vector_Instance),
		.Indirect = u64(len(f.commands)) * size_of(sdl.GPUIndexedIndirectDrawCommand),
	}
	sources := [Vector_Buffer]rawptr{
		.Vertex = raw_data(f.vertices), .Index = raw_data(f.indices),
		.Instance = raw_data(f.instances), .Indirect = raw_data(f.commands),
	}
	reuse_geometry := frame.buffers[.Vertex] != nil &&
		frame.buffers[.Index] != nil &&
		frame.uploaded_geometry_epoch == state.vector.gpu.geometry_epoch &&
		frame.uploaded_vertex_revision == vector_frame().vertex_revision &&
		frame.uploaded_vertex_bytes == sizes[.Vertex] &&
		frame.uploaded_index_bytes == sizes[.Index]
	if reuse_geometry {
		sizes[.Vertex] = 0
		sizes[.Index] = 0
		sources[.Vertex] = nil
		sources[.Index] = nil
	}
	usages := [Vector_Buffer]sdl.GPUBufferUsageFlags{
		.Vertex = {.VERTEX}, .Index = {.INDEX}, .Instance = {.VERTEX}, .Indirect = {.INDIRECT},
	}
	bytes := u64(0)
	capacities := frame.capacities
	for kind in Vector_Buffer {
		bytes += sizes[kind]
		capacities[kind] = max(capacities[kind], sizes[kind])
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
	budget_delta := new_buffer_bytes + new_ramp_bytes
	// Replacement buffers/ramps coexist with live ones until install succeeds.
	if state.vector.gpu.bytes + budget_delta > VECTOR_GPU_BUDGET {
		return false
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
		data := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
		if data == nil {
			return false
		}
		offset := u64(0)
		for kind in Vector_Buffer {
			if sizes[kind] > 0 { mem.copy((cast([^]u8)data)[offset:], sources[kind], int(sizes[kind])) }
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
				sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transfer, offset = u32(offset)}, {buffer = buffers[kind], size = u32(sizes[kind])}, false)
			}
			offset += sizes[kind]
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
	success = true
	if !reuse_geometry {
		frame.uploaded_geometry_epoch = state.vector.gpu.geometry_epoch
		frame.uploaded_vertex_revision = f.vertex_revision
		frame.uploaded_vertex_bytes = u64(len(f.vertices)) * size_of(Vector_Vertex)
		frame.uploaded_index_bytes = u64(len(f.indices)) * size_of(u32)
	}

	return true
}

@(private)
vector_gpu_pool_target :: proc(bounds: Rect, msaa: bool) -> (index: int, ok: bool) {
	frame := vector_gpu_frame()
	index = frame.pool_cursor
	if index == len(frame.pool) {
		if _, err := append(&frame.pool, Vector_Target{}); err != nil {
			return -1, false
		}
	}
	if !vector_target_ensure(&frame.pool[index], bounds, true, true, msaa) {
		return -1, false
	}
	frame.pool_cursor += 1
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
	sdl.SetGPUScissor(pass, {x = i32(left), y = i32(top), w = i32(right - left), h = i32(bottom - top)})
	g := &state.vector.gpu
	frame := vector_gpu_frame()
	ramp := frame.ramp != nil ? frame.ramp : g.white
	bindings := [3]sdl.GPUTextureSamplerBinding{
		{texture = g.white, sampler = g.sampler},
		{texture = g.white, sampler = g.sampler},
		{texture = ramp, sampler = g.sampler},
	}
	sdl.BindGPUFragmentSamplers(pass, 0, raw_data(bindings[:]), 3)
	paint := [4]f32{}
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
					vector_gpu_draw_clip_mesh(cmd, pass, record, bounds, child_clip, msaa, stencil_depth, .Write)
					vector_gpu_draw_list(
						cmd,
						pass,
						record.first_child,
						bounds,
						child_clip,
						msaa = msaa,
						with_depth = true,
						stencil_depth = stencil_depth + 1,
					)
					vector_gpu_draw_clip_mesh(cmd, pass, record, bounds, child_clip, msaa, stencil_depth, .Pop)
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
					)
				}
			} else {
				paint := [4]f32{}
				content, mask := g.white, g.white
				draw_clip := clip
				if record.kind == .Group || record.kind == .Mask {
					output := frame.outputs[index]
					if output.content < 0 {
						index = record.next
						continue
					}
					content = frame.pool[output.content].resolved
					paint[0] = 1
					if record.kind == .Mask {
						mask = frame.pool[output.mask].resolved
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
					sdl.SetGPUScissor(pass, {x = i32(left), y = i32(top), w = i32(right - left), h = i32(bottom - top)})
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
		return false
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
	pass := sdl.BeginGPURenderPass(cmd, &colour, 1, &depth)
	if pass == nil {
		return false
	}
	clip := target.bounds
	if scissor.w > 0 && scissor.h > 0 {
		clip = rect_intersect(clip, scissor)
	}
	vector_gpu_draw_list(cmd, pass, first, target.bounds, clip, msaa = target.msaa, with_depth = true)
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
				content, ok := vector_gpu_pool_target(record.bounds, true)
				if !ok || !vector_gpu_render_target(cmd, content, record.first_child) {
					return false
				}
				vector_gpu_frame().outputs[index] = {content = content, mask = -1}
				if record.kind == .Mask {
					// Masks keep 4× MSAA so curved boundaries retain coverage quality.
					mask, mask_ok := vector_gpu_pool_target(record.bounds, true)
					mask_scissor := record.clip
					if !mask_ok || !vector_gpu_render_target(cmd, mask, record.first_mask, mask_scissor) {
						return false
					}
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
	for record in vector_frame().records {
		if record.kind == .Group || record.kind == .Mask || record.geometric {
			return true
		}
	}

	return false
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
	content := vector_gpu_compute_composite_bounds()
	needs_depth_clear := vector_gpu_frame_needs_depth_clear()
	// Root stays colour-only so five in-flight slots fit the GPU budget; groups
	// keep depth attachments via the pooled target path.
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
		return false
	}
	state.vector.gpu.sample_work += root_samples
	state.vector.gpu.command_visits += 1
	if state.vector.gpu.command_visits > VECTOR_MAX_COMMAND_VISITS {
		return false
	}

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
	for &draw, draw_index in vector_frame().draws {
		if !draw.failed && !vector_gpu_prepare_list(cmd, draw.first) {
			if failed_submission != nil {
				failed_submission^ = draw_index
			}
			return false
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
Clears CPU upload bookkeeping and pooled targets after a cancelled encode.

`vector_gpu_upload` records copy passes on the command buffer and may mark
geometry as uploaded before prepare finishes. Cancelling that buffer means the
GPU never received the copies, so the next encode must not skip vertex/index
uploads. Pooled MSAA targets from the aborted buffer are released for the same
reason.
*/
@(private)
vector_gpu_reset_after_cancelled_encode :: proc() {
	frame := vector_gpu_frame()
	frame.uploaded_geometry_epoch = 0
	frame.uploaded_vertex_revision = 0
	frame.uploaded_vertex_bytes = 0
	frame.uploaded_index_bytes = 0
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
	for _ in 0 ..< attempts {
		cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
		if cmd == nil {
			state.vector.last_error = .GPU_Failed
			return nil
		}

		failed := -1
		if vector_gpu_encode_frame(cmd, format, background, &failed) {
			return cmd
		}

		if !sdl.CancelGPUCommandBuffer(cmd) || failed < 0 {
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
vector_gpu_present :: proc() {
	format := sdl.GetGPUSwapchainTextureFormat(state.gpu, state.window)
	background := sdl.FColor(color_to_f32(theme.background))
	cmd := vector_gpu_prepare_frame(format, background)
	if cmd == nil {
		log_errorf("Vector frame encoding failed: %s", sdl.GetError())
		return
	}
	target: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, state.window, &target, nil, nil) || target == nil {
		_ = sdl.CancelGPUCommandBuffer(cmd)
		return
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
		// Swapchain was acquired; Cancel is illegal — submit the empty buffer.
		log_errorf("Vector swapchain clear failed: %s", sdl.GetError())
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		return
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
