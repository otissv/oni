#+test
package oni_vector

import "core:fmt"
import "core:testing"

@(test)
svg_instances_pin_geometry_across_reload_and_asset_destruction :: proc(t: ^testing.T) {
	for _ in 0 ..< 100 {
		asset, loaded := svg_test_load(`<rect width="10" height="10"/>`)
		Destroy_Svg_Load_Result(&loaded)
		instance, prepared := Svg_Prepare_Instance(asset)
		Destroy_Svg_Load_Result(&prepared)
		testing.expect(t, instance != nil)
		if instance == nil { Destroy_Svg_Asset(asset); return }
		owner := asset.owner
		testing.expect_value(t, owner.refs, i64(2))
		reloaded := Reload_Svg_From_String(asset, `<svg xmlns="http://www.w3.org/2000/svg"><rect width="20" height="20"/></svg>`)
		testing.expect(t, reloaded.ok)
		Destroy_Svg_Load_Result(&reloaded)
		testing.expect_value(t, owner.refs, i64(1))
		Destroy_Svg_Asset(asset)
		bounds, err := Geometry_Bounds(instance.roots[0].item.commands)
		testing.expect_value(t, err, Error.None)
		testing.expect_value(t, bounds.max, Point{10, 10})
		Destroy_Svg_Instance(instance)
	}
}

@(test)
svg_reload_success_replaces_content_and_bumps_revision :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="a" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	handle, ok := Svg_Asset_Lookup(asset, "a")
	testing.expect(t, ok)
	old_revision := asset.revision

	result := Reload_Svg_From_String(asset, fmt.tprintf(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" width="20" height="20"/></svg>`))
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok)
	testing.expect(t, asset.revision > old_revision)
	handle_after, ok_after := Svg_Asset_Lookup(asset, "a")
	testing.expect(t, ok_after && handle_after.revision == asset.revision)
	testing.expect(t, handle.revision != handle_after.revision)
}

@(test)
svg_reload_failure_preserves_previous_revision :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="a" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	old_revision := asset.revision
	handle, ok := Svg_Asset_Lookup(asset, "a")
	testing.expect(t, ok)

	result := Reload_Svg_From_String(asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>unsupported</text></svg>`)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, !result.ok)
	testing.expect_value(t, asset.revision, old_revision)
	still, still_ok := Svg_Asset_Lookup(asset, "a")
	testing.expect(t, still_ok && still.revision == handle.revision)
}

@(test)
svg_reload_repeated_cycles_return_to_baseline :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="a" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)

	for cycle in 0 ..< 100 {
		good := Reload_Svg_From_String(asset, fmt.tprintf(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" width="%d" height="10"/></svg>`, 10 + cycle))
		testing.expect(t, good.ok)
		Destroy_Svg_Load_Result(&good)
		bad := Reload_Svg_From_String(asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>x</text></svg>`)
		testing.expect(t, !bad.ok)
		Destroy_Svg_Load_Result(&bad)
		_, ok := Svg_Asset_Lookup(asset, "a")
		testing.expect(t, ok)
		_ = cycle
	}
}

@(test)
svg_reload_nil_asset_owns_diagnostic_result :: proc(t: ^testing.T) {
	result := Reload_Svg_From_String(nil, `<svg xmlns="http://www.w3.org/2000/svg"/>`)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, !result.ok)
	testing.expect_value(t, result.error, Svg_Diagnostic_Category.Invalid_Handle)
	testing.expect(t, len(result.diagnostics) > 0)
}
