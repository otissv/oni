#+test
package oni_vector

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

@(private)
svg_test_load :: proc(body: string) -> (^Svg_Asset, Svg_Load_Result) {
	return Load_Svg_From_String(fmt.tprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">%s</svg>`, body))
}

@(test)
svg_contract_rejects_invalid_complete_documents :: proc(t: ^testing.T) {
	cases := []string{
		`<defs><path d="M0 0 L1"/></defs>`,
		`<g display="none"><rect width="bad" height="10"/></g>`,
		`<rect width="10" height="10" unknown="1"/>`,
		`<defs><rect filter="url(#f)" width="1" height="1"/></defs>`,
		`<style>.unused { unsupported: 1; }</style>`,
		`<rect width="10garbage" height="1"/>`,
		`<path d="M0 0 L1e999 0"/>`,
		`<use href="other.svg#x"/>`,
		`<defs><use href="#missing"/></defs>`,
		`<linearGradient id="a" href="#b"/><linearGradient id="b" href="#a"/>`,
		`<rect width="1" width="2"/>`,
		`<rect p:width="1"/>`,
		`<g>&unknown;</g>`,
		`<g>&#0;</g>`,
		`<g>&#xD800;</g>`,
		`<linearGradient id="g" xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="external.svg#g"/>`,
		`<defs><mask id="m"><rect class="loop" width="1" height="1"/></mask></defs><style>.loop { mask: url(#m); }</style>`,
		`<rect pathLength="1px" width="1" height="1"/>`,
		`<linearGradient id="g"><stop offset="1px"/></linearGradient>`,
		`<g>unconverted lettering</g>`,
		`<path d="M0 0"><rect width="1" height="1"/></path>`,
		`<path d="M0 0L1 1" stroke-linecap="invalid"/>`,
		`<path d="M0 0L1 1" stroke-linejoin="invalid"/>`,
		`<path d="M0 0L1 1" stroke-miterlimit=".5"/>`,
		`<path d="M0 0L1 1" stroke-dasharray="1 -2"/>`,
		`<path d="M0 0L1 1" vector-effect="invalid"/>`,
		`<path d="M0 0L1 1" paint-order="fill fill"/>`,
		`<g mask-type="invalid"/>`,
		`<g color-interpolation="invalid"/>`,
	}
	for source in cases {
		asset, result := svg_test_load(source)
		testing.expect(t, asset == nil && !result.ok && len(result.diagnostics) > 0, source)
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_contract_stroke_properties_reach_scene_data :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<path d="M0 0L40 20" fill="none" stroke="rgba(0,0,255,.5)" stroke-width="10%" stroke-linecap="square" stroke-linejoin="bevel" stroke-miterlimit="2" stroke-dasharray="10% 2" stroke-dashoffset="3" pathLength="100" vector-effect="non-scaling-stroke" stroke-opacity=".5" paint-order="stroke fill"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil || len(asset.roots) != 1 { return }
	item := asset.roots[0].item
	settings := item.stroke_settings
	testing.expect(t, !item.draw_fill && item.draw_stroke)
	testing.expect(t, abs(settings.width - 7.905694150420948) < 1e-12)
	testing.expect(t, settings.cap == .Square && settings.join == .Bevel && settings.miter_limit == 2)
	testing.expect(t, len(settings.dash) == 2 && abs(settings.dash[0] - settings.width) < 1e-12 && settings.dash[1] == 2)
	testing.expect(t, settings.dash_offset == 3 && settings.path_length == 100 && settings.non_scaling)
	testing.expect(t, item.stroke_opacity == .5 && item.paint_order == .Stroke_Fill)
}

@(test)
svg_contract_defs_are_nonrendering_and_use_resolves_target_style :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<defs><g id="shape" fill="red"><rect width="10" height="10"/></g></defs><use href="#shape" x="7" transform="scale(2)" fill="blue"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 1)
	if len(items) != 1 { return }
	testing.expect_value(t, items[0].fill.solid, Color{255, 0, 0, 255})
	testing.expect_value(t, items[0].transform[4], f64(14))
}

