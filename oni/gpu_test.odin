package oni

import "core:math/linalg"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

/*
CPU-only GPU state for blend / projection / destroy-nil paths.
*/
@(private)
with_gpu_cpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	defer {
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		delete(test_state.gpu_state.batch.opacity_stack)
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.view = view_default()
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	body(t)
}

/*
GPU device without a window — shaders, sampler, white texture, upload.
*/
@(private)
with_gpu_device_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu == nil {
		testing.expectf(t, false, "SDL_CreateGPUDevice failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyGPUDevice(gpu)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		batch_destroy()
		if state.gpu_state.white_texture != nil {
			sdl.ReleaseGPUTexture(gpu, state.gpu_state.white_texture)
			state.gpu_state.white_texture = nil
		}
		if state.gpu_state.sampler != nil {
			sdl.ReleaseGPUSampler(gpu, state.gpu_state.sampler)
			state.gpu_state.sampler = nil
		}
		if state.gpu_state.pipeline != nil {
			sdl.ReleaseGPUGraphicsPipeline(gpu, state.gpu_state.pipeline)
			state.gpu_state.pipeline = nil
		}
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.gpu = gpu
	state.view = view_default()
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	body(t)
}

/*
Claimed window + GPU device for pipeline / init / reload.
*/
@(private)
with_gpu_window_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()

	ok := create_window(
		{
			title = "oni gpu test",
			width = 320,
			height = 240,
			min_width = 64,
			min_height = 64,
		},
	)
	if !ok {
		testing.expectf(t, false, "create_window failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	body(t)
}

@(private)
expect_proj_mat :: proc(t: ^testing.T, got, want: matrix[4, 4]f32, loc := #caller_location) {
	for i in 0 ..< 4 {
		for j in 0 ..< 4 {
			expect_close(t, got[i, j], want[i, j], loc = loc)
		}
	}
}

/*
Downloads a 1x1 RGBA8 texture into CPU memory after a GPU fence.
*/
@(private)
gpu_test_download_rgba1 :: proc(
	t: ^testing.T,
	texture: ^sdl.GPUTexture,
	loc := #caller_location,
) -> (
	pixel: [4]u8,
	ok: bool,
) {
	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .DOWNLOAD, size = 4})
	if transfer == nil {
		testing.expectf(t, false, "CreateGPUTransferBuffer(DOWNLOAD) failed: %s", sdl.GetError(), loc = loc)
		return {}, false
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	if cmd == nil {
		testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError(), loc = loc)
		return {}, false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.DownloadFromGPUTexture(
		copy_pass,
		{texture = texture, mip_level = 0, layer = 0, x = 0, y = 0, z = 0, w = 1, h = 1, d = 1},
		{transfer_buffer = transfer, offset = 0, pixels_per_row = 1, rows_per_layer = 1},
	)
	sdl.EndGPUCopyPass(copy_pass)

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		testing.expectf(t, false, "SubmitGPUCommandBufferAndAcquireFence failed: %s", sdl.GetError(), loc = loc)
		return {}, false
	}
	defer sdl.ReleaseGPUFence(state.gpu, fence)

	fences := [1]^sdl.GPUFence{fence}
	if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
		testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError(), loc = loc)
		return {}, false
	}

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if mapped == nil {
		testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)
		return {}, false
	}
	pixel = (cast(^[4]u8)mapped)^
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)
	return pixel, true
}

// ---------------------------------------------------------------------------
// gpu_blend_state
// ---------------------------------------------------------------------------

@(test)
gpu_blend_state_matches_ui_compositing :: proc(t: ^testing.T) {
	blend := gpu_blend_state()
	testing.expect_value(t, blend.src_color_blendfactor, sdl.GPUBlendFactor.SRC_ALPHA)
	testing.expect_value(t, blend.dst_color_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC_ALPHA)
	testing.expect_value(t, blend.color_blend_op, sdl.GPUBlendOp.ADD)
	testing.expect_value(t, blend.src_alpha_blendfactor, sdl.GPUBlendFactor.ONE)
	testing.expect_value(t, blend.dst_alpha_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC_ALPHA)
	testing.expect_value(t, blend.alpha_blend_op, sdl.GPUBlendOp.ADD)
	testing.expect(t, blend.enable_blend)
}

