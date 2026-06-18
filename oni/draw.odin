package oni

import "core:math"
import sdl "vendor:sdl3"

screen_to_logical :: proc(px_x, px_y: f32, dpi: Dpi_Info) -> Vec2 {
	scale := dpi.scale
	if scale <= 0 do scale = 1
	return {px_x / scale, px_y / scale}
}

logical_to_screen :: proc(log_x, log_y: f32, dpi: Dpi_Info) -> Vec2 {
	scale := dpi.scale
	if scale <= 0 do scale = 1
	return {log_x * scale, log_y * scale}
}

rect_contains :: proc(r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

color_to_f32 :: proc(c: Color) -> [4]f32 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}

draw_record_begin :: proc(dpi: Dpi_Info) {
	state.gpu_state.batch.dpi = dpi
}

draw_record_end :: proc() {
	batch_finalize_segments()
}

draw_begin :: proc(cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, dpi: Dpi_Info) {
	state.gpu_state.batch.cmd = cmd
	state.gpu_state.batch.pass = pass
	state.gpu_state.batch.dpi = dpi
}

draw_flush :: proc() {
	batch_flush_draws()
}

draw_end :: proc() {
	draw_flush()
	state.gpu_state.batch.cmd = nil
	state.gpu_state.batch.pass = nil
}

draw_push_clip :: proc(r: Rect) {
	append(&state.gpu_state.batch.clip_stack, r)
}

draw_pop_clip :: proc() {
	if len(state.gpu_state.batch.clip_stack) > 0 {
		ordered_remove(&state.gpu_state.batch.clip_stack, len(state.gpu_state.batch.clip_stack) - 1)
	}
}

draw_current_space :: proc() -> Draw_Space {
	if state == nil || len(state.gpu_state.batch.space_stack) == 0 do return .Screen
	return state.gpu_state.batch.space_stack[len(state.gpu_state.batch.space_stack) - 1]
}

draw_push_space :: proc(space: Draw_Space) {
	append(&state.gpu_state.batch.space_stack, space)
}

draw_pop_space :: proc() {
	if len(state.gpu_state.batch.space_stack) > 0 {
		ordered_remove(&state.gpu_state.batch.space_stack, len(state.gpu_state.batch.space_stack) - 1)
	}
}

draw_push_artboard :: proc() { draw_push_space(.Artboard) }
draw_pop_artboard :: proc() { draw_pop_space() }
draw_push_screen :: proc() { draw_push_space(.Screen) }
draw_pop_screen :: proc() { draw_pop_space() }

draw_rect :: proc(r: Rect, color: Color, radius: f32 = 0) {
	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(TEXTURE_WHITE_ID)
	batch_push_axis_quad(r, {}, color, {r.w, r.h}, radius * view_artboard_zoom(), .Solid)
}

draw_rect_outline :: proc(r: Rect, color: Color, thickness: f32) {
	t := thickness
	if t <= 0 do return

	draw_rect({r.x, r.y, r.w, t}, color)
	draw_rect({r.x, r.y + r.h - t, r.w, t}, color)
	draw_rect({r.x, r.y, t, r.h}, color)
	draw_rect({r.x + r.w - t, r.y, t, r.h}, color)
}

draw_line :: proc(a, b: Vec2, color: Color, thickness: f32) {
	a_screen := view_transform_point(a)
	b_screen := view_transform_point(b)
	scale := view_artboard_zoom()
	line_thickness := thickness * scale

	dir := b_screen - a_screen
	length := math.sqrt(dir.x * dir.x + dir.y * dir.y)
	if length <= 0 do return

	inv_len := 1 / length
	norm := Vec2{dir.x * inv_len, dir.y * inv_len}
	half_t := line_thickness * 0.5
	perp := Vec2{-norm.y * half_t, norm.x * half_t}

	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(TEXTURE_WHITE_ID)

	corners := [4]Vec2{a_screen + perp, b_screen + perp, b_screen - perp, a_screen - perp}
	uvs := [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	batch_push_quad(corners, uvs, color, {length, line_thickness}, 0, .Line)
}

draw_texture :: proc(tex: Texture_Handle, src, dst: Rect, tint: Color = {255, 255, 255, 255}) {
	if tex.w <= 0 || tex.h <= 0 do return

	uv := Rect{src.x / tex.w, src.y / tex.h, src.w / tex.w, src.h / tex.h}

	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(tex.id)
	batch_push_axis_quad(dst, uv, tint, {dst.w, dst.h}, 0, .Textured)
}

draw_atlas_region :: proc(region: Atlas_Region, dst: Rect, tint: Color = {255, 255, 255, 255}) {
	tex := atlas_region_handle(region)
	src := Rect{region.x, region.y, region.w, region.h}
	draw_texture(tex, src, dst, tint)
}
