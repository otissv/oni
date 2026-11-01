#+test
package oni

import "core:math"
import "core:log"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
gpu_vector_target_requires_a_device :: proc(t: ^testing.T) {
	format, ok := gpu_vector_depth_format(nil, .R8G8B8A8_UNORM)
	testing.expect(t, !ok)
	testing.expect_value(t, format, sdl.GPUTextureFormat.INVALID)
}

@(test)
gpu_ui_multisample_pipeline_rejects_missing_device :: proc(t: ^testing.T) {
	testing.expect(
		t,
		gpu_create_ui_layout_pipeline(
			nil,
			.R8G8B8A8_UNORM,
			frag_shader_code,
			gpu_blend_state(),
			sample_count = ._4,
			depth_stencil_format = .D24_UNORM_S8_UINT,
		) == nil,
	)
}

// Required release runs must fail rather than count an unavailable GPU as a pass.
@(test)
gpu_vector_msaa_lcd_configuration_readback :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	available := test_gpu_device_available_unlocked()
	sync.mutex_unlock(&test_global_state_guard)

	if !available {
		if #config(ONI_REQUIRE_VECTOR_GPU_TESTS, false) {
			testing.expect(t, false, "Vector M1 gate requires an accessible Vulkan GPU; it cannot be skipped")
		} else {
			log.info("SKIP: vector M1 readback requires a GPU; release gate uses --require-vector-gpu")
		}

		return
	}

	with_gpu_device_env(t, gpu_vector_msaa_lcd_readback)
}

