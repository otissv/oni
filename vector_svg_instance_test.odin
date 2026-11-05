#+test
package oni

import "core:testing"
import "core:mem"
import v "./vector"

@(test)
svg_recording_node_allocation_failure_is_atomic :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect width="8" height="8"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		for allowed in 0 ..< 1 {
			fault := Test_Vector_Failing_Allocator{backing = context.allocator, remaining = allowed}
			allocator := mem.Allocator{procedure = test_vector_failing_allocator, data = &fault}
			nodes := make([dynamic]Vector_Node, allocator)
			err := draw_svg_build_nodes(asset.roots, Vector_Identity, &nodes)
			delete(nodes)
			testing.expect_value(t, err, Vector_Error.Allocation_Failed)
			vector_expect_owned_svg_cache(t)
		}
	})
}

@(test)
svg_recording_scratch_failure_sweep_is_atomic_for_overridden_composition :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><defs><clipPath id="a"><rect width="30" height="30"/></clipPath><clipPath id="b" clip-path="url(#a)"><rect width="28" height="28"/></clipPath><mask id="m" mask-type="alpha"><rect width="32" height="32" fill="white"/></mask></defs><g opacity=".5" mask="url(#m)" clip-path="url(#b)"><rect id="r" width="24" height="24" stroke="red" stroke-dasharray="2 3" vector-effect="non-scaling-stroke"/></g></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		r, _ := Svg_Lookup_Element(asset, "r")
		instance, prepared := Prepare_Svg_Instance(asset, []Svg_Override{{target = r, property = .Fill, paint = Linear_Paint({x2 = 1, stops = []Vector_Gradient_Stop{{0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}}})}})
		defer Destroy_Svg_Instance(instance)
		defer Destroy_Svg_Load_Result(&prepared)
		testing.expect(t, prepared.ok)
		storage := make([]byte, 4 * mem.Megabyte)
		defer delete(storage)
		arena: mem.Arena
		mem.arena_init(&arena, storage)
		state.ui.pass = .Draw
		state.dpi.scale = 2
		saved_temp := context.temp_allocator
		defer context.temp_allocator = saved_temp
		success := false
		for allowed in 0 ..< 512 {
			mem.arena_free_all(&arena)
			fault := Test_Vector_Failing_Allocator{backing = mem.arena_allocator(&arena), remaining = allowed}
			context.temp_allocator = {procedure = test_vector_failing_allocator, data = &fault}
			err := Draw_Svg_Instance(instance)
			context.temp_allocator = saved_temp
			if fault.rejected {
				testing.expect_value(t, err, Vector_Error.Allocation_Failed)
				testing.expect_value(t, len(vector_frame().draws), 0)
			} else { testing.expect_value(t, err, Vector_Error.None); success = true }
			vector_expect_owned_svg_cache(t)
			vector_scene_reset()
			if success { break }
		}
		testing.expect(t, success)
	})
}