@(test)
svg_contract_css_compounds_cascade_inheritance_and_visibility :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<style>g > rect.a.b, .unused { fill: red !important; } svg g rect { stroke: blue; }</style><g opacity=".5" transform="translate(3)" visibility="hidden"><rect class="a b" width="10" height="10" visibility="visible" fill="green" style="fill: yellow"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 1)
	if len(items) != 1 { return }
	testing.expect_value(t, items[0].fill.solid, Color{255, 0, 0, 255})
	testing.expect_value(t, items[0].stroke.solid, Color{0, 0, 255, 255})
	testing.expect_value(t, items[0].opacity, f64(1))
	testing.expect_value(t, items[0].transform[4], f64(3))
	testing.expect_value(t, asset.roots[0].opacity, f64(.5))
}

@(test)
svg_contract_viewports_lengths_and_rounded_rects :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<svg x="10" y="5" width="40" height="40" viewBox="0,0,20,10"><rect width="50%" height="100%" rx="2"/></svg>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 1)
	if len(items) != 1 { return }
	testing.expect_value(t, items[0].transform, Affine{2, 0, 0, 2, 10, 15})
	found_arc := false
	for command in items[0].commands { found_arc = found_arc || command.kind == .Arc }
	testing.expect(t, found_arc)
	for unit in ([]string{"px", "in", "cm", "mm", "pt", "pc"}) {
		v, ok := svg_parse_length(strings.concatenate({"1", unit}, context.temp_allocator), 100)
		testing.expect(t, ok && v > 0, unit)
	}
}

@(test)
svg_contract_path_grammar_and_smooth_control_reset :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, Parse_Path_Data("M1e1,2 L3-4 C1 2 3 4 5 6 L7 8 S9 10 11 12 A2 3 45 01 15 16z", &path), Error.None)
	if len(path.commands) < 5 { return }
	testing.expect_value(t, path.commands[4].points[0], Point{7, 8})
	for data in ([]string{"L0 0", "M0 0 L", "M0 0 L1", "M0 0z1", "M0 0 A1 1 0 2 0 1 1", "M0,,0", "M0 0 C1 2"}) {
		testing.expect(t, Parse_Path_Data(data, &path) != .None, data)
	}
}

@(test)
svg_contract_gradients_inherit_stops_and_percent_axes :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<defs><linearGradient id="base"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><linearGradient id="derived" href="#base" x2="100%" y2="100%" gradientUnits="userSpaceOnUse"/></defs><rect width="10" height="10" fill="url(#derived)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	if len(items) != 1 { testing.expect(t, false); return }
	testing.expect_value(t, len(items[0].fill.linear.stops), 2)
	testing.expect_value(t, items[0].fill.linear.x2, f64(100))
	testing.expect_value(t, items[0].fill.linear.y2, f64(50))
}

@(test)
svg_contract_gradient_styles_and_stop_css :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<style>stop.first { stop-color: currentColor; stop-opacity: .5 }</style><defs><linearGradient id="g" color="blue" color-interpolation="linearRGB"><stop class="first" offset="0"/><stop offset="1" stop-color="red"/></linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil || len(asset.roots) != 1 { return }
	gradient := asset.roots[0].item.fill.linear
	testing.expect_value(t, gradient.color_interpolation, Color_Interpolation.Linear_RGB)
	testing.expect_value(t, len(gradient.stops), 2)
	if len(gradient.stops) == 2 { testing.expect_value(t, gradient.stops[0].color, Color{0, 0, 255, 128}) }
}

@(test)
svg_contract_mask_and_shape_opacity_compile_as_composition :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<defs><mask id="m" mask-type="alpha"><rect width="100%" height="100%" fill="white"/></mask></defs><rect width="20" height="20" fill="red" stroke="blue" stroke-width="2" opacity=".5" mask="url(#m)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	testing.expect(t, len(asset.roots) == 1 && asset.roots[0].kind != .Path)
}

@(test)
svg_contract_metadata_scope_entities_and_cdata :: proc(t: ^testing.T) {
	source := `<?xml version="1.0"?><s:svg xmlns:s="http://www.w3.org/2000/svg" xmlns:p="urn:editor"><s:metadata><p:thing value="&amp;&#65;&#x42;"/></s:metadata><?editor ok?><s:style><![CDATA[rect { fill: red; }]]></s:style><s:g xmlns="urn:other"><s:rect width="10" height="10"/></s:g></s:svg><!--end-->`
	asset, result := Load_Svg_From_String(source)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
}

