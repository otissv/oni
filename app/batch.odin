package app

import "core:fmt"
import "core:mem"
import sdl "vendor:sdl3"

Draw_Mode :: enum {
	Solid,
	Textured,
	Line,
}

draw_mode_f32 :: proc(mode: Draw_Mode) -> f32 {
	return f32(mode)
}

BATCH_INITIAL_VERT_CAPACITY :: 64 * 1024

Batch_Key :: struct {
	texture_id: Asset_Id,
	clip:       Rect,
}

Batch_Segment :: struct {
	key:          Batch_Key,
	first_index:  u32,
	index_count:  u32,
}

Batch_State :: struct {
	vertices:        [dynamic]UI_Vertex,
	indices:         [dynamic]u16,
	segments:        [dynamic]Batch_Segment,
	clip_stack:      [dynamic]Rect,
	current_key:     Batch_Key,
	has_current_key: bool,

	vertex_buffer: ^sdl.GPUBuffer,
	index_buffer:  ^sdl.GPUBuffer,
	vertex_capacity: u32,
	index_capacity:  u32,

	cmd:  ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	dpi:  Dpi_Info,
}

batch_init :: proc() {
	g.gpu_state.batch.vertex_capacity = BATCH_INITIAL_VERT_CAPACITY
	g.gpu_state.batch.index_capacity = BATCH_INITIAL_VERT_CAPACITY * 6
	batch_create_gpu_buffers()
}

batch_create_gpu_buffers :: proc() -> bool {
	if g.gpu == nil do return false

	vertex_bytes := g.gpu_state.batch.vertex_capacity * u32(size_of(UI_Vertex))
	index_bytes := g.gpu_state.batch.index_capacity * u32(size_of(u16))

	if g.gpu_state.batch.vertex_buffer != nil {
		sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.vertex_buffer)
		g.gpu_state.batch.vertex_buffer = nil
	}
	if g.gpu_state.batch.index_buffer != nil {
		sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.index_buffer)
		g.gpu_state.batch.index_buffer = nil
	}

	g.gpu_state.batch.vertex_buffer = sdl.CreateGPUBuffer(
		g.gpu,
		{usage = {.VERTEX}, size = vertex_bytes},
	)
	g.gpu_state.batch.index_buffer = sdl.CreateGPUBuffer(
		g.gpu,
		{usage = {.INDEX}, size = index_bytes},
	)

	if g.gpu_state.batch.vertex_buffer == nil || g.gpu_state.batch.index_buffer == nil {
		fmt.eprintln("SDL_CreateGPUBuffer failed:", sdl.GetError())
		if g.gpu_state.batch.vertex_buffer != nil do sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.vertex_buffer)
		if g.gpu_state.batch.index_buffer != nil do sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.index_buffer)
		g.gpu_state.batch.vertex_buffer = nil
		g.gpu_state.batch.index_buffer = nil
		return false
	}

	return true
}

batch_destroy :: proc() {
	if g == nil do return

	if g.gpu != nil {
		if g.gpu_state.batch.vertex_buffer != nil {
			sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.vertex_buffer)
			g.gpu_state.batch.vertex_buffer = nil
		}
		if g.gpu_state.batch.index_buffer != nil {
			sdl.ReleaseGPUBuffer(g.gpu, g.gpu_state.batch.index_buffer)
			g.gpu_state.batch.index_buffer = nil
		}
	}

	delete(g.gpu_state.batch.vertices)
	delete(g.gpu_state.batch.indices)
	delete(g.gpu_state.batch.segments)
	delete(g.gpu_state.batch.clip_stack)
	g.gpu_state.batch.vertices = nil
	g.gpu_state.batch.indices = nil
	g.gpu_state.batch.segments = nil
	g.gpu_state.batch.clip_stack = nil

	g.gpu_state.batch.vertex_capacity = 0
	g.gpu_state.batch.index_capacity = 0
	g.gpu_state.batch.has_current_key = false
}

batch_reset :: proc() {
	clear(&g.gpu_state.batch.vertices)
	clear(&g.gpu_state.batch.indices)
	clear(&g.gpu_state.batch.segments)
	clear(&g.gpu_state.batch.clip_stack)
	g.gpu_state.batch.has_current_key = false
}

