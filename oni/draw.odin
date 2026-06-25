package oni

import "core:math"
import sdl "vendor:sdl3"

/*
Converts pixel coordinates to logical (DPI-scaled) space.

Divides by the DPI scale factor, defaulting to 1 when scale is invalid.
*/
screen_to_logical :: proc(px_x, px_y: f32, dpi: Dpi_Info) -> Vec2 {
	scale := dpi.scale
	if scale <= 0 do scale = 1
	return {px_x / scale, px_y / scale}
}

/*
Converts logical coordinates to pixel (screen) space.

Multiplies by the DPI scale factor, defaulting to 1 when scale is invalid.
*/
logical_to_screen :: proc(log_x, log_y: f32, dpi: Dpi_Info) -> Vec2 {
	scale := dpi.scale
	if scale <= 0 do scale = 1
	return {log_x * scale, log_y * scale}
}

/*
Returns true when point p lies inside rectangle r.

Uses half-open bounds: the left and top edges are inclusive, right and bottom
are exclusive.
*/
rect_contains :: proc(r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

/*
Computes the axis-aligned overlap of two rectangles.

Returns an empty rect when the inputs do not intersect.
*/
rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	if x1 <= x0 || y1 <= y0 do return {}
	return {x0, y0, x1 - x0, y1 - y0}
}

/*
Begins CPU-side draw recording for the current frame.

Sets the batch DPI used when geometry is later uploaded and flushed.
*/
draw_record_begin :: proc(dpi: Dpi_Info) {
	state.gpu_state.batch.dpi = dpi
}

/*
Ends CPU-side draw recording and finalizes batch segments.

Call after all draw commands for the frame have been recorded.
*/
draw_record_end :: proc() {
	batch_finalize_segments()
}

/*
Binds the active GPU command buffer and render pass for immediate drawing.

Also stores DPI info used by subsequent flush and clip operations.
*/
draw_begin :: proc(cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, dpi: Dpi_Info) {
	state.gpu_state.batch.cmd = cmd
	state.gpu_state.batch.pass = pass
	state.gpu_state.batch.dpi = dpi
}

/*
Uploads pending batch geometry and issues draw calls for the current pass.

Does nothing when the batch has no segments or the pipeline is unavailable.
*/
draw_flush :: proc() {
	batch_flush_draws()
}

/*
Flushes pending draws and clears the active command buffer and render pass.

Call at the end of a GPU render pass before starting another pass.
*/
draw_end :: proc() {
	draw_flush()
	state.gpu_state.batch.cmd = nil
	state.gpu_state.batch.pass = nil
}

/*
Pushes a clip rectangle onto the batch clip stack.

Intersected clips from nested pushes constrain subsequent draw geometry.
*/
draw_push_clip :: proc(r: Rect) {
	append(&state.gpu_state.batch.clip_stack, r)
}

/*
Pops the top clip rectangle from the batch clip stack.

No-op when the clip stack is empty.
*/
draw_pop_clip :: proc() {
	if len(state.gpu_state.batch.clip_stack) > 0 {
		ordered_remove(
			&state.gpu_state.batch.clip_stack,
			len(state.gpu_state.batch.clip_stack) - 1,
		)
	}
}

/*
Returns the active draw coordinate space from the top of the space stack.

Defaults to Screen when no space has been pushed.
*/
draw_current_space :: proc() -> Draw_Space {
	if state == nil || len(state.gpu_state.batch.space_stack) == 0 do return .Screen
	return state.gpu_state.batch.space_stack[len(state.gpu_state.batch.space_stack) - 1]
}

/*
Pushes a draw coordinate space onto the batch space stack.

Used to switch between screen and artboard coordinate transforms.
*/
draw_push_space :: proc(space: Draw_Space) {
	append(&state.gpu_state.batch.space_stack, space)
}

/*
Pops the top draw coordinate space from the batch space stack.

No-op when the space stack is empty.
*/
draw_pop_space :: proc() {
	if len(state.gpu_state.batch.space_stack) > 0 {
		ordered_remove(
			&state.gpu_state.batch.space_stack,
			len(state.gpu_state.batch.space_stack) - 1,
		)
	}
}