@(test)
svg_contract_lifetime_and_repeated_failure_cleanup :: proc(t: ^testing.T) {
	for _ in 0 ..< 100 {
		source := strings.clone(`<svg xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="paint"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><g fill="url(#paint)" stroke="red" stroke-dasharray="2,3"><rect id="a" width="4" height="5"/><rect id="b" width="6" height="7"/></g></svg>`)
		asset, result := Load_Svg_From_String(source)
		delete(source)
		testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
		if asset != nil {
			a, a_ok := Svg_Asset_Lookup(asset, "a")
			b, b_ok := Svg_Asset_Lookup(asset, "b")
			testing.expect(t, a_ok && b_ok && a.index != b.index && a.revision == b.revision)
		}
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
		bad, failure := svg_test_load(`<rect width="4" height="5"/><g fill="url(#missing)"><path d="M0 0"/></g>`)
		testing.expect(t, bad == nil && !failure.ok)
		Destroy_Svg_Asset(bad)
		Destroy_Svg_Load_Result(&failure)
	}
}

@(test)
svg_contract_limits_reject_before_unbounded_work :: proc(t: ^testing.T) {
	for index in 0 ..< 7 {
		limits := DEFAULT_SVG_LIMITS
		body := `<rect width="1" height="1"/>`
		switch index {
		case 0: limits.max_decoded_bytes = 1
		case 1: limits.max_elements = 1
		case 2: limits.max_xml_depth = 1
		case 3: limits.max_path_commands = 1; body = `<defs><rect width="1" height="1"/></defs>`
		case 4: limits.max_css_rules = 0; body = `<style>rect{fill:red}</style>`
		case 5: limits.max_selector_ops = 0; body = `<style>rect{fill:red}</style><rect width="1" height="1"/>`
		case 6: limits.max_expanded_references = 0; body = `<defs><rect id="r" width="1" height="1"/></defs><use href="#r"/>`
		}
		asset, result := Load_Svg_From_String(fmt.tprintf(`<svg xmlns="http://www.w3.org/2000/svg">%s</svg>`, body), {limits = limits})
		testing.expectf(t, asset == nil && !result.ok && len(result.diagnostics) > 0, "limit %d: %v", index, result)
		if len(result.diagnostics) > 0 { testing.expect_value(t, result.diagnostics[0].category, Svg_Diagnostic_Category.Limit_Exceeded) }
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_contract_allocation_failure_rolls_back :: proc(t: ^testing.T) {
	for allowed in 0 ..< 40 {
		failing := Test_Failing_Allocator{backing = context.allocator, remaining = allowed}
		allocator := mem.Allocator{procedure = test_failing_allocator_proc, data = &failing}
		asset, result := Load_Svg_From_String(`<svg xmlns="http://www.w3.org/2000/svg"><defs><mask id="m"><rect width="20" height="20" fill="white"/></mask></defs><rect width="20" height="20" mask="url(#m)"/></svg>`, allocator = allocator)
		testing.expect(t, result.ok == (asset != nil))
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_contract_clip_mesh_boolean_coverage :: proc(t: ^testing.T) {
	a: Path
	b: Path
	defer Destroy_Path(&a)
	defer Destroy_Path(&b)
	_ = Rectangle(&a, {0, 0}, {3, 3})
	_ = Rectangle(&b, {2, 2}, {3, 3})
	ma, ea := Tessellate(a.commands[:], IDENTITY, .Nonzero)
	mb, eb := Tessellate(b.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&ma)
	defer Destroy_Mesh(&mb)
	testing.expect(t, ea == .None && eb == .None)
	intersection: Mesh
	defer Destroy_Mesh(&intersection)
	testing.expect_value(t, Intersect_Meshes_Into(&intersection, ma, mb), Error.None)
	area := f64(0)
	for i := 0; i < len(intersection.indices); i += 3 {
		p := intersection.vertices[intersection.indices[i]]
		q := intersection.vertices[intersection.indices[i + 1]]
		r := intersection.vertices[intersection.indices[i + 2]]
		area += abs(f64((q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x))) / 2
	}
	testing.expect_value(t, area, f64(1))
}

@(test)
svg_contract_object_bounds_include_exact_curve_extrema :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Circle(&path, {88, 30}, 22)
	bounds, err := Geometry_Bounds(path.commands[:])
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bounds, Bounds{min = {66, 8}, max = {110, 52}})
	Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Cubic_To(&path, {0, 3}, {3, 3}, {3, 0})
	bounds, err = Geometry_Bounds(path.commands[:])
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bounds.max.y, f64(2.25))
}

@(test)
svg_contract_escaped_selectors_and_utf8_annotations :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<title>Replacement character: �</title><style>.a\62 { fill: red }</style><rect class="ab" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 1)
	if len(items) == 1 { testing.expect_value(t, items[0].fill.solid, Color{255, 0, 0, 255}) }
}

