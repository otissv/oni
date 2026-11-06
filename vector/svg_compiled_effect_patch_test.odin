#+test
package oni_vector

import "core:testing"

@(test)
svg_compiled_effect_patches_preserve_mask_transform_and_group_opacity :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><mask id="m" maskUnits="userSpaceOnUse"><ellipse id="e" cx="10" cy="10" rx="8" ry="6" fill="white"/></mask></defs><g transform="translate(4 7)"><g id="g" opacity=".7" mask="url(#m)"><path d="M0 0L20 0L0 20Z" fill="red"/></g></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	e, _ := Svg_Asset_Lookup(asset, "e")
	g, _ := Svg_Asset_Lookup(asset, "g")
	overrides := [2]Svg_Override{{target = e, property = .Transform, transform = {1, 0, 0, 1, 2, 3}}, {target = g, property = .Opacity, opacity = .4}}
	testing.expect(t, svg_overrides_can_patch_compiled_roots(asset, overrides[:]))
	instance, result := Svg_Prepare_Instance(asset, overrides[:])
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok)
	if instance == nil { return }
	testing.expect_value(t, instance.roots[0].opacity, f64(.4))
	ellipse := instance.roots[0].children[0].mask_nodes[0].children[0]
	testing.expect_value(t, ellipse.item.transform, Affine{1, 0, 0, 1, 6, 10})
	testing.expect_value(t, asset.roots[0].opacity, f64(.7))
	testing.expect_value(t, asset.roots[0].children[0].mask_nodes[0].children[0].item.transform, Affine{1, 0, 0, 1, 4, 7})
}

@(test)
svg_transform_patch_rejects_nonfinite_parent_composition :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<g transform="scale(1e300)"><path id="p" d="M0 0L1 0L0 1Z"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	testing.expect(t, loaded.ok)
	if asset == nil { return }
	p, _ := Svg_Asset_Lookup(asset, "p")
	override := [1]Svg_Override{{target = p, property = .Transform, transform = {1e300, 0, 0, 1e300, 0, 0}}}
	instance, result := Svg_Prepare_Instance(asset, override[:])
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, !result.ok && instance == nil)
	testing.expect_value(t, result.error, Svg_Diagnostic_Category.Invalid_Value)
}
