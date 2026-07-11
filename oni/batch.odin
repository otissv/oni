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
Identifies a draw batch by texture asset and active clip rectangle.
*/
Batch_Key :: struct {
	texture_id: Asset_Id,
	clip:       Rect,
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
	vertices:        [dynamic]UI_Vertex,
	indices:         [dynamic]u16,
	segments:        [dynamic]Batch_Segment,
	clip_stack:      [dynamic]Rect,
	space_stack:     [dynamic]Draw_Space,
	current_key:     Batch_Key,
	has_current_key: bool,
	vertex_buffer:   ^sdl.GPUBuffer,
	index_buffer:    ^sdl.GPUBuffer,
	vertex_capacity: u32,
	index_capacity:  u32,
	cmd:             ^sdl.GPUCommandBuffer,
	pass:            ^sdl.GPURenderPass,
	dpi:             Dpi_Info,
}

/*
Initializes batch CPU buffers and allocates initial GPU vertex/index buffers.

Uses BATCH_INITIAL_VERT_CAPACITY as the starting vertex capacity.
*/
batch_init :: proc() {
	state.gpu_state.batch.vertex_capacity = BATCH_INITIAL_VERT_CAPACITY
	state.gpu_state.batch.index_capacity = BATCH_INITIAL_VERT_CAPACITY * 6
	batch_create_gpu_buffers()
}

/*
Creates or recreates GPU vertex and index buffers at the current capacities.

Releases existing buffers before allocation. Returns false on SDL failure.
*/
batch_create_gpu_buffers :: proc() -> bool {
	if state.gpu == nil do return false

	vertex_bytes := state.gpu_state.batch.vertex_capacity * u32(size_of(UI_Vertex))
	index_bytes := state.gpu_state.batch.index_capacity * u32(size_of(u16))

	if state.gpu_state.batch.vertex_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.vertex_buffer)
		state.gpu_state.batch.vertex_buffer = nil
	}
	if state.gpu_state.batch.index_buffer != nil {
		sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.index_buffer)
		state.gpu_state.batch.index_buffer = nil
	}

	state.gpu_state.batch.vertex_buffer = sdl.CreateGPUBuffer(
		state.gpu,
		{usage = {.VERTEX}, size = vertex_bytes},
	)
	state.gpu_state.batch.index_buffer = sdl.CreateGPUBuffer(
		state.gpu,
		{usage = {.INDEX}, size = index_bytes},
	)

	if state.gpu_state.batch.vertex_buffer == nil || state.gpu_state.batch.index_buffer == nil {
		fmt.eprintln("SDL_CreateGPUBuffer failed:", sdl.GetError())
		if state.gpu_state.batch.vertex_buffer != nil do sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.vertex_buffer)
		if state.gpu_state.batch.index_buffer != nil do sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.index_buffer)
		state.gpu_state.batch.vertex_buffer = nil
		state.gpu_state.batch.index_buffer = nil
		return false
	}

	return true
}

/*
Releases batch GPU buffers and frees all CPU-side dynamic arrays.

Safe to call when state is nil or the GPU device is already destroyed.
*/
batch_destroy :: proc() {
	if state == nil do return

	if state.gpu != nil {
		if state.gpu_state.batch.vertex_buffer != nil {
			sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.vertex_buffer)
			state.gpu_state.batch.vertex_buffer = nil
		}
		if state.gpu_state.batch.index_buffer != nil {
			sdl.ReleaseGPUBuffer(state.gpu, state.gpu_state.batch.index_buffer)
			state.gpu_state.batch.index_buffer = nil
		}
	}

	delete(state.gpu_state.batch.vertices)
	delete(state.gpu_state.batch.indices)
	delete(state.gpu_state.batch.segments)
	delete(state.gpu_state.batch.clip_stack)
	delete(state.gpu_state.batch.space_stack)
	state.gpu_state.batch.vertices = nil
	state.gpu_state.batch.indices = nil
	state.gpu_state.batch.segments = nil
	state.gpu_state.batch.clip_stack = nil
	state.gpu_state.batch.space_stack = nil

	state.gpu_state.batch.vertex_capacity = 0
	state.gpu_state.batch.index_capacity = 0
	state.gpu_state.batch.has_current_key = false
}

