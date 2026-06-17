package game

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

vert_shader_code := #load("shaders/ui.spv.vert")
frag_shader_code := #load("shaders/ui.spv.frag")

UI_Vertex :: struct {
	pos:       [2]f32,
	uv:        [2]f32,
	color:     [4]f32,
	rect_size: [2]f32,
	params:    [2]f32,
}

GPU_Proj_UBO :: struct {
	proj: matrix[4, 4]f32,
}

GPU_State :: struct {
	pipeline:      ^sdl.GPUGraphicsPipeline,
	sampler:       ^sdl.GPUSampler,
	white_texture: ^sdl.GPUTexture,
	proj_mat:      matrix[4, 4]f32,
	batch:         Batch_State,
}

gpu_load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
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
}

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

	vertex_buffer_descs := [1]sdl.GPUVertexBufferDescription {
		{slot = 0, pitch = u32(size_of(UI_Vertex))},
	}

	vertex_attributes := [5]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(UI_Vertex, uv))},
		{
			location = 2,
			buffer_slot = 0,
			format = .FLOAT4,
			offset = u32(offset_of(UI_Vertex, color)),
		},
		{
			location = 3,
			buffer_slot = 0,
			format = .FLOAT2,
			offset = u32(offset_of(UI_Vertex, rect_size)),
		},
		{
			location = 4,
			buffer_slot = 0,
			format = .FLOAT2,
			offset = u32(offset_of(UI_Vertex, params)),
		},
	}

	vertex_input := sdl.GPUVertexInputState {
		vertex_buffer_descriptions = raw_data(vertex_buffer_descs[:]),
		num_vertex_buffers         = 1,
		vertex_attributes          = raw_data(vertex_attributes[:]),
		num_vertex_attributes      = 5,
	}

	color_target_desc := sdl.GPUColorTargetDescription {
		format      = sdl.GetGPUSwapchainTextureFormat(gpu, window),
		blend_state = gpu_blend_state(),
	}

	return sdl.CreateGPUGraphicsPipeline(
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
}

gpu_create_sampler :: proc(gpu: ^sdl.GPUDevice) -> ^sdl.GPUSampler {
	return sdl.CreateGPUSampler(
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
}

gpu_upload_white_pixel :: proc(
	texture: ^sdl.GPUTexture,
	transfer: ^sdl.GPUTransferBuffer,
) -> bool {
	cmd := sdl.AcquireGPUCommandBuffer(g.gpu)
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

	if !sdl.SubmitGPUCommandBuffer(cmd) {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
		return false
	}

	return true
}

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
	if texture == nil {
		fmt.eprintln("SDL_CreateGPUTexture failed:", sdl.GetError())
		return nil
	}

	transfer := sdl.CreateGPUTransferBuffer(gpu, {usage = .UPLOAD, size = 4})
	if transfer == nil {
		fmt.eprintln("SDL_CreateGPUTransferBuffer failed:", sdl.GetError())
		sdl.ReleaseGPUTexture(gpu, texture)
		return nil
	}
	defer sdl.ReleaseGPUTransferBuffer(gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(gpu, transfer, false)
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

gpu_update_projection :: proc(dpi: Dpi_Info) {
	w := f32(dpi.logical_w)
	h := f32(dpi.logical_h)
	if w <= 0 || h <= 0 do return

	g.gpu_state.proj_mat = linalg.matrix_ortho3d_f32(0, w, h, 0, -1, 1)
}

gpu_destroy :: proc() {
	if g == nil do return

	batch_destroy()
	if g.gpu == nil do return

	if g.gpu_state.white_texture != nil {
		sdl.ReleaseGPUTexture(g.gpu, g.gpu_state.white_texture)
		g.gpu_state.white_texture = nil
	}
	if g.gpu_state.sampler != nil {
		sdl.ReleaseGPUSampler(g.gpu, g.gpu_state.sampler)
		g.gpu_state.sampler = nil
	}
	if g.gpu_state.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(g.gpu, g.gpu_state.pipeline)
		g.gpu_state.pipeline = nil
	}
}

gpu_init :: proc() {
	if g.gpu == nil || g.window == nil || g.gpu_state.pipeline != nil do return

	pipeline := gpu_create_pipeline(g.gpu, g.window)
	if pipeline == nil do return

	sampler := gpu_create_sampler(g.gpu)
	if sampler == nil {
		sdl.ReleaseGPUGraphicsPipeline(g.gpu, pipeline)
		return
	}

	white_texture := gpu_create_white_texture(g.gpu)
	if white_texture == nil {
		sdl.ReleaseGPUSampler(g.gpu, sampler)
		sdl.ReleaseGPUGraphicsPipeline(g.gpu, pipeline)
		return
	}

	g.gpu_state.pipeline = pipeline
	g.gpu_state.sampler = sampler
	g.gpu_state.white_texture = white_texture

	assets_init(g.gpu)
	batch_init()
	gpu_update_projection(g.dpi)
}

gpu_reload :: proc() {
	texture_release_gpu()
	gpu_destroy()
	gpu_init()
	texture_reload_gpu()
	font_reload_faces()
}
