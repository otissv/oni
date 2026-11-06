#+test
package oni

import "core:math"
import "core:testing"

@(test)
vector_svg_flat_mesh_cache_does_not_retain_snapshot_commands :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		for frame in 0 ..< 4 {
			asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><path id="p" d="M0 0L10 0L0 10Z"/></svg>`)
			testing.expect(t, loaded.ok)
			Destroy_Svg_Load_Result(&loaded)
			target, _ := Svg_Lookup_Element(asset, "p")
			commands := [4]Vector_Path_Command{{kind = .Move}, {kind = .Line, points = {{f64(20 + frame), 0}, {}, {}}},
				{kind = .Line, points = {{0, 20}, {}, {}}}, {kind = .Close}}
			overrides := [1]Svg_Override{{target = target, property = .Path, commands = commands[:]}}
			instance, prepared := Prepare_Svg_Instance(asset, overrides[:])
			testing.expect(t, prepared.ok)
			Destroy_Svg_Load_Result(&prepared)
			testing.expect_value(t, Draw_Svg_Instance(instance), Vector_Error.None)
			Destroy_Svg_Instance(instance)
			Destroy_Svg_Asset(asset)
			for entry in state.vector.paths {
				if !entry.live { continue }
				testing.expect_value(t, len(entry.commands), 0)
				testing.expect_value(t, len(entry.basis_commands), 0)
			}
			testing.expect_value(t, state.vector.svg_path_bytes, u64(0))
			testing.expect_value(t, len(vector_frame().commands), 1)
			vector_scene_reset()
			state.ui.frame += 1
		}
	})
}

@(test)
vector_svg_mesh_cache_promotes_to_owned_commands_for_generic_draws :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L10 0L0 10Z"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		testing.expect_value(t, state.vector.svg_path_bytes, u64(0))
		items := make([dynamic]Vector_Path_Draw, context.temp_allocator)
		testing.expect(t, draw_svg_collect_paths(asset.roots, Vector_Identity, 1, &items))
		testing.expect_value(t, len(items), 1)
		entry := vector_path_entry(items[0].handle)
		testing.expect(t, !entry.svg_mesh_only)
		testing.expect_value(t, len(entry.commands), len(asset.roots[0].item.commands))
		testing.expect(t, raw_data(entry.commands) != raw_data(asset.roots[0].item.commands))
		testing.expect_value(t, state.vector.svg_path_bytes, u64(len(entry.commands)) * size_of(Vector_Path_Command))
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
	})
}

@(test)
vector_svg_mesh_cache_releases_borrowed_commands_on_recording_failure :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L10 0L0 10Z"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		state.ui.pass = .Draw
		state.vector.next_geometry_id = max(u64)
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, len(vector_frame().commands), 0)
		for entry in state.vector.paths {
			if entry.live {
				testing.expect_value(t, len(entry.commands), 0)
				testing.expect_value(t, len(entry.basis_commands), 0)
			}
		}
	})
}

@(test)
vector_svg_recycling_validates_untrusted_commands_before_mutation :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := [4]Vector_Path_Command{{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close}}
		handle, err := vector_svg_path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		state.ui.frame += 1
		commands[1].points[0].x = math.nan_f64()
		_, err = vector_svg_path(commands[:])
		testing.expect_value(t, err, Vector_Error.Invalid_Value)
		testing.expect_value(t, vector_path_entry(handle).commands[1].points[0].x, f64(10))
		testing.expect_value(t, len(state.vector.svg_paths), 1)
	})
}

@(test)
vector_svg_prepared_path_recycling_keeps_independent_snapshots :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><path id="p" d="M0 0L10 0L0 10Z"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		target, _ := Svg_Lookup_Element(asset, "p")
		commands := [4]Vector_Path_Command{{kind = .Move}, {kind = .Line, points = {{20, 0}, {}, {}}},
			{kind = .Line, points = {{0, 20}, {}, {}}}, {kind = .Close}}
		overrides := [1]Svg_Override{{target = target, property = .Path, commands = commands[:]}}
		first, prepared := Prepare_Svg_Instance(asset, overrides[:])
		defer Destroy_Svg_Instance(first)
		defer Destroy_Svg_Load_Result(&prepared)
		testing.expect(t, prepared.ok)
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Instance(first), Vector_Error.None)
		vector_scene_reset()
		state.ui.frame += 1
		commands[1].points[0].x = 30
		second, changed := Prepare_Svg_Instance(asset, overrides[:])
		defer Destroy_Svg_Instance(second)
		defer Destroy_Svg_Load_Result(&changed)
		testing.expect(t, changed.ok)
		testing.expect_value(t, Draw_Svg_Instance(second), Vector_Error.None)
		testing.expect_value(t, first.roots[0].item.commands[1].points[0].x, f64(20))
		testing.expect_value(t, second.roots[0].item.commands[1].points[0].x, f64(30))
		testing.expect_value(t, Draw_Svg_Instance(first), Vector_Error.None)
	})
}
