#+test
package oni

import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
gpu_shader_bundles_cover_every_backend :: proc(t: ^testing.T) {
	for asset in gpu_shader_assets {
		formats := [3]sdl.GPUShaderFormat{{.SPIRV}, {.DXIL}, {.MSL}}
		for format in formats {
			selected, ok := gpu_shader_select(asset, format)
			testing.expectf(t, ok, "%s: missing format %v", asset.name, format)
			testing.expect_value(t, selected.format, format)
			testing.expect(t, len(selected.code) > 0)
			if format == {.MSL} {
				testing.expect_value(t, string(selected.entrypoint), "main0")
				testing.expect(t, strings.contains(string(selected.code), "main0("))
			} else {
				testing.expect_value(t, string(selected.entrypoint), "main")
			}
		}
		testing.expect(t, len(asset.spirv) >= 20 && asset.spirv[0] == 3 && asset.spirv[1] == 2 && asset.spirv[2] == 35 && asset.spirv[3] == 7)
		testing.expect(t, len(asset.dxil) > 32 && string(asset.dxil[:4]) == "DXBC")
	}
}

@(test)
gpu_shader_selection_rejects_missing_and_unsupported_formats :: proc(t: ^testing.T) {
	unsupported := [4]sdl.GPUShaderFormat{{}, {.DXBC}, {.METALLIB}, {.PRIVATE}}
	for formats in unsupported {
		_, ok := gpu_shader_select(gpu_shader_assets[.UI_Vertex], formats)
		testing.expect(t, !ok)
	}
	supported := [3]sdl.GPUShaderFormat{{.SPIRV}, {.MSL}, {.DXIL}}
	for formats in supported {
		_, ok := gpu_shader_select({}, formats)
		testing.expect(t, !ok)
	}
	_, ok := gpu_shader_select(gpu_shader_assets[.UI_Vertex], {.SPIRV, .DXIL, .MSL})
	testing.expect(t, ok)
	testing.expect(t, gpu_load_shader(nil, .UI_Vertex) == nil)
}

@(test)
gpu_shader_dual_source_outputs_survive_translation :: proc(t: ^testing.T) {
	ids := [2]GPU_Shader{.LCD_Fragment, .Probe_Fragment}
	for id in ids {
		msl := string(gpu_shader_assets[id].msl)
		testing.expect(t, strings.contains(msl, "[[color(0), index(0)]]"))
		testing.expect(t, strings.contains(msl, "[[color(0), index(1)]]"))
	}
}

// --gpu-backend makes device availability and the actual driver mandatory.
@(test)
gpu_shader_required_backend :: proc(t: ^testing.T) {
	expected_driver :: #config(ONI_TEST_GPU_DRIVER, "")
	if expected_driver == "" do return
	{
		sync.mutex_lock(&test_global_state_guard)
		defer sync.mutex_unlock(&test_global_state_guard)
		if !sdl.Init({.VIDEO}) {
			testing.expectf(t, false, "Required backend SDL init failed: %s", sdl.GetError())
			return
		}
		defer sdl.Quit()
		device := gpu_create_device(ODIN_DEBUG)
		testing.expectf(t, device != nil, "Required %s device unavailable: %s", expected_driver, sdl.GetError())
		if device == nil do return
		defer sdl.DestroyGPUDevice(device)
		testing.expect_value(t, string(sdl.GetGPUDeviceDriver(device)), expected_driver)
		testing.expect(t, gpu_device_supports_dual_source_blending(device))
		for _, id in gpu_shader_assets {
			shader := gpu_load_shader(device, id)
			testing.expectf(t, shader != nil, "Required backend shader %v failed: %s", id, sdl.GetError())
			if shader != nil do sdl.ReleaseGPUShader(device, shader)
		}
	}
}
