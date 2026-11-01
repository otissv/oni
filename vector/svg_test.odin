#+test
package oni_vector

import "core:os"
import "core:reflect"
import "core:strings"
import "core:testing"

@(private)
Svg_Fixture_Case :: struct { name, file, expect, category: string }

@(private)
svg_check_fixture :: proc(t: ^testing.T, fixture: Svg_Fixture_Case) {
	testing.expect(t, fixture.name != "" && fixture.file != "" && (fixture.expect == "positive" || fixture.expect == "negative"), "incomplete fixture manifest entry")
	if fixture.file == "" { return }
	path := strings.concatenate({"fixtures/vector/m6/", fixture.file}, context.temp_allocator)
	asset, result := Load_Svg_From_File(path)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&result)
	if fixture.expect == "positive" {
		testing.expect(t, asset != nil && result.ok, path)
	} else {
		testing.expect(t, asset == nil && !result.ok && len(result.diagnostics) > 0, path)
		category, valid := reflect.enum_from_name(Svg_Diagnostic_Category, fixture.category)
		testing.expect(t, valid && category != .None, "unknown diagnostic category in fixture manifest")
		if valid && len(result.diagnostics) > 0 { testing.expect(t, result.diagnostics[0].category == category, path) }
	}
}

@(test)
svg_m6_manifest_fixtures :: proc(t: ^testing.T) {
	manifest, err := os.read_entire_file("fixtures/vector/m6/manifest.toml", context.temp_allocator)
	testing.expect(t, err == nil)
	if err != nil { return }
	fixture: Svg_Fixture_Case
	seen := make(map[string]bool, context.temp_allocator)
	count := 0
	for line in strings.split(string(manifest), "\n", context.temp_allocator) {
		value := strings.trim_space(line)
		if value == "" || strings.has_prefix(value, "#") { continue }
		if value == "[[case]]" {
			if fixture.name != "" {
				svg_check_fixture(t, fixture)
				testing.expect(t, !seen[fixture.name], "duplicate fixture name")
				seen[fixture.name] = true
				count += 1
			}
			fixture = {}
			continue
		}
		split := strings.index_byte(value, '=')
		testing.expect(t, split > 0, "invalid fixture manifest line")
		if split <= 0 { continue }
		name := strings.trim_space(value[:split])
		text := strings.trim(strings.trim_space(value[split + 1:]), `"`)
		switch name {
		case "name": fixture.name = text
		case "file": fixture.file = text
		case "expect": fixture.expect = text
		case "category": fixture.category = text
		case: testing.expect(t, false, "unknown fixture manifest key")
		}
	}
	if fixture.name != "" {
		svg_check_fixture(t, fixture)
		testing.expect(t, !seen[fixture.name], "duplicate final fixture name")
		count += 1
	}
	testing.expect_value(t, count, 38)
}

@(test)
svg_fills_document_items :: proc(t: ^testing.T) {
	asset, result := Load_Svg_From_File("fixtures/vector/fills.svg")
	defer Destroy_Svg_Load_Result(&result)
	defer Destroy_Svg_Asset(asset)
	testing.expect(t, asset != nil && result.ok)
	if asset == nil {
		return
	}

	testing.expect_value(t, svg_count_path_leaves(asset.roots), 6)
	testing.expect_value(t, len(asset.roots), 6)
	w, h := Svg_Asset_Intrinsic_Size(asset)
	testing.expect(t, w == 128 && h == 64)
}

@(test)
svg_shape_path_bowtie_command_count :: proc(t: ^testing.T) {
	node := Xml_Node{
		kind = .Element,
		name = "path",
		attrs = []Xml_Attr{{name = "d", value = "M2 36 L30 60 L2 60 L30 36 Z"}},
	}
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, svg_shape_path(&node, &path), Error.None)
	testing.expect_value(t, len(path.commands), 5)
}

