package oni

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

vert_shader_code := #load("shaders/ui.spv.vert")
frag_shader_code := #load("shaders/ui.spv.frag")

/*
Per-vertex data for the UI shader: position, UVs, colors, radii, and borders.
*/
UI_Vertex :: struct {
	pos:          [2]f32,
	uv:           [2]f32,
	local_uv:     [2]f32,
	color:        [4]f32,
	border_color: [4]f32,
	rect_size:    [2]f32,
	radii:        [4]f32,
	params:       [2]f32,
	border:       [4]f32,
}

/*
Uniform buffer object carrying the orthographic projection matrix.
*/
GPU_Proj_UBO :: struct {
	proj: matrix[4, 4]f32,
}

/*
GPU rendering resources: pipeline, sampler, white texture, projection, and batch.
*/
GPU_State :: struct {
	pipeline:      ^sdl.GPUGraphicsPipeline,
	sampler:       ^sdl.GPUSampler,
	white_texture: ^sdl.GPUTexture,
	proj_mat:      matrix[4, 4]f32,
	batch:         Batch_State,
}

/*
Creates an SDL GPU shader from embedded SPIR-V bytecode.

Wraps CreateGPUShader with the UI shader entrypoint and format settings.
*/
gpu_load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	shader := sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
			num_samplers = num_samplers,
		},
	)
	if shader != nil &&
	   ((test_hook_gpu_fail_vert_shader && stage == .VERTEX) ||
			   (test_hook_gpu_fail_frag_shader && stage == .FRAGMENT)) {
		sdl.ReleaseGPUShader(device, shader)
		return nil
	}
	return shader
}

/*
Returns premultiplied-style alpha blending state for the UI color target.

Uses standard src-alpha over dst-alpha compositing for UI transparency.
*/
gpu_blend_state :: proc() -> sdl.GPUColorTargetBlendState {
	return {
		src_color_blendfactor = .SRC_ALPHA,
		dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
		color_blend_op = .ADD,
		src_alpha_blendfactor = .ONE,
		dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
		alpha_blend_op = .ADD,
		enable_blend = true,
	}
}

/*
Vertex buffer pitch and attribute layout for UI_Vertex.

Kept in one place so the pipeline and tests cannot drift.
*/
gpu_ui_vertex_layout :: proc() -> (
	pitch: u32,
	attrs: [9]sdl.GPUVertexAttribute,
) {
	pitch = u32(size_of(UI_Vertex))
	attrs = {
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(UI_Vertex, uv))},
		{
			location = 2,
			buffer_slot = 0,
			format = .FLOAT2,
			offset = u32(offset_of(UI_Vertex, local_uv)),
		},
		{
			location = 3,
			buffer_slot = 0,
			format = .FLOAT4,
			offset = u32(offset_of(UI_Vertex, color)),
		},
		{
			location = 4,
			buffer_slot = 0,
			format = .FLOAT4,
			offset = u32(offset_of(UI_Vertex, border_color)),
		},
		{
			location = 5,
			buffer_slot = 0,
			format = .FLOAT2,
			offset = u32(offset_of(UI_Vertex, rect_size)),
		},
		{
			location = 6,
			buffer_slot = 0,
			format = .FLOAT4,
			offset = u32(offset_of(UI_Vertex, radii)),
		},
		{
			location = 7,
			buffer_slot = 0,
			format = .FLOAT2,
			offset = u32(offset_of(UI_Vertex, params)),
		},
		{
			location = 8,
			buffer_slot = 0,
			format = .FLOAT4,
			offset = u32(offset_of(UI_Vertex, border)),
		},
	}
	return
}

