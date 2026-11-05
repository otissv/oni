package main

import "core:os"
import "core:math"
import "core:fmt"
import "core:strings"
import o "./oni"
import v "./oni/vector"
import set "./oni/set"
import w "./oni/widgets"
import tengu "libs:tengu"

Persistent :: struct {
	m7_asset: o.Svg_Asset,
	m7_group, m7_body: o.Svg_Element_Handle,
	m7_occurrence: o.Svg_Occurrence_Handle,
	m7_commands: [3]o.Vector_Path_Command,
	m7_playing, m7_show_spaces, m7_spaces_snapshot: bool,
	motion: tengu.Tween_State(f32),
	animated_color: tengu.Tween_State(tengu.RGBA),
	animated_stroke, animated_bend: tengu.Tween_State(f32),
	m7_phase: f32,
	m7_tint: o.RGBA,
	m7_error: o.Vector_Error,

	engine: o.State,
	theme: o.Theme,
	paths: [4]o.Vector_Path_Handle,
	stroke_paths: [5]o.Vector_Path_Handle,
	paint_paths: [3]o.Vector_Path_Handle,
	zoom: f32,
	fraction: f32,
	bend: f32,
	last_bend: f32,
	stroke_width: f32,
	miter_limit: f32,
	dash_offset: f32,
	stop_phase: f32,
	svg_assets: [3]o.Svg_Asset,
	svg_references, svg_differences: [3][2]o.Texture_Handle,
	svg_errors: [3]string,
	svg_draw_errors: [3]o.Vector_Error,
	svg_negative_error: string,
	svg_selected: int,
	svg_difference: bool,
	m8_asset: o.Svg_Asset,
	m8_reload_status: string,
	m8_status_storage: [256]u8,
	m8_workload: f32,
	m8_animate: bool,
	m8_seconds, m8_frame_ms: f32,
	m8_inject_error: bool,
}

persistent: ^Persistent

SVG_GALLERY_NAMES :: [3]string{"css-classes", "namespace-prefixed", "symbol-instances"}

init_svg_gallery :: proc() {
	for name, index in SVG_GALLERY_NAMES {
		asset, result := o.Load_Svg_File(fmt.tprintf("oni/fixtures/vector/m6/%s.svg", name))
		persistent.svg_assets[index] = asset
		if !result.ok && len(result.diagnostics) > 0 {
			diag := result.diagnostics[0]
			persistent.svg_errors[index] = strings.clone(fmt.tprintf("%v at %d:%d %s %s: %s", diag.category, diag.line, diag.column, diag.element, diag.property, diag.message))
		}
		o.Destroy_Svg_Load_Result(&result)
		for scale in 1 ..= 2 {
			persistent.svg_references[index][scale - 1], _ = o.Load_Texture(fmt.tprintf("oni/fixtures/vector/m6/%s-%dx.png", name, scale))
			persistent.svg_differences[index][scale - 1], _ = o.Load_Texture(fmt.tprintf("oni/build/test/svg-%s-%dx-difference.png", name, scale))
		}
	}
	asset, result := o.Load_Svg_File("oni/fixtures/vector/m6/negative-text.svg")
	defer o.Destroy_Svg_Asset(asset)
	defer o.Destroy_Svg_Load_Result(&result)
	if len(result.diagnostics) > 0 {
		diag := result.diagnostics[0]
		persistent.svg_negative_error = strings.clone(fmt.tprintf("Rejected text: %v at %d:%d — %s", diag.category, diag.line, diag.column, diag.message))
	}
}

shutdown_svg_gallery :: proc() {
	for asset, index in persistent.svg_assets {
		o.Destroy_Svg_Asset(asset)
		for scale in 0 ..< 2 {
			o.Unload_Texture(persistent.svg_references[index][scale])
			o.Unload_Texture(persistent.svg_differences[index][scale])
		}
		delete(persistent.svg_errors[index])
	}
	delete(persistent.svg_negative_error)
}

