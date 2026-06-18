package engine

import "core:math"

View :: struct {
	zoom:   f32,
	pan:    Vec2,
	zoom_min: f32,
	zoom_max: f32,
}

VIEW_ZOOM_QUANTIZE :: f32(0.1)
VIEW_ZOOM_MIN :: f32(0.25)
VIEW_ZOOM_MAX :: f32(8.0)
VIEW_ZOOM_DEFAULT :: f32(1.0)
VIEW_ZOOM_STEP :: f32(1.1)

view_default :: proc() -> View {
	return {
		zoom     = VIEW_ZOOM_DEFAULT,
		pan      = {},
		zoom_min = VIEW_ZOOM_MIN,
		zoom_max = VIEW_ZOOM_MAX,
	}
}

view_quantize_zoom :: proc(zoom: f32) -> f32 {
	if VIEW_ZOOM_QUANTIZE <= 0 do return zoom
	return math.round(zoom / VIEW_ZOOM_QUANTIZE) * VIEW_ZOOM_QUANTIZE
}

view_effective_zoom :: proc() -> f32 {
	if state == nil do return VIEW_ZOOM_DEFAULT
	z := view_quantize_zoom(state.view.zoom)
	return clamp(z, state.view.zoom_min, state.view.zoom_max)
}

view_clamp_zoom :: proc(zoom: f32) -> f32 {
	if state == nil do return view_quantize_zoom(zoom)
	z := view_quantize_zoom(zoom)
	return clamp(z, state.view.zoom_min, state.view.zoom_max)
}

view_set_zoom :: proc(zoom: f32) {
	if state == nil do return
	state.view.zoom = view_clamp_zoom(zoom)
}

view_set_pan :: proc(pan: Vec2) {
	if state == nil do return
	state.view.pan = pan
}

view_pan_by :: proc(delta: Vec2) {
	if state == nil do return
	state.view.pan += delta
}

view_screen_to_world :: proc(screen: Vec2) -> Vec2 {
	if state == nil do return screen
	z := view_effective_zoom()
	if z <= 0 do return screen
	return (screen - state.view.pan) / z
}

view_world_to_screen :: proc(world: Vec2) -> Vec2 {
	if state == nil do return world
	z := view_effective_zoom()
	return world * z + state.view.pan
}

view_zoom_at_screen :: proc(screen: Vec2, zoom: f32) {
	if state == nil do return

	world := view_screen_to_world(screen)
	state.view.zoom = view_clamp_zoom(zoom)
	z := view_effective_zoom()
	state.view.pan = screen - world * z
}

view_zoom_by_screen :: proc(screen: Vec2, factor: f32) {
	if state == nil do return
	view_zoom_at_screen(screen, state.view.zoom * factor)
}

view_zoom_in_screen :: proc(screen: Vec2) {
	view_zoom_by_screen(screen, VIEW_ZOOM_STEP)
}

view_zoom_out_screen :: proc(screen: Vec2) {
	view_zoom_by_screen(screen, 1 / VIEW_ZOOM_STEP)
}

view_reset :: proc() {
	if state == nil do return
	state.view = view_default()
}

view_transform_rect :: proc(r: Rect) -> Rect {
	if draw_current_space() != .Artboard do return r
	z := view_effective_zoom()
	if state == nil do return r
	return {
		x = r.x * z + state.view.pan.x,
		y = r.y * z + state.view.pan.y,
		w = r.w * z,
		h = r.h * z,
	}
}

view_transform_point :: proc(p: Vec2) -> Vec2 {
	if draw_current_space() != .Artboard do return p
	return view_world_to_screen(p)
}

view_artboard_zoom :: proc() -> f32 {
	if draw_current_space() == .Artboard {
		return view_effective_zoom()
	}
	return 1
}