@(private)
gpu_vector_msaa_lcd_readback :: proc(t: ^testing.T) {
	depth_format, supported := gpu_vector_depth_format(state.gpu, .R8G8B8A8_UNORM)
	testing.expect(t, supported, "4x MSAA colour and depth/stencil targets are required")

	if !supported {
		return
	}

	lcd := gpu_create_lcd_pipeline(
		state.gpu,
		.R8G8B8A8_UNORM,
		sample_count = ._4,
		depth_stencil_format = depth_format,
	)
	testing.expectf(t, lcd != nil, "4x LCD pipeline creation failed: %s", sdl.GetError())

	if lcd == nil {
		return
	}
	defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, lcd)

	ui := gpu_create_ui_layout_pipeline(
		state.gpu,
		.R8G8B8A8_UNORM,
		frag_shader_code,
		gpu_blend_state(),
		sample_count = ._4,
		depth_stencil_format = depth_format,
	)
	testing.expectf(t, ui != nil, "4x UI pipeline creation failed: %s", sdl.GetError())

	if ui == nil {
		return
	}
	defer sdl.ReleaseGPUGraphicsPipeline(state.gpu, ui)

	colour := sdl.CreateGPUTexture(state.gpu, {
		type = .D2, format = .R8G8B8A8_UNORM, usage = {.COLOR_TARGET},
		width = 8, height = 8, layer_count_or_depth = 1, num_levels = 1, sample_count = ._4,
	})
	testing.expectf(t, colour != nil, "MSAA colour allocation failed: %s", sdl.GetError())

	if colour == nil {
		return
	}
	defer sdl.ReleaseGPUTexture(state.gpu, colour)

	depth := sdl.CreateGPUTexture(state.gpu, {
		type = .D2, format = depth_format, usage = {.DEPTH_STENCIL_TARGET},
		width = 8, height = 8, layer_count_or_depth = 1, num_levels = 1, sample_count = ._4,
	})
	testing.expectf(t, depth != nil, "MSAA depth/stencil allocation failed: %s", sdl.GetError())

	if depth == nil {
		return
	}
	defer sdl.ReleaseGPUTexture(state.gpu, depth)

	resolved := sdl.CreateGPUTexture(state.gpu, {
		type = .D2, format = .R8G8B8A8_UNORM, usage = {.COLOR_TARGET, .SAMPLER},
		width = 8, height = 8, layer_count_or_depth = 1, num_levels = 1,
	})
	testing.expect(t, resolved != nil)

	if resolved == nil {
		return
	}
	defer sdl.ReleaseGPUTexture(state.gpu, resolved)

	cov := [4]u8{128, 64, 192, 255}
	coverage := gpu_test_create_rgba1_texture(t, cov)

	if coverage == nil {
		return
	}
	defer sdl.ReleaseGPUTexture(state.gpu, coverage)

	sampler := gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
	testing.expect(t, sampler != nil)

	if sampler == nil {
		return
	}
	defer sdl.ReleaseGPUSampler(state.gpu, sampler)

	tint := [4]f32{0.8, 0.2, 0.1, 1}
	ui_tint := [4]f32{0.1, 0.7, 0.3, 1}
	vertices := [6]UI_Vertex{
		{pos = {-1, -1}, uv = {0.5, 0.5}, color = tint},
		{pos = {3, -1}, uv = {0.5, 0.5}, color = tint},
		{pos = {-1, 3}, uv = {0.5, 0.5}, color = tint},
		{pos = {-1, -1}, uv = {0.5, 0.5}, color = ui_tint, rect_size = {8, 8}},
		{pos = {3, -1}, uv = {0.5, 0.5}, color = ui_tint, rect_size = {8, 8}},
		{pos = {-1, 3}, uv = {0.5, 0.5}, color = ui_tint, rect_size = {8, 8}},
	}
	buffer := sdl.CreateGPUBuffer(state.gpu, {usage = {.VERTEX}, size = u32(size_of(vertices))})
	testing.expect(t, buffer != nil)

	if buffer == nil {
		return
	}
	defer sdl.ReleaseGPUBuffer(state.gpu, buffer)

	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = u32(size_of(vertices))})
	testing.expect(t, transfer != nil)

	if transfer == nil {
		return
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	testing.expect(t, mapped != nil)

	if mapped == nil {
		return
	}
	(cast(^[6]UI_Vertex)mapped)^ = vertices
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
	testing.expect(t, cmd != nil)

	if cmd == nil {
		return
	}
	submitted := false
	defer if !submitted {
		_ = sdl.CancelGPUCommandBuffer(cmd)
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	testing.expect(t, copy_pass != nil)

	if copy_pass == nil {
		return
	}
	sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transfer}, {buffer = buffer, size = u32(size_of(vertices))}, false)
	sdl.EndGPUCopyPass(copy_pass)

	colour_info := sdl.GPUColorTargetInfo{
		texture = colour, clear_color = {1, 1, 1, 1}, load_op = .CLEAR, store_op = .STORE,
	}
	depth_info := sdl.GPUDepthStencilTargetInfo{
		texture = depth, clear_depth = 1, load_op = .CLEAR, store_op = .STORE,
		stencil_load_op = .CLEAR, stencil_store_op = .STORE, clear_stencil = 0,
	}
	proj := GPU_Proj_UBO{}
	for i in 0 ..< 4 {
		proj.proj[i, i] = 1
	}
	lcd_uniform := GPU_Lcd_UBO{}
	bindings: [ATLAS_SAMPLER_SLOTS]sdl.GPUTextureSamplerBinding
	for &binding in bindings {
		binding = {texture = coverage, sampler = sampler}
	}

	// The second pass must load both attachments and restore LCD after ordinary UI.
	for pass_index in 0 ..< 2 {
		if pass_index == 1 {
			colour_info.load_op = .LOAD
			colour_info.store_op = .RESOLVE
			colour_info.resolve_texture = resolved
			depth_info.load_op = .LOAD
			depth_info.stencil_load_op = .LOAD
			depth_info.store_op = .DONT_CARE
			depth_info.stencil_store_op = .DONT_CARE
		}

		pass := sdl.BeginGPURenderPass(cmd, &colour_info, 1, &depth_info)
		testing.expectf(t, pass != nil, "MSAA render pass failed: %s", sdl.GetError())

		if pass == nil {
			return
		}

		sdl.BindGPUVertexBuffers(pass, 0, &sdl.GPUBufferBinding{buffer = buffer}, 1)
		sdl.BindGPUFragmentSamplers(pass, 0, raw_data(bindings[:]), ATLAS_SAMPLER_SLOTS)
		sdl.PushGPUVertexUniformData(cmd, 0, &proj, u32(size_of(proj)))
		sdl.PushGPUFragmentUniformData(cmd, 0, &lcd_uniform, u32(size_of(lcd_uniform)))

		if pass_index == 0 {
			sdl.BindGPUGraphicsPipeline(pass, lcd)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
		} else {
			sdl.SetGPUScissor(pass, {x = 4, y = 0, w = 4, h = 8})
			sdl.BindGPUGraphicsPipeline(pass, ui)
			sdl.DrawGPUPrimitives(pass, 3, 1, 3, 0)
			sdl.SetGPUScissor(pass, {x = 4, y = 4, w = 4, h = 4})
			sdl.BindGPUGraphicsPipeline(pass, lcd)
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
		}

		sdl.EndGPURenderPass(pass)
	}

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	submitted = true
	testing.expect(t, fence != nil)

	if fence == nil {
		return
	}
	defer sdl.ReleaseGPUFence(state.gpu, fence)

	testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
	pixels, ok := gpu_test_download_rgba(t, resolved, 8, 8)

	if !ok {
		return
	}
	defer delete(pixels)

	luminance := 0.2126 * tint[0] + 0.7152 * tint[1] + 0.0722 * tint[2]
	for channel in 0 ..< 3 {
		adjusted := font_text_coverage_alpha(f32(cov[channel]) / 255, luminance)
		expected_lcd := u8(math.round((tint[channel] * adjusted + 1 - adjusted) * 255))
		gpu_test_expect_u8_near(t, pixels[(2 * 8 + 2) * 4 + channel], expected_lcd, "LCD after attachment LOAD")
		gpu_test_expect_u8_near(t, pixels[(2 * 8 + 6) * 4 + channel], u8(math.round(ui_tint[channel] * 255)), "ordinary UI after LOAD")
		expected_restored := tint[channel] * adjusted + ui_tint[channel] * (1 - adjusted)
		gpu_test_expect_u8_near(t, pixels[(6 * 8 + 6) * 4 + channel], u8(math.round(expected_restored * 255)), "LCD restored after ordinary UI")
	}
	for pixel in 0 ..< 64 {
		gpu_test_expect_u8_near(t, pixels[pixel * 4 + 3], 255, "resolved alpha")
	}
}
