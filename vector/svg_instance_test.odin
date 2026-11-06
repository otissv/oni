#+test
package oni_vector

import "core:testing"
import "core:mem"

@(test)
svg_flat_snapshot_failure_sweep_releases_all_owned_storage :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z"/><path id="q" d="M0 0L5 0L0 5Z"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	p, _ := Svg_Asset_Lookup(asset, "p")
	q, _ := Svg_Asset_Lookup(asset, "q")
	commands := [4]Command{{kind = .Move}, {kind = .Line, points = {{20, 0}, {}, {}}}, {kind = .Line, points = {{0, 20}, {}, {}}}, {kind = .Close}}
	overrides := [3]Svg_Override{{target = p, property = .Path, commands = commands[:]},
		{target = q, property = .Path, commands = commands[:]}, {target = p, property = .Fill, paint = Solid_Paint({10, 20, 30, 255})}}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	success := false
	for allowed in 0 ..< 16 {
		failing := Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), remaining = allowed}
		instance, result := Svg_Prepare_Instance(asset, overrides[:], allocator = {procedure = test_failing_allocator_proc, data = &failing})
		if failing.rejected { testing.expect_value(t, result.error, Svg_Diagnostic_Category.Allocation_Failed)
		} else {
			testing.expect(t, result.ok && instance != nil)
			success = true
			if instance != nil {
				testing.expect(t, raw_data(instance.roots[0].item.commands) != raw_data(commands[:]))
				testing.expect(t, raw_data(instance.roots[0].item.commands) != raw_data(instance.roots[1].item.commands))
			}
		}
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		if success { break }
	}
	testing.expect(t, success)
	budget := DEFAULT_SVG_INSTANCE_BUDGET
	budget.nodes = 1
	limited, rejected := Svg_Prepare_Instance(asset, overrides[:], budget, mem.tracking_allocator(&tracking))
	testing.expect(t, limited == nil)
	testing.expect_value(t, rejected.error, Svg_Diagnostic_Category.Limit_Exceeded)
	Destroy_Svg_Instance(limited)
	Destroy_Svg_Load_Result(&rejected)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
}

@(test)
svg_command_structure_key_is_exact_across_packed_word_boundary :: proc(t: ^testing.T) {
	commands: [41]Command
	for &command in commands { command.kind = .Line }
	commands[0].kind = .Move
	key: [2]u64
	hash := Commands_Hash(commands[:40], &key)
	testing.expect(t, key != {})
	testing.expect_value(t, hash, Commands_Hash(commands[:40]))
	for index in ([3]int{20, 21, 39}) {
		commands[index].kind = .Cubic
		changed: [2]u64
		_ = Commands_Hash(commands[:40], &changed)
		testing.expect(t, changed != key)
		commands[index].kind = .Line
	}
	commands[1].points[0].x = 10
	changed: [2]u64
	testing.expect(t, Commands_Hash(commands[:40], &changed) != hash && changed == key)
	_ = Commands_Hash(commands[:41], &changed)
	testing.expect(t, changed == {})
	commands[1].kind = .Arc
	_ = Commands_Hash(commands[:40], &changed)
	testing.expect(t, changed == {})
}

@(test)
svg_leaf_instances_remain_independent_across_repeated_storage_reuse :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z" fill="red"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	p, _ := Svg_Asset_Lookup(asset, "p")
	for cycle in 0 ..< 3 {
		first, a := Svg_Prepare_Instance(asset, []Svg_Override{{target = p, property = .Fill, paint = Solid_Paint({0, 255, 0, 255})}})
		second, b := Svg_Prepare_Instance(asset)
		testing.expect(t, a.ok && b.ok && first != second)
		if first != nil && second != nil {
			testing.expect_value(t, first.roots[0].item.fill.solid, Color{0, 255, 0, 255})
			testing.expect_value(t, second.roots[0].item.fill.solid, Color{255, 0, 0, 255})
		}
		Destroy_Svg_Instance(first)
		Destroy_Svg_Instance(second)
		Destroy_Svg_Load_Result(&a)
		Destroy_Svg_Load_Result(&b)
		budget := DEFAULT_SVG_INSTANCE_BUDGET
		budget.decoded_bytes = size_of(Svg_Instance) + 1
		limited, rejected := Svg_Prepare_Instance(asset, budget = budget)
		testing.expect(t, limited == nil && !rejected.ok && rejected.error == .Limit_Exceeded)
		Destroy_Svg_Instance(limited)
		Destroy_Svg_Load_Result(&rejected)
		_ = cycle
	}
}

