package oni

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
dual_source_test_vert_code := #load("shaders/dual_source_test.spv.vert")
@(private)
dual_source_test_frag_code := #load("shaders/dual_source_test.spv.frag")

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
		batch_delete_cpu_arrays(&test_state.gpu_state)
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

	if !test_require_gpu_device_unlocked() {
		return
	}

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := gpu_create_device(true)
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
		if state.gpu_state.sampler_nearest != nil {
			sdl.ReleaseGPUSampler(gpu, state.gpu_state.sampler_nearest)
			state.gpu_state.sampler_nearest = nil
		}
		if state.gpu_state.lcd_pipeline != nil {
			sdl.ReleaseGPUGraphicsPipeline(gpu, state.gpu_state.lcd_pipeline)
			state.gpu_state.lcd_pipeline = nil
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

	if !test_require_gpu_window_unlocked() {
		return
	}

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

/*
Creates and uploads a 1x1 RGBA8 texture for LCD / dual-source tests.
*/
@(private)
gpu_test_create_rgba1_texture :: proc(
	t: ^testing.T,
	pixel: [4]u8,
	loc := #caller_location,
) -> ^sdl.GPUTexture {
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
	if texture == nil {
		testing.expectf(t, false, "CreateGPUTexture failed: %s", sdl.GetError(), loc = loc)

		return nil
	}

	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = 4})
	if transfer == nil {
		testing.expectf(t, false, "CreateGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if mapped == nil {
		testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	(cast(^[4]u8)mapped)^ = pixel
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	if cmd == nil {
		testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(
		copy_pass,
		{transfer_buffer = transfer, offset = 0, pixels_per_row = 1, rows_per_layer = 1},
		{texture = texture, mip_level = 0, layer = 0, x = 0, y = 0, z = 0, w = 1, h = 1, d = 1},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		testing.expectf(
			t,
			false,
			"SubmitGPUCommandBufferAndAcquireFence failed: %s",
			sdl.GetError(),
			loc = loc,
		)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	defer sdl.ReleaseGPUFence(state.gpu, fence)

	fences := [1]^sdl.GPUFence{fence}
	if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
		testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}

	return texture
}

@(private)
gpu_test_expect_u8_near :: proc(t: ^testing.T, got, want: u8, channel: string) {
	diff := abs(i32(got) - i32(want))
	testing.expectf(t, diff <= 2, "%s: got %d want ~%d", channel, got, want)
}

/*
Creates and uploads a WxH RGBA8 texture from tightly packed pixels (row-major).
*/
@(private)
gpu_test_create_rgba_texture :: proc(
	t: ^testing.T,
	w, h: u32,
	pixels: []u8,
	loc := #caller_location,
) -> ^sdl.GPUTexture {
	need := int(w) * int(h) * 4
	if w == 0 || h == 0 || len(pixels) < need {
		testing.expectf(t, false, "gpu_test_create_rgba_texture: bad size/pixels", loc = loc)

		return nil
	}

	texture := sdl.CreateGPUTexture(
		state.gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = w,
			height = h,
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
	if texture == nil {
		testing.expectf(t, false, "CreateGPUTexture failed: %s", sdl.GetError(), loc = loc)

		return nil
	}

	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = u32(need)})
	if transfer == nil {
		testing.expectf(t, false, "CreateGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if mapped == nil {
		testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	mem.copy(mapped, raw_data(pixels), need)
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	if cmd == nil {
		testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(
		copy_pass,
		{transfer_buffer = transfer, offset = 0, pixels_per_row = w, rows_per_layer = h},
		{texture = texture, mip_level = 0, layer = 0, x = 0, y = 0, z = 0, w = w, h = h, d = 1},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		testing.expectf(
			t,
			false,
			"SubmitGPUCommandBufferAndAcquireFence failed: %s",
			sdl.GetError(),
			loc = loc,
		)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}
	defer sdl.ReleaseGPUFence(state.gpu, fence)

	fences := [1]^sdl.GPUFence{fence}
	if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
		testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError(), loc = loc)
		sdl.ReleaseGPUTexture(state.gpu, texture)

		return nil
	}

	return texture
}

/*
Downloads a WxH RGBA8 texture into a heap slice (caller deletes).
*/
@(private)
gpu_test_download_rgba :: proc(
	t: ^testing.T,
	texture: ^sdl.GPUTexture,
	w, h: u32,
	loc := #caller_location,
) -> (
	pixels: []u8,
	ok: bool,
) {
	need := int(w) * int(h) * 4
	if w == 0 || h == 0 {
		testing.expectf(t, false, "gpu_test_download_rgba: bad size", loc = loc)

		return nil, false
	}

	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .DOWNLOAD, size = u32(need)})
	if transfer == nil {
		testing.expectf(t, false, "CreateGPUTransferBuffer(DOWNLOAD) failed: %s", sdl.GetError(), loc = loc)

		return nil, false
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	if cmd == nil {
		testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError(), loc = loc)

		return nil, false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.DownloadFromGPUTexture(
		copy_pass,
		{texture = texture, mip_level = 0, layer = 0, x = 0, y = 0, z = 0, w = w, h = h, d = 1},
		{transfer_buffer = transfer, offset = 0, pixels_per_row = w, rows_per_layer = h},
	)
	sdl.EndGPUCopyPass(copy_pass)

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		testing.expectf(t, false, "SubmitGPUCommandBufferAndAcquireFence failed: %s", sdl.GetError(), loc = loc)

		return nil, false
	}
	defer sdl.ReleaseGPUFence(state.gpu, fence)

	fences := [1]^sdl.GPUFence{fence}
	if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
		testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError(), loc = loc)

		return nil, false
	}

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if mapped == nil {
		testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError(), loc = loc)

		return nil, false
	}

	out := make([]u8, need)
	mem.copy(raw_data(out), mapped, need)
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	return out, true
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

