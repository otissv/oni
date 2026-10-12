package oni

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

vert_shader_code := #load("shaders/ui.spv.vert")
frag_shader_code := #load("shaders/ui.spv.frag")
lcd_frag_shader_code := #load("shaders/ui_lcd.spv.frag")

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
LCD fragment uniform: FreeType atlas is RGB; set bgr=1 when the display is BGR.

Padded to 16 bytes for std140-friendly push size.
*/
GPU_Lcd_UBO :: struct {
	bgr:  f32,
	_pad: [3]f32,
}

/*
GPU rendering resources: pipelines, sampler, white texture, projection, and batches.

`pipeline` is SRC_ALPHA UI (including gray text). `lcd_pipeline` is dual-source
LCD text (ONE / ONE_MINUS_SRC1_*). Both share `UI_Vertex` layout.

`batches` is ping-ponged via `batch_index` so CPU recording for frame N+1 can
proceed while the GPU still reads frame N's vertex/index buffers. WaitAndAcquire
remains the swapchain sync point; alternate slots avoid uploading into in-flight
GPU buffers within the same present_frame.
*/
GPU_State :: struct {
	pipeline:         ^sdl.GPUGraphicsPipeline,
	lcd_pipeline:     ^sdl.GPUGraphicsPipeline,
	sampler:          ^sdl.GPUSampler,
	sampler_nearest:  ^sdl.GPUSampler,
	white_texture:    ^sdl.GPUTexture,
	proj_mat:         matrix[4, 4]f32,
	batches:          [2]Batch_State,
	batch_index:      int,
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
Creates an SDL GPU device with SPIR-V shaders and dual-source blending enabled.

Dual-source is required for LCD text (Phase C). Device create fails when the
backend cannot enable it (Vulkan without dualSrcBlend).
*/
gpu_create_device :: proc(debug_mode := true) -> ^sdl.GPUDevice {
	props := sdl.CreateProperties()
	if props == 0 {
		return nil
	}
	defer sdl.DestroyProperties(props)

	_ = sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true)
	_ = sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, debug_mode)
	_ = sdl.SetBooleanProperty(
		props,
		sdl.PROP_GPU_DEVICE_CREATE_FEATURE_DUAL_SOURCE_BLENDING_BOOLEAN,
		true,
	)

	return sdl.CreateGPUDeviceWithProperties(props)
}

/*
True when the device was created with dual-source blending and the backend supports it.
*/
gpu_device_supports_dual_source_blending :: proc(device: ^sdl.GPUDevice) -> bool {
	if test_hook_gpu_force_no_dual_source {
		return false
	}

	if device == nil {
		return false
	}

	props := sdl.GetGPUDeviceProperties(device)
	if props == 0 {
		return false
	}

	return sdl.GetBooleanProperty(
		props,
		sdl.PROP_GPU_DEVICE_FEATURE_DUAL_SOURCE_BLENDING_BOOLEAN,
		false,
	)
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
Dual-source LCD blend: dst = src0 + dst * (1 - src1) per channel.

Requires a fragment shader that writes color location/index 0 (src0) and 1 (src1),
and a device created with dual-source blending enabled.
*/
gpu_dual_source_blend_state :: proc() -> sdl.GPUColorTargetBlendState {
	return {
		src_color_blendfactor = .ONE,
		dst_color_blendfactor = .ONE_MINUS_SRC1_COLOR,
		color_blend_op = .ADD,
		src_alpha_blendfactor = .ONE,
		dst_alpha_blendfactor = .ONE_MINUS_SRC1_ALPHA,
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
Builds a graphics pipeline with UI_Vertex layout, shared vertex shader, and
the given fragment SPIR-V + color-target blend state.

`frag_uniform_buffers` is 0 for the UI pipeline and 1 for LCD (subpixel order).
*/
gpu_create_ui_layout_pipeline :: proc(
	gpu: ^sdl.GPUDevice,
	format: sdl.GPUTextureFormat,
	frag_code: []u8,
	blend: sdl.GPUColorTargetBlendState,
	frag_uniform_buffers: u32 = 0,
) -> ^sdl.GPUGraphicsPipeline {
	vert := gpu_load_shader(gpu, vert_shader_code, .VERTEX, 1, 0)
	frag := gpu_load_shader(gpu, frag_code, .FRAGMENT, frag_uniform_buffers, 1)

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
		format      = format,
		blend_state = blend,
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

/*
Builds the UI graphics pipeline with vertex layout matching UI_Vertex.

Loads embedded SPIR-V shaders, configures SRC_ALPHA blend for the swapchain
format, and returns nil if shader compilation or pipeline creation fails.
*/
gpu_create_pipeline :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window) -> ^sdl.GPUGraphicsPipeline {
	if gpu == nil || window == nil {
		return nil
	}

	format := sdl.GetGPUSwapchainTextureFormat(gpu, window)
	pipeline := gpu_create_ui_layout_pipeline(gpu, format, frag_shader_code, gpu_blend_state())
	if test_hook_gpu_fail_pipeline && pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(gpu, pipeline)

		return nil
	}

	return pipeline
}

/*
Builds the LCD text pipeline: same UI_Vertex layout, dual-source blend.

Fragment shader writes location/index 0 (tint*coverage) and 1 (coverage).
Requires a device created with dual-source blending enabled.
*/
gpu_create_lcd_pipeline :: proc(
	gpu: ^sdl.GPUDevice,
	format: sdl.GPUTextureFormat,
) -> ^sdl.GPUGraphicsPipeline {
	if gpu == nil {
		return nil
	}

	pipeline := gpu_create_ui_layout_pipeline(
		gpu,
		format,
		lcd_frag_shader_code,
		gpu_dual_source_blend_state(),
		1,
	)
	if test_hook_gpu_fail_lcd_pipeline && pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(gpu, pipeline)

		return nil
	}

	return pipeline
}

/*
Creates a clamp-to-edge sampler with the given min/mag filters.

LINEAR is the default UI path; NEAREST is used for 1:1 glyph atlas quads.
*/
gpu_create_sampler :: proc(
	gpu: ^sdl.GPUDevice,
	min_filter: sdl.GPUFilter = .LINEAR,
	mag_filter: sdl.GPUFilter = .LINEAR,
) -> ^sdl.GPUSampler {
	sampler := sdl.CreateGPUSampler(
		gpu,
		{
			min_filter = min_filter,
			mag_filter = mag_filter,
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
Tears down batch state and releases pipelines, samplers, and white texture.

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
	if state.gpu_state.sampler_nearest != nil {
		sdl.ReleaseGPUSampler(state.gpu, state.gpu_state.sampler_nearest)
		state.gpu_state.sampler_nearest = nil
	}
	if state.gpu_state.lcd_pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, state.gpu_state.lcd_pipeline)
		state.gpu_state.lcd_pipeline = nil
	}
	if state.gpu_state.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, state.gpu_state.pipeline)
		state.gpu_state.pipeline = nil
	}
}

