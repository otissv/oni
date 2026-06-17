package game

import "core:fmt"
import "core:math/linalg"
import sdl "vendor:sdl3"

vert_shader_code := #load("shaders/triangle.spv.vert")
frag_shader_code := #load("shaders/triangle.spv.frag")

GPU_State :: struct {
	pipeline: ^sdl.GPUGraphicsPipeline,
	rotation: f32,
	proj_mat: matrix[4, 4]f32,
}

gpu_load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
		},
	)
}

gpu_create_pipeline :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window) -> ^sdl.GPUGraphicsPipeline {
	vert := gpu_load_shader(gpu, vert_shader_code, .VERTEX, 1)
	frag := gpu_load_shader(gpu, frag_shader_code, .FRAGMENT, 0)

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

	color_target_desc := sdl.GPUColorTargetDescription {
		format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
	}

	return sdl.CreateGPUGraphicsPipeline(
		gpu,
		{
			vertex_shader = vert,
			fragment_shader = frag,
			primitive_type = .TRIANGLELIST,
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &color_target_desc,
			},
		},
	)
}

gpu_update_projection :: proc() {
	if g.window == nil do return

	win_w, win_h: i32
	if !sdl.GetWindowSize(g.window, &win_w, &win_h) do return
	if win_w <= 0 || win_h <= 0 do return

	g.gpu_state.proj_mat = linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(70)),
		f32(win_w) / f32(win_h),
		0.0001,
		1000,
	)
}

gpu_init :: proc() {
	if g.gpu == nil || g.window == nil || g.gpu_state.pipeline != nil do return

	pipeline := gpu_create_pipeline(g.gpu, g.window)
	if pipeline == nil {
		fmt.eprintln("gpu_create_pipeline failed:", sdl.GetError())
		return
	}

	g.gpu_state.pipeline = pipeline
	gpu_update_projection()
}

gpu_destroy :: proc() {
	if g.gpu != nil && g.gpu_state.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(g.gpu, g.gpu_state.pipeline)
		g.gpu_state.pipeline = nil
	}
}

gpu_reload :: proc() {
	// safe to call from game_hot_reloaded after a code reload
	gpu_destroy()
	gpu_init()
}