@(test)
gpu_dual_source_blend_state_matches_lcd_compositing :: proc(t: ^testing.T) {
	blend := gpu_dual_source_blend_state()
	testing.expect_value(t, blend.src_color_blendfactor, sdl.GPUBlendFactor.ONE)
	testing.expect_value(t, blend.dst_color_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC1_COLOR)
	testing.expect_value(t, blend.color_blend_op, sdl.GPUBlendOp.ADD)
	testing.expect_value(t, blend.src_alpha_blendfactor, sdl.GPUBlendFactor.ONE)
	testing.expect_value(t, blend.dst_alpha_blendfactor, sdl.GPUBlendFactor.ONE_MINUS_SRC1_ALPHA)
	testing.expect_value(t, blend.alpha_blend_op, sdl.GPUBlendOp.ADD)
	testing.expect(t, blend.enable_blend)
}

/*
Prove dst = src0 + dst * (1 - src1) per channel with colored dual-source blend.

Shader emits tint*coverage and coverage; clear is opaque white. Expected:
  R=0.9 G=0.8 B=0.325 A=1 → ~{230,204,83,255}
*/
@(test)
gpu_dual_source_colored_blend_matches_skia_math :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_device_supports_dual_source_blending(state.gpu))

			target := sdl.CreateGPUTexture(
				state.gpu,
				{
					type = .D2,
					format = .R8G8B8A8_UNORM,
					usage = {.COLOR_TARGET, .SAMPLER},
					width = 1,
					height = 1,
					layer_count_or_depth = 1,
					num_levels = 1,
				},
			)
			if target == nil {
				testing.expectf(t, false, "CreateGPUTexture failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUTexture(state.gpu, target)

			vert := gpu_load_shader(state.gpu, dual_source_test_vert_code, .VERTEX, 0, 0)
			frag := gpu_load_shader(state.gpu, dual_source_test_frag_code, .FRAGMENT, 0, 0)
			if vert == nil || frag == nil {
				testing.expectf(t, false, "dual-source shader load failed: %s", sdl.GetError())

				if vert != nil {
					sdl.ReleaseGPUShader(state.gpu, vert)
				}

				if frag != nil {
					sdl.ReleaseGPUShader(state.gpu, frag)
				}

				return
			}
			defer sdl.ReleaseGPUShader(state.gpu, vert)
			defer sdl.ReleaseGPUShader(state.gpu, frag)

			vertex_buffer_descs := [1]sdl.GPUVertexBufferDescription {
				{slot = 0, pitch = u32(size_of([2]f32))},
			}
			vertex_attrs := [1]sdl.GPUVertexAttribute {
				{location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
			}
			color_target := sdl.GPUColorTargetDescription {
				format      = .R8G8B8A8_UNORM,
				blend_state = gpu_dual_source_blend_state(),
			}
			pipeline := sdl.CreateGPUGraphicsPipeline(
				state.gpu,
				{
					vertex_shader = vert,
					fragment_shader = frag,
					vertex_input_state = {
						vertex_buffer_descriptions = raw_data(vertex_buffer_descs[:]),
						num_vertex_buffers = 1,
						vertex_attributes = raw_data(vertex_attrs[:]),
						num_vertex_attributes = 1,
					},
					primitive_type = .TRIANGLELIST,
					rasterizer_state = {cull_mode = .NONE},
					target_info = {
						num_color_targets = 1,
						color_target_descriptions = &color_target,
					},
				},
			)
			if pipeline == nil {
				testing.expectf(t, false, "CreateGPUGraphicsPipeline(dual-source) failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

			verts := [3][2]f32{{-1, -1}, {3, -1}, {-1, 3}}
			vbuf := sdl.CreateGPUBuffer(
				state.gpu,
				{usage = {.VERTEX}, size = u32(size_of(verts))},
			)
			if vbuf == nil {
				testing.expectf(t, false, "CreateGPUBuffer failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUBuffer(state.gpu, vbuf)

			transfer := sdl.CreateGPUTransferBuffer(
				state.gpu,
				{usage = .UPLOAD, size = u32(size_of(verts))},
			)
			if transfer == nil {
				testing.expectf(t, false, "CreateGPUTransferBuffer failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

			mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
			if mapped == nil {
				testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError())

				return
			}
			(cast(^[3][2]f32)mapped)^ = verts
			sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			if cmd == nil {
				testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError())

				return
			}

			copy_pass := sdl.BeginGPUCopyPass(cmd)
			sdl.UploadToGPUBuffer(
				copy_pass,
				{transfer_buffer = transfer, offset = 0},
				{buffer = vbuf, offset = 0, size = u32(size_of(verts))},
				false,
			)
			sdl.EndGPUCopyPass(copy_pass)

			color_info := sdl.GPUColorTargetInfo {
				texture     = target,
				clear_color = {1, 1, 1, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
			if pass == nil {
				testing.expectf(t, false, "BeginGPURenderPass failed: %s", sdl.GetError())
				_ = sdl.CancelGPUCommandBuffer(cmd)

				return
			}
			sdl.BindGPUGraphicsPipeline(pass, pipeline)
			vbind := sdl.GPUBufferBinding {
				buffer = vbuf,
			}
			sdl.BindGPUVertexBuffers(pass, 0, &vbind, 1)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)

			fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			if fence == nil {
				testing.expectf(t, false, "SubmitGPUCommandBufferAndAcquireFence failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUFence(state.gpu, fence)

			fences := [1]^sdl.GPUFence{fence}
			if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
				testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError())

				return
			}

			pixel, ok := gpu_test_download_rgba1(t, target)
			testing.expect(t, ok)
			if !ok {
				return
			}

			// dst = src0 + dst_clear * (1 - src1); allow ±2 for GPU rounding.
			gpu_test_expect_u8_near(t, pixel[0], 230, "R")
			gpu_test_expect_u8_near(t, pixel[1], 204, "G")
			gpu_test_expect_u8_near(t, pixel[2], 83, "B")
			gpu_test_expect_u8_near(t, pixel[3], 255, "A")
		},
	)
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
	testing.expect_value(t, attrs[7].format, sdl.GPUVertexElementFormat.FLOAT4)

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
			append(&batch_current().vertices, UI_Vertex{})
			gpu_destroy()
			testing.expect(t, batch_current().vertices == nil)
		},
	)
}

@(test)
gpu_destroy_releases_pipeline_sampler_and_white_texture :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_init())
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)

			gpu_destroy()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.sampler_nearest == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, batch_current().vertex_buffer == nil)
			testing.expect(t, batch_current().index_buffer == nil)
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
// gpu_create_lcd_pipeline
// ---------------------------------------------------------------------------

