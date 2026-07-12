package oni

import "core:fmt"
import sdl "vendor:sdl3"

Draw_Proc :: proc()

/*
Acquires the swapchain, records draw commands, and submits the GPU frame.

Call once per frame after tick and UI layout; no-ops when rendering is
unavailable or the draw batch is empty.
*/
present_frame :: proc(draw: Draw_Proc) {
	if !state.can_render || state.window == nil || state.gpu == nil do return
	if state.gpu_state.pipeline == nil do return
	if theme == nil do return

	cmd_buf := sdl.AcquireGPUCommandBuffer(state.gpu)
	if test_hook_present_fail_acquire_cmd && cmd_buf != nil {
		_ = sdl.CancelGPUCommandBuffer(cmd_buf)
		cmd_buf = nil
	}
	if cmd_buf == nil {
		fmt.eprintln("SDL_AcquireGPUCommandBuffer failed:", sdl.GetError())
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
		fmt.eprintln("SDL_WaitAndAcquireGPUSwapchainTexture failed:", sdl.GetError())
		if !sdl.CancelGPUCommandBuffer(cmd_buf) || test_hook_present_fail_cancel {
			fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	if swapchain_tex == nil {
		if !sdl.CancelGPUCommandBuffer(cmd_buf) || test_hook_present_fail_cancel {
			fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	draw_record_begin(state.dpi)
	if draw != nil do draw()
	draw_record_end()

	// After a non-nil swapchain acquire, Cancel is illegal — always Submit.
	uploaded := true
	if len(state.gpu_state.batch.vertices) > 0 {
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
		fmt.eprintln("SDL_BeginGPURenderPass failed:", sdl.GetError())
		if !sdl.SubmitGPUCommandBuffer(cmd_buf) || test_hook_present_fail_submit {
			fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
		}
		batch_reset()
		return
	}

	if uploaded {
		draw_begin(cmd_buf, render_pass, state.dpi)
		draw_flush()
		draw_end()
	}
	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) || test_hook_present_fail_submit {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
	}

	batch_reset()
}
