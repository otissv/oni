package oni

import "core:math"

/*
2D camera transform: zoom level, pan offset, and zoom clamp limits.
*/
View :: struct {
	zoom:     f32,
	pan:      Vec2,
	zoom_min: f32,
	zoom_max: f32,
}

VIEW_ZOOM_QUANTIZE :: f32(0.1)
VIEW_ZOOM_MIN :: f32(0.25)
VIEW_ZOOM_MAX :: f32(8.0)
VIEW_ZOOM_DEFAULT :: f32(1.0)
VIEW_ZOOM_STEP :: f32(1.1)

/*
Returns a view with default zoom, pan, and clamp limits.
*/
view_default :: proc() -> View {
	return {zoom = VIEW_ZOOM_DEFAULT, pan = {}, zoom_min = VIEW_ZOOM_MIN, zoom_max = VIEW_ZOOM_MAX}
}

/*
Snaps a zoom value to the nearest quantization step.
*/
view_quantize_zoom :: proc(zoom: f32) -> f32 {
	if VIEW_ZOOM_QUANTIZE <= 0 do return zoom
	return math.round(zoom / VIEW_ZOOM_QUANTIZE) * VIEW_ZOOM_QUANTIZE
}

/*
Returns the current zoom quantized and clamped to view limits.
*/
view_effective_zoom :: proc() -> f32 {
	if state == nil do return VIEW_ZOOM_DEFAULT
	z := view_quantize_zoom(state.view.zoom)
	return clamp(z, state.view.zoom_min, state.view.zoom_max)
}

/*
Quantizes and clamps a zoom value to the view min/max range.
*/
view_clamp_zoom :: proc(zoom: f32) -> f32 {
	if state == nil do return view_quantize_zoom(zoom)
	z := view_quantize_zoom(zoom)
	return clamp(z, state.view.zoom_min, state.view.zoom_max)
}

/*
Sets the view zoom, clamped to configured limits.
*/
view_set_zoom :: proc(zoom: f32) {
	if state == nil do return
	state.view.zoom = view_clamp_zoom(zoom)
}

/*
Sets the view pan offset in screen space.
*/
view_set_pan :: proc(pan: Vec2) {
	if state == nil do return
	state.view.pan = pan
}

/*
Adds a delta to the current view pan offset.
*/
view_pan_by :: proc(delta: Vec2) {
	if state == nil do return
	state.view.pan += delta
}

/*
Converts a screen-space point to world (artboard) coordinates.
*/
view_screen_to_world :: proc(screen: Vec2) -> Vec2 {
	if state == nil do return screen
	z := view_effective_zoom()
	if z <= 0 do return screen
	return (screen - state.view.pan) / z
}

/*
Converts a world (artboard) point to screen-space coordinates.
*/
view_world_to_screen :: proc(world: Vec2) -> Vec2 {
	if state == nil do return world
	z := view_effective_zoom()
	return world * z + state.view.pan
}

/*
Sets zoom while keeping the world point under a screen anchor fixed.
*/
view_zoom_at_screen :: proc(screen: Vec2, zoom: f32) {
	if state == nil do return

	world := view_screen_to_world(screen)
	state.view.zoom = view_clamp_zoom(zoom)
	z := view_effective_zoom()
	state.view.pan = screen - world * z
}

/*
Multiplies the current zoom by a factor around a screen anchor point.
*/
view_zoom_by_screen :: proc(screen: Vec2, factor: f32) {
	if state == nil do return
	view_zoom_at_screen(screen, state.view.zoom * factor)
}

/*
Zooms in by VIEW_ZOOM_STEP around a screen anchor point.
*/
view_zoom_in_screen :: proc(screen: Vec2) {
	view_zoom_by_screen(screen, VIEW_ZOOM_STEP)
}

/*
Zooms out by VIEW_ZOOM_STEP around a screen anchor point.
*/
view_zoom_out_screen :: proc(screen: Vec2) {
	view_zoom_by_screen(screen, 1 / VIEW_ZOOM_STEP)
}

/*
Resets zoom and pan to default view values.
*/
view_reset :: proc() {
	if state == nil do return
	state.view = view_default()
}

/*
Transforms a rect from artboard space to screen space when drawing on the artboard.

Returns the rect unchanged for screen-space drawing.
*/
view_transform_rect :: proc(r: Rect) -> Rect {
	if draw_current_space() != .ARTBOARD do return r
	z := view_effective_zoom()
	if state == nil do return r
	return {
		x = r.x * z + state.view.pan.x,
		y = r.y * z + state.view.pan.y,
		w = r.w * z,
		h = r.h * z,
	}
}

/*
Transforms a point from artboard space to screen space when drawing on the artboard.

Returns the point unchanged for screen-space drawing.
*/
view_transform_point :: proc(p: Vec2) -> Vec2 {
	if draw_current_space() != .ARTBOARD do return p
	return view_world_to_screen(p)
}

/*
Returns the effective artboard zoom when drawing in artboard space, else 1.
*/
view_artboard_zoom :: proc() -> f32 {
	if draw_current_space() == .ARTBOARD {
		return view_effective_zoom()
	}
	return 1
}

/*
Converts a point from screen to logical artboard coordinates when in artboard space.

Returns the point unchanged for screen-space drawing.
*/
draw_space_to_logical :: proc(p: Vec2) -> Vec2 {
	if draw_current_space() != .ARTBOARD do return p
	return view_screen_to_world(p)
}