/*
Initializes the full GPU rendering stack when device and window are ready.

Creates UI + LCD pipelines, samplers, white texture, asset GPU resources, batch
buffers, and projection matrix. Requires dual-source blending. Returns true when
the stack is ready (including idempotent re-entry). Returns false if prerequisites
are missing or any create fails; leaves GPU stack resources clean on failure.
*/
gpu_init :: proc() -> bool {
	if state.gpu == nil || state.window == nil {
		return false
	}

	if state.gpu_state.pipeline != nil {
		return true
	}

	if !gpu_device_supports_dual_source_blending(state.gpu) {
		log_errorf("gpu_init: dual-source blending is required for LCD text")

		return false
	}

	pipeline := gpu_create_pipeline(state.gpu, state.window)
	if pipeline == nil {
		log_errorf("gpu_init: failed to create UI graphics pipeline: %s", sdl.GetError())

		return false
	}

	format := sdl.GetGPUSwapchainTextureFormat(state.gpu, state.window)
	lcd_pipeline := gpu_create_lcd_pipeline(state.gpu, format)
	if lcd_pipeline == nil {
		log_errorf("gpu_init: failed to create LCD graphics pipeline: %s", sdl.GetError())
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

		return false
	}

	sampler := gpu_create_sampler(state.gpu, .LINEAR, .LINEAR)
	if sampler == nil {
		log_errorf("gpu_init: failed to create UI sampler: %s", sdl.GetError())
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, lcd_pipeline)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

		return false
	}

	sampler_nearest := gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
	if sampler_nearest == nil {
		log_errorf("gpu_init: failed to create nearest UI sampler: %s", sdl.GetError())
		sdl.ReleaseGPUSampler(state.gpu, sampler)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, lcd_pipeline)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

		return false
	}

	white_texture := gpu_create_white_texture(state.gpu)
	if white_texture == nil {
		log_errorf("gpu_init: failed to create white fallback texture: %s", sdl.GetError())
		sdl.ReleaseGPUSampler(state.gpu, sampler_nearest)
		sdl.ReleaseGPUSampler(state.gpu, sampler)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, lcd_pipeline)
		sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

		return false
	}

	state.gpu_state.pipeline = pipeline
	state.gpu_state.lcd_pipeline = lcd_pipeline
	state.gpu_state.sampler = sampler
	state.gpu_state.sampler_nearest = sampler_nearest
	state.gpu_state.white_texture = white_texture

	assets_init(state.gpu)
	batch_init()
	gpu_update_projection(state.dpi)

	return true
}

/*
Recreates GPU resources after hot reload or device state changes.

Releases texture GPU handles, destroys and re-inits the GPU stack, then
reloads textures and font GPU faces. Returns false if re-init fails; skips
texture/font GPU restore when the stack is not ready.
*/
gpu_reload :: proc() -> bool {
	texture_release_gpu()
	gpu_destroy()

	if !gpu_init() {
		return false
	}

	texture_reload_gpu()
	font_reload_faces()

	return true
}
