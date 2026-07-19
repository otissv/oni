package oni

import "core:fmt"
import "core:math"
import "core:mem"
import sdl "vendor:sdl3"

Draw_Mode :: enum {
	Solid,
	Textured,
	Line,
	Textured_Rounded,
}

/*
Returns the draw mode as an f32 for packing into vertex shader params.
*/
draw_mode_f32 :: proc(mode: Draw_Mode) -> f32 {
	return f32(mode)
}

BATCH_INITIAL_VERT_CAPACITY :: 64 * 1024

/*
Identifies a draw batch by texture asset, active clip rectangle, and stack index.
*/
Batch_Key :: struct {
	texture_id:  Asset_Id,
	clip:        Rect,
	stack_index: u32,
}

/*
Contiguous index range within the batch that shares one Batch_Key.
*/
Batch_Segment :: struct {
	key:         Batch_Key,
	first_index: u32,
	index_count: u32,
}

/*
CPU-side vertex/index buffers, clip/space stacks, and GPU upload state for a frame.
*/
Batch_State :: struct {
	vertices:            [dynamic]UI_Vertex,
	indices:             [dynamic]u16,
	segments:            [dynamic]Batch_Segment,
	clip_stack:          [dynamic]Rect,
	space_stack:         [dynamic]Draw_Space,
	opacity_stack:       [dynamic]f32,
	current_key:         Batch_Key,
	has_current_key:     bool,
	current_stack:       u32,
	vertex_buffer:       ^sdl.GPUBuffer,
	index_buffer:        ^sdl.GPUBuffer,
	vertex_capacity:     u32,
	index_capacity:      u32,
	cmd:                 ^sdl.GPUCommandBuffer,
	pass:                ^sdl.GPURenderPass,
	dpi:                 Dpi_Info,
	// Cached products / derived state; invalidated on push/pop / dpi / view change.
	cached_opacity:      f32,
	cached_clip:         Rect,
	clip_cache_valid:    bool,
	cached_space:        Draw_Space,
	cached_view_zoom:    f32,
	cached_view_pan:     Vec2,
	view_cache_valid:    bool,
}

/*
Returns the ping-pong Batch_State currently used for CPU recording / GPU upload.
*/
batch_current :: #force_inline proc() -> ^Batch_State {
	return &state.gpu_state.batches[state.gpu_state.batch_index]
}

/*
Switches to the alternate batch slot after a successful submit.

The next frame records into the other CPU/GPU buffers so work can proceed while
the previous slot's GPU buffers may still be in flight.
*/
batch_flip :: proc() {
	state.gpu_state.batch_index = 1 - state.gpu_state.batch_index
}

/*
Destroys CPU dynamic arrays for every batch slot in `gpu_state`.

Used by tests that tear down a State without going through `batch_destroy`.
*/
batch_delete_cpu_arrays :: proc(gpu_state: ^GPU_State) {
	if gpu_state == nil do return
	for &b in gpu_state.batches {
		delete(b.vertices)
		delete(b.indices)
		delete(b.segments)
		delete(b.clip_stack)
		delete(b.space_stack)
		delete(b.opacity_stack)
		b.vertices = nil
		b.indices = nil
		b.segments = nil
		b.clip_stack = nil
		b.space_stack = nil
		b.opacity_stack = nil
	}
}

/*
Initializes both ping-pong batch slots with CPU capacities and GPU VB/IB.

Uses BATCH_INITIAL_VERT_CAPACITY as the starting vertex capacity. Leaves
`batch_index` at 0 for the first frame.
*/
batch_init :: proc() {
	for i in 0 ..< len(state.gpu_state.batches) {
		state.gpu_state.batch_index = i
		b := batch_current()
		b.vertex_capacity = BATCH_INITIAL_VERT_CAPACITY
		b.index_capacity = BATCH_INITIAL_VERT_CAPACITY * 6
		batch_create_gpu_buffers()
	}
	state.gpu_state.batch_index = 0
}