// ---------------------------------------------------------------------------
// UI_Vertex / gpu_ui_vertex_layout
// ---------------------------------------------------------------------------

@(test)
gpu_ui_vertex_layout_matches_ui_vertex_offsets_and_formats :: proc(t: ^testing.T) {
	pitch, attrs := gpu_ui_vertex_layout()
	testing.expect_value(t, pitch, u32(size_of(UI_Vertex)))
	testing.expect_value(t, len(attrs), 9)

	testing.expect_value(t, attrs[0].location, u32(0))
	testing.expect_value(t, attrs[0].format, sdl.GPUVertexElementFormat.FLOAT2)
	testing.expect_value(t, attrs[0].offset, u32(0))

	testing.expect_value(t, attrs[1].offset, u32(offset_of(UI_Vertex, uv)))
	testing.expect_value(t, attrs[1].format, sdl.GPUVertexElementFormat.FLOAT2)

	testing.expect_value(t, attrs[2].offset, u32(offset_of(UI_Vertex, local_uv)))
	testing.expect_value(t, attrs[2].format, sdl.GPUVertexElementFormat.FLOAT2)

	testing.expect_value(t, attrs[3].offset, u32(offset_of(UI_Vertex, color)))
	testing.expect_value(t, attrs[3].format, sdl.GPUVertexElementFormat.FLOAT4)

	testing.expect_value(t, attrs[4].offset, u32(offset_of(UI_Vertex, border_color)))
	testing.expect_value(t, attrs[4].format, sdl.GPUVertexElementFormat.FLOAT4)

	testing.expect_value(t, attrs[5].offset, u32(offset_of(UI_Vertex, rect_size)))
	testing.expect_value(t, attrs[5].format, sdl.GPUVertexElementFormat.FLOAT2)

	testing.expect_value(t, attrs[6].offset, u32(offset_of(UI_Vertex, radii)))
	testing.expect_value(t, attrs[6].format, sdl.GPUVertexElementFormat.FLOAT4)

	testing.expect_value(t, attrs[7].offset, u32(offset_of(UI_Vertex, params)))
	testing.expect_value(t, attrs[7].format, sdl.GPUVertexElementFormat.FLOAT2)

	testing.expect_value(t, attrs[8].offset, u32(offset_of(UI_Vertex, border)))
	testing.expect_value(t, attrs[8].format, sdl.GPUVertexElementFormat.FLOAT4)

	for attr, i in attrs {
		testing.expect_value(t, attr.buffer_slot, u32(0))
		testing.expect_value(t, attr.location, u32(i))
		testing.expect(t, attr.offset < pitch)
	}

	// Field order must be packed without gaps that would desync the shader.
	testing.expect(t, offset_of(UI_Vertex, uv) > 0)
	testing.expect(t, offset_of(UI_Vertex, local_uv) > offset_of(UI_Vertex, uv))
	testing.expect(t, offset_of(UI_Vertex, color) > offset_of(UI_Vertex, local_uv))
	testing.expect(t, offset_of(UI_Vertex, border_color) > offset_of(UI_Vertex, color))
	testing.expect(t, offset_of(UI_Vertex, rect_size) > offset_of(UI_Vertex, border_color))
	testing.expect(t, offset_of(UI_Vertex, radii) > offset_of(UI_Vertex, rect_size))
	testing.expect(t, offset_of(UI_Vertex, params) > offset_of(UI_Vertex, radii))
	testing.expect(t, offset_of(UI_Vertex, border) > offset_of(UI_Vertex, params))
}

// ---------------------------------------------------------------------------
// gpu_update_projection
// ---------------------------------------------------------------------------