svg_gallery :: proc() {
	names := SVG_GALLERY_NAMES
	w.Text({config = {id = "svg-gallery-title", text = "SVG import: CSS, namespaces and independent symbol instances", height = set.Height(28)}})
	w.Rectangle({
		config = {id = "svg-gallery-controls", direction = set.Direction(.HORIZONTAL), gap_x = set.Gap_X(16), height = set.Height(36)},
		child = proc(_: w.Rectangle_State) {
			w.Button({
				config = {id = "svg-gallery-next", width = set.Width(180)},
				child = proc(_: w.Button_State) { w.Text({config = {text = "Next SVG example"}}) },
				on_click = proc(_: w.Button_Event) { persistent.svg_selected = (persistent.svg_selected + 1) % len(SVG_GALLERY_NAMES) },
			})
			w.Checkbox({
				config = {id = "svg-gallery-difference", checked = persistent.svg_difference ? .TRUE : .FALSE},
				on_checked_change = proc(value: w.Checkbox_Value) { persistent.svg_difference = value == .TRUE },
			})
			w.Text({config = {text = "Show measured difference", height = set.Height(32)}})
		},
	})
	w.Rectangle({
		config = {id = "svg-gallery-comparison", direction = set.Direction(.HORIZONTAL), gap_x = set.Gap_X(16), height = set.Height(128)},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {id = "svg-gallery-native", width = set.Width(418), height = set.Height(128), background = set.Background(.GRAY_900)},
				child = proc(_: w.Rectangle_State) {
					if o.ui_pass() != .Draw {
						return
					}

					asset := persistent.svg_assets[persistent.svg_selected]
					if asset == nil {
						return
					}

					rect := o.ui_layout_rect(o.ui_id("svg-gallery-native"))
					width, height := o.Svg_Intrinsic_Size(asset)
					persistent.svg_draw_errors[persistent.svg_selected] = o.Draw_Svg_Asset(asset, {1, 0, 0, 1, f64(rect.x + (rect.w - f32(width)) / 2), f64(rect.y + (rect.h - f32(height)) / 2)})
				},
			})
			w.Rectangle({
				config = {id = "svg-gallery-reference", width = set.Width(418), height = set.Height(128), background = set.Background(.GRAY_900)},
				child = proc(_: w.Rectangle_State) {
					if o.ui_pass() != .Draw {
						return
					}

					index := persistent.svg_selected
					scale := persistent.engine.dpi.scale > 1 ? 2 : 1
					texture := persistent.svg_difference ? persistent.svg_differences[index][scale - 1] : persistent.svg_references[index][scale - 1]
					texture = o.Get_Texture(texture.id)
					if o.Texture_Status(texture) != .Ready {
						return
					}

					rect := o.ui_layout_rect(o.ui_id("svg-gallery-reference"))
					width, height := texture.w / f32(scale), texture.h / f32(scale)
					dst := o.Rect{rect.x + (rect.w - width) / 2, rect.y + (rect.h - height) / 2, width, height}
					o.Draw_Texture(texture, {0, 0, texture.w, texture.h}, dst)
				},
			})
		},
	})
	index := persistent.svg_selected
	status := fmt.tprintf("%s.svg — native rendering / %s", names[index], persistent.svg_difference ? "measured absolute difference" : "independent librsvg reference")
	if persistent.svg_errors[index] != "" { status = persistent.svg_errors[index] }
	if persistent.svg_draw_errors[index] != .None { status = fmt.tprintf("SVG drawing rejected: %v", persistent.svg_draw_errors[index]) }
	scale := persistent.engine.dpi.scale > 1 ? 2 : 1
	if persistent.svg_difference && o.Texture_Status(persistent.svg_differences[index][scale - 1]) == .Failed { status = "Difference image unavailable: run the required SVG GPU image suite first." }
	w.Text({config = {id = "svg-gallery-status", text = status, height = set.Height(28)}})
	w.Text({config = {id = "svg-gallery-diagnostic", text = persistent.svg_negative_error, height = set.Height(28)}})
}

main :: proc() {
	if !run_gallery() { os.exit(1) }
}

run_gallery :: proc() -> bool {
	defer free_all(context.temp_allocator)
	persistent = new(Persistent)
	defer free(persistent)
	persistent.theme = {palette = o.palette, background = .BACKGROUND, color = .FOREGROUND}
	o.Bind(&persistent.engine, &persistent.theme)
	defer o.Shutdown()
	o.Set_Frame_Mode(.On_Demand)
	if !o.Init_Window_Only({title = "Oni vector gallery", width = 900, height = 1600, min_width = 900, min_height = 1600}) || !o.Init() {
		return false
	}
	family, ok := o.Settings_Register_Fonts()
	if !ok {
		o.Log_Error("Vector gallery could not load fonts")
		return false
	}
	persistent.theme.font_body = o.Font_With_Size(family, 18)
	persistent.zoom, persistent.bend = 1, 50
	persistent.stroke_width = 8
	persistent.miter_limit = 4
	persistent.last_bend = -1
	if !init_paths() { return false }
	if !init_stroke_paths() { return false }
	if !init_paint_paths() { return false }
	defer shutdown_svg_gallery()
	init_svg_gallery()
	if !m8_init_stress() { return false }
	defer o.Destroy_Svg_Asset(persistent.m8_asset)
	if !m7_init_asset() { return false }
	defer o.Destroy_Svg_Asset(persistent.m7_asset)
	m7_init_animation()
	smoke := len(os.args) > 1 && os.args[1] == "--smoke"
	persistent.m7_show_spaces = smoke
	o.Request_Frame()
	frames := 0
	for o.Should_Run() {
		free_all(context.temp_allocator)
		o.Run_Frame(m7_tick, draw, nil)
		frames += 1
		if smoke && frames >= 3 {
			break
		}
	}
	if smoke && persistent.m7_error != .None {
		o.Log_Error(fmt.tprintf("M7 gallery rendering failed: %v", persistent.m7_error))
		return false
	}
	return true
}

draw :: proc() {
	o.Render(gallery)
}

gallery :: proc() {
	if o.ui_pass() == .Layout { persistent.m7_spaces_snapshot = persistent.m7_show_spaces }
	o.Begin_Screen()
	defer o.End_Screen()
	w.Rectangle({
		config = {id = "vector-gallery", direction = set.Direction(.VERTICAL), padding = set.Padding(24), gap_y = set.Gap_Y(16), height = set.Height(f32(persistent.engine.dpi.logical_h)), overflow_y = set.Overflow_Y(.SCROLL)},
		child = proc(_: w.Rectangle_State) {
			w.Text({config = {id = "vector-title", text = "Native vector composition", height = set.Height(32)}})
			w.Text({config = {id = "vector-description", text = "Nested clips, alpha/luminance masks, and isolated group opacity on contrasting grounds.", height = set.Height(32)}})
			m7_gallery()
			m8_stress_gallery()
			svg_gallery()
			path_gallery()
			stroke_gallery()
			paint_gallery()
			composition_gallery()
		},
	})
	if persistent.m7_spaces_snapshot { m7_space_examples() }
}

