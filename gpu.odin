package oni

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

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
	params:       [4]f32,
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
Creates a shader from the embedded format supported by this SDL GPU device.
Resource counts and stage come from the build-verified shader registry.
*/
gpu_load_shader :: proc(
	device: ^sdl.GPUDevice,
	id: GPU_Shader,
) -> ^sdl.GPUShader {
	if device == nil || int(id) < 0 || int(id) >= len(gpu_shader_assets) {
		sdl.SetError("Oni shader creation requires a device and a valid shader ID")
		return nil
	}
	asset := gpu_shader_assets[id]
	selected, ok := gpu_shader_select(asset, sdl.GetGPUShaderFormats(device))
	if !ok {
		sdl.SetError("Oni shader bundle does not support this GPU device's shader formats")
		return nil
	}
	shader := sdl.CreateGPUShader(
		device,
		{
			code_size = len(selected.code),
			code = raw_data(selected.code),
			entrypoint = selected.entrypoint,
			format = selected.format,
			stage = asset.stage,
			num_uniform_buffers = asset.num_uniform_buffers,
			num_samplers = asset.num_samplers,
		},
	)
	if shader != nil &&
	   ((test_hook_gpu_fail_vert_shader && asset.stage == .VERTEX) ||
			   (test_hook_gpu_fail_frag_shader && asset.stage == .FRAGMENT)) {
		sdl.ReleaseGPUShader(device, shader)
		return nil
	}
	return shader
}

/*
Creates GPU device properties. The caller owns the returned properties and must
destroy them. Returns zero on failure, releasing any partially configured set.
*/
gpu_create_device_properties :: proc(debug_mode: bool) -> sdl.PropertiesID {
	props := sdl.CreateProperties()
	if props == 0 {
		return 0
	}

	if !sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true) ||
	   !sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_DXIL_BOOLEAN, true) ||
	   !sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_MSL_BOOLEAN, true) ||
	   !sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, debug_mode) ||
	   !sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_FEATURE_INDIRECT_DRAW_FIRST_INSTANCE_BOOLEAN, true) ||
	   !sdl.SetBooleanProperty(
		props,
		sdl.PROP_GPU_DEVICE_CREATE_FEATURE_DUAL_SOURCE_BLENDING_BOOLEAN,
		true,
	) {
		sdl.DestroyProperties(props)
		return 0
	}

	return props
}

/*
Creates an SDL GPU device with SPIR-V, DXIL and MSL shaders available.

Debug mode must be explicit. Engine startup uses ODIN_DEBUG so development builds
enable GPU diagnostics and production builds disable them. Dual-source blending
is required for LCD text; creation fails when the backend cannot enable it.
*/
gpu_create_device :: proc(debug_mode: bool) -> ^sdl.GPUDevice {
	props := gpu_create_device_properties(debug_mode)
	if props == 0 {
		return nil
	}
	defer sdl.DestroyProperties(props)

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
Returns straight-alpha blending state for the UI color target.

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
Premultiplied source blending for vector meshes and group composites.

Fragment shaders emit premultiplied RGBA; UI pipelines keep gpu_blend_state().
*/
gpu_vector_blend_state :: proc() -> sdl.GPUColorTargetBlendState {
	return {
		src_color_blendfactor = .ONE,
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
			format = .FLOAT4,
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
the given fragment shader and color-target blend state.
*/
gpu_create_ui_layout_pipeline :: proc(
	gpu: ^sdl.GPUDevice,
	format: sdl.GPUTextureFormat,
	frag_shader: GPU_Shader,
	blend: sdl.GPUColorTargetBlendState,
	sample_count: sdl.GPUSampleCount = ._1,
	depth_stencil_format: sdl.GPUTextureFormat = .INVALID,
) -> ^sdl.GPUGraphicsPipeline {
	if gpu == nil {
		return nil
	}

	vert := gpu_load_shader(gpu, .UI_Vertex)
	frag := gpu_load_shader(gpu, frag_shader)

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
			multisample_state = {sample_count = sample_count},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &color_target_desc,
				has_depth_stencil_target = depth_stencil_format != .INVALID,
				depth_stencil_format = depth_stencil_format,
			},
		},
	)
}

/*
Builds the UI graphics pipeline with vertex layout matching UI_Vertex.

Loads backend-matched embedded shaders, configures SRC_ALPHA blend for the swapchain
format, and returns nil if shader compilation or pipeline creation fails.
*/
gpu_create_pipeline :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window) -> ^sdl.GPUGraphicsPipeline {
	if gpu == nil || window == nil {
		return nil
	}

	format := sdl.GetGPUSwapchainTextureFormat(gpu, window)
	pipeline := gpu_create_ui_layout_pipeline(gpu, format, .UI_Fragment, gpu_blend_state())
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
	sample_count: sdl.GPUSampleCount = ._1,
	depth_stencil_format: sdl.GPUTextureFormat = .INVALID,
) -> ^sdl.GPUGraphicsPipeline {
	if gpu == nil {
		return nil
	}

	pipeline := gpu_create_ui_layout_pipeline(
		gpu,
		format,
		.LCD_Fragment,
		gpu_dual_source_blend_state(),
		sample_count,
		depth_stencil_format,
	)
	if test_hook_gpu_fail_lcd_pipeline && pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(gpu, pipeline)

		return nil
	}

	return pipeline
}

/*
Selects a depth/stencil format supported together with a 4x colour target.
Pipeline creation and readback remain necessary to validate dual-source drawing.
*/
gpu_vector_depth_format :: proc(
	gpu: ^sdl.GPUDevice,
	colour_format: sdl.GPUTextureFormat,
) -> (format: sdl.GPUTextureFormat, ok: bool) {
	if gpu == nil {
		return .INVALID, false
	}

	if !sdl.GPUTextureSupportsFormat(gpu, colour_format, .D2, {.COLOR_TARGET}) ||
	   !sdl.GPUTextureSupportsSampleCount(gpu, colour_format, ._4) {
		return .INVALID, false
	}

	candidates := [2]sdl.GPUTextureFormat{.D24_UNORM_S8_UINT, .D32_FLOAT_S8_UINT}
	for candidate in candidates {
		if sdl.GPUTextureSupportsFormat(gpu, candidate, .D2, {.DEPTH_STENCIL_TARGET}) &&
		   sdl.GPUTextureSupportsSampleCount(gpu, candidate, ._4) {
			return candidate, true
		}
	}

	return .INVALID, false
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

	vector_gpu_shutdown()
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

	// Pipeline creation with ATLAS_SAMPLER_SLOTS is the portable SDL_GPU
	// capability probe: success proves the backend accepted all bindings.
	texture_atlas_select_draw_mode(true)

	// Atlas growth ceiling (Group D); tests may override max_2d_texture_size later.
	texture_atlas_probe_device_max()

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
	vector_after_gpu_recreate()

	return true
}