@(test)
gpu_update_projection_writes_ortho_for_positive_logical_size :: proc(t: ^testing.T) {
	with_gpu_cpu_env(
		t,
		proc(t: ^testing.T) {
			gpu_update_projection({logical_w = 800, logical_h = 600, scale = 1})
			want := linalg.matrix_ortho3d_f32(0, 800, 600, 0, -1, 1)
			expect_proj_mat(t, state.gpu_state.proj_mat, want)

			gpu_update_projection({logical_w = 1920, logical_h = 1080, scale = 2})
			want = linalg.matrix_ortho3d_f32(0, 1920, 1080, 0, -1, 1)
			expect_proj_mat(t, state.gpu_state.proj_mat, want)
		},
	)
}

@(test)
gpu_update_projection_noop_when_logical_size_non_positive :: proc(t: ^testing.T) {
	with_gpu_cpu_env(
		t,
		proc(t: ^testing.T) {
			sentinel: matrix[4, 4]f32
			sentinel[0, 0] = 42
			sentinel[1, 1] = 7
			state.gpu_state.proj_mat = sentinel

			gpu_update_projection({logical_w = 0, logical_h = 600})
			expect_proj_mat(t, state.gpu_state.proj_mat, sentinel)

			gpu_update_projection({logical_w = 800, logical_h = 0})
			expect_proj_mat(t, state.gpu_state.proj_mat, sentinel)

			gpu_update_projection({logical_w = -1, logical_h = 600})
			expect_proj_mat(t, state.gpu_state.proj_mat, sentinel)

			gpu_update_projection({logical_w = 800, logical_h = -10})
			expect_proj_mat(t, state.gpu_state.proj_mat, sentinel)
		},
	)
}

// ---------------------------------------------------------------------------
// gpu_destroy
// ---------------------------------------------------------------------------

@(test)
gpu_destroy_nil_state_is_safe :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			gpu_destroy()
		},
	)
}

@(test)
gpu_destroy_with_nil_gpu_skips_resource_release :: proc(t: ^testing.T) {
	with_gpu_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.gpu = nil
			append(&state.gpu_state.batch.vertices, UI_Vertex{})
			gpu_destroy()
			testing.expect(t, state.gpu_state.batch.vertices == nil)
		},
	)
}

@(test)
gpu_destroy_releases_pipeline_sampler_and_white_texture :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)

			gpu_destroy()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
			testing.expect(t, state.gpu_state.batch.index_buffer == nil)
		},
	)
}

@(test)
gpu_destroy_partial_resources_is_safe :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			sampler := gpu_create_sampler(state.gpu)
			testing.expect(t, sampler != nil)
			if sampler == nil do return
			state.gpu_state.sampler = sampler

			white := gpu_create_white_texture(state.gpu)
			testing.expect(t, white != nil)
			if white == nil do return
			state.gpu_state.white_texture = white

			testing.expect(t, state.gpu_state.pipeline == nil)
			gpu_destroy()
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.pipeline == nil)
		},
	)
}

@(test)
gpu_destroy_pipeline_only_is_safe :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			pipeline := gpu_create_pipeline(state.gpu, state.window)
			testing.expect(t, pipeline != nil)
			if pipeline == nil do return
			state.gpu_state.pipeline = pipeline
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)

			gpu_destroy()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
		},
	)
}

@(test)
gpu_destroy_white_texture_only_is_safe :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			white := gpu_create_white_texture(state.gpu)
			testing.expect(t, white != nil)
			if white == nil do return
			state.gpu_state.white_texture = white

			gpu_destroy()
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.pipeline == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// gpu_load_shader / gpu_create_sampler / gpu_create_white_texture
// ---------------------------------------------------------------------------

@(test)
gpu_load_shader_loads_embedded_vert_and_frag :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			vert := gpu_load_shader(state.gpu, vert_shader_code, .VERTEX, 1, 0)
			testing.expect(t, vert != nil)
			if vert != nil do sdl.ReleaseGPUShader(state.gpu, vert)

			frag := gpu_load_shader(state.gpu, frag_shader_code, .FRAGMENT, 0, 1)
			testing.expect(t, frag != nil)
			if frag != nil do sdl.ReleaseGPUShader(state.gpu, frag)
		},
	)
}