/*
Builds the UI graphics pipeline with vertex layout matching UI_Vertex.

Loads embedded SPIR-V shaders, configures blend state for the swapchain
format, and returns nil if shader compilation or pipeline creation fails.
*/
gpu_create_pipeline :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window) -> ^sdl.GPUGraphicsPipeline {
	vert := gpu_load_shader(gpu, vert_shader_code, .VERTEX, 1, 0)
	frag := gpu_load_shader(gpu, frag_shader_code, .FRAGMENT, 0, 1)

	defer {
		if vert != nil do sdl.ReleaseGPUShader(gpu, vert)
		if frag != nil do sdl.ReleaseGPUShader(gpu, frag)
	}

	if vert == nil {
		fmt.eprintln("gpu_load_shader (vertex) failed:", sdl.GetError())
		return nil
	}
	if frag == nil {
		fmt.eprintln("gpu_load_shader (fragment) failed:", sdl.GetError())
		return nil
	}

	pitch, vertex_attributes := gpu_ui_vertex_layout()
	vertex_buffer_descs := [1]sdl.GPUVertexBufferDescription {
		{slot = 0, pitch = pitch},
	}

	vertex_input := sdl.GPUVertexInputState {
		vertex_buffer_descriptions = raw_data(vertex_buffer_descs[:]),
		num_vertex_buffers         = 1,
		vertex_attributes          = raw_data(vertex_attributes[:]),
		num_vertex_attributes      = u32(len(vertex_attributes)),
	}

	color_target_desc := sdl.GPUColorTargetDescription {
		format      = sdl.GetGPUSwapchainTextureFormat(gpu, window),
		blend_state = gpu_blend_state(),
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		gpu,
		{
			vertex_shader = vert,
			fragment_shader = frag,
			vertex_input_state = vertex_input,
			primitive_type = .TRIANGLELIST,
			rasterizer_state = {cull_mode = .NONE},
			target_info = {num_color_targets = 1, color_target_descriptions = &color_target_desc},
		},
	)
	if test_hook_gpu_fail_pipeline && pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(gpu, pipeline)
		return nil
	}
	return pipeline
}

