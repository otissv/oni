package game

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

ROTATION_SPEED :: f32(90) * (3.14159265 / 180.0)

render :: proc(dt: f32) {
	if !g.can_render || g.window == nil || g.gpu == nil || g.gpu_state.pipeline == nil do return

	g.gpu_state.rotation += ROTATION_SPEED * dt

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

	// Minimized or otherwise unavailable swapchain: cancel, do not submit.
	if swapchain_tex == nil {
		if !sdl.CancelGPUCommandBuffer(cmd_buf) {
			fmt.eprintln("SDL_CancelGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	UBO :: struct {
		mvp: matrix[4, 4]f32,
	}

	model_mat :=
		linalg.matrix4_translate_f32({0, 0, -5}) *
		linalg.matrix4_rotate_f32(g.gpu_state.rotation, {0, 1, 0})
	ubo := UBO {
		mvp = g.gpu_state.proj_mat * model_mat,
	}

	color_target := sdl.GPUColorTargetInfo {
		texture = swapchain_tex,
		load_op = .CLEAR,
		clear_color = {0, 0.2, 0.4, 1},
		store_op = .STORE,
	}
	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
	if render_pass == nil {
		fmt.eprintln("SDL_BeginGPURenderPass failed:", sdl.GetError())
		if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
			fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
		}
		return
	}

	sdl.BindGPUGraphicsPipeline(render_pass, g.gpu_state.pipeline)
	sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
	sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
	sdl.EndGPURenderPass(render_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd_buf) {
		fmt.eprintln("SDL_SubmitGPUCommandBuffer failed:", sdl.GetError())
	}
}

// Kept for player/structure render paths until the GPU sprite pipeline lands.
draw_rect :: proc(renderer: ^sdl.Renderer, rect: sdl.FRect, color: [4]u8, filled: bool = true) {
	_, _, _, _ = renderer, rect, color, filled
}