@(test)
gpu_load_shader_empty_code_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_load_shader(state.gpu, {}, .VERTEX, 1, 0) == nil)
			testing.expect(t, gpu_load_shader(state.gpu, {}, .FRAGMENT, 0, 1) == nil)
		},
	)
}

@(test)
gpu_load_shader_vert_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_vert_shader = true
			vert := gpu_load_shader(state.gpu, vert_shader_code, .VERTEX, 1, 0)
			testing.expect(t, vert == nil)

			frag := gpu_load_shader(state.gpu, frag_shader_code, .FRAGMENT, 0, 1)
			testing.expect(t, frag != nil)
			if frag != nil do sdl.ReleaseGPUShader(state.gpu, frag)
		},
	)
}

@(test)
gpu_load_shader_frag_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_frag_shader = true
			frag := gpu_load_shader(state.gpu, frag_shader_code, .FRAGMENT, 0, 1)
			testing.expect(t, frag == nil)

			vert := gpu_load_shader(state.gpu, vert_shader_code, .VERTEX, 1, 0)
			testing.expect(t, vert != nil)
			if vert != nil do sdl.ReleaseGPUShader(state.gpu, vert)
		},
	)
}

@(test)
gpu_create_sampler_succeeds :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			sampler := gpu_create_sampler(state.gpu)
			testing.expect(t, sampler != nil)
			if sampler != nil do sdl.ReleaseGPUSampler(state.gpu, sampler)
		},
	)
}

@(test)
gpu_create_sampler_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_sampler = true
			testing.expect(t, gpu_create_sampler(state.gpu) == nil)
		},
	)
}

@(test)
gpu_create_white_texture_succeeds :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			white := gpu_create_white_texture(state.gpu)
			testing.expect(t, white != nil)
			if white != nil do sdl.ReleaseGPUTexture(state.gpu, white)
		},
	)
}

@(test)
gpu_create_white_texture_uploads_opaque_white_pixel :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			white := gpu_create_white_texture(state.gpu)
			testing.expect(t, white != nil)
			if white == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, white)

			pixel, ok := gpu_test_download_rgba1(t, white)
			testing.expect(t, ok)
			if !ok do return
			testing.expect_value(t, pixel[0], u8(255))
			testing.expect_value(t, pixel[1], u8(255))
			testing.expect_value(t, pixel[2], u8(255))
			testing.expect_value(t, pixel[3], u8(255))
		},
	)
}

@(test)
gpu_upload_white_pixel_succeeds_and_submit_hook_returns_false :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			texture := sdl.CreateGPUTexture(
				state.gpu,
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
			testing.expect(t, texture != nil)
			if texture == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, texture)

			transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = 4})
			testing.expect(t, transfer != nil)
			if transfer == nil do return
			defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

			mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
			testing.expect(t, mapped != nil)
			if mapped == nil do return
			(cast(^[4]u8)mapped)^ = {255, 255, 255, 255}
			sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

			testing.expect(t, gpu_upload_white_pixel(texture, transfer))

			pixel, ok := gpu_test_download_rgba1(t, texture)
			testing.expect(t, ok)
			if ok {
				testing.expect_value(t, pixel, [4]u8{255, 255, 255, 255})
			}

			// Hook forces the shared `!Submit || hook` failure arm after a real submit call.
			test_hook_gpu_fail_submit_cmd = true
			testing.expect(t, !gpu_upload_white_pixel(texture, transfer))
			test_hook_gpu_fail_submit_cmd = false
		},
	)
}

@(test)
gpu_create_white_texture_create_texture_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_create_texture = true
			testing.expect(t, gpu_create_white_texture(state.gpu) == nil)
		},
	)
}

@(test)
gpu_create_white_texture_transfer_buffer_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_transfer_buffer = true
			testing.expect(t, gpu_create_white_texture(state.gpu) == nil)
		},
	)
}

@(test)
gpu_create_white_texture_map_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_map_transfer = true
			testing.expect(t, gpu_create_white_texture(state.gpu) == nil)
		},
	)
}

