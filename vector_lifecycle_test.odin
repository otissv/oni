#+test
package oni

import "core:fmt"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
vector_lifecycle_stats_track_live_paths_and_gpu_bytes :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		before := vector_stats()
		testing.expect_value(t, before.live_paths, 0)
		commands := vector_tess_test_triangle()
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)
		after := vector_stats()
		testing.expect_value(t, after.live_paths, 1)
		_ = Draw_Vector_Path(handle, Solid_Paint({255, 0, 0, 255}))
		testing.expect(t, after.path_cache_bytes <= vector_stats().path_cache_bytes || vector_stats().path_cache_bytes == 0)
	})
}

@(test)
vector_lifecycle_svg_reload_preserves_failed_revision :: proc(t: ^testing.T) {
	asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="10" height="10"/></svg>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	r, ok := Svg_Lookup_Element(asset, "r")
	testing.expect(t, ok)
	old := asset.revision
	result := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>nope</text></svg>`)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, !result.ok)
	testing.expect_value(t, asset.revision, old)
	testing.expect(t, r.revision == asset.revision)
}

@(test)
vector_lifecycle_svg_reload_invalidates_stale_handles :: proc(t: ^testing.T) {
	asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="10" height="10"/></svg>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	r, _ := Svg_Lookup_Element(asset, "r")
	result := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="30" height="30"/></svg>`)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok)
	instance, prep := Prepare_Svg_Instance(asset, []Svg_Override{{target = r, property = .Opacity, opacity = .5}})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&prep)
	testing.expect(t, instance == nil && Svg_Result_Error(prep) == Vector_Error.Invalid_Handle)
}

@(test)
vector_lifecycle_migrate_preserves_retained_paths :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := vector_tess_test_triangle()
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)
		dst: State
		copy_state_fields(&dst, state)
		testing.expect_value(t, len(dst.vector.paths), len(state.vector.paths))
		testing.expect(t, dst.vector.tess_pool == nil)
		entry := dst.vector.paths[handle.index - 1]
		testing.expect(t, entry.live && entry.generation == handle.generation)
		dst.assets.io_pool = nil
		dst.fonts.raster_pool = nil
	})
}

@(test)
vector_lifecycle_gpu_reload_bumps_geometry_epoch :: proc(t: ^testing.T) {
	with_gpu_window_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		before := state.vector.gpu.geometry_epoch
		testing.expect(t, gpu_reload())
		testing.expect(t, state.vector.gpu.geometry_epoch > before)
	})
}

@(test)
vector_lifecycle_dpi_change_reallocates_vector_msaa_root :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
		batch_init()
		state.ui.pass = .Draw
		state.dpi = {logical_w = 640, logical_h = 480, drawable_w = 640, drawable_h = 480, scale = 1}
		gpu_update_projection(state.dpi)
		draw_record_begin(state.dpi)
		nodes := [1]Vector_Node{vector_test_rect({10, 10, 40, 40}, {255, 0, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		first := vector_gpu_frame().root.alloc_w
		_ = sdl.CancelGPUCommandBuffer(cmd)
		state.dpi = {logical_w = 800, logical_h = 600, drawable_w = 800, drawable_h = 600, scale = 1}
		gpu_update_projection(state.dpi)
		draw_record_begin(state.dpi)
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		cmd = vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		second := vector_gpu_frame().root.alloc_w
		_ = sdl.CancelGPUCommandBuffer(cmd)
		testing.expect(t, second >= first)
	})
}

@(test)
vector_lifecycle_one_hundred_svg_load_reload_destroy_cycles :: proc(t: ^testing.T) {
	for cycle in 0 ..< 100 {
		asset, loaded := Load_Svg_Memory(fmt.tprintf(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="%d" height="10"/></svg>`, 10 + cycle))
		testing.expect(t, loaded.ok)
		Destroy_Svg_Load_Result(&loaded)
		reloaded := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="20" height="20"/></svg>`)
		testing.expect(t, reloaded.ok)
		Destroy_Svg_Load_Result(&reloaded)
		bad := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>x</text></svg>`)
		testing.expect(t, !bad.ok)
		Destroy_Svg_Load_Result(&bad)
		Destroy_Svg_Asset(asset)
		_ = cycle
	}
}