/*
Creates or recreates GPU vertex and index buffers at the current capacities.

Releases existing buffers before allocation. Returns false on SDL failure.
*/
batch_create_gpu_buffers :: proc() -> bool {
	if state.gpu == nil do return false

	b := batch_current()
	vertex_bytes := b.vertex_capacity * u32(size_of(UI_Vertex))
	index_bytes := b.index_capacity * u32(size_of(u16))

	if b.vertex_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, b.vertex_buffer)
		b.vertex_buffer = nil
	}
	if b.index_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, b.index_buffer)
		b.index_buffer = nil
	}

	b.vertex_buffer = sdl.CreateGPUBuffer(state.gpu, {usage = {.VERTEX}, size = vertex_bytes})
	b.index_buffer = sdl.CreateGPUBuffer(state.gpu, {usage = {.INDEX}, size = index_bytes})

	if test_hook_batch_fail_vertex_buffer && b.vertex_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, b.vertex_buffer)
		b.vertex_buffer = nil
	}
	if test_hook_batch_fail_index_buffer && b.index_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, b.index_buffer)
		b.index_buffer = nil
	}

	if b.vertex_buffer == nil || b.index_buffer == nil {
		fmt.eprintln("SDL_CreateGPUBuffer failed:", sdl.GetError())
		if b.vertex_buffer != nil do sdl.ReleaseGPUBuffer(state.gpu, b.vertex_buffer)
		if b.index_buffer != nil do sdl.ReleaseGPUBuffer(state.gpu, b.index_buffer)
		b.vertex_buffer = nil
		b.index_buffer = nil
		return false
	}

	return true
}

/*
Releases both ping-pong slots' GPU buffers and frees all CPU-side dynamic arrays.

Safe to call when state is nil or the GPU device is already destroyed.
*/
batch_destroy :: proc() {
	if state == nil do return

	for i in 0 ..< len(state.gpu_state.batches) {
		state.gpu_state.batch_index = i
		b := batch_current()
		if state.gpu != nil {
			if b.vertex_buffer != nil {
				sdl.ReleaseGPUBuffer(state.gpu, b.vertex_buffer)
				b.vertex_buffer = nil
			}
			if b.index_buffer != nil {
				sdl.ReleaseGPUBuffer(state.gpu, b.index_buffer)
				b.index_buffer = nil
			}
		}

		delete(b.vertices)
		delete(b.indices)
		delete(b.segments)
		delete(b.clip_stack)
		delete(b.space_stack)
		delete(b.opacity_stack)
		b.vertices = nil
		b.indices = nil
		b.segments = nil
		b.clip_stack = nil
		b.space_stack = nil
		b.opacity_stack = nil

		b.vertex_capacity = 0
		b.index_capacity = 0
		b.has_current_key = false
		b.cached_opacity = 1
		b.clip_cache_valid = false
		b.view_cache_valid = false
	}
	state.gpu_state.batch_index = 0
}

/*
Clears recorded vertices, indices, segments, and stack state for a new frame.

Does not release GPU buffers or change capacity.
*/
batch_reset :: proc() {
	clear(&batch_current().vertices)
	clear(&batch_current().indices)
	clear(&batch_current().segments)
	clear(&batch_current().clip_stack)
	clear(&batch_current().space_stack)
	clear(&batch_current().opacity_stack)
	batch_current().has_current_key = false
	batch_current().current_stack = 0
	batch_current().cached_opacity = 1
	batch_current().clip_cache_valid = false
	batch_current().view_cache_valid = false
}

/*
Invalidates cached clip/view products used while recording draw commands.
*/
batch_invalidate_clip_cache :: proc() {
	if state == nil do return
	batch_current().clip_cache_valid = false
}

/*
Invalidates cached artboard zoom/pan used by view transforms during recording.
*/
batch_invalidate_view_cache :: proc() {
	if state == nil do return
	batch_current().view_cache_valid = false
	batch_current().clip_cache_valid = false
}