/*
Creates a linear, clamp-to-edge sampler for UI texture rendering.

Used for both atlas textures and the 1x1 white fallback texture.
*/
gpu_create_sampler :: proc(gpu: ^sdl.GPUDevice) -> ^sdl.GPUSampler {
	sampler := sdl.CreateGPUSampler(
		gpu,
		{
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	if test_hook_gpu_fail_sampler && sampler != nil {
		sdl.ReleaseGPUSampler(gpu, sampler)
		return nil
	}
	return sampler
}

/*
Uploads white pixel data to a 1x1 GPU texture via a one-shot command buffer.

Acquires a command buffer, copies from the transfer buffer, and submits.
Returns false on SDL acquisition, upload, or submit failure.
*/
gpu_upload_white_pixel :: proc(
	texture: ^sdl.GPUTexture,
	transfer: ^sdl.GPUTransferBuffer,
) -> bool {
	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	if test_hook_gpu_fail_acquire_cmd && cmd != nil {
		_ = sdl.CancelGPUCommandBuffer(cmd)
		cmd = nil
	}
	if cmd == nil {
		fmt.eprintln("SDL_AcquireGPUCommandBuffer failed:", sdl.GetError())
		return false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(
		copy_pass,
		{transfer_buffer = transfer, offset = 0, pixels_per_row = 1, rows_per_layer = 1},
		{texture = texture, mip_level = 0, layer = 0, x = 0, y = 0, z = 0, w = 1, h = 1, d = 1},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd) || test_hook_gpu_fail_submit_cmd {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
		return false
	}

	return true
}

/*
Creates and uploads a 1x1 white RGBA texture for solid-color batch draws.

Allocates GPU texture and transfer buffer, writes opaque white, and uploads.
Returns nil and releases partial resources on any failure.
*/
gpu_create_white_texture :: proc(gpu: ^sdl.GPUDevice) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(
		gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = 1,
			height = 1,
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
	if test_hook_gpu_fail_create_texture && texture != nil {
		sdl.ReleaseGPUTexture(gpu, texture)
		texture = nil
	}
	if texture == nil {
		fmt.eprintln("SDL_CreateGPUTexture failed:", sdl.GetError())
		return nil
	}

	transfer := sdl.CreateGPUTransferBuffer(gpu, {usage = .UPLOAD, size = 4})
	if test_hook_gpu_fail_transfer_buffer && transfer != nil {
		sdl.ReleaseGPUTransferBuffer(gpu, transfer)
		transfer = nil
	}
	if transfer == nil {
		fmt.eprintln("SDL_CreateGPUTransferBuffer failed:", sdl.GetError())
		sdl.ReleaseGPUTexture(gpu, texture)
		return nil
	}
	defer sdl.ReleaseGPUTransferBuffer(gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(gpu, transfer, false)
	if test_hook_gpu_fail_map_transfer {
		if mapped != nil {
			sdl.UnmapGPUTransferBuffer(gpu, transfer)
		}
		mapped = nil
	}
	if mapped == nil {
		fmt.eprintln("SDL_MapGPUTransferBuffer failed:", sdl.GetError())
		sdl.ReleaseGPUTexture(gpu, texture)
		return nil
	}

	(cast(^[4]u8)mapped)^ = {255, 255, 255, 255}
	sdl.UnmapGPUTransferBuffer(gpu, transfer)

	upload_ok := gpu_upload_white_pixel(texture, transfer)

	if !upload_ok {
		sdl.ReleaseGPUTexture(gpu, texture)
		return nil
	}

	return texture
}

/*
Rebuilds the orthographic projection matrix from logical viewport dimensions.

Maps logical coordinates (0,0) top-left to (w,h) bottom-right for UI drawing.
No-op when logical width or height is zero or negative.
*/
gpu_update_projection :: proc(dpi: Dpi_Info) {
	w := f32(dpi.logical_w)
	h := f32(dpi.logical_h)
	if w <= 0 || h <= 0 do return

	state.gpu_state.proj_mat = linalg.matrix_ortho3d_f32(0, w, h, 0, -1, 1)
}

/*
Tears down batch state and releases pipeline, sampler, and white texture.

Safe to call when state is nil or GPU resources were partially initialized.
*/
gpu_destroy :: proc() {
	if state == nil do return

	batch_destroy()
	if state.gpu == nil do return

	if state.gpu_state.white_texture != nil {
		sdl.ReleaseGPUTexture(state.gpu, state.gpu_state.white_texture)
		state.gpu_state.white_texture = nil
	}
	if state.gpu_state.sampler != nil {
		sdl.ReleaseGPUSampler(state.gpu, state.gpu_state.sampler)
		state.gpu_state.sampler = nil
	}
	if state.gpu_state.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, state.gpu_state.pipeline)
		state.gpu_state.pipeline = nil
	}
}

/*
Initializes the full GPU rendering stack when device and window are ready.

Creates pipeline, sampler, white texture, asset GPU resources, batch buffers,
and projection matrix. No-op if already initialized or prerequisites missing.
*/
gpu_init :: proc() {
	if state.gpu == nil || state.window == nil || state.gpu_state.pipeline != nil do return

	pipeline := gpu_create_pipeline(state.gpu, state.window)
	if pipeline == nil do return

	sampler := gpu_create_sampler(state.gpu)
	if sampler == nil {
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)
		return
	}

	white_texture := gpu_create_white_texture(state.gpu)
	if white_texture == nil {
		sdl.ReleaseGPUSampler(state.gpu, sampler)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)
		return
	}

	state.gpu_state.pipeline = pipeline
	state.gpu_state.sampler = sampler
	state.gpu_state.white_texture = white_texture

	assets_init(state.gpu)
	batch_init()
	gpu_update_projection(state.dpi)
}

/*
Recreates GPU resources after hot reload or device state changes.

Releases texture GPU handles, destroys and re-inits the GPU stack, then
reloads textures and font GPU faces.
*/
gpu_reload :: proc() {
	texture_release_gpu()
	gpu_destroy()
	gpu_init()
	texture_reload_gpu()
	font_reload_faces()
}
