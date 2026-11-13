#+test
package oni

import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
test_gpu_device_properties_debug_and_release :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	debug_modes := [2]bool{true, false}
	feature_names := [5]cstring{
		sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN,
		sdl.PROP_GPU_DEVICE_CREATE_SHADERS_DXIL_BOOLEAN,
		sdl.PROP_GPU_DEVICE_CREATE_SHADERS_MSL_BOOLEAN,
		sdl.PROP_GPU_DEVICE_CREATE_FEATURE_INDIRECT_DRAW_FIRST_INSTANCE_BOOLEAN,
		sdl.PROP_GPU_DEVICE_CREATE_FEATURE_DUAL_SOURCE_BLENDING_BOOLEAN,
	}
	for debug_mode in debug_modes {
		props := gpu_create_device_properties(debug_mode)
		testing.expect(t, props != 0)
		if props == 0 do return
		defer sdl.DestroyProperties(props)

		// Opposite fallback values catch omitted properties in either mode.
		testing.expect_value(t, sdl.GetBooleanProperty(
			props,
			sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN,
			!debug_mode,
		), debug_mode)
		for name in feature_names {
			testing.expect(t, sdl.GetBooleanProperty(props, name, false))
		}
		testing.expect(t, !sdl.GetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_DXBC_BOOLEAN, false))
		testing.expect(t, !sdl.GetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_METALLIB_BOOLEAN, false))
	}
}

@(test)
test_gpu_device_properties_build_mode :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	expected_debug :: #config(ONI_TEST_EXPECT_GPU_DEBUG, ODIN_DEBUG)
	testing.expect_value(t, ODIN_DEBUG, expected_debug)
	props := gpu_create_device_properties(ODIN_DEBUG)
	testing.expect(t, props != 0)
	if props == 0 do return
	defer sdl.DestroyProperties(props)
	testing.expect_value(t, sdl.GetBooleanProperty(
		props,
		sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN,
		!expected_debug,
	), expected_debug)
}
