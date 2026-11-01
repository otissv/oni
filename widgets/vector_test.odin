#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"
import sdl "vendor:sdl3"
import "core:reflect"

@(test)
vector_widget_domain_data_is_in_config_and_props_contain_only_procedures :: proc(t: ^testing.T) {
	for T in ([]typeid{Vector_Props, Svg_Props}) {
		for field in reflect.struct_fields_zipped(T) {
			if field.name == "config" { continue }
			testing.expect(t, reflect.is_procedure(field.type), field.name)
		}
	}
	for T in ([]typeid{Vector_Config, Svg_Config}) {
		for field in reflect.struct_fields_zipped(T) { testing.expect(t, !reflect.is_procedure(field.type), field.name) }
	}
}

@(private)
vector_test_draw_calls, vector_test_layout_children, vector_test_draw_children: int
@(private)
vector_test_canvas: Vector_Canvas
@(private)
vector_test_child :: proc(_: Vector_State) {
	if o.ui_pass() == .Layout { vector_test_layout_children += 1 } else { vector_test_draw_children += 1 }
	Text({config = {id = "vector-child", text = "child"}})
}
@(private)
vector_test_draw :: proc(_: Vector_State, canvas: Vector_Canvas) {
	vector_test_draw_calls += 1
	vector_test_canvas = canvas
}
@(test)
vector_widget_snapshots_viewport_and_runs_draw_only_with_composable_children :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		vector_test_draw_calls, vector_test_layout_children, vector_test_draw_children = 0, 0, 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		props := Vector_Props{config = {id = "canvas", viewport = {10, 20, 100, 50}, width = set.Width(200), height = set.Height(200)}, draw = vector_test_draw, child = vector_test_child}
		Vector(props)
		widget_test_finish_layout()
		testing.expect_value(t, vector_test_draw_calls, 0)
		widget_test_begin_draw()
		props.config.viewport = {0, 0, 1, 1}
		Vector(props)
		testing.expect_value(t, vector_test_draw_calls, 1)
		testing.expect_value(t, vector_test_layout_children, 1)
		testing.expect_value(t, vector_test_draw_children, 1)
		testing.expect_value(t, vector_test_canvas.viewport, o.Rect{10, 20, 100, 50})
		expect_close(t, f32(vector_test_canvas.transform[0]), 2)
		expect_registered_id(t, "vector-child")
	})
}

@(test)
svg_widget_uses_layout_snapshot_after_asset_release_and_intrinsic_sizing :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40"/></svg>`)
		defer o.Destroy_Svg_Load_Result(&loaded)
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "icon", asset = asset, width = set.Width(40)}})
		widget_test_finish_layout()
		node, ok := widget_test_layout_node("icon")
		testing.expect(t, ok)
		if ok { expect_close(t, node.rect.w, 40); expect_close(t, node.rect.h, 20) }
		o.Destroy_Svg_Asset(asset)
		widget_test_begin_draw()
		Svg({config = {id = "icon"}})
	})
}

@(private)
vector_test_errors: int
@(private)
vector_test_error :: proc(_: o.Vector_Error, _: []o.Svg_Diagnostic) { vector_test_errors += 1 }

@(test)
vector_widget_cover_uses_layout_crop_and_invalid_content_preserves_children :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		vector_test_errors = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		props := Vector_Props{config = {id = "cover", viewport = {10, 20, 100, 50}, fit = .Cover, width = set.Width(100), height = set.Height(100)}, draw = vector_test_draw}
		Vector(props)
		Vector({config = {id = "invalid", viewport = {0, 0, 0, 0}}, child = vector_test_child, on_error = vector_test_error})
		widget_test_finish_layout()
		widget_test_begin_draw()
		Vector(props)
		expect_close(t, f32(vector_test_canvas.transform[0]), 2)
		expect_close(t, f32(vector_test_canvas.transform[4]), -70)
		Vector({config = {id = "invalid"}, child = vector_test_child, on_error = vector_test_error})
		testing.expect_value(t, vector_test_errors, 1)
		expect_registered_id(t, "vector-child")
	})
}