@(test)
svg_definition_override_rejects_occurrence_chain_without_terminal :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	target, _ := Svg_Asset_Lookup(asset, "p")
	for index in ([3]u32{1, 63, 127}) {
		override := Svg_Override{target = target, property = .Fill, paint = Solid_Paint({255, 0, 0, 255})}
		override.occurrence.chain = index
		instance, result := Svg_Prepare_Instance(asset, []Svg_Override{override})
		testing.expect(t, instance == nil && result.error == .Invalid_Handle)
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_occurrence_handles_reject_forged_chain_indices_depths_and_terminals :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><g id="s"><rect id="r" width="2" height="2"/></g></defs><use id="u" href="#s"/><rect id="outside" width="3" height="3"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	u, _ := Svg_Asset_Lookup(asset, "u")
	r, _ := Svg_Asset_Lookup(asset, "r")
	outside, _ := Svg_Asset_Lookup(asset, "outside")
	valid, ok := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{u}, r)
	testing.expect(t, ok)
	again, found := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{u}, r)
	testing.expect(t, found && again == valid)
	for field in 0 ..< 4 {
		forged := valid
		switch field {
		case 0: forged.chain = max(u32)
		case 1: forged.depth = 0
		case 2: forged.element = outside
		case 3: forged.depth = 128
		}
		instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{occurrence = forged, property = .Fill, paint = Solid_Paint({255, 0, 0, 255})}})
		testing.expect(t, instance == nil && result.error == .Invalid_Handle)
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_occurrence_registry_exhaustion_preserves_existing_handles :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><rect id="r" width="2" height="2"/></defs><use id="a" href="#r"/><use id="b" href="#r"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	a, _ := Svg_Asset_Lookup(asset, "a")
	b, _ := Svg_Asset_Lookup(asset, "b")
	r, _ := Svg_Asset_Lookup(asset, "r")
	first, ok := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{a}, r)
	testing.expect(t, ok)
	reserved := asset.arena.reserved
	asset.arena.limit = reserved
	asset.arena.block.used = asset.arena.block.capacity
	_, rejected := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{b}, r)
	testing.expect(t, !rejected)
	again, found := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{a}, r)
	testing.expect(t, found && again == first)
	testing.expect_value(t, asset.arena.reserved, reserved)
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{occurrence = first, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})}})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok && instance != nil)
}

@(test)
svg_leaf_patches_apply_in_any_order_and_reject_duplicates :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="a" d="M0 0L10 0L0 10Z"/><path id="b" d="M0 0L20 0L0 20Z"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	a, _ := Svg_Asset_Lookup(asset, "a")
	b, _ := Svg_Asset_Lookup(asset, "b")
	overrides := [3]Svg_Override{
		{target = b, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})},
		{target = a, property = .Fill_Opacity, opacity = .25},
		{target = a, property = .Fill, paint = Solid_Paint({255, 0, 0, 255})},
	}
	instance, result := Svg_Prepare_Instance(asset, overrides[:])
	testing.expect(t, result.ok && instance != nil)
	if instance != nil {
		testing.expect_value(t, instance.roots[0].item.fill.solid, Color{255, 0, 0, 255})
		testing.expect_value(t, instance.roots[0].item.fill_opacity, f64(.25))
		testing.expect_value(t, instance.roots[1].item.fill.solid, Color{0, 0, 255, 255})
	}
	Destroy_Svg_Instance(instance)
	Destroy_Svg_Load_Result(&result)
	overrides[1] = overrides[2]
	instance, result = Svg_Prepare_Instance(asset, overrides[:])
	testing.expect(t, instance == nil && result.error == .Duplicate_Override)
	Destroy_Svg_Instance(instance)
	Destroy_Svg_Load_Result(&result)
}