composition_gallery :: proc() {
	w.Rectangle({
		config = {
			id = "vector-composition-row",
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(16),
			width = set.Width(852),
			height = set.Height(280),
		},
		child = proc(_: w.Rectangle_State) {
			w.Rectangle({
				config = {id = "vector-surface-blue", width = set.Width(418), height = set.Height(280), background = set.Background(.BLUE_900)},
				child = proc(_: w.Rectangle_State) {
					if o.ui_pass() != .Draw {
						return
					}

					composition_blue_art(o.ui_layout_rect(o.ui_id("vector-surface-blue")))
				},
			})
			w.Rectangle({
				config = {id = "vector-surface-amber", width = set.Width(418), height = set.Height(280), background = set.Background(.AMBER_900)},
				child = proc(_: w.Rectangle_State) {
					if o.ui_pass() != .Draw {
						return
					}

					composition_amber_art(o.ui_layout_rect(o.ui_id("vector-surface-amber")))
				},
			})
		},
	})
}

composition_blue_art :: proc(rect: o.Rect) {
	left := [2]o.Vector_Node{
		rectangle({rect.x + 24, rect.y + 24, 160, 160}, {255, 80, 80, 255}),
		rectangle({rect.x + 104, rect.y + 64, 160, 160}, {255, 80, 80, 255}),
	}
	group := [1]o.Vector_Node{{kind = .Group, opacity = 0.5, children = left[:]}}
	_ = o.Draw_Vector_Scene({nodes = group[:], opacity = 1})

	right := [1]o.Vector_Node{rectangle({rect.x + 240, rect.y + 24, 160, 220}, {80, 255, 180, 255})}
	triangle_points := [3]o.Vec2{{rect.x + 220, rect.y + 260}, {rect.x + 320, rect.y + 20}, {rect.x + 420, rect.y + 260}}
	triangle_indices := [3]u32{0, 1, 2}
	mask := [1]o.Vector_Node{{kind = .Mesh, opacity = 1, colour = {255, 255, 255, 255}, mesh = {vertices = triangle_points[:], indices = triangle_indices[:]}}}
	masked := [1]o.Vector_Node{{kind = .Mask, opacity = 1, children = right[:], mask = mask[:], mask_kind = .Alpha}}
	outer_clip := rectangle({rect.x + 250, rect.y + 48, 140, 180}, {255, 255, 255, 255})
	inner_clip := rectangle({rect.x + 250, rect.y + 100, 140, 100}, {255, 255, 255, 255})
	clipped_inner := [1]o.Vector_Node{{kind = .Clip, opacity = 1, mesh = inner_clip.mesh, children = masked[:]}}
	clipped := [1]o.Vector_Node{{kind = .Clip, opacity = 1, mesh = outer_clip.mesh, children = clipped_inner[:]}}
	_ = o.Draw_Vector_Scene({nodes = clipped[:], opacity = 1})
}

composition_amber_art :: proc(rect: o.Rect) {
	fill := [1]o.Vector_Node{rectangle({rect.x + 40, rect.y + 40, 200, 200}, {40, 120, 255, 255})}
	// Mid-grey luminance softens the fill; alpha of the same colour would stay opaque.
	mask := [1]o.Vector_Node{rectangle({rect.x + 40, rect.y + 40, 200, 200}, {160, 160, 160, 220})}
	masked := [1]o.Vector_Node{{
		kind = .Mask,
		opacity = 1,
		children = fill[:],
		mask = mask[:],
		mask_kind = .Luminance,
	}}
	_ = o.Draw_Vector_Scene({nodes = masked[:], opacity = 1})

	overlap := [2]o.Vector_Node{
		rectangle({rect.x + 260, rect.y + 60, 120, 120}, {255, 255, 255, 255}),
		rectangle({rect.x + 300, rect.y + 100, 120, 120}, {255, 255, 255, 255}),
	}
	faded := [1]o.Vector_Node{{kind = .Group, opacity = 0.35, children = overlap[:]}}
	_ = o.Draw_Vector_Scene({nodes = faded[:], opacity = 1})
}

rectangle :: proc(rect: o.Rect, colour: o.RGBA) -> o.Vector_Node {
	points := make([]o.Vec2, 4, context.temp_allocator)
	points[0] = {rect.x, rect.y}
	points[1] = {rect.x + rect.w, rect.y}
	points[2] = {rect.x + rect.w, rect.y + rect.h}
	points[3] = {rect.x, rect.y + rect.h}
	indices := make([]u32, 6, context.temp_allocator)
	copy(indices, []u32{0, 1, 2, 0, 2, 3})
	return {kind = .Mesh, opacity = 1, colour = colour, mesh = {vertices = points, indices = indices}}
}

curved_path :: proc(bend: f64) -> (path: v.Path) {
	_ = v.Move_To(&path, {0, 60})
	_ = v.Cubic_To(&path, {0, -bend}, {100, -bend}, {100, 60})
	_ = v.Quadratic_To(&path, {50, 110}, {0, 60})
	_ = v.Close(&path)
	return
}