@(test)
svg_override_recording_copies_transitive_inputs_and_rejects_invalid_sibling_atomically :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect id="r" width="8" height="8"/></svg>`)
		defer Destroy_Svg_Load_Result(&loaded)
		r, _ := Svg_Lookup_Element(asset, "r")
		path: v.Path
		_ = v.Rectangle(&path, {}, {16, 12})
		stops := make([]Vector_Gradient_Stop, 2)
		stops[0], stops[1] = {0, {255, 0, 0, 255}}, {1, {0, 0, 255, 255}}
		overrides := make([]Svg_Override, 2)
		overrides[0] = {target = r, property = .Path, commands = path.commands[:]}
		overrides[1] = {target = r, property = .Fill, paint = Linear_Paint({x2 = 1, stops = stops})}
		state.ui.pass = .Draw
		testing.expect_value(t, Draw_Svg_Asset(asset, overrides = overrides), Vector_Error.None)
		first := len(vector_frame().records)
		bad := [2]Svg_Override{{target = r, property = .Opacity, opacity = .5}, {target = r, property = .Opacity, opacity = .6}}
		diagnostic: Svg_Load_Result
		testing.expect_value(t, Draw_Svg_Asset(asset, overrides = bad[:], diagnostics = &diagnostic), Vector_Error.Invalid_Value)
		defer Destroy_Svg_Load_Result(&diagnostic)
		testing.expect_value(t, diagnostic.error, Svg_Diagnostic_Category.Duplicate_Override)
		testing.expect_value(t, len(vector_frame().records), first)
		testing.expect_value(t, len(vector_frame().draws), 1)
		v.Destroy_Path(&path)
		delete(stops)
		delete(overrides)
		Destroy_Svg_Asset(asset)
		testing.expect_value(t, vector_frame().ramp_rows, 1)
		testing.expect(t, len(vector_frame().vertices) > 0)
		vector_scene_reset()
		testing.expect_value(t, len(vector_frame().draws), 0)
		testing.expect_value(t, vector_frame().svg_usage.nodes, 0)
	})
}

@(test)
svg_instance_compilation_enforces_aggregate_frame_budget :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" width="8" height="8"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		vector_frame().svg_usage.nodes = VECTOR_MAX_FRAME_NODES
		instance, result := Prepare_Svg_Instance(asset)
		defer Destroy_Svg_Instance(instance)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, instance == nil && !result.ok)
		testing.expect_value(t, result.error, Svg_Diagnostic_Category.Limit_Exceeded)
	})
}

@(test)
svg_draw_diagnostics_cover_success_and_instance_input_failures :: proc(t: ^testing.T) {
	testing.expect_value(t, Svg_Result_Error({error = .Rendering_Failed}), Vector_Error.GPU_Failed)
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"/>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		state.ui.pass = .Draw
		result: Svg_Load_Result
		testing.expect_value(t, Draw_Svg_Asset(asset, diagnostics = &result), Vector_Error.None)
		testing.expect(t, result.ok)
		testing.expect_value(t, Draw_Svg_Asset(asset, opacity = -1, diagnostics = &result), Vector_Error.Invalid_Value)
		testing.expect(t, !result.ok && result.error == .Invalid_Value && len(result.diagnostics) > 0)
		testing.expect_value(t, Draw_Svg_Asset(asset, opacity = -1, diagnostics = &result), Vector_Error.Invalid_Value)
		testing.expect(t, !result.ok && result.error == .Invalid_Value && len(result.diagnostics) == 1)
		Destroy_Svg_Load_Result(&result)
	})
}

@(test)
svg_gpu_instance_overrides_are_independent_and_survive_input_release :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 64, 32) { return }
		state.ui.pass = .Draw
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><defs><g id="s"><rect id="r" x="2" y="2" width="20" height="20"/></g></defs><use id="u" href="#s"/></svg>`)
		defer Destroy_Svg_Load_Result(&loaded)
		r, _ := Svg_Lookup_Element(asset, "r")
		u, _ := Svg_Lookup_Element(asset, "u")
		occurrence, found := Svg_Lookup_Occurrence(asset, []Svg_Element_Handle{u}, r)
		testing.expect(t, found)
		draw_record_begin(state.dpi)
		testing.expect_value(t, Draw_Svg_Asset(asset, overrides = []Svg_Override{{target = r, property = .Fill, paint = Solid_Paint({255, 0, 0, 255})}}), Vector_Error.None)
		testing.expect_value(t, Draw_Svg_Asset(asset, {1, 0, 0, 1, 32, 0}, overrides = []Svg_Override{{occurrence = occurrence, property = .Fill, paint = Solid_Paint({0, 0, 255, 255})}}), Vector_Error.None)
		Destroy_Svg_Asset(asset)
		draw_record_end()
		if !vector_composition_gpu_submit(t) { return }
		pixels, ok := gpu_test_download_vector_framebuffer(t, 64, 32)
		if !ok { return }
		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 64, 10, 10, {255, 0, 0, 255}, "definition override")
		vector_composition_expect_rgba(t, pixels, 64, 42, 10, {0, 0, 255, 255}, "occurrence override")
	})
}

@(test)
svg_gpu_override_snapshots_survive_replay_after_an_earlier_instance_rendered :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 64, 32) { return }
		state.ui.pass = .Draw
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><g id="g"><rect x="2" y="2" width="20" height="20"/><rect x="12" y="2" width="10" height="20"/></g></svg>`)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, asset != nil && loaded.ok)
		if asset == nil { return }
		g, _ := Svg_Lookup_Element(asset, "g")
		draw_record_begin(state.dpi)
		for i in 0 ..< 2 {
			color := RGBA{255, 0, 0, 255} if i == 0 else RGBA{0, 0, 255, 255}
			overrides := [2]Svg_Override{{target = g, property = .Fill, paint = Solid_Paint(color)}, {target = g, property = .Opacity, opacity = .5}}
			testing.expect_value(t, Draw_Svg_Asset(asset, {1, 0, 0, 1, f64(i * 32), 0}, overrides = overrides[:]), Vector_Error.None)
		}
		Destroy_Svg_Asset(asset)
		draw_rect({56, 0, 8, 32}, {0, 255, 0, 255})
		draw_record_end()
		test_hook_vector_fail_pass_after = 2
		if !vector_composition_gpu_submit(t) { return }
		testing.expect_value(t, Vector_Last_Error(), Vector_Error.GPU_Failed)
		testing.expect(t, !vector_frame().draws[0].failed && vector_frame().draws[1].failed)
		pixels, ok := gpu_test_download_vector_framebuffer(t, 64, 32)
		if !ok { return }
		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 64, 10, 10, {128, 0, 0, 128}, "immutable first instance replay")
		vector_composition_expect_rgba(t, pixels, 64, 42, 10, {0, 0, 0, 0}, "failed sibling omitted")
		vector_composition_expect_rgba(t, pixels, 64, 60, 10, {0, 255, 0, 255}, "ordinary UI after replay")
	})
}