@(test)
gpu_create_lcd_pipeline_succeeds_with_rgba8_format :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_device_supports_dual_source_blending(state.gpu))
			pipeline := gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
			testing.expect(t, pipeline != nil)
			if pipeline != nil {
				sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)
			}
		},
	)
}

@(test)
gpu_create_lcd_pipeline_frag_shader_failure_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_frag_shader = true
			testing.expect(t, gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM) == nil)
		},
	)
}

@(test)
gpu_create_lcd_pipeline_create_failure_returns_nil :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_lcd_pipeline = true
			testing.expect(t, gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM) == nil)
		},
	)
}

/*
Phase C.2 exit: bind the production LCD pipeline and draw a dual-source quad
with UI_Vertex + a test RGB coverage texture.
*/
@(test)
gpu_lcd_pipeline_binds_and_draws_dual_source_quad :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_device_supports_dual_source_blending(state.gpu))

			pipeline := gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
			if pipeline == nil {
				testing.expectf(t, false, "gpu_create_lcd_pipeline failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, pipeline)

			sampler := gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
			if sampler == nil {
				testing.expectf(t, false, "gpu_create_sampler failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUSampler(state.gpu, sampler)

			// RGB coverage atlas sample (A unused for LCD).
			cov_px := [4]u8{128, 64, 192, 255}
			cov_tex := gpu_test_create_rgba1_texture(t, cov_px)
			if cov_tex == nil {
				return
			}
			defer sdl.ReleaseGPUTexture(state.gpu, cov_tex)

			target := sdl.CreateGPUTexture(
				state.gpu,
				{
					type = .D2,
					format = .R8G8B8A8_UNORM,
					usage = {.COLOR_TARGET, .SAMPLER},
					width = 1,
					height = 1,
					layer_count_or_depth = 1,
					num_levels = 1,
				},
			)
			if target == nil {
				testing.expectf(t, false, "CreateGPUTexture(target) failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUTexture(state.gpu, target)

			tint := [4]f32{0.8, 0.2, 0.1, 1}
			verts := [3]UI_Vertex {
				{pos = {-1, -1}, uv = {0.5, 0.5}, color = tint},
				{pos = {3, -1}, uv = {0.5, 0.5}, color = tint},
				{pos = {-1, 3}, uv = {0.5, 0.5}, color = tint},
			}
			vbuf := sdl.CreateGPUBuffer(
				state.gpu,
				{usage = {.VERTEX}, size = u32(size_of(verts))},
			)
			if vbuf == nil {
				testing.expectf(t, false, "CreateGPUBuffer failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUBuffer(state.gpu, vbuf)

			transfer := sdl.CreateGPUTransferBuffer(
				state.gpu,
				{usage = .UPLOAD, size = u32(size_of(verts))},
			)
			if transfer == nil {
				testing.expectf(t, false, "CreateGPUTransferBuffer failed: %s", sdl.GetError())

				return
			}
			defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

			mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
			if mapped == nil {
				testing.expectf(t, false, "MapGPUTransferBuffer failed: %s", sdl.GetError())

				return
			}
			(cast(^[3]UI_Vertex)mapped)^ = verts
			sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			if cmd == nil {
				testing.expectf(t, false, "AcquireGPUCommandBuffer failed: %s", sdl.GetError())

				return
			}

			copy_pass := sdl.BeginGPUCopyPass(cmd)
			sdl.UploadToGPUBuffer(
				copy_pass,
				{transfer_buffer = transfer, offset = 0},
				{buffer = vbuf, offset = 0, size = u32(size_of(verts))},
				false,
			)
			sdl.EndGPUCopyPass(copy_pass)

			color_info := sdl.GPUColorTargetInfo {
				texture     = target,
				clear_color = {1, 1, 1, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
			if pass == nil {
				testing.expectf(t, false, "BeginGPURenderPass failed: %s", sdl.GetError())
				_ = sdl.CancelGPUCommandBuffer(cmd)

				return
			}

			identity: matrix[4, 4]f32
			identity[0, 0] = 1
			identity[1, 1] = 1
			identity[2, 2] = 1
			identity[3, 3] = 1
			ubo := GPU_Proj_UBO {
				proj = identity,
			}

			sdl.BindGPUGraphicsPipeline(pass, pipeline)
			sdl.PushGPUVertexUniformData(cmd, 0, &ubo, u32(size_of(ubo)))
			lcd_ubo := GPU_Lcd_UBO {
				bgr = 0,
			}
			sdl.PushGPUFragmentUniformData(cmd, 0, &lcd_ubo, u32(size_of(lcd_ubo)))
			vbind := sdl.GPUBufferBinding {
				buffer = vbuf,
			}
			sdl.BindGPUVertexBuffers(pass, 0, &vbind, 1)
			samp := sdl.GPUTextureSamplerBinding {
				texture = cov_tex,
				sampler = sampler,
			}
			samps := [ATLAS_SAMPLER_SLOTS]sdl.GPUTextureSamplerBinding{samp, samp, samp, samp}
			sdl.BindGPUFragmentSamplers(pass, 0, raw_data(samps[:]), ATLAS_SAMPLER_SLOTS)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)

			fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			if fence == nil {
				testing.expectf(
					t,
					false,
					"SubmitGPUCommandBufferAndAcquireFence failed: %s",
					sdl.GetError(),
				)

				return
			}
			defer sdl.ReleaseGPUFence(state.gpu, fence)

			fences := [1]^sdl.GPUFence{fence}
			if !sdl.WaitForGPUFences(state.gpu, true, raw_data(fences[:]), 1) {
				testing.expectf(t, false, "WaitForGPUFences failed: %s", sdl.GetError())

				return
			}

			pixel, ok := gpu_test_download_rgba1(t, target)
			testing.expect(t, ok)
			if !ok {
				return
			}

			cov := [3]f32 {
				f32(cov_px[0]) / 255,
				f32(cov_px[1]) / 255,
				f32(cov_px[2]) / 255,
			}
			lum := 0.2126 * tint[0] + 0.7152 * tint[1] + 0.0722 * tint[2]
			want_u8 :: proc(cov_c, tint_c, lum: f32) -> u8 {
				adj := font_text_coverage_alpha(cov_c, lum)
				dst := tint_c * adj + (1 - adj)

				return u8(math.round(dst * 255))
			}
			gpu_test_expect_u8_near(t, pixel[0], want_u8(cov[0], tint[0], lum), "R")
			gpu_test_expect_u8_near(t, pixel[1], want_u8(cov[1], tint[1], lum), "G")
			gpu_test_expect_u8_near(t, pixel[2], want_u8(cov[2], tint[2], lum), "B")
			gpu_test_expect_u8_near(t, pixel[3], 255, "A")
		},
	)
}

/*
Phase C.7: colored LCD text shows distinct R/G/B edge coverage through the
production LCD pipeline + frag UBO; gray UI-pipeline fallback still composites.
*/
@(test)
gpu_lcd_rgb_edge_coverage_and_gray_fallback_readback :: proc(t: ^testing.T) {
	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_device_supports_dual_source_blending(state.gpu))

			lcd_pipeline := gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
			testing.expect(t, lcd_pipeline != nil)
			if lcd_pipeline == nil do return
			defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, lcd_pipeline)

			ui_pipeline := gpu_create_ui_layout_pipeline(
				state.gpu,
				.R8G8B8A8_UNORM,
				frag_shader_code,
				gpu_blend_state(),
			)
			testing.expect(t, ui_pipeline != nil)
			if ui_pipeline == nil do return
			defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, ui_pipeline)

			sampler := gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
			testing.expect(t, sampler != nil)
			if sampler == nil do return
			defer sdl.ReleaseGPUSampler(state.gpu, sampler)

			identity: matrix[4, 4]f32
			identity[0, 0] = 1
			identity[1, 1] = 1
			identity[2, 2] = 1
			identity[3, 3] = 1
			proj := GPU_Proj_UBO {
				proj = identity,
			}

			// --- LCD: 3×1 R|G|B coverage on black → distinct edge channels ---
			cov_px := [12]u8{255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255}
			cov_tex := gpu_test_create_rgba_texture(t, 3, 1, cov_px[:])
			if cov_tex == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, cov_tex)

			lcd_target := sdl.CreateGPUTexture(
				state.gpu,
				{
					type = .D2,
					format = .R8G8B8A8_UNORM,
					usage = {.COLOR_TARGET, .SAMPLER},
					width = 3,
					height = 1,
					layer_count_or_depth = 1,
					num_levels = 1,
				},
			)
			testing.expect(t, lcd_target != nil)
			if lcd_target == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, lcd_target)

			tint := [4]f32{1, 1, 1, 1}
			// Clip-covering triangle; UV.x spans 0..1 across NDC x ∈ [-1,1].
			lcd_verts := [3]UI_Vertex {
				{pos = {-1, -1}, uv = {0, 0.5}, color = tint},
				{pos = {3, -1}, uv = {2, 0.5}, color = tint},
				{pos = {-1, 3}, uv = {0, 0.5}, color = tint},
			}
			vbuf := sdl.CreateGPUBuffer(
				state.gpu,
				{usage = {.VERTEX}, size = u32(size_of(lcd_verts))},
			)
			testing.expect(t, vbuf != nil)
			if vbuf == nil do return
			defer sdl.ReleaseGPUBuffer(state.gpu, vbuf)

			transfer := sdl.CreateGPUTransferBuffer(
				state.gpu,
				{usage = .UPLOAD, size = u32(size_of(lcd_verts))},
			)
			testing.expect(t, transfer != nil)
			if transfer == nil do return
			defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

			mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
			testing.expect(t, mapped != nil)
			if mapped == nil do return
			(cast(^[3]UI_Vertex)mapped)^ = lcd_verts
			sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return

			copy_pass := sdl.BeginGPUCopyPass(cmd)
			sdl.UploadToGPUBuffer(
				copy_pass,
				{transfer_buffer = transfer, offset = 0},
				{buffer = vbuf, offset = 0, size = u32(size_of(lcd_verts))},
				false,
			)
			sdl.EndGPUCopyPass(copy_pass)

			color_info := sdl.GPUColorTargetInfo {
				texture     = lcd_target,
				clear_color = {0, 0, 0, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
			testing.expect(t, pass != nil)
			if pass == nil {
				_ = sdl.CancelGPUCommandBuffer(cmd)

				return
			}

			lcd_ubo := GPU_Lcd_UBO {
				bgr = 0,
			}
			sdl.BindGPUGraphicsPipeline(pass, lcd_pipeline)
			sdl.PushGPUVertexUniformData(cmd, 0, &proj, u32(size_of(proj)))
			sdl.PushGPUFragmentUniformData(cmd, 0, &lcd_ubo, u32(size_of(lcd_ubo)))
			vbind := sdl.GPUBufferBinding {
				buffer = vbuf,
			}
			sdl.BindGPUVertexBuffers(pass, 0, &vbind, 1)
			samp := sdl.GPUTextureSamplerBinding {
				texture = cov_tex,
				sampler = sampler,
			}
			samps := [ATLAS_SAMPLER_SLOTS]sdl.GPUTextureSamplerBinding{samp, samp, samp, samp}
			sdl.BindGPUFragmentSamplers(pass, 0, raw_data(samps[:]), ATLAS_SAMPLER_SLOTS)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)

			fence_rgb := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, fence_rgb != nil)
			if fence_rgb == nil do return
			defer sdl.ReleaseGPUFence(state.gpu, fence_rgb)
			fences_rgb := [1]^sdl.GPUFence{fence_rgb}
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, raw_data(fences_rgb[:]), 1))

			lcd_pixels, lcd_ok := gpu_test_download_rgba(t, lcd_target, 3, 1)
			testing.expect(t, lcd_ok)
			if !lcd_ok do return
			defer delete(lcd_pixels)

			// Fake-gamma on pure 0/1 coverage leaves channels at 0 or 1 for white tint
			// on black: columns must stay distinctly R / G / B.
			gpu_test_expect_u8_near(t, lcd_pixels[0], 255, "LCD col0 R")
			gpu_test_expect_u8_near(t, lcd_pixels[1], 0, "LCD col0 G")
			gpu_test_expect_u8_near(t, lcd_pixels[2], 0, "LCD col0 B")
			gpu_test_expect_u8_near(t, lcd_pixels[4], 0, "LCD col1 R")
			gpu_test_expect_u8_near(t, lcd_pixels[5], 255, "LCD col1 G")
			gpu_test_expect_u8_near(t, lcd_pixels[6], 0, "LCD col1 B")
			gpu_test_expect_u8_near(t, lcd_pixels[8], 0, "LCD col2 R")
			gpu_test_expect_u8_near(t, lcd_pixels[9], 0, "LCD col2 G")
			gpu_test_expect_u8_near(t, lcd_pixels[10], 255, "LCD col2 B")

			// BGR UBO swaps coverage → column 0 becomes blue.
			cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			color_info = {
				texture     = lcd_target,
				clear_color = {0, 0, 0, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass = sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
			testing.expect(t, pass != nil)
			if pass == nil {
				_ = sdl.CancelGPUCommandBuffer(cmd)

				return
			}
			lcd_ubo.bgr = 1
			sdl.BindGPUGraphicsPipeline(pass, lcd_pipeline)
			sdl.PushGPUVertexUniformData(cmd, 0, &proj, u32(size_of(proj)))
			sdl.PushGPUFragmentUniformData(cmd, 0, &lcd_ubo, u32(size_of(lcd_ubo)))
			sdl.BindGPUVertexBuffers(pass, 0, &vbind, 1)
			sdl.BindGPUFragmentSamplers(pass, 0, raw_data(samps[:]), ATLAS_SAMPLER_SLOTS)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)
			fence_bgr := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, fence_bgr != nil)
			if fence_bgr == nil do return
			defer sdl.ReleaseGPUFence(state.gpu, fence_bgr)
			fences_bgr := [1]^sdl.GPUFence{fence_bgr}
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, raw_data(fences_bgr[:]), 1))

			bgr_pixels, bgr_ok := gpu_test_download_rgba(t, lcd_target, 3, 1)
			testing.expect(t, bgr_ok)
			if !bgr_ok do return
			defer delete(bgr_pixels)
			gpu_test_expect_u8_near(t, bgr_pixels[0], 0, "BGR col0 R")
			gpu_test_expect_u8_near(t, bgr_pixels[2], 255, "BGR col0 B")

			// --- Gray AA fallback on UI pipeline (coverage in .a) ---
			gray_px := [4]u8{255, 255, 255, 128}
			gray_tex := gpu_test_create_rgba1_texture(t, gray_px)
			if gray_tex == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, gray_tex)

			gray_target := sdl.CreateGPUTexture(
				state.gpu,
				{
					type = .D2,
					format = .R8G8B8A8_UNORM,
					usage = {.COLOR_TARGET, .SAMPLER},
					width = 1,
					height = 1,
					layer_count_or_depth = 1,
					num_levels = 1,
				},
			)
			testing.expect(t, gray_target != nil)
			if gray_target == nil do return
			defer sdl.ReleaseGPUTexture(state.gpu, gray_target)

			gray_verts := [3]UI_Vertex {
				{pos = {-1, -1}, uv = {0.5, 0.5}, color = tint, params = {0, 4, 0, 0}},
				{pos = {3, -1}, uv = {0.5, 0.5}, color = tint, params = {0, 4, 0, 0}},
				{pos = {-1, 3}, uv = {0.5, 0.5}, color = tint, params = {0, 4, 0, 0}},
			}
			gtransfer := sdl.CreateGPUTransferBuffer(
				state.gpu,
				{usage = .UPLOAD, size = u32(size_of(gray_verts))},
			)
			testing.expect(t, gtransfer != nil)
			if gtransfer == nil do return
			defer sdl.ReleaseGPUTransferBuffer(state.gpu, gtransfer)
			gmapped := sdl.MapGPUTransferBuffer(state.gpu, gtransfer, false)
			testing.expect(t, gmapped != nil)
			if gmapped == nil do return
			(cast(^[3]UI_Vertex)gmapped)^ = gray_verts
			sdl.UnmapGPUTransferBuffer(state.gpu, gtransfer)

			cmd = sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			copy_pass = sdl.BeginGPUCopyPass(cmd)
			sdl.UploadToGPUBuffer(
				copy_pass,
				{transfer_buffer = gtransfer, offset = 0},
				{buffer = vbuf, offset = 0, size = u32(size_of(gray_verts))},
				false,
			)
			sdl.EndGPUCopyPass(copy_pass)
			color_info = {
				texture     = gray_target,
				clear_color = {0, 0, 0, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass = sdl.BeginGPURenderPass(cmd, &color_info, 1, nil)
			testing.expect(t, pass != nil)
			if pass == nil {
				_ = sdl.CancelGPUCommandBuffer(cmd)

				return
			}
			sdl.BindGPUGraphicsPipeline(pass, ui_pipeline)
			sdl.PushGPUVertexUniformData(cmd, 0, &proj, u32(size_of(proj)))
			sdl.BindGPUVertexBuffers(pass, 0, &vbind, 1)
			gsamp := sdl.GPUTextureSamplerBinding {
				texture = gray_tex,
				sampler = sampler,
			}
			gsamps := [ATLAS_SAMPLER_SLOTS]sdl.GPUTextureSamplerBinding {
				gsamp,
				gsamp,
				gsamp,
				gsamp,
			}
			sdl.BindGPUFragmentSamplers(pass, 0, raw_data(gsamps[:]), ATLAS_SAMPLER_SLOTS)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(pass)
			fence_gray := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, fence_gray != nil)
			if fence_gray == nil do return
			defer sdl.ReleaseGPUFence(state.gpu, fence_gray)
			fences_gray := [1]^sdl.GPUFence{fence_gray}
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, raw_data(fences_gray[:]), 1))

			gray_pixel, gray_ok := gpu_test_download_rgba1(t, gray_target)
			testing.expect(t, gray_ok)
			if !gray_ok do return
			// SRC_ALPHA: white × coverage_alpha(~0.5) over black → mid-gray, not LCD fringe.
			testing.expect(t, gray_pixel[0] > 40 && gray_pixel[0] < 220)
			testing.expect_value(t, gray_pixel[0], gray_pixel[1])
			testing.expect_value(t, gray_pixel[1], gray_pixel[2])
		},
	)
}