@(test)
svg_contract_rejects_malformed_xml_declarations :: proc(t: ^testing.T) {
	for preamble in ([]string{`<?xml version="9.0"?>`, `<?xml?>`, `<?xml version="1.0" encoding="latin1"?>`, `<?XML version="1.0"?>`, `<?xml-stylesheet href="external.css"?>`}) {
		asset, result := Load_Svg_From_String(strings.concatenate({preamble, `<svg xmlns="http://www.w3.org/2000/svg"/>`}, context.temp_allocator))
		testing.expect(t, asset == nil && !result.ok, preamble)
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_contract_css_comments_and_case_insensitive_keywords :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<style>rect.a/**/.b { FILL: blue !IMPORTANT }</style><rect class="a b" width="10" height="10" style="fill: /* author */ RED !important; visibility: VISIBLE"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 1)
	if len(items) == 1 { testing.expect_value(t, items[0].fill.solid, Color{255, 0, 0, 255}) }
}

@(test)
svg_contract_css_comments_preserve_quoted_urls :: proc(t: ^testing.T) {
	for source in ([]string{`fill: url('#a/*b*/');`, `fill: url("#a/*b*/");`, `fill: url('#a\'/*b*/');`}) {
		clean, ok := css_remove_comments(source)
		testing.expect(t, ok)
		testing.expect_value(t, clean, source)
	}
}

@(test)
svg_contract_metadata_still_requires_valid_xml_names :: proc(t: ^testing.T) {
	for body in ([]string{"<metadata><\U000F0000/></metadata>", "<metadata xmlns:p=\"urn:editor\"><p:\u0301/></metadata>"}) {
		asset, result := svg_test_load(body)
		testing.expect(t, asset == nil && !result.ok, body)
		Destroy_Svg_Asset(asset)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_contract_partial_points_and_xml_failure_return_no_owned_debris :: proc(t: ^testing.T) {
	points, err := Parse_Points_Attribute("0,0 1,1 2,bad")
	defer delete(points)
	testing.expect(t, err != .None && len(points) == 0)
	result: Svg_Load_Result
	root, ok := Parse_Xml_Document(`<svg xmlns="http://www.w3.org/2000/svg" width="1" height="2" p:bad="1"/>`, DEFAULT_SVG_LIMITS, &result)
	defer Destroy_Svg_Load_Result(&result)
	defer Destroy_Xml_Node(&root)
	testing.expect(t, !ok)
}

@(test)
svg_contract_singular_gradients_and_svg11_focal_clamping :: proc(t: ^testing.T) {
	asset, result := svg_test_load(`<defs><linearGradient id="zero" gradientTransform="scale(0)"><stop offset="0"/></linearGradient><radialGradient id="far" cx=".5" cy=".5" r=".5" fx="2" fy=".5"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient></defs><rect width="10" height="10" fill="url(#zero)"/><rect x="20" width="10" height="10" fill="url(#far)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, asset != nil && result.ok, "%v", result.diagnostics[:])
	if asset == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, len(items), 2)
	if len(items) != 2 { return }
	testing.expect_value(t, items[0].fill.kind, Paint_Kind.None)
	testing.expect_value(t, items[1].fill.radial.fx, f64(1))
	color, painted := Paint_Color_At(items[1].fill, {2, .5}, {min = {0, 0}, max = {1, 1}})
	testing.expect(t, painted)
	testing.expect_value(t, color, Color{0, 0, 255, 255})
}
