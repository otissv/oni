package app

import "core:fmt"
import sdl "vendor:sdl3"

render_frame :: proc() {
	if !g.can_render || g.window == nil || g.gpu == nil do return
	if g.gpu_state.pipeline == nil do return

	cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)
	if cmd_buf == nil {
		fmt.eprintln("SDL_AcquireGPUCommandBuffer failed:", sdl.GetError())
		return
	}

	swapchain_tex: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, g.window, &swapchain_tex, nil, nil) {
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

	draw_record_begin(g.dpi)

	draw_rect({100, 100, 200, 80}, theme_color(&g.theme, .Accent), g.theme.radius_sm)

	draw_record_end()

	if len(g.gpu_state.batch.vertices) > 0 {
		if !batch_upload(cmd_buf) {
			if !sdl.CancelGPUCommandBuffer(cmd_buf) {
				fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
			}
			return
		}
	}

	clear := g.theme.bg
	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = sdl.FColor(color_to_f32(clear)),
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

	draw_begin(cmd_buf, render_pass, g.dpi)
	draw_flush()
	draw_end()
	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
	}

	batch_reset()
}