/*
Refreshes and returns cached artboard zoom/pan for the current draw space.

Screen space returns zoom 1 and zero pan without consulting the view.
*/
batch_cached_view :: proc() -> (zoom: f32, pan: Vec2, space: Draw_Space) {
	space = draw_current_space()
	if space != .ARTBOARD {
		return 1, {}, space
	}
	if batch_current().view_cache_valid && batch_current().cached_space == space {
		return batch_current().cached_view_zoom, batch_current().cached_view_pan, space
	}
	zoom = view_effective_zoom()
	pan = state.view.pan
	batch_current().cached_space = space
	batch_current().cached_view_zoom = zoom
	batch_current().cached_view_pan = pan
	batch_current().view_cache_valid = true
	return zoom, pan, space
}

/*
Ensures the batch can hold extra_verts additional vertices.

Doubles GPU buffer capacity until sufficient, recreating buffers as needed.
Returns false if buffer recreation fails.
*/
batch_ensure_capacity :: proc(extra_verts: int) -> bool {
	needed := len(batch_current().vertices) + extra_verts
	if u32(needed) <= batch_current().vertex_capacity do return true

	new_cap := batch_current().vertex_capacity
	for u32(needed) > new_cap {
		new_cap *= 2
	}
	batch_current().vertex_capacity = new_cap
	batch_current().index_capacity = new_cap * 6
	return batch_create_gpu_buffers()
}

/*
Returns the effective clip rect in screen space for the current draw batch.

Uses the top of the clip stack intersected with the logical viewport, or the
full viewport when no clip has been pushed. Result is cached until clip, space,
DPI, or view transform inputs change.
*/
batch_current_clip :: proc() -> Rect {
	if batch_current().clip_cache_valid {
		return batch_current().cached_clip
	}

	clip: Rect
	if len(batch_current().clip_stack) == 0 {
		clip = {
			0,
			0,
			f32(batch_current().dpi.logical_w),
			f32(batch_current().dpi.logical_h),
		}
	} else {
		clip = batch_current().clip_stack[len(batch_current().clip_stack) - 1]
	}
	clip = view_transform_rect(clip)
	viewport := Rect {
		0,
		0,
		f32(batch_current().dpi.logical_w),
		f32(batch_current().dpi.logical_h),
	}
	clip = rect_intersect(clip, viewport)
	batch_current().cached_clip = clip
	batch_current().clip_cache_valid = true
	return clip
}

/*
Sets the stack index applied to subsequent draw commands in this batch.
*/
batch_set_stack_index :: proc(stack_index: u32) {
	batch_current().current_stack = stack_index
}

/*
Starts a new batch segment when the texture, clip, or stack index key changes.

Finalizes the previous segment's index count before appending a new one.
*/
batch_check_key :: proc(texture_id: Asset_Id) {
	clip := batch_current_clip()
	key := Batch_Key {
		texture_id  = texture_id,
		clip        = clip,
		stack_index = batch_current().current_stack,
	}

	if batch_current().has_current_key &&
	   batch_current().current_key.texture_id == key.texture_id &&
	   batch_current().current_key.clip == key.clip &&
	   batch_current().current_key.stack_index == key.stack_index {
		return
	}

	if batch_current().has_current_key && len(batch_current().indices) > 0 {
		seg := batch_current().segments[len(batch_current().segments) - 1]
		seg.index_count = u32(len(batch_current().indices)) - seg.first_index
		batch_current().segments[len(batch_current().segments) - 1] = seg
	}

	append(
		&batch_current().segments,
		Batch_Segment{key = key, first_index = u32(len(batch_current().indices))},
	)
	batch_current().current_key = key
	batch_current().has_current_key = true
}

/*
Appends two triangles (six indices) for a quad starting at vertex base.
*/
batch_push_indices :: proc(base: u16) {
	append(
		&batch_current().indices,
		base + 0,
		base + 1,
		base + 2,
		base + 0,
		base + 2,
		base + 3,
	)
}