@(test)
svg_compiled_leaf_patch_reports_allocation_failures_and_cleans_up :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	shape, _ := Svg_Asset_Lookup(asset, "p")
	stops := [2]Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}
	overrides := [1]Svg_Override{{target = shape, property = .Fill, paint = Linear_Paint({x2 = 10, stops = stops[:]})}}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	success := false
	for allowed in 0 ..< 128 {
		failing := Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), remaining = allowed}
		instance, result := Svg_Prepare_Instance(asset, overrides[:], allocator = {procedure = test_failing_allocator_proc, data = &failing})
		if failing.rejected { testing.expect_value(t, result.error, Svg_Diagnostic_Category.Allocation_Failed) } else { testing.expect(t, result.ok); success = true }
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		if success { break }
	}
	testing.expect(t, success)
}

@(test)
svg_flat_path_patch_owns_commands_and_preserves_compiled_style :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z" fill="red" transform="translate(3 4)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	shape, _ := Svg_Asset_Lookup(asset, "p")
	commands := [4]Command{{kind = .Move}, {kind = .Line, points = {{20, 0}, {}, {}}}, {kind = .Line, points = {{0, 20}, {}, {}}}, {kind = .Close}}
	overrides := [2]Svg_Override{
		{target = shape, property = .Path, commands = commands[:]},
		{target = shape, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})},
	}
	testing.expect(t, svg_overrides_can_patch_compiled_roots(asset, overrides[:]))
	instance, result := Svg_Prepare_Instance(asset, overrides[:])
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok && instance != nil)
	if instance == nil { return }
	commands[1].points[0].x = 100
	testing.expect_value(t, instance.roots[0].item.commands[1].points[0].x, f64(20))
	testing.expect_value(t, instance.roots[0].item.commands_hash, Commands_Hash(instance.roots[0].item.commands))
	testing.expect_value(t, instance.roots[0].item.fill.solid, Color{0, 0, 255, 255})
	testing.expect_value(t, instance.roots[0].item.transform, asset.roots[0].item.transform)
	testing.expect_value(t, asset.roots[0].item.commands[1].points[0].x, f64(10))
	testing.expect_value(t, asset.roots[0].item.commands_hash, Commands_Hash(asset.roots[0].item.commands))
	testing.expect_value(t, asset.roots[0].item.fill.solid, Color{255, 0, 0, 255})
	overrides[0].commands = nil
	testing.expect(t, !svg_overrides_can_patch_compiled_roots(asset, overrides[:]))
	limited := asset.limits
	asset.limits.max_path_commands = 3
	overrides[0].commands = commands[:]
	failed, rejected := Svg_Prepare_Instance(asset, overrides[:])
	defer Destroy_Svg_Instance(failed)
	testing.expect(t, !rejected.ok && failed == nil)
	Destroy_Svg_Load_Result(&rejected)
	asset.limits = limited
}

@(test)
svg_instances_apply_local_overrides_before_inheritance_without_mutating_asset :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<g id="parent" fill="red" transform="translate(2 3)"><rect id="shape" width="10" height="8"/><rect x="15" width="5" height="5" fill="green"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	testing.expect(t, loaded.ok)
	parent, _ := Svg_Asset_Lookup(asset, "parent")
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{
		{target = parent, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})},
		{target = parent, property = .Transform, transform = {1, 0, 0, 1, 7, 9}},
	})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, result.ok && instance != nil, "%v", result.diagnostics[:])
	if instance == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(instance.roots, &items)
	testing.expect_value(t, len(items), 2)
	if len(items) == 2 {
		testing.expect_value(t, items[0].fill.solid, Color{0, 0, 255, 255})
		testing.expect_value(t, items[1].fill.solid, Color{0, 128, 0, 255})
		testing.expect_value(t, items[0].transform[4], f64(7))
	}
	clear(&items)
	svg_flatten_paths(asset.roots, &items)
	testing.expect_value(t, items[0].fill.solid, Color{255, 0, 0, 255})
	testing.expect_value(t, items[0].transform[4], f64(2))
}

@(test)
svg_occurrence_handles_validate_nested_use_paths_and_override_precedence :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><g id="outer"><use id="inner" href="#leaf"/></g><rect id="leaf" width="10" height="10" fill="red"/></defs><use id="a" href="#outer"/><use id="b" x="20" href="#outer"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	a, _ := Svg_Asset_Lookup(asset, "a")
	b, _ := Svg_Asset_Lookup(asset, "b")
	inner, _ := Svg_Asset_Lookup(asset, "inner")
	leaf, _ := Svg_Asset_Lookup(asset, "leaf")
	occurrence, ok := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{b, inner}, leaf)
	testing.expect(t, ok)
	_, forged := Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{inner, a}, leaf)
	testing.expect(t, !forged)
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{
		{target = leaf, property = .Fill, paint = Solid_Paint({0, 255, 0, 255})},
		{occurrence = occurrence, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})},
	})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, result.ok, "%v", result.diagnostics[:])
	if instance == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(instance.roots, &items)
	testing.expect_value(t, len(items), 2)
	if len(items) == 2 {
		testing.expect_value(t, items[0].fill.solid, Color{0, 255, 0, 255})
		testing.expect_value(t, items[1].fill.solid, Color{0, 0, 255, 255})
	}
}