@(test)
gpu_init_refuses_without_dual_source_blending :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_force_no_dual_source = true
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
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
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
		},
	)

	with_gpu_device_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window == nil)
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
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
			testing.expect(t, gpu_init())
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.sampler_nearest != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
			testing.expect(t, batch_current().vertex_buffer != nil)
			testing.expect(t, batch_current().index_buffer != nil)
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
			testing.expect(t, gpu_init())
			pipeline := state.gpu_state.pipeline
			lcd_pipeline := state.gpu_state.lcd_pipeline
			sampler := state.gpu_state.sampler
			white := state.gpu_state.white_texture
			testing.expect(t, gpu_init())
			testing.expect(t, state.gpu_state.pipeline == pipeline)
			testing.expect(t, state.gpu_state.lcd_pipeline == lcd_pipeline)
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
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, batch_current().vertex_buffer == nil)
		},
	)
}

@(test)
gpu_init_lcd_pipeline_failure_releases_ui_pipeline :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_lcd_pipeline = true
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, batch_current().vertex_buffer == nil)
		},
	)
}

@(test)
gpu_init_sampler_failure_releases_pipeline :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_sampler = true
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, batch_current().vertex_buffer == nil)
		},
	)
}

@(test)
gpu_init_white_texture_failure_releases_sampler_and_pipeline :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gpu_fail_create_texture = true
			testing.expect(t, !gpu_init())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.gpu_state.sampler == nil)
			testing.expect(t, state.gpu_state.white_texture == nil)
			testing.expect(t, batch_current().vertex_buffer == nil)
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
			testing.expect(t, gpu_init())
			old_pipeline := state.gpu_state.pipeline
			old_lcd := state.gpu_state.lcd_pipeline
			old_sampler := state.gpu_state.sampler
			old_white := state.gpu_state.white_texture
			testing.expect(t, old_pipeline != nil)
			testing.expect(t, old_lcd != nil)

			testing.expect(t, gpu_reload())
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
			// Handles are recreated; identity may or may not change across drivers.
			_ = old_pipeline
			_ = old_lcd
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
			testing.expect(t, gpu_init())
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

			testing.expect(t, gpu_reload())

			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
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
			testing.expect(t, gpu_init())
			gpu_destroy()
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)

			testing.expect(t, gpu_reload())
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
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
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, gpu_reload())
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.gpu_state.white_texture != nil)
		},
	)
}