init_paths :: proc() -> bool {
	for i in 0 ..< 4 {
		path: v.Path
		switch i {
		case 0: path = curved_path(50)
		case 1:
			_ = v.Circle(&path, {50, 50}, 46)
			_ = v.Circle(&path, {50, 50}, 29)
		case 2:
			points: [5]v.Point
			for &point, j in points {
				a := -math.PI * 0.5 + f64(j) * 4 * math.PI / 5
				point = {50 + 48 * math.cos(a), 50 + 48 * math.sin(a)}
			}
			_ = v.Polyline(&path, points[:], true)
		case 3:
			_ = v.Rectangle(&path, {0, 0}, {100, 100}, {12, 12})
			_ = v.Rectangle(&path, {20, 20}, {60, 60})
		}
		handle, err := o.Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		if err != .None { o.Log_Error("Gallery path creation failed"); return false }
		persistent.paths[i] = handle
	}
	specs := make([]o.Vector_Path_Tess_Spec, len(persistent.paths), context.temp_allocator)
	for i in 0 ..< len(persistent.paths) {
		specs[i] = {handle = persistent.paths[i], transform = o.Vector_Identity, rule = .Nonzero}
	}
	if err := o.Vector_Prefetch_Paths(specs); err != .None {
		o.Log_Error("Gallery path prefetch failed")
		return false
	}
	return true
}

init_stroke_paths :: proc() -> bool {
	for i in 0 ..< 5 {
		path: v.Path
		switch i {
		case 0:
			_ = v.Move_To(&path, {8, 40})
			_ = v.Line_To(&path, {120, 40})
		case 1:
			_ = v.Move_To(&path, {8, 72})
			_ = v.Line_To(&path, {64, 8})
			_ = v.Line_To(&path, {120, 72})
		case 2:
			_ = v.Move_To(&path, {8, 40})
			_ = v.Line_To(&path, {120, 40})
		case 3:
			_ = v.Move_To(&path, {64, 40})
			_ = v.Line_To(&path, {64, 40})
		case 4:
			_ = v.Rectangle(&path, {16, 16}, {96, 64})
		}
		handle, err := o.Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		if err != .None {
			o.Log_Error("Gallery stroke path creation failed")
			return false
		}
		persistent.stroke_paths[i] = handle
	}
	return true
}

path_gallery :: proc() {
	w.Text({config = {id = "path-controls", text = fmt.tprintf("M2 fills: zoom %.2f / fractional offset %.3f / curve control %.1f", persistent.zoom, persistent.fraction, persistent.bend), height = set.Height(24)}})
	w.Slider({
		config = {id = "path-zoom", values = {persistent.zoom}, min = 0.25, max = 1.5, step = 0.01, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.zoom = values[0]; o.Request_Frame() },
	})
	w.Slider({
		config = {id = "path-fraction", values = {persistent.fraction}, min = 0, max = 1, step = 0.001, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.fraction = values[0]; o.Request_Frame() },
	})
	w.Slider({
		config = {id = "path-bend", values = {persistent.bend}, min = 0, max = 100, step = 0.25, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.bend = values[0]; persistent.m7_playing = false; o.Request_Frame() },
	})
	w.Text({config = {id = "path-labels", text = "Editable curves       Ring (even-odd)       Star (nonzero / even-odd)       Rounded hole", height = set.Height(24)}})
	w.Rectangle({
		config = {id = "path-surface", width = set.Width(820), height = set.Height(180), background = set.Background(.BLUE_900)},
		child = proc(_: w.Rectangle_State) {
			if o.ui_pass() != .Draw { return }
			rect := o.ui_layout_rect(o.ui_id("path-surface"))
			items: [5]o.Vector_Path_Draw
			for i in 0 ..< 5 {
				index := i < 3 ? i : (i == 3 ? 2 : 3)
				transform := o.Vector_Transform{f64(persistent.zoom), 0, 0, f64(persistent.zoom), f64(rect.x) + 12 + f64(i) * 164 + f64(persistent.fraction), f64(rect.y) + 12 + f64(persistent.fraction)}
				rule: o.Vector_Fill_Rule = i == 0 || i == 2 ? .Nonzero : .Even_Odd
				items[i] = {
					handle    = persistent.paths[index],
					paint = o.Solid_Paint({80, 230, 190, 255}),
					transform = transform,
					rule      = rule,
					opacity   = 0.75,
				}
			}
			if err := o.Draw_Vector_Paths(items[:]); err != .None {
				o.Log_Error("Gallery path draw failed")
			}
		},
	})
}

