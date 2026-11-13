package oni

import sdl "vendor:sdl3"

Draw_Proc :: proc()

/*
Acquires the swapchain, records draw commands, and submits the GPU frame.

Layout/draw record and deferred texture uploads run before WaitAndAcquire so CPU
work overlaps the previous frame's present. Wait is the sync point before GPU
buffer reuse (safe with the dual Batch_State ping-pong). Call once per frame after
tick; the draw callback typically runs o.Render (Layout + Draw) before GPU upload.
No-ops when rendering is unavailable.
*/
present_frame :: proc(draw: Draw_Proc) {
	if !state.can_render || state.window == nil || state.gpu == nil do return
	if state.gpu_state.pipeline == nil do return
	if theme == nil do return
	debug_overlay_begin_present()
	defer debug_overlay_end_present(sdl.GetTicksNS())

	// Adopt decode completions before draw. Newly decoded textures stay Pending
	// until upload flush below publishes Ready for the next UI frame.
	assets_io_drain()

	// Record into the current CPU/GPU batch slot before waiting on the swapchain.
	draw_record_begin(state.dpi)
	if draw != nil do draw()
	draw_record_end()

	// Flush glyph atlas / texture uploads; asset records become Ready after submit.
	assets_io_drain()
	_ = texture_uploads_flush(state.gpu)

	if len(vector_frame().draws) > 0 {
		if !vector_gpu_present() {
			vector_discard_frame_submissions()
			visits := u64(len(batch_current().segments))
			if visits > VECTOR_MAX_COMMAND_VISITS - min(state.vector.gpu.command_visits, VECTOR_MAX_COMMAND_VISITS) { batch_reset(); batch_flip(); return }
			state.vector.gpu.command_visits += visits
			state.vector.gpu.encode_attempts += 1
			present_ui_frame()
			return
		}
		batch_reset()
		batch_flip()
		return
	}
	present_ui_frame()
}

@(private)
present_ui_frame :: proc() {
	cmd_buf := sdl.AcquireGPUCommandBuffer(state.gpu)
	if test_hook_present_fail_acquire_cmd && cmd_buf != nil {
		_ = sdl.CancelGPUCommandBuffer(cmd_buf)
		cmd_buf = nil
	}
	if cmd_buf == nil {
		log_errorf("SDL_AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		batch_reset()

		return
	}

	swapchain_tex: ^sdl.GPUTexture
	swapchain_ok: bool
	if test_hook_present_fail_swapchain {
		// Simulate acquire failure without claiming a swapchain texture (Cancel is illegal after acquire).
		swapchain_ok = false
		swapchain_tex = nil
	} else if test_hook_present_nil_swapchain {
		// Simulate minimized/hidden window: Wait succeeds but texture is nil.
		swapchain_ok = true
		swapchain_tex = nil
	} else {
		swapchain_ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, state.window, &swapchain_tex, nil, nil)
	}
	if !swapchain_ok {
		log_errorf("SDL_WaitAndAcquireGPUSwapchainTexture failed: %s", sdl.GetError())
		if !sdl.CancelGPUCommandBuffer(cmd_buf) || test_hook_present_fail_cancel {
			log_errorf("SDL_CancelGPUCommandBuffer failed: %s", sdl.GetError())
		}
		batch_reset()

		return
	}

	if swapchain_tex == nil {
		if !sdl.CancelGPUCommandBuffer(cmd_buf) || test_hook_present_fail_cancel {
			log_errorf("SDL_CancelGPUCommandBuffer failed: %s", sdl.GetError())
		}
		batch_reset()

		return
	}

	// After a non-nil swapchain acquire, Cancel is illegal — always Submit.
	uploaded := true
	if len(batch_current().vertices) > 0 {
		uploaded = batch_upload(cmd_buf)
	}

	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = sdl.FColor(color_to_f32(theme.background)),
		store_op    = .STORE,
	}

	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
	if test_hook_present_fail_render_pass && render_pass != nil {
		// End the pass so the acquired swapchain stays valid, then take the nil-pass failure path.
		sdl.EndGPURenderPass(render_pass)
		render_pass = nil
	}
	if render_pass == nil {
		log_errorf("SDL_BeginGPURenderPass failed: %s", sdl.GetError())
		if !sdl.SubmitGPUCommandBuffer(cmd_buf) || test_hook_present_fail_submit {
			log_errorf("SDL_SubmitGPUCommandBuffer failed: %s", sdl.GetError())
		} else {
			state.debug_overlay.current.presented = true
		}
		batch_reset()

		return
	}

	if uploaded {
		draw_begin(cmd_buf, render_pass, state.dpi)
		draw_end()
	}
	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) || test_hook_present_fail_submit {
		log_errorf("SDL_SubmitGPUCommandBuffer failed: %s", sdl.GetError())
	} else {
		state.debug_overlay.current.presented = true
	}

	batch_reset()
	batch_flip()
}