@(test)
svg_instance_rejects_duplicate_stale_and_invalid_overrides_atomically :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="r" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	handle, _ := Svg_Asset_Lookup(asset, "r")
	stale := handle
	stale.revision += 1
	for overrides in ([][]Svg_Override{
		{{target = handle, property = .Opacity, opacity = .5}, {target = handle, property = .Opacity, opacity = .7}},
		{{target = stale, property = .Opacity, opacity = .5}},
		{{target = handle, property = .Opacity, opacity = transmute(f64)u64(0x7ff8000000000000)}},
		{{target = handle, property = .Transform, transform = {1, 0, 0, transmute(f64)u64(0x7ff0000000000000), 0, 0}}},
	}) {
		instance, result := Svg_Prepare_Instance(asset, overrides)
		testing.expect(t, instance == nil && !result.ok && result.error != .None)
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_instance_owns_inline_paths_and_paints_after_inputs_and_asset_are_released :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="r" width="10" height="10"/>`)
	defer Destroy_Svg_Load_Result(&loaded)
	handle, _ := Svg_Asset_Lookup(asset, "r")
	path: Path
	_ = Rectangle(&path, {}, {20, 7})
	stops := make([]Gradient_Stop, 2)
	stops[0], stops[1] = {0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{
		{target = handle, property = .Path, commands = path.commands[:]},
		{target = handle, property = .Fill, paint = Linear_Paint({x2 = 1, stops = stops})},
	})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	Destroy_Path(&path)
	delete(stops)
	Destroy_Svg_Asset(asset)
	testing.expectf(t, result.ok, "%v", result.diagnostics[:])
	if instance == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(instance.roots, &items)
	bounds, err := Geometry_Bounds(items[0].commands)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bounds.max, Point{20, 7})
	testing.expect_value(t, items[0].fill.linear.stops[1].color, Color{0, 0, 255, 255})
}

@(test)
svg_instance_hidden_occurrences_and_terminal_use_have_structural_addresses :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><g id="s"><rect id="r" width="2" height="2"/></g></defs><g display="none"><use id="u" href="#s"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	u, _ := Svg_Asset_Lookup(asset, "u")
	r, _ := Svg_Asset_Lookup(asset, "r")
	_, ok := Svg_Asset_Lookup_Occurrence(asset, nil, u)
	testing.expect(t, ok)
	_, ok = Svg_Asset_Lookup_Occurrence(asset, []Svg_Element_Handle{u}, r)
	testing.expect(t, ok)
	_, ok = Svg_Asset_Lookup_Occurrence(asset, nil, r)
	testing.expect(t, !ok)
}

@(test)
svg_instance_recomputes_path_bounds_for_object_bbox_clipping :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs><clipPath id="c" clipPathUnits="objectBoundingBox"><rect width=".5" height="1"/></clipPath></defs><rect id="r" width="10" height="10" clip-path="url(#c)"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	r, _ := Svg_Asset_Lookup(asset, "r")
	path: Path
	defer Destroy_Path(&path)
	_ = Rectangle(&path, {}, {40, 20})
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{target = r, property = .Path, commands = path.commands[:]}})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, result.ok, "%v", result.diagnostics[:])
	if instance == nil { return }
	clip := instance.roots[0].clip_nodes[0].item
	bounds, err := Geometry_Bounds(clip.commands, clip.transform)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bounds.max, Point{20, 20})
}

@(test)
svg_instance_allocation_failures_and_repeated_instances_release_every_owner :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<g id="g"><rect width="10" height="10"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	g, _ := Svg_Asset_Lookup(asset, "g")
	for i in 0 ..< 100 {
		instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{target = g, property = .Fill, paint = Solid_Paint({u8(i), 0, 0, 255})}})
		testing.expect(t, result.ok)
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
	for failure in 0 ..< 40 {
		failing := Test_Failing_Allocator{backing = context.allocator, remaining = failure}
		instance, result := Svg_Prepare_Instance(asset, allocator = {procedure = test_failing_allocator_proc, data = &failing})
		if instance == nil { testing.expect(t, !result.ok && result.error != .None) }
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_instance_rejects_shape_only_properties_on_containers_and_nonvisual_targets :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<defs id="defs"/><g id="g"><rect width="3" height="3"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	g, _ := Svg_Asset_Lookup(asset, "g")
	defs, _ := Svg_Asset_Lookup(asset, "defs")
	for override in ([]Svg_Override{
		{target = g, property = .Path},
		{target = g, property = .Stroke_Settings, stroke = DEFAULT_STROKE},
		{target = defs, property = .Opacity, opacity = .5},
	}) {
		instance, result := Svg_Prepare_Instance(asset, []Svg_Override{override})
		testing.expect(t, instance == nil && !result.ok)
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
	}
}

@(test)
svg_instance_definition_colour_override_reaches_gradient_and_mask_source_styles :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<g id="palette" color="red"><defs><linearGradient id="p"><stop stop-color="currentColor"/><stop offset="1" stop-color="white"/></linearGradient><mask id="m" mask-type="alpha"><rect width="100%" height="100%" fill="currentColor"/></mask></defs><rect width="10" height="10" fill="url(#p)" mask="url(#m)"/></g>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	palette, _ := Svg_Asset_Lookup(asset, "palette")
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{target = palette, property = .Color, color = {0, 0, 255, 255}}})
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expectf(t, result.ok, "%v", result.diagnostics[:])
	if instance == nil { return }
	items := make([dynamic]Svg_Path_Item, context.temp_allocator)
	svg_flatten_paths(instance.roots, &items)
	testing.expect_value(t, items[0].fill.linear.stops[0].color, Color{0, 0, 255, 255})
	clear(&items)
	svg_flatten_paths(instance.roots[0].mask_nodes, &items)
	testing.expect_value(t, items[0].fill.solid, Color{0, 0, 255, 255})
}

@(test)
svg_instance_stroke_dash_is_owned_and_occurrences_reject_replaced_revisions :: proc(t: ^testing.T) {
	for cycle in 0 ..< 2 {
		asset, loaded := svg_test_load(`<rect id="r" width="10" height="10"/>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		r, _ := Svg_Asset_Lookup(asset, "r")
		occurrence, _ := Svg_Asset_Lookup_Occurrence(asset, nil, r)
		dash := [2]f64{3, 2}
		stroke := DEFAULT_STROKE
		stroke.dash = dash[:]
		instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{occurrence = occurrence, property = .Stroke_Settings, stroke = stroke}})
		defer Destroy_Svg_Instance(instance)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, result.ok)
		if instance == nil { return }
		dash[0] = 99
		items := make([dynamic]Svg_Path_Item, context.temp_allocator)
		svg_flatten_paths(instance.roots, &items)
		testing.expect_value(t, items[0].stroke_settings.dash[0], f64(3))
		replacement, reloaded := svg_test_load(`<rect id="r" width="10" height="10"/>`)
		defer Destroy_Svg_Asset(replacement)
		defer Destroy_Svg_Load_Result(&reloaded)
		bad, failure := Svg_Prepare_Instance(replacement, []Svg_Override{{occurrence = occurrence, property = .Opacity, opacity = .5}})
		defer Destroy_Svg_Instance(bad)
		defer Destroy_Svg_Load_Result(&failure)
		testing.expect(t, bad == nil && failure.error == .Invalid_Handle)
		_ = cycle
	}
}

@(test)
svg_instance_charges_payload_validation_before_copying :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<rect id="r" width="10" height="10"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	r, _ := Svg_Asset_Lookup(asset, "r")
	path: Path
	defer Destroy_Path(&path)
	_ = Rectangle(&path, {}, {5, 5})
	budget := DEFAULT_SVG_INSTANCE_BUDGET
	budget.selectors = asset.limits.max_xml_depth + 2
	instance, result := Svg_Prepare_Instance(asset, []Svg_Override{{target = r, property = .Path, commands = path.commands[:]}}, budget)
	defer Destroy_Svg_Instance(instance)
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, instance == nil && result.error == .Limit_Exceeded)
}