batch_ensure_capacity :: proc(extra_verts: int) -> bool {
	needed := len(g.gpu_state.batch.vertices) + extra_verts
	if u32(needed) <= g.gpu_state.batch.vertex_capacity do return true

	new_cap := g.gpu_state.batch.vertex_capacity
	for u32(needed) > new_cap {
		new_cap *= 2
	}
	g.gpu_state.batch.vertex_capacity = new_cap
	g.gpu_state.batch.index_capacity = new_cap * 6
	return batch_create_gpu_buffers()
}

batch_current_clip :: proc() -> Rect {
	if len(g.gpu_state.batch.clip_stack) == 0 {
		return {0, 0, f32(g.gpu_state.batch.dpi.logical_w), f32(g.gpu_state.batch.dpi.logical_h)}
	}
	return g.gpu_state.batch.clip_stack[len(g.gpu_state.batch.clip_stack) - 1]
}

batch_check_key :: proc(texture_id: Asset_Id) {
	clip := batch_current_clip()
	key := Batch_Key{texture_id = texture_id, clip = clip}

	if g.gpu_state.batch.has_current_key &&
	   g.gpu_state.batch.current_key.texture_id == key.texture_id &&
	   g.gpu_state.batch.current_key.clip == key.clip {
		return
	}

	if g.gpu_state.batch.has_current_key && len(g.gpu_state.batch.indices) > 0 {
		seg := g.gpu_state.batch.segments[len(g.gpu_state.batch.segments) - 1]
		seg.index_count = u32(len(g.gpu_state.batch.indices)) - seg.first_index
		g.gpu_state.batch.segments[len(g.gpu_state.batch.segments) - 1] = seg
	}

	append(
		&g.gpu_state.batch.segments,
		Batch_Segment{key = key, first_index = u32(len(g.gpu_state.batch.indices))},
	)
	g.gpu_state.batch.current_key = key
	g.gpu_state.batch.has_current_key = true
}

batch_push_indices :: proc(base: u16) {
	append(&g.gpu_state.batch.indices, base + 0, base + 1, base + 2, base + 0, base + 2, base + 3)
}

batch_push_vertex :: proc(
	pos: Vec2,
	uv: Vec2,
	color: [4]f32,
	rect_size: Vec2,
	radius: f32,
	mode: Draw_Mode,
) {
	append(
		&g.gpu_state.batch.vertices,
		UI_Vertex {
			pos = pos,
			uv = uv,
			color = color,
			rect_size = rect_size,
			params = {radius, draw_mode_f32(mode)},
		},
	)
}

batch_push_quad :: proc(
	corners: [4]Vec2,
	uvs: [4]Vec2,
	color: Color,
	rect_size: Vec2,
	radius: f32,
	mode: Draw_Mode,
) {
	if !batch_ensure_capacity(4) do return

	tint := color_to_f32(color)
	base := u16(len(g.gpu_state.batch.vertices))

	for i in 0 ..< 4 {
		batch_push_vertex(corners[i], uvs[i], tint, rect_size, radius, mode)
	}
	batch_push_indices(base)
}