/*
Clears recorded vertices, indices, segments, and stack state for a new frame.

Does not release GPU buffers or change capacity.
*/
batch_reset :: proc() {
	clear(&state.gpu_state.batch.vertices)
	clear(&state.gpu_state.batch.indices)
	clear(&state.gpu_state.batch.segments)
	clear(&state.gpu_state.batch.clip_stack)
	clear(&state.gpu_state.batch.space_stack)
	state.gpu_state.batch.has_current_key = false
}

/*
Ensures the batch can hold extra_verts additional vertices.

Doubles GPU buffer capacity until sufficient, recreating buffers as needed.
Returns false if buffer recreation fails.
*/
batch_ensure_capacity :: proc(extra_verts: int) -> bool {
	needed := len(state.gpu_state.batch.vertices) + extra_verts
	if u32(needed) <= state.gpu_state.batch.vertex_capacity do return true

	new_cap := state.gpu_state.batch.vertex_capacity
	for u32(needed) > new_cap {
		new_cap *= 2
	}
	state.gpu_state.batch.vertex_capacity = new_cap
	state.gpu_state.batch.index_capacity = new_cap * 6
	return batch_create_gpu_buffers()
}

/*
Returns the effective clip rect in screen space for the current draw batch.

Uses the top of the clip stack intersected with the logical viewport, or the
full viewport when no clip has been pushed.
*/
batch_current_clip :: proc() -> Rect {
	clip: Rect
	if len(state.gpu_state.batch.clip_stack) == 0 {
		clip = {
			0,
			0,
			f32(state.gpu_state.batch.dpi.logical_w),
			f32(state.gpu_state.batch.dpi.logical_h),
		}
	} else {
		clip = state.gpu_state.batch.clip_stack[len(state.gpu_state.batch.clip_stack) - 1]
	}
	clip = view_transform_rect(clip)
	viewport := Rect {
		0,
		0,
		f32(state.gpu_state.batch.dpi.logical_w),
		f32(state.gpu_state.batch.dpi.logical_h),
	}
	return rect_intersect(clip, viewport)
}

/*
Starts a new batch segment when the texture or clip key changes.

Finalizes the previous segment's index count before appending a new one.
*/
batch_check_key :: proc(texture_id: Asset_Id) {
	clip := batch_current_clip()
	key := Batch_Key {
		texture_id = texture_id,
		clip       = clip,
	}

	if state.gpu_state.batch.has_current_key &&
	   state.gpu_state.batch.current_key.texture_id == key.texture_id &&
	   state.gpu_state.batch.current_key.clip == key.clip {
		return
	}

	if state.gpu_state.batch.has_current_key && len(state.gpu_state.batch.indices) > 0 {
		seg := state.gpu_state.batch.segments[len(state.gpu_state.batch.segments) - 1]
		seg.index_count = u32(len(state.gpu_state.batch.indices)) - seg.first_index
		state.gpu_state.batch.segments[len(state.gpu_state.batch.segments) - 1] = seg
	}

	append(
		&state.gpu_state.batch.segments,
		Batch_Segment{key = key, first_index = u32(len(state.gpu_state.batch.indices))},
	)
	state.gpu_state.batch.current_key = key
	state.gpu_state.batch.has_current_key = true
}

