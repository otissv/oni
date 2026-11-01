#+test
package oni

import "core:testing"

@(test)
vector_stroke_cache_separates_settings_from_fill_and_paint :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [2]Vector_Path_Command{
			{kind = .Move, points = {{10, 20}, {}, {}}},
			{kind = .Line, points = {{110, 20}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stroke_a := Vector_Stroke{width = 6, cap = .Butt, join = .Miter, miter_limit = 4}
		stroke_b := Vector_Stroke{width = 6, cap = .Round, join = .Miter, miter_limit = 4}
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 255, 0, 255}, opacity = 0.5), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}, op = .Stroke, stroke = stroke_a), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 255, 0, 255}, op = .Stroke, stroke = stroke_b), Vector_Error.None)

		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil)
		fill_slots, stroke_slots := 0, 0
		for cached in entry.cache {
			if !cached.valid {
				continue
			}

			if cached.op == .Fill {
				fill_slots += 1
			} else {
				stroke_slots += 1
			}
		}

		testing.expect_value(t, fill_slots, 1)
		testing.expect_value(t, stroke_slots, 2)
	})
}

@(test)
vector_stroke_edit_invalidates_only_matching_stroke_geometry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [3]Vector_Path_Command{
			{kind = .Move, points = {{8, 16}, {}, {}}},
			{kind = .Line, points = {{120, 16}, {}, {}}},
			{kind = .Line, points = {{120, 64}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		dash := [2]f64{12, 8}
		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Bevel, miter_limit = 4, dash = dash[:]}
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}, op = .Stroke, stroke = stroke), Vector_Error.None)

		entry := vector_path_entry(handle)
		testing.expect(t, entry != nil)
		fill_id, stroke_id := u64(0), u64(0)
		for cached in entry.cache {
			if !cached.valid {
				continue
			}

			if cached.op == .Fill {
				fill_id = cached.geometry_id
			} else {
				stroke_id = cached.geometry_id
			}
		}

		testing.expect(t, fill_id != 0 && stroke_id != 0)

		// Affine-compatible edits keep the fill basis mesh; stroke meshes bake morph
		// so only stroke slots are invalidated.
		morphed := [3]Vector_Path_Command{
			{kind = .Move, points = {{10, 18}, {}, {}}},
			{kind = .Line, points = {{122, 18}, {}, {}}},
			{kind = .Line, points = {{122, 66}, {}, {}}},
		}
		testing.expect_value(t, Vector_Update_Path(handle, morphed[:]), Vector_Error.None)
		for cached in entry.cache {
			if cached.geometry_id == fill_id {
				testing.expect(t, cached.valid)
			}

			if cached.geometry_id == stroke_id {
				testing.expect(t, !cached.valid)
			}
		}

		// Distinct stroke settings use a separate cache slot; fill stays shared.
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}, op = .Stroke, stroke = stroke), Vector_Error.None)
		dash2 := [2]f64{20, 4}
		stroke2 := Vector_Stroke{width = 4, cap = .Butt, join = .Bevel, miter_limit = 4, dash = dash2[:]}
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 255, 0, 255}, op = .Stroke, stroke = stroke2), Vector_Error.None)
		fill_slots, stroke_slots := 0, 0
		for cached in entry.cache {
			if !cached.valid {
				continue
			}

			if cached.op == .Fill {
				fill_slots += 1
			} else {
				stroke_slots += 1
			}
		}

		testing.expect_value(t, fill_slots, 1)
		testing.expect_value(t, stroke_slots, 2)

		// Topology change invalidates every geometry slot for the path.
		changed := [2]Vector_Path_Command{
			{kind = .Move, points = {{8, 16}, {}, {}}},
			{kind = .Line, points = {{120, 16}, {}, {}}},
		}
		testing.expect_value(t, Vector_Update_Path(handle, changed[:]), Vector_Error.None)
		for cached in entry.cache {
			testing.expect(t, !cached.valid)
		}
	})
}

@(test)
vector_stroke_set_path_morph_invalidates_stroke_keeps_fill :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [2]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{50, 0}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4}
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {0, 0, 255, 255}, op = .Stroke, stroke = stroke), Vector_Error.None)

		entry := vector_path_entry(handle)
		fill_id, stroke_id := u64(0), u64(0)
		for cached in entry.cache {
			if !cached.valid {
				continue
			}

			if cached.op == .Fill {
				fill_id = cached.geometry_id
			} else {
				stroke_id = cached.geometry_id
			}
		}

		testing.expect_value(t, Vector_Set_Path_Morph(handle, {1, 0, 0, 1, 4, 2}), Vector_Error.None)
		for cached in entry.cache {
			if cached.geometry_id == fill_id {
				testing.expect(t, cached.valid)
			}

			if cached.geometry_id == stroke_id {
				testing.expect(t, !cached.valid)
			}
		}
	})
}

@(test)
vector_stroke_translation_reuses_geometry_linear_does_not :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [2]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{40, 0}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4}
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}, op = .Stroke, stroke = stroke), Vector_Error.None)
		geometry_id := vector_path_entry(handle).cache[0].geometry_id

		translated := Vector_Transform{1, 0, 0, 1, 18.5, -3}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 255, 0, 255}, translated, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		testing.expect_value(t, vector_path_entry(handle).cache[0].geometry_id, geometry_id)
		testing.expect_value(t, len(vector_path_entry(handle).cache), 1)

		scaled := Vector_Transform{2, 0, 0, 2, 0, 0}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 0, 255, 255}, scaled, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		entry := vector_path_entry(handle)
		valid_strokes := 0
		for cached in entry.cache {
			if cached.valid && cached.op == .Stroke {
				valid_strokes += 1
			}
		}

		testing.expect_value(t, valid_strokes, 2)
	})
}

@(test)
vector_stroke_ignores_fill_rule_and_keys_path_length :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [2]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{60, 0}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		dash := [2]f64{20, 10}
		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, dash = dash[:]}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {255, 0, 0, 255}, rule = .Nonzero, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 255, 0, 255}, rule = .Even_Odd, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		testing.expect_value(t, len(vector_path_entry(handle).cache), 1)

		stroke_pl := stroke
		stroke_pl.path_length = 40
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 0, 255, 255}, op = .Stroke, stroke = stroke_pl),
			Vector_Error.None,
		)
		valid := 0
		for cached in vector_path_entry(handle).cache {
			if cached.valid {
				valid += 1
			}
		}

		testing.expect_value(t, valid, 2)
	})
}

@(test)
vector_stroke_non_scaling_ignores_instance_morph_width :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [2]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{40, 0}, {}, {}}},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		stroke := Vector_Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, non_scaling = true}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {255, 0, 0, 255}, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		base := vector_path_entry(handle).cache[0].bounds

		morph := Vector_Transform{3, 0, 0, 3, 0, 0}
		testing.expect_value(
			t,
			Draw_Vector_Path(handle, {0, 255, 0, 255}, instance_morph = morph, op = .Stroke, stroke = stroke),
			Vector_Error.None,
		)
		entry := vector_path_entry(handle)
		stroke_slots := 0
		morphed_h := f32(0)
		for cached in entry.cache {
			if cached.valid && cached.op == .Stroke {
				stroke_slots += 1
				if cached.morph == morph {
					morphed_h = cached.bounds.h
				}
			}
		}

		testing.expect_value(t, stroke_slots, 2)
		// Non-scaling width stays ~4 even under a 3× instance morph; a GPU morph
		// of the expanded mesh would have produced ~12.
		testing.expectf(t, morphed_h < base.h * 1.5 + 1, "morphed height=%v base=%v", morphed_h, base.h)
	})
}