batch_push_axis_quad :: proc(
	r: Rect,
	uv_rect: Rect,
	color: Color,
	rect_size: Vec2,
	radius: f32,
	mode: Draw_Mode,
) {
	x0, y0 := r.x, r.y
	x1, y1 := r.x + r.w, r.y + r.h
	u0, v0 := uv_rect.x, uv_rect.y
	u1, v1 := uv_rect.x + uv_rect.w, uv_rect.y + uv_rect.h

	corners := [4]Vec2{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}
	uvs: [4]Vec2
	switch mode {
	case .Solid, .Line:
		uvs = [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	case .Textured:
		uvs = [4]Vec2{{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
	}

	batch_push_quad(corners, uvs, color, rect_size, radius, mode)
}

batch_finalize_segments :: proc() {
	if g.gpu_state.batch.has_current_key && len(g.gpu_state.batch.segments) > 0 {
		seg := g.gpu_state.batch.segments[len(g.gpu_state.batch.segments) - 1]
		seg.index_count = u32(len(g.gpu_state.batch.indices)) - seg.first_index
		g.gpu_state.batch.segments[len(g.gpu_state.batch.segments) - 1] = seg
	}
}

batch_upload :: proc(cmd: ^sdl.GPUCommandBuffer) -> bool {
	if len(g.gpu_state.batch.vertices) == 0 || len(g.gpu_state.batch.indices) == 0 do return true
	if g.gpu_state.batch.vertex_buffer == nil || g.gpu_state.batch.index_buffer == nil do return false

	batch_finalize_segments()

	vertex_bytes := u32(len(g.gpu_state.batch.vertices) * size_of(UI_Vertex))
	index_bytes := u32(len(g.gpu_state.batch.indices) * size_of(u16))

	transfer_size := vertex_bytes + index_bytes
	transfer := sdl.CreateGPUTransferBuffer(g.gpu, {usage = .UPLOAD, size = transfer_size})
	if transfer == nil {
		fmt.eprintln("SDL_CreateGPUTransferBuffer failed:", sdl.GetError())
		return false
	}
	defer sdl.ReleaseGPUTransferBuffer(g.gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(g.gpu, transfer, false)
	if mapped == nil {
		fmt.eprintln("SDL_MapGPUTransferBuffer failed:", sdl.GetError())
		return false
	}

	dst_bytes := cast([^]u8)mapped
	mem.copy(dst_bytes, raw_data(g.gpu_state.batch.vertices), int(vertex_bytes))
	mem.copy(dst_bytes[vertex_bytes:], raw_data(g.gpu_state.batch.indices), int(index_bytes))
	sdl.UnmapGPUTransferBuffer(g.gpu, transfer)

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = 0},
		{buffer = g.gpu_state.batch.vertex_buffer, offset = 0, size = vertex_bytes},
		true,
	)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer, offset = vertex_bytes},
		{buffer = g.gpu_state.batch.index_buffer, offset = 0, size = index_bytes},
		true,
	)
	sdl.EndGPUCopyPass(copy_pass)
	return true
}

clip_to_scissor :: proc(clip: Rect, dpi: Dpi_Info) -> sdl.Rect {
	scale := dpi.scale
	if scale <= 0 do scale = 1

	x := max(i32(clip.x * scale), 0)
	y := max(i32(clip.y * scale), 0)
	w := max(i32(clip.w * scale), 0)
	h := max(i32(clip.h * scale), 0)

	max_w := dpi.drawable_w - x
	max_h := dpi.drawable_h - y
	if w > max_w do w = max_w
	if h > max_h do h = max_h

	return {x, y, w, h}
}

batch_flush_draws :: proc() {
	if g.gpu_state.pipeline == nil do return
	if len(g.gpu_state.batch.segments) == 0 do return

	ubo := GPU_Proj_UBO{proj = g.gpu_state.proj_mat}
	sdl.BindGPUGraphicsPipeline(g.gpu_state.batch.pass, g.gpu_state.pipeline)
	sdl.PushGPUVertexUniformData(g.gpu_state.batch.cmd, 0, &ubo, u32(size_of(ubo)))

	vertex_binding := sdl.GPUBufferBinding {
		buffer = g.gpu_state.batch.vertex_buffer,
		offset = 0,
	}
	index_binding := sdl.GPUBufferBinding {
		buffer = g.gpu_state.batch.index_buffer,
		offset = 0,
	}

	sdl.BindGPUVertexBuffers(g.gpu_state.batch.pass, 0, &vertex_binding, 1)
	sdl.BindGPUIndexBuffer(g.gpu_state.batch.pass, index_binding, ._16BIT)

	for seg in g.gpu_state.batch.segments {
		if seg.index_count == 0 do continue

		tex := texture_get_gpu(seg.key.texture_id)
		if tex == nil do continue

		binding := sdl.GPUTextureSamplerBinding {
			texture = tex,
			sampler = g.gpu_state.sampler,
		}
		sdl.BindGPUFragmentSamplers(g.gpu_state.batch.pass, 0, &binding, 1)

		scissor := clip_to_scissor(seg.key.clip, g.gpu_state.batch.dpi)
		sdl.SetGPUScissor(g.gpu_state.batch.pass, scissor)

		sdl.DrawGPUIndexedPrimitives(g.gpu_state.batch.pass, seg.index_count, 1, seg.first_index, 0, 0)
	}
}
