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
	if cmd_buf == nil {
		fmt.eprintln("SDL_AcquireGPUCommandBuffer failed:", sdl.GetError())
		return
	}

	swapchain_tex: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, state.window, &swapchain_tex, nil, nil) {
		fmt.eprintln("SDL_WaitAndAcquireGPUSwapchainTexture failed:", sdl.GetError())
		if !sdl.CancelGPUCommandBuffer(cmd_buf) {
			fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	if swapchain_tex == nil {
		if !sdl.CancelGPUCommandBuffer(cmd_buf) {
			fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	draw_record_begin(state.dpi)
	draw()
	draw_record_end()

	if len(state.gpu_state.batch.vertices) > 0 {
		if !batch_upload(cmd_buf) {
			if !sdl.CancelGPUCommandBuffer(cmd_buf) {
				fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
			}
			return
		}
	}

	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = sdl.FColor(color_to_f32(theme.background)),
		store_op    = .STORE,
	}

	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
	if render_pass == nil {
		fmt.eprintln("SDL_BeginGPURenderPass failed:", sdl.GetError())
		if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
			fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	draw_begin(cmd_buf, render_pass, state.dpi)
	draw_flush()
	draw_end()
	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
	}

	batch_reset()
}