@(test)
svg_fills_path_commands_match_native :: proc(t: ^testing.T) {
	asset, result := Load_Svg_From_File("fixtures/vector/fills.svg")
	defer Destroy_Svg_Load_Result(&result)
	defer Destroy_Svg_Asset(asset)
	testing.expect(t, asset != nil && result.ok)
	if asset == nil || len(asset.roots) < 6 {
		return
	}

	for i in 0 ..< 6 {
		native: Path
		switch i {
		case 0:
			_ = Circle(&native, {16, 16}, 12)
			_ = Circle(&native, {16, 16}, 6)
		case 1:
			_ = Polyline(&native, []Point{{48, 2}, {57, 28}, {34, 12}, {62, 12}, {39, 28}}, true)
		case 2:
			_ = Move_To(&native, {66, 28})
			_ = Cubic_To(&native, {66, -4}, {94, -4}, {94, 28})
			_ = Quadratic_To(&native, {80, 40}, {66, 28})
			_ = Close(&native)
		case 3:
			_ = Polyline(&native, []Point{{2, 36}, {30, 60}, {2, 60}, {30, 36}}, true)
		case 4:
			_ = Rectangle(&native, {34, 40}, {28, 0.5})
		case 5:
			_ = Parse_Path_Data("M4 36 L28 36 L28 60 L4 60 Z M10 42 L10 54 L22 54 L22 42 Z", &native)
		}

		if i == 4 {
			testing.expect_value(t, len(asset.roots[i].item.commands), 5)
			got_bounds, got_error := Path_Bounds(asset.roots[i].item.commands)
			want_bounds, want_error := Path_Bounds(native.commands[:])
			testing.expect(t, got_error == .None && want_error == .None)
			testing.expect_value(t, got_bounds, want_bounds)

			Destroy_Path(&native)

			continue
		}

		got := len(asset.roots[i].item.commands)
		want := len(native.commands)
		testing.expectf(t, got == want, "path %v commands got %v want %v", i, got, want)
		Destroy_Path(&native)
	}
}

@(test)
svg_bowtie_path_data_command_count :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, Parse_Path_Data("M2 36 L30 60 L2 60 L30 36 Z", &path), Error.None)
	testing.expect_value(t, len(path.commands), 5)
}

@(test)
svg_thin_bar_preserves_exact_source_coordinates :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, Parse_Path_Data("M34 40 L62 40 L62 40.5 L34 40.5 Z", &path), Error.None)
	testing.expect_value(t, path.commands[2].points[0], Point{62, 40.5})
	native: Path
	defer Destroy_Path(&native)
	testing.expect_value(t, Rectangle(&native, {34, 40}, {28, 0.5}), Error.None)
	a, _ := Path_Bounds(path.commands[:])
	b, _ := Path_Bounds(native.commands[:])
	testing.expect_value(t, a, b)
}

@(test)
svg_namespace_documents_equivalent :: proc(t: ^testing.T) {
	a, ra := Load_Svg_From_File("fixtures/vector/m6/namespace-default.svg")
	defer Destroy_Svg_Load_Result(&ra)
	defer Destroy_Svg_Asset(a)
	b, rb := Load_Svg_From_File("fixtures/vector/m6/namespace-prefixed.svg")
	defer Destroy_Svg_Load_Result(&rb)
	defer Destroy_Svg_Asset(b)
	testing.expect(t, a != nil && b != nil && ra.ok && rb.ok)
	if a == nil || b == nil {
		return
	}

	testing.expect_value(t, svg_count_path_leaves(a.roots), svg_count_path_leaves(b.roots))
	testing.expect_value(t, a.width, b.width)
	testing.expect_value(t, a.height, b.height)
	if len(a.roots) != 1 || len(b.roots) != 1 { testing.expect(t, false); return }
	x, y := a.roots[0].item, b.roots[0].item
	testing.expect_value(t, x.transform, y.transform)
	testing.expect_value(t, x.fill.solid, y.fill.solid)
	testing.expect_value(t, len(x.commands), len(y.commands))
	if len(x.commands) == len(y.commands) {
		for command, index in x.commands { testing.expect_value(t, command, y.commands[index]) }
	}
}

@(test)
svg_symbol_instances_distinct_fill :: proc(t: ^testing.T) {
	asset, result := Load_Svg_From_File("fixtures/vector/m6/symbol-instances.svg")
	defer Destroy_Svg_Load_Result(&result)
	defer Destroy_Svg_Asset(asset)
	testing.expect(t, asset != nil && result.ok)
	leaves := svg_count_path_leaves(asset.roots)
	if leaves < 2 {
		return
	}

	found := 0
	first, second: Paint
	svg_walk_path_paints(asset.roots, &found, &first, &second)
	testing.expect(t, first.kind == .Solid && second.kind == .Solid)
	testing.expect(t, first.solid != second.solid)
}

@(private)
svg_walk_path_paints :: proc(nodes: []Svg_Draw_Node, found: ^int, first, second: ^Paint) {
	for &node in nodes {
		switch node.kind {
		case .Path:
			if found^ == 0 {
				first^ = node.item.fill
			} else if found^ == 1 {
				second^ = node.item.fill
			}

			found^ += 1
		case .Group, .Clip, .Mask:
			svg_walk_path_paints(node.children, found, first, second)
		}

		if found^ >= 2 {
			return
		}
	}
}