/*
Appends one UI vertex with color, border, radii, and draw-mode params.

Optionally sets the tex_clip flag for nine-slice-style image clipping.
*/
batch_push_vertex :: proc(
	pos: Vec2,
	uv: Vec2,
	local_uv: Vec2,
	color: [4]f32,
	border_color: [4]f32,
	rect_size: Vec2,
	radii: [4]f32,
	border: Bd_px,
	mode_f32: f32,
	tex_clip: bool = false,
) {
	tex_clip_flag: f32 = 0
	if tex_clip do tex_clip_flag = 1
	append(
		&batch_current().vertices,
		UI_Vertex {
			pos = pos,
			uv = uv,
			local_uv = local_uv,
			color = color,
			border_color = border_color,
			rect_size = rect_size,
			radii = radii,
			params = {tex_clip_flag, mode_f32},
			border = {border.t, border.b, border.l, border.r},
		},
	)
}

/*
Records a four-corner quad with shared rect styling into the batch.

Ensures vertex capacity, converts colors to f32, and emits triangle indices.
*/
batch_push_quad :: proc(
	corners: [4]Vec2,
	uvs: [4]Vec2,
	local_uvs: [4]Vec2,
	color: RGBA,
	border_color: RGBA,
	rect_size: Vec2,
	radii: [4]f32,
	border: Bd_px,
	mode: Draw_Mode,
	tex_clip: bool = false,
) {
	if !batch_ensure_capacity(4) do return

	opacity := draw_effective_opacity()
	tint := rgba_to_f32(color)
	border_tint := rgba_to_f32(border_color)
	tint[3] *= opacity
	border_tint[3] *= opacity
	base := u16(len(batch_current().vertices))
	mode_f32 := draw_mode_f32(mode)

	for i in 0 ..< 4 {
		batch_push_vertex(
			corners[i],
			uvs[i],
			local_uvs[i],
			tint,
			border_tint,
			rect_size,
			radii,
			border,
			mode_f32,
			tex_clip,
		)
	}
	batch_push_indices(base)
}

@(private)
batch_axis_quad_has_chrome :: proc(radii: [4]f32, border: Bd_px) -> bool {
	return radii[0] > 0 ||
		radii[1] > 0 ||
		radii[2] > 0 ||
		radii[3] > 0 ||
		border.t > 0 ||
		border.b > 0 ||
		border.l > 0 ||
		border.r > 0
}

/*
Snaps screen-space rect edges to device pixels for stable 1px chrome.

This keeps bordered / rounded solid quads from landing on fractional edges,
which otherwise makes thin borders fade or disappear inconsistently.
*/
@(private)
batch_snap_rect_to_pixels :: proc(r: Rect) -> Rect {
	if r.w <= 0 || r.h <= 0 do return r

	x0 := math.floor(r.x + 0.5)
	y0 := math.floor(r.y + 0.5)
	x1 := math.floor(r.x + r.w + 0.5)
	y1 := math.floor(r.y + r.h + 0.5)

	if x1 <= x0 {
		x1 = x0 + 1
	}

	if y1 <= y0 {
		y1 = y0 + 1
	}

	return {x0, y0, x1 - x0, y1 - y0}
}