@(test)
svg_widget_layout_copies_override_paths_and_preserves_standard_focus_lifecycle :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect id="r" width="8" height="8"/></svg>`)
		defer o.Destroy_Svg_Load_Result(&loaded)
		r, _ := o.Svg_Lookup_Element(asset, "r")
		overrides := make([]o.Svg_Override, 1)
		overrides[0] = {target = r, property = .Fill, paint = o.Solid_Paint({255, 0, 0, 255})}
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "snapshot", asset = asset, overrides = overrides, tabbable = set.Bool(true)}})
		Svg({config = {id = "disabled-svg", asset = asset, disabled = set.Bool(true), tabbable = set.Bool(true)}})
		Svg({config = {id = "unmounted-svg", asset = asset, unmount = true}, on_unmount = proc(_: Svg_State) -> o.Mount { return .COMPLETED }})
		expect_in_tab_order(t, "snapshot", true)
		expect_in_tab_order(t, "disabled-svg", false)
		_, exists := widget_test_layout_node("unmounted-svg")
		testing.expect(t, !exists)
		delete(overrides)
		o.Destroy_Svg_Asset(asset)
		widget_test_finish_layout()
		widget_test_begin_draw()
		Svg({config = {id = "snapshot"}})
		testing.expect_value(t, len(o.state.vector.frames[0].draws), 1)
		testing.expect_value(t, o.state.vector.frames[0].instances[0].colour[0], f32(1))
		testing.expect_value(t, o.state.vector.frames[0].instances[0].colour[1], f32(0))
	})
}

@(private)
svg_test_mounts, svg_test_clicks: int

@(test)
svg_widget_two_instances_record_independent_colours_after_caller_overrides_change :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect id="r" width="8" height="8"/></svg>`)
		defer o.Destroy_Svg_Load_Result(&loaded)
		r, _ := o.Svg_Lookup_Element(asset, "r")
		left := make([]o.Svg_Override, 1)
		right := make([]o.Svg_Override, 1)
		left[0] = {target = r, property = .Fill, paint = o.Solid_Paint({255, 0, 0, 255})}
		right[0] = {target = r, property = .Fill, paint = o.Solid_Paint({0, 0, 255, 255})}
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "left", asset = asset, overrides = left, width = set.Width(32), height = set.Height(32)}})
		Svg({config = {id = "right", asset = asset, overrides = right, width = set.Width(32), height = set.Height(32)}})
		widget_test_finish_layout()
		left[0].paint = o.Solid_Paint({0, 255, 0, 255})
		right[0].paint = o.Solid_Paint({255, 255, 0, 255})
		delete(left)
		delete(right)
		o.Destroy_Svg_Asset(asset)
		widget_test_begin_draw()
		Svg({config = {id = "left"}})
		Svg({config = {id = "right"}})
		testing.expect_value(t, len(o.state.vector.frames[0].draws), 2)
		testing.expect_value(t, o.state.vector.frames[0].instances[0].colour[0], f32(1))
		testing.expect_value(t, o.state.vector.frames[0].instances[0].colour[2], f32(0))
		testing.expect_value(t, o.state.vector.frames[0].instances[1].colour[2], f32(1))
		testing.expect_value(t, o.state.vector.frames[0].instances[1].colour[0], f32(0))
	})
}

@(test)
svg_widget_nil_asset_reports_invalid_handle_without_replaced_element_sizing :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		vector_test_errors = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "missing-asset", asset = nil, width = set.Width(120), height = set.Height(80)}, on_error = vector_test_error})
		widget_test_finish_layout()
		node, ok := widget_test_layout_node("missing-asset")
		testing.expect(t, ok)
		if ok { expect_close(t, node.rect.w, 120); expect_close(t, node.rect.h, 80) }
		widget_test_begin_draw()
		Svg({config = {id = "missing-asset"}, on_error = vector_test_error})
		testing.expect_value(t, vector_test_errors, 1)
		testing.expect_value(t, len(o.state.vector.frames[0].draws), 0)
	})
}

