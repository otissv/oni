package oni

import sdl "vendor:sdl3"

@(private)
GPU_Shader_Asset :: struct {
	name: cstring,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers, num_samplers: u32,
	spirv, msl, dxil: []u8,
}

@(private)
GPU_Shader_Code :: struct {
	code: []u8,
	entrypoint: cstring,
	format: sdl.GPUShaderFormat,
}

// These slices borrow embedded, process-lifetime data. No allocation or cache
// survives a DLL swap; selection uses the retained device's actual formats.
@(private)
gpu_shader_select :: proc(asset: GPU_Shader_Asset, formats: sdl.GPUShaderFormat) -> (GPU_Shader_Code, bool) {
	selected: GPU_Shader_Code
	if .SPIRV in formats {
		selected = {asset.spirv, "main", {.SPIRV}}
	} else if .DXIL in formats {
		selected = {asset.dxil, "main", {.DXIL}}
	} else if .MSL in formats {
		selected = {asset.msl, "main0", {.MSL}}
	}
	return selected, len(selected.code) > 0
}