@(test)
gpu_create_white_texture_acquire_cmd_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_acquire_cmd = true
			testing.expect(t, gpu_create_white_texture(state.gpu) == nil)
		},
	)
}

@(test)
gpu_create_white_texture_submit_cmd_hook_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_submit_cmd = true
			testing.expect(t, gpu_create_white_texture(state.gpu) == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// gpu_create_pipeline
// ---------------------------------------------------------------------------

@(test)
gpu_create_pipeline_succeeds_with_claimed_window :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			pipeline := gpu_create_pipeline(state.gpu, state.window)
			testing.expect(t, pipeline != nil)
			if pipeline != nil do sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)
		},
	)
}

@(test)
gpu_create_pipeline_vert_shader_failure_returns_nil :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_vert_shader = true
			testing.expect(t, gpu_create_pipeline(state.gpu, state.window) == nil)
		},
	)
}

@(test)
gpu_create_pipeline_frag_shader_failure_returns_nil :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_frag_shader = true
			testing.expect(t, gpu_create_pipeline(state.gpu, state.window) == nil)
		},
	)
}

@(test)
gpu_create_pipeline_create_failure_returns_nil :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_pipeline = true
			testing.expect(t, gpu_create_pipeline(state.gpu, state.window) == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// gpu_init
// ---------------------------------------------------------------------------

@(test)
gpu_init_noop_without_gpu_or_window :: proc(t: ^testing.T) {
	with_gpu_cpu_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
		},
	)

	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window == nil)
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
		},
	)
}

@(test)
gpu_init_creates_pipeline_sampler_white_batch_and_projection :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
			testing.expect(t, state.gpu_state.batch.vertex_buffer != nil)
			testing.expect(t, state.gpu_state.batch.index_buffer != nil)
			// Empty maps may compare equal to nil; prove assets_init ran via texture slot.
			testing.expect_value(t, len(state.textures.records), 1)
			want := linalg.matrix_ortho3d_f32(
				0,
				f32(state.dpi.logical_w),
				f32(state.dpi.logical_h),
				0,
				-1,
				1,
			)
			expect_proj_mat(t, state.gpu_state.proj_mat, want)
		},
	)
}

@(test)
gpu_init_is_idempotent_when_pipeline_already_set :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			pipeline := state.gpu_state.pipeline
			sampler := state.gpu_state.sampler
			white := state.gpu_state.white_texture
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == pipeline)
			testing.expect(t, state.gpu_state.sampler == sampler)
			testing.expect(t, state.gpu_state.white_texture == white)
		},
	)
}

@(test)
gpu_init_pipeline_failure_leaves_state_clean :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_pipeline = true
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
		},
	)
}

@(test)
gpu_init_sampler_failure_releases_pipeline :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_sampler = true
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
		},
	)
}

@(test)
gpu_init_white_texture_failure_releases_sampler_and_pipeline :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_create_texture = true
			gpu_init()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// gpu_reload
// ---------------------------------------------------------------------------

@(test)
gpu_reload_recreates_gpu_stack :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			old_pipeline := state.gpu_state.pipeline
			old_sampler := state.gpu_state.sampler
			old_white := state.gpu_state.white_texture
			testing.expect(t, old_pipeline != nil)

			gpu_reload()
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
			// Handles are recreated; identity may or may not change across drivers.
			_ = old_pipeline
			_ = old_sampler
			_ = old_white
			want := linalg.matrix_ortho3d_f32(
				0,
				f32(state.dpi.logical_w),
				f32(state.dpi.logical_h),
				0,
				-1,
				1,
			)
			expect_proj_mat(t, state.gpu_state.proj_mat, want)
		},
	)
}