@(test)
svg_widget_mount_runs_in_layout_and_keyboard_click_uses_standard_draw_dispatch :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		svg_test_mounts, svg_test_clicks = 0, 0
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8"/></svg>`)
		defer o.Destroy_Svg_Asset(asset)
		defer o.Destroy_Svg_Load_Result(&loaded)
		props := Svg_Props{
			config = {id = "interactive-svg", asset = asset, tabbable = set.Bool(true)},
			on_mount = proc(_: Svg_State) -> o.Mount { svg_test_mounts += 1; return .COMPLETED },
			on_click = proc(_: Svg_Event) { svg_test_clicks += 1 },
		}
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg(props)
		testing.expect_value(t, svg_test_mounts, 1)
		widget_test_finish_layout()
		testing.expect(t, FocusElement("interactive-svg"))
		widget_test_begin_draw()
		o.w_ctx.keys[int(sdl.Scancode.RETURN)].pressed = true
		Svg(props)
		testing.expect_value(t, svg_test_mounts, 1)
		testing.expect_value(t, svg_test_clicks, 1)
	})
}

@(test)
vector_widget_auto_axis_uses_resolved_dimensions_and_intrinsics_survive_children :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Rectangle({config = {id = "sizing-parent", width = set.Width(400), height = set.Height(300)}, child = proc(_: Rectangle_State) {
			Vector({config = {id = "percent-vector", viewport = {0, 0, 100, 50}, width = set.Width(o.Dim_struct{percent = 50})}})
			Vector({config = {id = "clamped-vector", viewport = {0, 0, 100, 50}, width = set.Width(200), max_w = set.Max_W(120)}})
			Vector({config = {id = "child-vector", viewport = {0, 0, 100, 50}, width = set.Width(.FIT)}, child = proc(_: Vector_State) {
				Rectangle({config = {width = set.Width(10), height = set.Height(10)}})
			}})
		}})
		widget_test_finish_layout()
		o.ui_push_scope(o.ui_id("sizing-parent"))
		defer o.ui_pop_scope()
		for expected in ([]struct {id: string, w, h: f32}{{"percent-vector", 200, 100}, {"clamped-vector", 120, 60}, {"child-vector", 100, 50}}) {
			node, found := widget_test_layout_node(expected.id)
			testing.expect(t, found)
			if found { testing.expect_value(t, node.rect.w, expected.w); testing.expect_value(t, node.rect.h, expected.h) }
		}
	})
}

@(private)
vector_test_percent_asset: o.Svg_Asset

@(test)
svg_widget_percent_width_resolves_before_auto_height_aspect_ratio :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40"/></svg>`)
		defer o.Destroy_Svg_Asset(asset)
		defer o.Destroy_Svg_Load_Result(&loaded)
		vector_test_percent_asset = asset
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Rectangle({config = {id = "percent-parent", width = set.Width(400), height = set.Height(300)}, child = proc(_: Rectangle_State) {
			Svg({config = {id = "percent-icon", asset = vector_test_percent_asset, width = set.Width(o.Dim_struct{percent = 50})}})
		}})
		widget_test_finish_layout()
		o.ui_push_scope(o.ui_id("percent-parent"))
		defer o.ui_pop_scope()
		node, ok := widget_test_layout_node("percent-icon")
		testing.expect(t, ok)
		if ok { expect_close(t, node.rect.w, 200); expect_close(t, node.rect.h, 100) }
	})
}

@(test)
svg_widget_composable_children_do_not_replace_intrinsic_measurement :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50"/></svg>`)
		defer o.Destroy_Svg_Asset(asset)
		defer o.Destroy_Svg_Load_Result(&loaded)
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "overlay-icon", asset = asset, width = set.Width(.FIT)}, child = proc(_: Svg_State) {
			Rectangle({config = {width = set.Width(240), height = set.Height(120)}})
		}})
		widget_test_finish_layout()
		node, ok := widget_test_layout_node("overlay-icon")
		testing.expect(t, ok)
		if ok { expect_close(t, node.rect.w, 100); expect_close(t, node.rect.h, 50) }
	})
}

@(test)
svg_widget_unmounted_content_does_not_compile_or_consume_instance_budget :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer o.Shutdown()
		asset, loaded := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect width="8" height="8"/></svg>`)
		defer o.Destroy_Svg_Asset(asset)
		defer o.Destroy_Svg_Load_Result(&loaded)
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Svg({config = {id = "unmounted-budget", asset = asset, unmount = true}, on_unmount = proc(_: Svg_State) -> o.Mount { return .COMPLETED }})
		testing.expect_value(t, o.state.vector.frames[0].svg_usage.nodes, 0)
		testing.expect_value(t, o.state.vector.frames[0].svg_usage.decoded_bytes, 0)
		widget_test_finish_layout()
	})
}