/*
Appends two triangles (six indices) for a quad starting at vertex base.
*/
batch_push_indices :: proc(base: u16) {
	append(
		&state.gpu_state.batch.indices,
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
	mode: Draw_Mode,
	tex_clip: bool = false,
) {
	tex_clip_flag: f32 = 0
	if tex_clip do tex_clip_flag = 1
	append(
		&state.gpu_state.batch.vertices,
		UI_Vertex {
			pos = pos,
			uv = uv,
			local_uv = local_uv,
			color = color,
			border_color = border_color,
			rect_size = rect_size,
			radii = radii,
			params = {tex_clip_flag, draw_mode_f32(mode)},
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

	tint := rgba_to_f32(color)
	border_tint := rgba_to_f32(border_color)
	base := u16(len(state.gpu_state.batch.vertices))

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
			mode,
			tex_clip,
		)
	}
	batch_push_indices(base)
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
Finalizes the index count of the last open batch segment.

Call before upload or flush when recording is complete.
*/
batch_finalize_segments :: proc() {
	if state.gpu_state.batch.has_current_key && len(state.gpu_state.batch.segments) > 0 {
		seg := state.gpu_state.batch.segments[len(state.gpu_state.batch.segments) - 1]
		seg.index_count = u32(len(state.gpu_state.batch.indices)) - seg.first_index
		state.gpu_state.batch.segments[len(state.gpu_state.batch.segments) - 1] = seg
	}
}

/*
Uploads recorded vertices and indices to GPU buffers via a transfer buffer.

Finalizes segments first. Returns true when there is nothing to upload or
the copy succeeds; false on buffer or SDL transfer failure.
*/
batch_upload :: proc(cmd: ^sdl.GPUCommandBuffer) -> bool {
	if len(state.gpu_state.batch.vertices) == 0 || len(state.gpu_state.batch.indices) == 0 do return true
	if state.gpu_state.batch.vertex_buffer == nil || state.gpu_state.batch.index_buffer == nil do return false

	batch_finalize_segments()

	vertex_bytes := u32(len(state.gpu_state.batch.vertices) * size_of(UI_Vertex))
	index_bytes := u32(len(state.gpu_state.batch.indices) * size_of(u16))

	transfer_size := vertex_bytes + index_bytes
	transfer := sdl.CreateGPUTransferBuffer(state.gpu, {usage = .UPLOAD, size = transfer_size})
	if transfer == nil {
		fmt.eprintln("SDL_CreateGPUTransferBuffer failed:", sdl.GetError())
		return false
	}
	defer sdl.ReleaseGPUTransferBuffer(state.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(state.gpu, transfer, false)
	if mapped == nil {
		fmt.eprintln("SDL_MapGPUTransferBuffer failed:", sdl.GetError())
		return false
	}

	dst_bytes := cast([^]u8)mapped
	mem.copy(dst_bytes, raw_data(state.gpu_state.batch.vertices), int(vertex_bytes))
	mem.copy(dst_bytes[vertex_bytes:], raw_data(state.gpu_state.batch.indices), int(index_bytes))
	sdl.UnmapGPUTransferBuffer(state.gpu, transfer)

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = 0},
		{buffer = state.gpu_state.batch.vertex_buffer, offset = 0, size = vertex_bytes},
		true,
	)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = vertex_bytes},
		{buffer = state.gpu_state.batch.index_buffer, offset = 0, size = index_bytes},
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
	if len(state.gpu_state.batch.segments) == 0 do return

	ubo := GPU_Proj_UBO {
		proj = state.gpu_state.proj_mat,
	}
	sdl.BindGPUGraphicsPipeline(state.gpu_state.batch.pass, state.gpu_state.pipeline)
	sdl.PushGPUVertexUniformData(state.gpu_state.batch.cmd, 0, &ubo, u32(size_of(ubo)))

	vertex_binding := sdl.GPUBufferBinding {
		buffer = state.gpu_state.batch.vertex_buffer,
		offset = 0,
	}
	index_binding := sdl.GPUBufferBinding {
		buffer = state.gpu_state.batch.index_buffer,
		offset = 0,
	}

	sdl.BindGPUVertexBuffers(state.gpu_state.batch.pass, 0, &vertex_binding, 1)
	sdl.BindGPUIndexBuffer(state.gpu_state.batch.pass, index_binding, ._16BIT)

	for seg in state.gpu_state.batch.segments {
		if seg.index_count == 0 do continue

		tex := texture_get_gpu(seg.key.texture_id)
		if tex == nil do continue

		binding := sdl.GPUTextureSamplerBinding {
			texture = tex,
			sampler = state.gpu_state.sampler,
		}
		sdl.BindGPUFragmentSamplers(state.gpu_state.batch.pass, 0, &binding, 1)

		scissor := clip_to_scissor(seg.key.clip, state.gpu_state.batch.dpi)
		sdl.SetGPUScissor(state.gpu_state.batch.pass, scissor)

		sdl.DrawGPUIndexedPrimitives(
			state.gpu_state.batch.pass,
			seg.index_count,
			1,
			seg.first_index,
			0,
			0,
		)
	}
}