stroke_gallery :: proc() {
	w.Text({
		config = {
			id = "stroke-controls",
			text = fmt.tprintf(
				"M3 strokes: width %.1f / miter %.1f / dash offset %.1f",
				persistent.stroke_width,
				persistent.miter_limit,
				persistent.dash_offset,
			),
			height = set.Height(24),
		},
	})
	w.Slider({
		config = {id = "stroke-width", values = {persistent.stroke_width}, min = 1, max = 18, step = 0.25, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.stroke_width = values[0]; o.Request_Frame() },
	})
	w.Slider({
		config = {id = "stroke-miter", values = {persistent.miter_limit}, min = 1, max = 10, step = 0.1, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.miter_limit = values[0]; o.Request_Frame() },
	})
	w.Slider({
		config = {id = "stroke-dash", values = {persistent.dash_offset}, min = 0, max = 40, step = 0.5, width = set.Width(800), height = set.Height(20)},
		on_value_change = proc(values: []f32) { persistent.dash_offset = values[0]; o.Request_Frame() },
	})
	w.Text({
		config = {
			id = "stroke-labels",
			text = "Caps (butt/round/square)   Joins (miter/round/bevel)   Dashes   Zero-length   Non-scaling",
			height = set.Height(24),
		},
	})
	w.Rectangle({
		config = {id = "stroke-surface", width = set.Width(820), height = set.Height(220), background = set.Background(.BLUE_900)},
		child = proc(_: w.Rectangle_State) {
			if o.ui_pass() != .Draw {
				return
			}

			rect := o.ui_layout_rect(o.ui_id("stroke-surface"))
			width := f64(persistent.stroke_width)
			miter := f64(persistent.miter_limit)
			dash := []f64{16, 10}
			items: [9]o.Vector_Path_Draw
			// Caps row
			caps := [3]o.Vector_Line_Cap{.Butt, .Round, .Square}
			for cap, i in caps {
				items[i] = {
					handle = persistent.stroke_paths[0],
					paint = o.Solid_Paint({255, 200, 90, 255}),
					transform = {1, 0, 0, 1, f64(rect.x) + 16 + f64(i) * 130, f64(rect.y) + 16},
					opacity = 0.85,
					op = .Stroke,
					stroke = {width = width, cap = cap, join = .Miter, miter_limit = miter},
				}
			}
			// Joins
			joins := [3]o.Vector_Line_Join{.Miter, .Round, .Bevel}
			for join, i in joins {
				items[3 + i] = {
					handle = persistent.stroke_paths[1],
					paint = o.Solid_Paint({120, 220, 255, 255}),
					transform = {1, 0, 0, 1, f64(rect.x) + 16 + f64(i) * 130, f64(rect.y) + 100},
					opacity = 0.85,
					op = .Stroke,
					stroke = {width = width, cap = .Butt, join = join, miter_limit = miter},
				}
			}
			// Dashes with pathLength-normalized offset
			items[6] = {
				handle = persistent.stroke_paths[2],
				paint = o.Solid_Paint({255, 120, 180, 255}),
				transform = {1, 0, 0, 1, f64(rect.x) + 420, f64(rect.y) + 16},
				opacity = 0.9,
				op = .Stroke,
				stroke = {
					width = width,
					cap = .Butt,
					join = .Miter,
					miter_limit = miter,
					dash = dash,
					dash_offset = f64(persistent.dash_offset),
					path_length = 80,
				},
			}
			// Zero-length round cap
			items[7] = {
				handle = persistent.stroke_paths[3],
				paint = o.Solid_Paint({180, 255, 140, 255}),
				transform = {1, 0, 0, 1, f64(rect.x) + 560, f64(rect.y) + 16},
				opacity = 1,
				op = .Stroke,
				stroke = {width = width, cap = .Round, join = .Miter, miter_limit = miter},
			}
			// Non-scaling stroke under 2× scale beside a scaling twin
			items[8] = {
				handle = persistent.stroke_paths[4],
				paint = o.Solid_Paint({255, 255, 255, 255}),
				transform = {1.75, 0, 0, 1.75, f64(rect.x) + 560, f64(rect.y) + 90},
				opacity = 0.8,
				op = .Stroke,
				stroke = {width = 3, cap = .Butt, join = .Miter, miter_limit = miter, non_scaling = true},
			}
			if err := o.Draw_Vector_Paths(items[:]); err != .None {
				o.Log_Error("Gallery stroke draw failed")
			}
		},
	})
}

init_paint_paths :: proc() -> bool {
	for i in 0 ..< 3 {
		path: v.Path
		switch i {
		case 0:
			_ = v.Rectangle(&path, {0, 0}, {96, 96}, {12, 12})
		case 1:
			_ = v.Circle(&path, {48, 48}, 44)
		case 2:
			_ = v.Rectangle(&path, {0, 0}, {96, 96})
			_ = v.Rectangle(&path, {24, 24}, {48, 48})
		}
		handle, err := o.Vector_Create_Path(path.commands[:])
		v.Destroy_Path(&path)
		if err != .None {
			o.Log_Error("Gallery paint path creation failed")
			return false
		}
		persistent.paint_paths[i] = handle
	}
	return true
}

paint_gallery :: proc() {
	w.Text({
		config = {
			id = "paint-title",
			text = fmt.tprintf("M4 paints: animated stop phase %.2f / themed currentColor / nested transforms", persistent.stop_phase),
			height = set.Height(24),
		},
	})
	w.Rectangle({
		config = {id = "paint-surface", width = set.Width(820), height = set.Height(200), background = set.Background(.SLATE_900)},
		child = proc(_: w.Rectangle_State) {
			if o.ui_pass() != .Draw {
				return
			}

			rect := o.ui_layout_rect(o.ui_id("paint-surface"))
			mid := u8(40 + 180 * persistent.stop_phase)
			lin_stops := [3]o.Vector_Gradient_Stop{
				{0, {255, 80, 80, 255}},
				{f64(persistent.stop_phase), {mid, 200, 255, 230}},
				{1, {80, 120, 255, 255}},
			}
			rad_stops := [2]o.Vector_Gradient_Stop{{0, {255, 255, 255, 255}}, {1, {40, 40, 80, 255}}}
			parent := o.Vector_Transform{1, 0, 0, 1, f64(rect.x) + 24, f64(rect.y) + 24}
			child := o.Vector_Transform{0.85, 0.15, -0.1, 0.9, 8, 4}
			nested := v.Affine_Compose(parent, child)
			theme := o.css_color_to_rgba(.PRIMARY)
			items := [4]o.Vector_Path_Draw{
				{
					handle = persistent.paint_paths[0],
					paint = o.Linear_Paint({
						x1 = 0, y1 = 0, x2 = 1, y2 = 0,
						units = .Object_Bounding_Box,
						stops = lin_stops[:],
					}),
					transform = {1, 0, 0, 1, f64(rect.x) + 24, f64(rect.y) + 24},
					opacity = 0.95,
				},
				{
					handle = persistent.paint_paths[1],
					paint = o.Radial_Paint({
						cx = 0.5, cy = 0.5, r = 0.5, fx = 0.35, fy = 0.35, fr = 0,
						units = .Object_Bounding_Box,
						stops = rad_stops[:],
					}),
					transform = {1, 0, 0, 1, f64(rect.x) + 160, f64(rect.y) + 24},
					opacity = 1,
				},
				{
					handle = persistent.paint_paths[2],
					paint = o.Current_Color_Paint(),
					transform = nested,
					opacity = 0.9,
					current_color = theme,
					rule = .Even_Odd,
				},
				{
					handle = persistent.paint_paths[0],
					paint = o.Solid_Paint({255, 255, 255, 64}),
					transform = {1, 0, 0, 1, f64(rect.x) + 520, f64(rect.y) + 40},
					opacity = 1,
				},
			}
			if err := o.Draw_Vector_Paths(items[:]); err != .None {
				o.Log_Error("Gallery paint draw failed")
			}
		},
	})
}