@(test)
gpu_reload_restores_registered_textures_and_font_faces :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			testing.expect(t, font_init())

			family, family_ok := font_register_family(
				"GpuReloadTest",
				{{path = PIXEL_FONT_FIXTURE, style = .NORMAL, weight = .Normal}},
			)
			testing.expect(t, family_ok)
			family = font_with_size(family, 8)
			_, _, resolved := font_resolve(family, 8, .SCREEN)
			testing.expect(t, resolved)
			testing.expect(t, len(state.fonts.families) >= 1)
			testing.expect(t, len(state.fonts.faces) >= 1)
			family_name_before := strings.clone(state.fonts.families[0].name)
			defer delete(family_name_before)

			surface := texture_test_make_surface(4, 4, {9, 8, 7, 6})
			testing.expect(t, surface != nil)
			if surface == nil do return
			id, _, tex_ok := texture_register_surface(surface, "gpu_reload_tex.png")
			testing.expect(t, tex_ok)
			testing.expect(t, state.textures.records[int(id)].gpu != nil)
			testing.expect(t, state.textures.records[int(id)].surface != nil)

			gpu_reload()

			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
			testing.expect(t, state.textures.records[int(id)].gpu != nil)
			testing.expect(t, state.textures.records[int(id)].surface != nil)

			// font_reload_faces re-registers families and clears live faces until resolve.
			testing.expect_value(t, len(state.fonts.families), 1)
			testing.expect_value(t, state.fonts.families[0].name, family_name_before)
			testing.expect_value(t, len(state.fonts.faces), 0)

			re_family := Font_Handle{id = Asset_Id(0), size_px = 8}
			_, _, re_ok := font_resolve(re_family, 8, .SCREEN)
			testing.expect(t, re_ok)
			testing.expect(t, len(state.fonts.faces) >= 1)

			pixel, ok := gpu_test_download_rgba1(t, state.gpu_state.white_texture)
			testing.expect(t, ok)
			if ok {
				testing.expect_value(t, pixel, [4]u8{255, 255, 255, 255})
			}
		},
	)
}

@(test)
gpu_reload_after_destroy_reinitializes :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			gpu_init()
			gpu_destroy()
			testing.expect(t, state.gpu_state.pipeline == nil)

			gpu_reload()
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
		},
	)
}

@(test)
gpu_reload_is_safe_without_prior_init :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline == nil)
			gpu_reload()
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
		},
	)
}

@(test)
clear_test_hooks_resets_gpu_hooks :: proc(t: ^testing.T) {
	test_hook_gpu_fail_vert_shader = true
	test_hook_gpu_fail_frag_shader = true
	test_hook_gpu_fail_pipeline = true
	test_hook_gpu_fail_sampler = true
	test_hook_gpu_fail_create_texture = true
	test_hook_gpu_fail_transfer_buffer = true
	test_hook_gpu_fail_map_transfer = true
	test_hook_gpu_fail_acquire_cmd = true
	test_hook_gpu_fail_submit_cmd = true
	test_hook_present_fail_acquire_cmd = true
	test_hook_present_fail_swapchain = true
	test_hook_present_nil_swapchain = true
	test_hook_present_fail_cancel = true
	test_hook_present_fail_render_pass = true
	test_hook_present_fail_submit = true
	clear_test_hooks()
	testing.expect(t, !test_hook_gpu_fail_vert_shader)
	testing.expect(t, !test_hook_gpu_fail_frag_shader)
	testing.expect(t, !test_hook_gpu_fail_pipeline)
	testing.expect(t, !test_hook_gpu_fail_sampler)
	testing.expect(t, !test_hook_gpu_fail_create_texture)
	testing.expect(t, !test_hook_gpu_fail_transfer_buffer)
	testing.expect(t, !test_hook_gpu_fail_map_transfer)
	testing.expect(t, !test_hook_gpu_fail_acquire_cmd)
	testing.expect(t, !test_hook_gpu_fail_submit_cmd)
	testing.expect(t, !test_hook_present_fail_acquire_cmd)
	testing.expect(t, !test_hook_present_fail_swapchain)
	testing.expect(t, !test_hook_present_nil_swapchain)
	testing.expect(t, !test_hook_present_fail_cancel)
	testing.expect(t, !test_hook_present_fail_render_pass)
	testing.expect(t, !test_hook_present_fail_submit)
}