/*
Enters artboard draw space with matching layout and root UI style.

During the layout pass, also begins a nested artboard layout region.
*/
begin_artboard :: proc() {
	draw_push_space(.Artboard)
	bounds := layout_space_bounds(.Artboard)
	ui_push_style(style_root(.Artboard, bounds))
	if ui_pass() == .Layout do layout_begin_space(.Artboard)
}


/*
Leaves artboard draw space and restores the previous layout and style state.

During the layout pass, ends the nested artboard layout region first.
*/
end_artboard :: proc() {
	if ui_pass() == .Layout do layout_end_space()
	ui_pop_style()
	draw_pop_space()
}

/*
Enters screen draw space with matching layout and root UI style.

During the layout pass, also begins a nested screen layout region.
*/
draw_push_screen :: proc() {
	draw_push_space(.Screen)
	bounds := layout_space_bounds(.Screen)
	ui_push_style(style_root(.Screen, bounds))
	if ui_pass() == .Layout do layout_begin_space(.Screen)
}

/*
Leaves screen draw space and restores the previous layout and style state.

During the layout pass, ends the nested screen layout region first.
*/
draw_pop_screen :: proc() {
	if ui_pass() == .Layout do layout_end_space()
	ui_pop_style()
	draw_pop_space()
}

/*
Draws a filled and/or bordered rectangle with optional corner radii.

Skips the draw when both fill and border are fully transparent or zero-sized.
Corner radii and border widths are scaled by the current artboard zoom.
*/
draw_rect :: proc(
	r: Rect,
	color: RGBA,
	radius: Radius_corners = {},
	border: Bd = {},
	border_color: RGBA = {},
) {
	has_fill := color.a > 0
	has_border :=
		border_color.a > 0 && (border.t > 0 || border.b > 0 || border.l > 0 || border.r > 0)
	if !has_fill && !has_border do return

	scale := view_artboard_zoom()
	screen_radii := [4]f32 {
		radius.tl * scale,
		radius.tr * scale,
		radius.br * scale,
		radius.bl * scale,
	}
	screen_border := Bd {
		t = border.t * scale,
		b = border.b * scale,
		l = border.l * scale,
		r = border.r * scale,
	}

	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(TEXTURE_WHITE_ID)
	batch_push_axis_quad(
		r,
		{},
		color,
		border_color,
		{r.w, r.h},
		screen_radii,
		screen_border,
		.Solid,
	)
}

/*
Draws a solid line segment between two points in logical space.

Transforms endpoints to screen space and expands the segment into a quad
with the given thickness, scaled by artboard zoom.
*/
draw_line :: proc(a, b: Vec2, color: RGBA, thickness: f32) {
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
	batch_push_quad(corners, uvs, uvs, color, {}, {length, line_thickness}, {}, {}, .Line)
}

/*
Draws a textured rectangle with optional tint, background fallback, and styling.

Falls back to draw_rect when the texture handle is invalid. Supports rounded
corners and borders; selects Textured_Rounded mode when either is present.
*/
draw_texture :: proc(
	texture: Texture_Handle,
	src, dst: Rect,
	tint: RGBA = {255, 255, 255, 255},
	background: RGBA = {},
	radius: Radius_corners = {},
	border: Bd = {},
	border_color: RGBA = {},
) {
	has_texture := texture.w > 0 && texture.h > 0
	has_radius := radius.tl > 0 || radius.tr > 0 || radius.br > 0 || radius.bl > 0
	has_border :=
		border_color.a > 0 && (border.t > 0 || border.b > 0 || border.l > 0 || border.r > 0)

	if !has_texture {
		draw_rect(dst, background, radius, border, border_color)
		return
	}

	scale := view_artboard_zoom()
	screen_radii := [4]f32 {
		radius.tl * scale,
		radius.tr * scale,
		radius.br * scale,
		radius.bl * scale,
	}
	screen_border := Bd {
		t = border.t * scale,
		b = border.b * scale,
		l = border.l * scale,
		r = border.r * scale,
	}

	uv := Rect{src.x / texture.w, src.y / texture.h, src.w / texture.w, src.h / texture.h}

	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(texture.id)
	mode: Draw_Mode = .Textured
	if has_radius || has_border do mode = .Textured_Rounded
	batch_push_axis_quad(
		dst,
		uv,
		tint,
		border_color,
		{dst.w, dst.h},
		screen_radii,
		screen_border,
		mode,
	)
}