// All animation state is app-owned. Only tick advances Tengu; both UI passes
// consume the same values. Pausing removes the app's continuing frame demand.
m7_init_animation :: proc() {
	tengu.tween_init(&persistent.motion, {start = 0, target = 1, duration = 3, easing = tengu.Ease.IN_OUT_SINE, repeat_count = 0, repeat_mode = .REVERSE})
	tengu.tween_init(&persistent.animated_color, {start = {1, .3, .15, 1}, target = {.15, .5, 1, 1}, duration = 3, repeat_count = 0, repeat_mode = .REVERSE})
	tengu.tween_init(&persistent.animated_stroke, {start = 1, target = 5, duration = 3, repeat_count = 0, repeat_mode = .REVERSE})
	tengu.tween_init(&persistent.animated_bend, {start = 25, target = 85, duration = 3, repeat_count = 0, repeat_mode = .REVERSE})
	persistent.m7_playing = true
}

m7_tick :: proc(dt: f32) {
	persistent.m8_frame_ms = dt * 1000
	if persistent.m8_animate { persistent.m8_seconds += dt; o.Request_Frame() }
	if persistent.m7_playing {
		motion := tengu.tween_step(tengu.Step_Params(f32){state = &persistent.motion, dt = dt, anim = tengu.F32_Animatable()})
		color := tengu.tween_step(tengu.Step_Params(tengu.RGBA){state = &persistent.animated_color, dt = dt, anim = tengu.RGBA_Animatable()})
		stroke := tengu.tween_step(tengu.Step_Params(f32){state = &persistent.animated_stroke, dt = dt, anim = tengu.F32_Animatable()})
		bend := tengu.tween_step(tengu.Step_Params(f32){state = &persistent.animated_bend, dt = dt, anim = tengu.F32_Animatable()})
		persistent.m7_phase, persistent.stop_phase = motion.value, motion.value
		persistent.m7_tint = {u8(color.value.r * 255), u8(color.value.g * 255), u8(color.value.b * 255), u8(color.value.a * 255)}
		persistent.stroke_width, persistent.bend = stroke.value, bend.value
		if !motion.done || !color.done || !stroke.done || !bend.done { o.Request_Frame() }
	}
	persistent.m7_commands = {
		{kind = .Move, points = {{10, 65}, {}, {}}},
		{kind = .Quadratic, points = {{50, f64(persistent.bend) - 20}, {90, 65}, {}}},
		{kind = .Close},
	}
	if persistent.paths[0].index != 0 && persistent.bend != persistent.last_bend {
		path := curved_path(f64(persistent.bend))
		defer v.Destroy_Path(&path)
		m7_record_error(o.Vector_Update_Path(persistent.paths[0], path.commands[:]))
		persistent.last_bend = persistent.bend
	}
}

m7_init_asset :: proc() -> bool {
	asset, result := o.Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80"><defs><g id="shape"><path id="body" d="M10 65 Q50 5 90 65 Z"/><circle cx="50" cy="55" r="5" fill="white"/></g></defs><use id="site" href="#shape"/></svg>`)
	defer o.Destroy_Svg_Load_Result(&result)
	if !result.ok { o.Log_Error("M7 gallery SVG could not load"); return false }
	persistent.m7_asset = asset
	persistent.m7_group, _ = o.Svg_Lookup_Element(asset, "shape")
	persistent.m7_body, _ = o.Svg_Lookup_Element(asset, "body")
	site, _ := o.Svg_Lookup_Element(asset, "site")
	persistent.m7_occurrence, _ = o.Svg_Lookup_Occurrence(asset, []o.Svg_Element_Handle{site}, persistent.m7_body)
	return true
}

m7_overrides :: proc(color: o.RGBA, occurrence := false) -> []o.Svg_Override {
	values := make([]o.Svg_Override, 5, context.temp_allocator)
	angle := f64(persistent.m7_phase - .5) * .3
	c, sn := math.cos(angle), math.sin(angle)
	values[0] = {target = persistent.m7_group, property = .Fill, paint = o.Solid_Paint(color)}
	values[1] = {target = persistent.m7_group, property = .Transform, transform = {c, sn, -sn, c, 50 - 50 * c + 40 * sn, 40 - 50 * sn - 40 * c}}
	values[2] = {target = persistent.m7_body, property = .Path, commands = persistent.m7_commands[:]}
	values[3] = {target = persistent.m7_body, property = .Stroke, paint = o.Solid_Paint({255, 255, 255, 255})}
	stroke := o.Vector_Default_Stroke
	stroke.width = f64(persistent.stroke_width)
	values[4] = {target = persistent.m7_body, property = .Stroke_Settings, stroke = stroke}
	if occurrence {
		values[0].paint = o.Solid_Paint({250, 180, 30, 255})
		values[0].target = {}
		values[0].occurrence = persistent.m7_occurrence
	}
	return values
}