/*
Records an axis-aligned rectangle quad, optionally clipped for textured draws.

For textured modes, intersects with the current clip and adjusts UVs to
match the visible sub-rect before delegating to batch_push_quad.
*/
batch_push_axis_quad :: proc(
	r: Rect,
	uv_rect: Rect,
	color: RGBA,
	border_color: RGBA,
	rect_size: Vec2,
	radii: [4]f32,
	border: Bd_px,
	mode: Draw_Mode,
) {
	screen := view_transform_rect(r)
	u0, v0 := uv_rect.x, uv_rect.y
	u1, v1 := uv_rect.x + uv_rect.w, uv_rect.y + uv_rect.h

	#partial switch mode {
	case .Textured, .Textured_Rounded:
		clip := batch_current_clip()
		visible := rect_intersect(screen, clip)
		if visible.w <= 0 || visible.h <= 0 do return

		if screen.w > 0 && screen.h > 0 {
			fx0 := (visible.x - screen.x) / screen.w
			fy0 := (visible.y - screen.y) / screen.h
			fx1 := fx0 + visible.w / screen.w
			fy1 := fy0 + visible.h / screen.h
			u0 = uv_rect.x + uv_rect.w * fx0
			v0 = uv_rect.y + uv_rect.h * fy0
			u1 = uv_rect.x + uv_rect.w * fx1
			v1 = uv_rect.y + uv_rect.h * fy1
		}
		screen = visible
	}

	if mode == .Solid && batch_axis_quad_has_chrome(radii, border) {
		screen = batch_snap_rect_to_pixels(screen)
	}

	x0, y0 := screen.x, screen.y
	x1, y1 := screen.x + screen.w, screen.y + screen.h
	screen_size := Vec2{screen.w, screen.h}

	corners := [4]Vec2{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}
	rect_local := [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	uvs: [4]Vec2
	local_uvs := rect_local
	switch mode {
	case .Solid, .Line:
		uvs = rect_local
	case .Textured, .Textured_Rounded:
		uvs = [4]Vec2{{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
	}

	batch_push_quad(corners, uvs, local_uvs, color, border_color, screen_size, radii, border, mode)
}

/*
Records multiple textured atlas quads that share one texture / clip / stack key.

Checks the batch key once and ensures vertex capacity for all quads up front,
so glyph runs avoid per-quad capacity growth and segment-key work.
`srcs` are pixel-space rectangles in the texture; `dsts` are logical quads.
*/
batch_push_atlas_quads :: proc(
	texture: Texture_Handle,
	dsts: []Rect,
	srcs: []Rect,
	tint: RGBA,
) {
	n := len(dsts)
	if n == 0 || len(srcs) != n do return
	if texture.w <= 0 || texture.h <= 0 do return

	batch_current().dpi = state.dpi
	batch_check_key(texture.id)
	if !batch_ensure_capacity(4 * n) do return

	inv_w := 1 / texture.w
	inv_h := 1 / texture.h
	for i in 0 ..< n {
		src := srcs[i]
		dst := dsts[i]
		uv := Rect{src.x * inv_w, src.y * inv_h, src.w * inv_w, src.h * inv_h}
		batch_push_axis_quad(dst, uv, tint, {}, {dst.w, dst.h}, {}, {}, .Textured)
	}
}

/*
Finalizes the index count of the last open batch segment, then sorts by stack index.

Higher stack_index paints on top. Equal stack keeps submission order (first_index ascending).
Call before upload or flush when recording is complete.
*/
batch_finalize_segments :: proc() {
	if batch_current().has_current_key && len(batch_current().segments) > 0 {
		seg := batch_current().segments[len(batch_current().segments) - 1]
		seg.index_count = u32(len(batch_current().indices)) - seg.first_index
		batch_current().segments[len(batch_current().segments) - 1] = seg
	}

	segs := batch_current().segments[:]
	n := len(segs)
	for i in 1 ..< n {
		key := segs[i]
		j := i - 1
		for j >= 0 &&
		    (segs[j].key.stack_index > key.key.stack_index ||
			    (segs[j].key.stack_index == key.key.stack_index &&
					    segs[j].first_index > key.first_index)) {
			segs[j + 1] = segs[j]
			j -= 1
		}
		segs[j + 1] = key
	}
}

/*
Uploads recorded vertices and indices to GPU buffers via a transfer buffer.

Finalizes segments first. Returns true when there is nothing to upload or
the copy succeeds; false on buffer or SDL transfer failure.
*/
batch_upload :: proc(cmd: ^sdl.GPUCommandBuffer) -> bool {
	if len(batch_current().vertices) == 0 || len(batch_current().indices) == 0 do return true
	if batch_current().vertex_buffer == nil || batch_current().index_buffer == nil do return false

	batch_finalize_segments()

	vertex_bytes := u32(len(batch_current().vertices) * size_of(UI_Vertex))
	index_bytes := u32(len(batch_current().indices) * size_of(u16))

	transfer_size := vertex_bytes + index_bytes
	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = transfer_size})
	if test_hook_batch_upload_fail_transfer && transfer != nil {
		sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)
		transfer = nil
	}
	if transfer == nil {
		fmt.eprintln("SDL_CreateGPUTransferBuffer failed:", sdl.GetError())
		return false
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if test_hook_batch_upload_fail_map {
		if mapped != nil {
			sdl.UnmapGPUTransferBuffer(state.gpu, transfer)
		}
		mapped = nil
	}
	if mapped == nil {
		fmt.eprintln("SDL_MapGPUTransferBuffer failed:", sdl.GetError())
		return false
	}

	dst_bytes := cast([^]u8)mapped
	mem.copy(dst_bytes, raw_data(batch_current().vertices), int(vertex_bytes))
	mem.copy(dst_bytes[vertex_bytes:], raw_data(batch_current().indices), int(index_bytes))
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = 0},
		{buffer = batch_current().vertex_buffer, offset = 0, size = vertex_bytes},
		true,
	)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = vertex_bytes},
		{buffer = batch_current().index_buffer, offset = 0, size = index_bytes},
		true,
	)
	sdl.EndGPUCopyPass(copy_pass)
	return true
}