/*
Draws an atlas sub-region into dst using normalized source UVs.

Convenience wrapper around draw_texture for font and asset atlas regions.
*/
draw_atlas_region :: proc(region: Atlas_Region, dst: Rect, tint: RGBA = {255, 255, 255, 255}) {
	texture := atlas_region_handle(region)
	src := Rect{region.x, region.y, region.w, region.h}
	draw_texture(texture, src, dst, tint, {})
}

/*
Maps a logical point inside image_dst to normalized texture UV coordinates.

Used by draw_texture_fitted to derive per-corner UVs from content layout.
*/
@(private)
texture_content_uv :: proc(px, py: f32, image_dst, src: Rect, tex_w, tex_h: f32) -> Vec2 {
	if image_dst.w <= 0 || image_dst.h <= 0 || tex_w <= 0 || tex_h <= 0 do return {0, 0}
	return {
		(src.x + (px - image_dst.x) / image_dst.w * src.w) / tex_w,
		(src.y + (py - image_dst.y) / image_dst.h * src.h) / tex_h,
	}
}

/*
Computes border insets between a content rect and its image destination rect.

Positive inset values mark regions where the source image does not cover
the content area, enabling nine-slice-style clipping in the shader.
*/
@(private)
texture_image_insets :: proc(content, image_dst: Rect) -> Bd {
	return {
		t = image_dst.y - content.y,
		b = (content.y + content.h) - (image_dst.y + image_dst.h),
		l = image_dst.x - content.x,
		r = (content.x + content.w) - (image_dst.x + image_dst.w),
	}
}

/*
Draws a texture fitted to a content rect with per-corner UV interpolation.

Clips to the current batch clip, maps visible corners to source UVs, and
uses image insets for nine-slice-style shader clipping when needed.
*/
draw_texture_fitted :: proc(
	texture: Texture_Handle,
	src, content, image_dst: Rect,
	tint: RGBA,
	radius: Radius_corners,
) {
	if texture.w <= 0 || texture.h <= 0 do return
	if content.w <= 0 || content.h <= 0 do return

	scale := view_artboard_zoom()
	screen_radii := [4]f32 {
		radius.tl * scale,
		radius.tr * scale,
		radius.br * scale,
		radius.bl * scale,
	}

	tw, th := texture.w, texture.h
	screen := view_transform_rect(content)
	clip := batch_current_clip()
	visible := rect_intersect(screen, clip)
	if visible.w <= 0 || visible.h <= 0 do return

	x0, y0 := visible.x, visible.y
	x1, y1 := visible.x + visible.w, visible.y + visible.h
	corners_screen := [4]Vec2{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}

	uvs: [4]Vec2
	local_uvs: [4]Vec2
	for i in 0 ..< 4 {
		logical := draw_space_to_logical(corners_screen[i])
		uvs[i] = texture_content_uv(logical.x, logical.y, image_dst, src, tw, th)
		local_uvs[i] = {
			(logical.x - content.x) / content.w,
			(logical.y - content.y) / content.h,
		}
	}

	insets := texture_image_insets(content, image_dst)
	use_image_clip :=
		insets.t > 0.001 ||
		insets.b > 0.001 ||
		insets.l > 0.001 ||
		insets.r > 0.001

	state.gpu_state.batch.dpi = state.dpi
	batch_check_key(texture.id)
	batch_push_quad(
		corners_screen,
		uvs,
		local_uvs,
		tint,
		{},
		{screen.w, screen.h},
		screen_radii,
		insets,
		.Textured_Rounded,
		use_image_clip,
	)
}