m7_widget_error :: proc(error: o.Vector_Error, _: []o.Svg_Diagnostic) {
	m7_record_error(error)
}

m7_record_error :: proc(error: o.Vector_Error) {
	if error != .None { persistent.m7_error = error }
}

m7_gallery :: proc() {
	w.Text({config = {id = "m7-title", text = "M7: controlled SVG widgets / independent instances / Tengu", height = set.Height(28)}})
	w.Rectangle({
		config = {id = "m7-controls", direction = set.Direction(.HORIZONTAL), gap_x = set.Gap_X(16), height = set.Height(40)},
		child = proc(_: w.Rectangle_State) {
			w.Button({
				config = {id = "m7-play", width = set.Width(180)},
				child = proc(_: w.Button_State) { w.Text({config = {text = persistent.m7_playing ? "Pause animation" : "Resume animation"}}) },
				on_click = proc(_: w.Button_Event) { persistent.m7_playing = !persistent.m7_playing; o.Request_Frame() },
			})
			w.Button({
				config = {id = "m7-spaces", width = set.Width(260)},
				child = proc(_: w.Button_State) { w.Text({config = {text = "Toggle artboard / overlay SVGs"}}) },
				on_click = proc(_: w.Button_Event) { persistent.m7_show_spaces = !persistent.m7_show_spaces },
			})
			w.Text({config = {text = fmt.tprintf("Draw status: %v", persistent.m7_error)}})
		},
	})
	w.Grid({
		config = {id = "m7-grid", width = set.Width(820), height = set.Height(120), grid_template_columns = set.Grid_Cols(4), gap_x = set.Gap_X(12)},
		child = proc(_: w.Grid_State) {
			w.Button({
				config = {id = "m7-icon-button", height = set.Height(100), direction = set.Direction(.HORIZONTAL)},
				child = proc(_: w.Button_State) {
					w.Svg({config = {id = "m7-button-icon", asset = persistent.m7_asset, width = set.Width(24), height = set.Height(24)}, on_error = m7_widget_error})
					w.Text({config = {text = "SVG button"}})
				},
				on_click = proc(_: w.Button_Event) { persistent.m7_playing = !persistent.m7_playing },
			})
			w.Svg({config = {id = "m7-instance-a", asset = persistent.m7_asset, overrides = m7_overrides(persistent.m7_tint), height = set.Height(100)}, on_error = m7_widget_error})
			w.Svg({config = {id = "m7-instance-b", asset = persistent.m7_asset, overrides = m7_overrides(persistent.m7_tint, true), height = set.Height(100)}, on_error = m7_widget_error})
			w.Rectangle({
				config = {id = "m7-scrollport", height = set.Height(100), overflow_y = set.Overflow_Y(.SCROLL)},
				child = proc(_: w.Rectangle_State) {
					w.Svg({config = {id = "m7-scroll-icon", asset = persistent.m7_asset, width = set.Width(180), height = set.Height(180)}, on_error = m7_widget_error})
					w.Text({config = {text = "Scroll this SVG"}})
				},
			})
		},
	})
	w.Vector({
		config = {id = "m7-vector", viewport = {0, 0, 210, 125}, width = set.Width(820), height = set.Height(140), background = set.Background(.SLATE_900)},
		draw = proc(_: w.Vector_State, canvas: w.Vector_Canvas) {
			m7_record_error(o.Draw_Vector_Path(persistent.paths[0], o.Solid_Paint(persistent.m7_tint), canvas.transform))
			stroke := o.Vector_Default_Stroke
			stroke.width = f64(persistent.stroke_width)
			m7_record_error(o.Draw_Vector_Path(persistent.paths[0], o.Solid_Paint({255, 255, 255, 255}), canvas.transform, op = .Stroke, stroke = stroke))
		},
		child = proc(_: w.Vector_State) { w.Text({config = {id = "m7-vector-child", text = "Composable child: path, colour and stroke advance once in tick"}}) },
		on_error = m7_widget_error,
	})
}

m7_space_examples :: proc() {
	o.Begin_Artboard()
	w.Svg({config = {id = "m7-artboard-icon", asset = persistent.m7_asset, overrides = m7_overrides(persistent.m7_tint), space = set.Space(.ARTBOARD), position = set.Position(.ABSOLUTE), x = set.F32(600), y = set.F32(380), width = set.Width(180), height = set.Height(140), background = set.Background(.BLUE_900)}, on_error = m7_widget_error})
	o.End_Artboard()
	o.Begin_Overlay()
	w.Svg({config = {id = "m7-overlay-icon", asset = persistent.m7_asset, space = set.Space(.OVERLAY), position = set.Position(.FIXED), right = set.Right(32), bottom = set.Bottom(32), width = set.Width(120), height = set.Height(96), background = set.Background(.AMBER_900)}, on_error = m7_widget_error})
	o.End_Overlay()
}

m8_init_stress :: proc() -> bool {
	asset, result := o.Load_Svg_File("oni/fixtures/vector/benchmark/icon-0.svg")
	defer o.Destroy_Svg_Load_Result(&result)
	if !result.ok {
		o.Log_Error("M8 stress gallery could not load benchmark SVG")
		return false
	}
	persistent.m8_asset = asset
	persistent.m8_reload_status = "Ready"
	return true
}