/*
Converts a logical clip rect to SDL scissor coordinates in drawable pixels.

Clamps width and height to the drawable surface and returns zero size when
the clip is empty or fully off-screen.
*/
clip_to_scissor :: proc(clip: Rect, dpi: Dpi_Info) -> sdl.Rect {
	if clip.w <= 0 || clip.h <= 0 do return {0, 0, 0, 0}

	scale := dpi.scale
	if scale <= 0 do scale = 1

	x := i32(math.floor(clip.x * scale + 0.5))
	y := i32(math.floor(clip.y * scale + 0.5))
	w := i32(math.floor(clip.w * scale + 0.5))
	h := i32(math.floor(clip.h * scale + 0.5))

	if w <= 0 || h <= 0 do return {0, 0, 0, 0}

	max_w := dpi.drawable_w - x
	max_h := dpi.drawable_h - y
	if max_w < 0 do max_w = 0
	if max_h < 0 do max_h = 0
	if w > max_w do w = max_w
	if h > max_h do h = max_h

	return {x, y, w, h}
}

/*
Issues indexed draw calls for each batch segment with bound texture and scissor.

Binds the UI pipeline, projection UBO, vertex/index buffers, and draws each
segment. Skips segments with zero indices or missing GPU textures.
*/
batch_flush_draws :: proc() {
	if state.gpu_state.pipeline == nil do return
	if len(batch_current().segments) == 0 do return

	ubo := GPU_Proj_UBO {
		proj = state.gpu_state.proj_mat,
	}
	sdl.BindGPUGraphicsPipeline(batch_current().pass, state.gpu_state.pipeline)
	sdl.PushGPUVertexUniformData(batch_current().cmd, 0, &ubo, u32(size_of(ubo)))

	vertex_binding := sdl.GPUBufferBinding {
		buffer = batch_current().vertex_buffer,
		offset = 0,
	}
	index_binding := sdl.GPUBufferBinding {
		buffer = batch_current().index_buffer,
		offset = 0,
	}

	sdl.BindGPUVertexBuffers(batch_current().pass, 0, &vertex_binding, 1)
	sdl.BindGPUIndexBuffer(batch_current().pass, index_binding, ._16BIT)

	sampler := state.gpu_state.sampler
	for seg in batch_current().segments {
		if seg.index_count == 0 do continue

		tex := texture_get_gpu(seg.key.texture_id)
		if tex == nil do continue

		binding := sdl.GPUTextureSamplerBinding {
			texture = tex,
			sampler = sampler,
		}
		sdl.BindGPUFragmentSamplers(batch_current().pass, 0, &binding, 1)

		scissor := clip_to_scissor(seg.key.clip, batch_current().dpi)
		sdl.SetGPUScissor(batch_current().pass, scissor)

		sdl.DrawGPUIndexedPrimitives(
			batch_current().pass,
			seg.index_count,
			1,
			seg.first_index,
			0,
			0,
		)
	}
}
