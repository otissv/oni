#+test
package oni

import "core:testing"

@(test)
svg_scene_records_masks_strokes_and_isolated_opacity :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><defs><mask id="m" mask-type="alpha"><rect width="100%" height="100%" fill="white"/></mask></defs><g opacity=".5"><rect width="20" height="20" fill="red" stroke="blue" stroke-width="2" mask="url(#m)"/></g></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
		if asset == nil { return }
		state.ui.pass = .Layout
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		testing.expect_value(t, len(state.vector.paths), 0)
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		f := vector_frame()
		testing.expect_value(t, len(f.draws), 1)
		if len(f.draws) != 1 { return }
		root := f.records[f.draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Group)
		testing.expect_value(t, root.opacity, f32(.5))
		testing.expect_value(t, f.records[root.first_child].kind, Vector_Node_Kind.Mask)
		vector_expect_owned_svg_cache(t)
	})
}

@(test)
svg_scene_nested_clip_intersection_retains_all_children :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><defs><clipPath id="a"><rect width="30" height="30"/></clipPath><clipPath id="b" clip-path="url(#a)"><rect x="20" y="20" width="20" height="20"/><rect x="32" y="32" width="5" height="5"/></clipPath></defs><rect width="40" height="40" clip-path="url(#b)"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
		if asset == nil { return }
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		f := vector_frame()
		testing.expect_value(t, len(f.draws), 1)
		if len(f.draws) != 1 { return }
		root := f.records[f.draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Clip)
		testing.expect_value(t, root.bounds, Rect{20, 20, 10, 10})
	})
}

@(test)
svg_recording_owns_paints_after_asset_release :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="p"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect width="10" height="10" fill="url(#p)"/></svg>`)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, asset != nil && result.ok)
		if asset == nil { return }
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		Destroy_Svg_Asset(asset)
		testing.expect_value(t, len(vector_frame().draws), 1)
		testing.expect_value(t, vector_frame().ramp_rows, 1)
		vector_expect_owned_svg_cache(t)
	})
}

@(test)
svg_clip_preparation_respects_aggregate_frame_budget :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="c"><rect width="10" height="10"/></clipPath></defs><rect width="10" height="10" clip-path="url(#c)"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, asset != nil && result.ok)
		if asset == nil { return }
		state.ui.pass = .Draw
		vector_frame().new_segments = VECTOR_MAX_NEW_SEGMENTS
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, len(vector_frame().draws), 0)
		vector_expect_owned_svg_cache(t)
	})
}

@(test)
svg_gpu_numeric_overflow_rejects_entire_submission :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g" x2="1e300"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect width="5" height="5"/><rect x="10" width="5" height="5" fill="url(#g)"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, asset != nil && result.ok)
		if asset == nil { return }
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().draws), 0)
		testing.expect_value(t, len(vector_frame().vertices), 0)
		vector_expect_owned_svg_cache(t)
	})
}

@(test)
svg_non_scaling_stroke_dpi_conversion_preserves_source_data :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		state.dpi.scale = 2
		dash := [2]f64{4, 2}
		stroke := Vector_Stroke{width = 3, cap = .Butt, join = .Miter, miter_limit = 4, dash = dash[:], dash_offset = 1, non_scaling = true}
		converted, err := vector_stroke_from_cpu(stroke)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, converted.width, f64(6))
		testing.expect_value(t, converted.dash[0], f64(8))
		testing.expect_value(t, converted.dash_offset, f64(2))
		testing.expect_value(t, dash, [2]f64{4, 2})
		stroke.path_length = 100
		converted, err = vector_stroke_from_cpu(stroke)
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, converted.dash[0], f64(4))
		testing.expect_value(t, converted.dash_offset, f64(1))
	})
}

@(test)
svg_reload_engine_wrappers_preserve_failed_assets :: proc(t: ^testing.T) {
	asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="12" height="12"/></svg>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	revision := asset.revision
	result := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>x</text></svg>`)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, !result.ok)
	testing.expect_value(t, asset.revision, revision)
	ok := Reload_Svg_Memory(asset, `<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="20" height="20"/></svg>`)
	defer Destroy_Svg_Load_Result(&ok)
	testing.expect(t, ok.ok && asset.revision > revision)
}