@(test)
gpu_reload_init_failure_skips_texture_and_font_restore :: proc(t: ^testing.T) {
	with_gpu_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, gpu_init())
			testing.expect(t, font_init())

			surface := texture_test_make_surface(2, 2, {1, 2, 3, 4})
			testing.expect(t, surface != nil)
			if surface == nil do return

			id, _, tex_ok := texture_register_surface(surface, "gpu_reload_fail_tex.png")
			testing.expect(t, tex_ok)
			testing.expect(t, state.textures.records[int(id)].gpu != nil)

			test_hook_gpu_fail_lcd_pipeline = true
			testing.expect(t, !gpu_reload())
			testing.expect(t, state.gpu_state.pipeline == nil)
			testing.expect(t, state.gpu_state.lcd_pipeline == nil)
			testing.expect(t, state.textures.records[int(id)].gpu == nil)
			testing.expect(t, state.textures.records[int(id)].surface != nil)
		},
	)
}

@(test)
clear_test_hooks_resets_gpu_hooks :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_hook_gpu_fail_vert_shader = true
	test_hook_gpu_fail_frag_shader = true
	test_hook_gpu_fail_pipeline = true
	test_hook_gpu_fail_lcd_pipeline = true
	test_hook_gpu_fail_sampler = true
	test_hook_gpu_fail_create_texture = true
	test_hook_gpu_fail_transfer_buffer = true
	test_hook_gpu_fail_map_transfer = true
	test_hook_gpu_fail_acquire_cmd = true
	test_hook_gpu_fail_submit_cmd = true
	test_hook_batch_record_pipeline_binds = true
	append(&test_batch_pipeline_binds, (^sdl.GPUGraphicsPipeline)(nil))
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
	testing.expect(t, !test_hook_gpu_fail_lcd_pipeline)
	testing.expect(t, !test_hook_gpu_fail_sampler)
	testing.expect(t, !test_hook_batch_record_pipeline_binds)
	testing.expect(t, test_batch_pipeline_binds == nil)
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