m8_status :: proc(format: string, args: ..any) {
	persistent.m8_reload_status = fmt.bprintf(persistent.m8_status_storage[:], format, ..args)
}

m8_stress_gallery :: proc() {
	w.Text({config = {id = "m8-title", text = "M8: lifecycle stress / counters / reload / deliberate errors", height = set.Height(28)}})
	w.Rectangle({
		config = {id = "m8-stats", direction = set.Direction(.VERTICAL), gap_y = set.Gap_Y(4), height = set.Height(72)},
		child = proc(_: w.Rectangle_State) {
			stats := o.Get_Vector_Stats()
			w.Text({config = {text = fmt.tprintf("Paths live=%d cache=%d KiB gpu=%d KiB pool=%d KiB epoch=%d tess=%d", stats.live_paths, stats.path_cache_bytes / 1024, stats.gpu_bytes / 1024, stats.gpu_pool_bytes / 1024, stats.geometry_epoch, stats.tess_workers), height = set.Height(24)}})
			w.Text({config = {text = fmt.tprintf("Encode p95 fence=%.2fms upload=%.2fms record=%.2fms sample_work=%d visits=%d", stats.encode_fence_ms, stats.encode_upload_ms, stats.encode_record_ms, stats.sample_work, stats.command_visits), height = set.Height(24)}})
			w.Text({config = {text = persistent.m8_reload_status, height = set.Height(24)}})
		},
	})
	w.Rectangle({
		config = {id = "m8-controls", direction = set.Direction(.HORIZONTAL), gap_x = set.Gap_X(12), height = set.Height(40)},
		child = proc(_: w.Rectangle_State) {
			w.Button({
				config = {id = "m8-reload-ok", width = set.Width(200)},
				child = proc(_: w.Button_State) { w.Text({config = {text = "Reload valid SVG"}}) },
				on_click = proc(_: w.Button_Event) {
					result := o.Reload_Svg_File(persistent.m8_asset, "oni/fixtures/vector/benchmark/icon-1.svg")
					defer o.Destroy_Svg_Load_Result(&result)
					if result.ok {
						m8_status("Reload ok revision=%d", persistent.m8_asset.revision)
					} else if len(result.diagnostics) > 0 {
						d := result.diagnostics[0]
						m8_status("Reload failed: %v", d.category)
					}
				},
			})
			w.Button({
				config = {id = "m8-reload-bad", width = set.Width(220)},
				child = proc(_: w.Button_State) { w.Text({config = {text = "Reload invalid (keep prior)"}}) },
				on_click = proc(_: w.Button_Event) {
					revision := persistent.m8_asset.revision
					result := o.Reload_Svg_Memory(persistent.m8_asset, `<svg xmlns="http://www.w3.org/2000/svg"><text>bad</text></svg>`)
					defer o.Destroy_Svg_Load_Result(&result)
					m8_status("Rejected reload; revision still %d", revision)
				},
			})
			w.Checkbox({
				config = {id = "m8-inject", checked = persistent.m8_inject_error ? .TRUE : .FALSE},
				on_checked_change = proc(value: w.Checkbox_Value) { persistent.m8_inject_error = value == .TRUE },
			})
			w.Text({config = {text = "Deliberate draw error", height = set.Height(32)}})
		},
	})
	w.Svg({
		config = {id = "m8-preview", asset = persistent.m8_asset, width = set.Width(120), height = set.Height(120), background = set.Background(.GRAY_900)},
		on_error = proc(error: o.Vector_Error, _: []o.Svg_Diagnostic) {
			if persistent.m8_inject_error {
				return
			}
			m8_status("Draw error: %v", error)
		},
	})
	w.Slider({config = {id = "m8-workload", values = []f32{persistent.m8_workload}, min = 0, max = 2048, step = 64, height = set.Height(32)}, on_value_change = proc(values: []f32) { persistent.m8_workload = values[0] }})
	w.Checkbox({config = {id = "m8-animate", checked = persistent.m8_animate ? .TRUE : .FALSE}, on_checked_change = proc(value: w.Checkbox_Value) { persistent.m8_animate = value == .TRUE; o.Request_Frame() }})
	w.Text({config = {text = fmt.tprintf("Instances=%d animation=%v frame=%.2fms", int(persistent.m8_workload), persistent.m8_animate, persistent.m8_frame_ms), height = set.Height(28)}})
	w.Vector({config = {id = "m8-dense", viewport = {0, 0, 1792, 896}, width = set.Width(820), height = set.Height(410)}, draw = proc(_: w.Vector_State, canvas: w.Vector_Canvas) {
		for i in 0 ..< int(persistent.m8_workload) {
			phase := f64(persistent.m8_seconds) + f64(i) * .0137
			c, s := math.cos(phase), math.sin(phase)
			local := o.Vector_Transform{c, s, -s, c, f64(i % 64) * 28 + 12 - 12 * c + 12 * s, f64(i / 64) * 28 + 12 - 12 * s - 12 * c}
			if err := o.Draw_Svg_Asset(persistent.m8_asset, v.Affine_Compose(canvas.transform, local)); err != .None { m8_status("Dense scene failed: %v", err); break }
		}
	}})
	if persistent.m8_inject_error && o.ui_pass() == .Draw {
		_ = o.Draw_Svg_Asset(persistent.m8_asset, opacity = -1)
	}
}
