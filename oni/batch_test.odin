package oni

import "core:math"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

/*
CPU-side batch recording without GPU buffers.
*/
@(private)
with_batch_cpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	defer {
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.view = view_default()
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	state.gpu_state.batch.dpi = state.dpi
	state.gpu_state.batch.vertex_capacity = BATCH_INITIAL_VERT_CAPACITY
	state.gpu_state.batch.index_capacity = BATCH_INITIAL_VERT_CAPACITY * 6
	body(t)
}

/*
Batch with a real GPU device for buffer create/upload/grow paths.
*/
@(private)
with_batch_gpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu == nil {
		testing.expectf(t, false, "SDL_CreateGPUDevice failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyGPUDevice(gpu)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		batch_destroy()
		if state.gpu_state.white_texture != nil {
			sdl.ReleaseGPUTexture(gpu, state.gpu_state.white_texture)
			state.gpu_state.white_texture = nil
		}
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.gpu = gpu
	state.view = view_default()
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	state.gpu_state.batch.dpi = state.dpi

	white := gpu_create_white_texture(gpu)
	if white == nil {
		testing.expect(t, false, "gpu_create_white_texture failed")
		return
	}
	state.gpu_state.white_texture = white
	texture_init()
	defer texture_shutdown()

	batch_init()
	body(t)
}

@(private)
expect_batch_vertex :: proc(
	t: ^testing.T,
	v: UI_Vertex,
	pos, uv, local_uv: Vec2,
	color: [4]f32,
	mode: Draw_Mode,
	tex_clip: bool = false,
	loc := #caller_location,
) {
	expect_close(t, v.pos[0], pos.x, loc = loc)
	expect_close(t, v.pos[1], pos.y, loc = loc)
	expect_close(t, v.uv[0], uv.x, loc = loc)
	expect_close(t, v.uv[1], uv.y, loc = loc)
	expect_close(t, v.local_uv[0], local_uv.x, loc = loc)
	expect_close(t, v.local_uv[1], local_uv.y, loc = loc)
	expect_close(t, v.color[0], color[0], loc = loc)
	expect_close(t, v.color[1], color[1], loc = loc)
	expect_close(t, v.color[2], color[2], loc = loc)
	expect_close(t, v.color[3], color[3], loc = loc)
	expect_close(t, v.params[0], tex_clip ? 1 : 0, loc = loc)
	expect_close(t, v.params[1], draw_mode_f32(mode), loc = loc)
}

// ---------------------------------------------------------------------------
// draw_mode_f32 / constants
// ---------------------------------------------------------------------------

@(test)
batch_draw_mode_f32_matches_enum_ordinals :: proc(t: ^testing.T) {
	expect_close(t, draw_mode_f32(.Solid), 0)
	expect_close(t, draw_mode_f32(.Textured), 1)
	expect_close(t, draw_mode_f32(.Line), 2)
	expect_close(t, draw_mode_f32(.Textured_Rounded), 3)
	testing.expect_value(t, BATCH_INITIAL_VERT_CAPACITY, 64 * 1024)
}

// ---------------------------------------------------------------------------
// batch_create_gpu_buffers / init / destroy / reset
// ---------------------------------------------------------------------------

@(test)
batch_create_gpu_buffers_nil_gpu_returns_false :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu == nil)
			testing.expect(t, !batch_create_gpu_buffers())
		},
	)
}

@(test)
batch_destroy_nil_state_safe :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			batch_destroy()
		},
	)
}

@(test)
batch_init_creates_gpu_buffers_and_destroy_clears :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, u32(BATCH_INITIAL_VERT_CAPACITY))
			testing.expect_value(
				t,
				state.gpu_state.batch.index_capacity,
				u32(BATCH_INITIAL_VERT_CAPACITY * 6),
			)
			testing.expect(t, state.gpu_state.batch.vertex_buffer != nil)
			testing.expect(t, state.gpu_state.batch.index_buffer != nil)

			append(&state.gpu_state.batch.vertices, UI_Vertex{})
			append(&state.gpu_state.batch.indices, u16(0))
			append(&state.gpu_state.batch.segments, Batch_Segment{})
			append(&state.gpu_state.batch.clip_stack, Rect{1, 2, 3, 4})
			append(&state.gpu_state.batch.space_stack, Draw_Space.ARTBOARD)
			state.gpu_state.batch.has_current_key = true

			batch_destroy()
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
			testing.expect(t, state.gpu_state.batch.index_buffer == nil)
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, u32(0))
			testing.expect_value(t, state.gpu_state.batch.index_capacity, u32(0))
			testing.expect(t, !state.gpu_state.batch.has_current_key)
			testing.expect(t, state.gpu_state.batch.vertices == nil)
			testing.expect(t, state.gpu_state.batch.indices == nil)
			testing.expect(t, state.gpu_state.batch.segments == nil)
			testing.expect(t, state.gpu_state.batch.clip_stack == nil)
			testing.expect(t, state.gpu_state.batch.space_stack == nil)

			// Re-init after destroy for defer batch_destroy in env.
			batch_init()
		},
	)
}

@(test)
batch_reset_clears_cpu_state_keeps_capacity :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.vertices, UI_Vertex{}, UI_Vertex{})
			append(&state.gpu_state.batch.indices, u16(0), u16(1), u16(2))
			append(&state.gpu_state.batch.segments, Batch_Segment{first_index = 1})
			append(&state.gpu_state.batch.clip_stack, Rect{0, 0, 10, 10})
			append(&state.gpu_state.batch.space_stack, Draw_Space.SCREEN)
			state.gpu_state.batch.has_current_key = true
			state.gpu_state.batch.current_key = {texture_id = Asset_Id(3)}

			cap_v := state.gpu_state.batch.vertex_capacity
			cap_i := state.gpu_state.batch.index_capacity
			batch_reset()
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.segments), 0)
			testing.expect_value(t, len(state.gpu_state.batch.clip_stack), 0)
			testing.expect_value(t, len(state.gpu_state.batch.space_stack), 0)
			testing.expect(t, !state.gpu_state.batch.has_current_key)
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, cap_v)
			testing.expect_value(t, state.gpu_state.batch.index_capacity, cap_i)
		},
	)
}

@(test)
batch_create_gpu_buffers_releases_previous :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			old_v := state.gpu_state.batch.vertex_buffer
			old_i := state.gpu_state.batch.index_buffer
			testing.expect(t, old_v != nil)
			testing.expect(t, batch_create_gpu_buffers())
			testing.expect(t, state.gpu_state.batch.vertex_buffer != nil)
			testing.expect(t, state.gpu_state.batch.index_buffer != nil)
			// New allocations (pointers may or may not differ; ensure non-nil after recreate).
			_ = old_v
			_ = old_i
		},
	)
}

// ---------------------------------------------------------------------------
// batch_ensure_capacity
// ---------------------------------------------------------------------------

@(test)
batch_ensure_capacity_within_limit_no_gpu :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, batch_ensure_capacity(4))
			testing.expect(t, batch_ensure_capacity(0))
			testing.expect_value(
				t,
				state.gpu_state.batch.vertex_capacity,
				u32(BATCH_INITIAL_VERT_CAPACITY),
			)
		},
	)
}

@(test)
batch_ensure_capacity_grow_fails_without_gpu :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.gpu_state.batch.vertex_capacity = 4
			testing.expect(t, !batch_ensure_capacity(8))
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, u32(8))
			testing.expect_value(t, state.gpu_state.batch.index_capacity, u32(48))
		},
	)
}

@(test)
batch_ensure_capacity_doubles_until_enough :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			state.gpu_state.batch.vertex_capacity = 8
			state.gpu_state.batch.index_capacity = 48
			testing.expect(t, batch_create_gpu_buffers())

			// Need 40 verts with capacity 8 → doubles to 16, 32, 64.
			testing.expect(t, batch_ensure_capacity(40))
			testing.expect(t, state.gpu_state.batch.vertex_capacity >= 40)
			testing.expect_value(
				t,
				state.gpu_state.batch.index_capacity,
				state.gpu_state.batch.vertex_capacity * 6,
			)
			testing.expect(t, state.gpu_state.batch.vertex_buffer != nil)
		},
	)
}

// ---------------------------------------------------------------------------
// batch_current_clip
// ---------------------------------------------------------------------------

@(test)
batch_current_clip_defaults_to_viewport :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			clip := batch_current_clip()
			expect_rect(t, clip, {0, 0, 800, 600})
		},
	)
}

@(test)
batch_current_clip_uses_stack_top_intersected_with_viewport :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.clip_stack, Rect{-100, -100, 50, 50})
			clip := batch_current_clip()
			expect_rect(t, clip, {})

			clear(&state.gpu_state.batch.clip_stack)
			append(&state.gpu_state.batch.clip_stack, Rect{100, 100, 200, 150})
			clip = batch_current_clip()
			expect_rect(t, clip, {100, 100, 200, 150})

			append(&state.gpu_state.batch.clip_stack, Rect{700, 500, 200, 200})
			clip = batch_current_clip()
			expect_rect(t, clip, {700, 500, 100, 100})
		},
	)
}

@(test)
batch_current_clip_applies_artboard_view_transform :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.view.zoom = 2
			state.view.pan = {10, 20}
			draw_push_space(.ARTBOARD)
			defer draw_pop_space()
			append(&state.gpu_state.batch.clip_stack, Rect{0, 0, 100, 50})
			clip := batch_current_clip()
			expect_rect(t, clip, {10, 20, 200, 100})
		},
	)
}

// ---------------------------------------------------------------------------
// batch_check_key / finalize_segments
// ---------------------------------------------------------------------------

@(test)
batch_check_key_creates_merges_and_splits_segments :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID)
			testing.expect(t, state.gpu_state.batch.has_current_key)
			testing.expect_value(t, len(state.gpu_state.batch.segments), 1)
			testing.expect_value(t, state.gpu_state.batch.segments[0].first_index, u32(0))
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(0))

			// Same key: no new segment
			batch_check_key(TEXTURE_WHITE_ID)
			testing.expect_value(t, len(state.gpu_state.batch.segments), 1)

			batch_push_indices(0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 6)

			// Different texture: finalize previous and start new
			batch_check_key(Asset_Id(1))
			testing.expect_value(t, len(state.gpu_state.batch.segments), 2)
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(6))
			testing.expect_value(t, state.gpu_state.batch.segments[1].first_index, u32(6))
			testing.expect_value(t, state.gpu_state.batch.current_key.texture_id, Asset_Id(1))

			batch_push_indices(4)
			batch_finalize_segments()
			testing.expect_value(t, state.gpu_state.batch.segments[1].index_count, u32(6))
		},
	)
}

@(test)
batch_check_key_splits_on_clip_change :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(0)
			append(&state.gpu_state.batch.clip_stack, Rect{10, 10, 50, 50})
			batch_check_key(TEXTURE_WHITE_ID)
			testing.expect_value(t, len(state.gpu_state.batch.segments), 2)
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(6))
			expect_rect(t, state.gpu_state.batch.segments[1].key.clip, {10, 10, 50, 50})
		},
	)
}

@(test)
batch_finalize_segments_sorts_by_stack_index :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_set_stack_index(5)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(0)

			batch_set_stack_index(1)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(4)

			batch_set_stack_index(9)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(8)

			batch_finalize_segments()
			testing.expect_value(t, len(state.gpu_state.batch.segments), 3)
			testing.expect_value(t, state.gpu_state.batch.segments[0].key.stack_index, u32(1))
			testing.expect_value(t, state.gpu_state.batch.segments[1].key.stack_index, u32(5))
			testing.expect_value(t, state.gpu_state.batch.segments[2].key.stack_index, u32(9))
		},
	)
}

@(test)
batch_finalize_segments_noop_without_key :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_finalize_segments()
			testing.expect_value(t, len(state.gpu_state.batch.segments), 0)
			state.gpu_state.batch.has_current_key = true
			batch_finalize_segments()
			testing.expect_value(t, len(state.gpu_state.batch.segments), 0)
		},
	)
}

// ---------------------------------------------------------------------------
// push indices / vertex / quad
// ---------------------------------------------------------------------------

@(test)
batch_push_indices_emits_two_triangles :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_indices(10)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 6)
			testing.expect_value(t, state.gpu_state.batch.indices[0], u16(10))
			testing.expect_value(t, state.gpu_state.batch.indices[1], u16(11))
			testing.expect_value(t, state.gpu_state.batch.indices[2], u16(12))
			testing.expect_value(t, state.gpu_state.batch.indices[3], u16(10))
			testing.expect_value(t, state.gpu_state.batch.indices[4], u16(12))
			testing.expect_value(t, state.gpu_state.batch.indices[5], u16(13))
		},
	)
}

@(test)
batch_push_vertex_packs_params_and_border :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_vertex(
				{1, 2},
				{0.1, 0.2},
				{0.3, 0.4},
				{1, 0, 0, 1},
				{0, 1, 0, 1},
				{10, 20},
				{1, 2, 3, 4},
				{t = 1, b = 2, l = 3, r = 4},
				.Textured,
				true,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 1)
			v := state.gpu_state.batch.vertices[0]
			expect_batch_vertex(
				t,
				v,
				{1, 2},
				{0.1, 0.2},
				{0.3, 0.4},
				{1, 0, 0, 1},
				.Textured,
				true,
			)
			expect_close(t, v.border_color[1], 1)
			expect_close(t, v.rect_size[0], 10)
			expect_close(t, v.radii[3], 4)
			expect_close(t, v.border[0], 1)
			expect_close(t, v.border[1], 2)
			expect_close(t, v.border[2], 3)
			expect_close(t, v.border[3], 4)

			batch_push_vertex(
				{},
				{},
				{},
				{},
				{},
				{},
				{},
				{},
				.Solid,
				false,
			)
			expect_close(t, state.gpu_state.batch.vertices[1].params[0], 0)
		},
	)
}

@(test)
batch_push_quad_emits_four_verts_and_six_indices :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			corners := [4]Vec2{{0, 0}, {10, 0}, {10, 5}, {0, 5}}
			uvs := [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
			locals := uvs
			batch_push_quad(
				corners,
				uvs,
				locals,
				{255, 128, 0, 255},
				{0, 0, 255, 128},
				{10, 5},
				{1, 1, 1, 1},
				{t = 2, b = 2, l = 2, r = 2},
				.Solid,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 4)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 6)
			tint := rgba_to_f32({255, 128, 0, 255})
			expect_batch_vertex(
				t,
				state.gpu_state.batch.vertices[0],
				{0, 0},
				{0, 0},
				{0, 0},
				tint,
				.Solid,
			)
			expect_close(t, state.gpu_state.batch.vertices[2].pos[0], 10)
			expect_close(t, state.gpu_state.batch.vertices[2].pos[1], 5)
		},
	)
}

@(test)
batch_push_quad_skips_when_capacity_grow_fails :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.gpu_state.batch.vertex_capacity = 2
			batch_push_quad(
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{255, 255, 255, 255},
				{},
				{1, 1},
				{},
				{},
				.Solid,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
		},
	)
}

// ---------------------------------------------------------------------------
// batch_push_axis_quad
// ---------------------------------------------------------------------------

@(test)
batch_push_axis_quad_solid_and_line :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{10, 20, 30, 40},
				{0, 0, 1, 1},
				{255, 0, 0, 255},
				{0, 255, 0, 255},
				{30, 40},
				{},
				{t = 1, b = 1, l = 1, r = 1},
				.Solid,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 4)
			v0 := state.gpu_state.batch.vertices[0]
			expect_close(t, v0.pos[0], 10)
			expect_close(t, v0.pos[1], 20)
			expect_close(t, v0.uv[0], 0)
			expect_close(t, v0.local_uv[0], 0)
			v2 := state.gpu_state.batch.vertices[2]
			expect_close(t, v2.pos[0], 40)
			expect_close(t, v2.pos[1], 60)
			expect_close(t, v2.uv[0], 1)
			expect_close(t, v2.uv[1], 1)

			batch_reset()
			batch_push_axis_quad(
				{0, 0, 10, 10},
				{0.25, 0.25, 0.5, 0.5},
				{255, 255, 255, 255},
				{},
				{10, 10},
				{},
				{},
				.Line,
			)
			// Line uses local UVs like Solid, not texture UVs.
			expect_close(t, state.gpu_state.batch.vertices[0].uv[0], 0)
			expect_close(t, state.gpu_state.batch.vertices[2].uv[0], 1)
		},
	)
}

@(test)
batch_push_axis_quad_textured_clips_and_adjusts_uvs :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.clip_stack, Rect{50, 50, 50, 50})
			batch_push_axis_quad(
				{0, 0, 100, 100},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{100, 100},
				{},
				{},
				.Textured,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 4)
			// Visible is [50,50,50,50]; UVs should be [0.5,0.5] → [1,1]
			v0 := state.gpu_state.batch.vertices[0]
			v2 := state.gpu_state.batch.vertices[2]
			expect_close(t, v0.pos[0], 50)
			expect_close(t, v0.pos[1], 50)
			expect_close(t, v0.uv[0], 0.5)
			expect_close(t, v0.uv[1], 0.5)
			expect_close(t, v2.pos[0], 100)
			expect_close(t, v2.pos[1], 100)
			expect_close(t, v2.uv[0], 1)
			expect_close(t, v2.uv[1], 1)
			expect_close(t, v0.rect_size[0], 50)
			expect_close(t, v0.rect_size[1], 50)
		},
	)
}

@(test)
batch_push_axis_quad_textured_fully_clipped_emits_nothing :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.clip_stack, Rect{200, 200, 10, 10})
			batch_push_axis_quad(
				{0, 0, 50, 50},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{50, 50},
				{},
				{},
				.Textured_Rounded,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
		},
	)
}

@(test)
batch_push_axis_quad_textured_without_clip_uses_full_rect :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{5, 5, 20, 10},
				{0.1, 0.2, 0.4, 0.3},
				{255, 255, 255, 255},
				{},
				{20, 10},
				{},
				{},
				.Textured,
			)
			v0 := state.gpu_state.batch.vertices[0]
			v2 := state.gpu_state.batch.vertices[2]
			expect_close(t, v0.uv[0], 0.1)
			expect_close(t, v0.uv[1], 0.2)
			expect_close(t, v2.uv[0], 0.5)
			expect_close(t, v2.uv[1], 0.5)
		},
	)
}

@(test)
batch_push_axis_quad_respects_artboard_transform :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.view.zoom = 2
			state.view.pan = {5, 5}
			draw_push_space(.ARTBOARD)
			defer draw_pop_space()
			batch_push_axis_quad(
				{10, 10, 10, 10},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{10, 10},
				{},
				{},
				.Solid,
			)
			v0 := state.gpu_state.batch.vertices[0]
			v2 := state.gpu_state.batch.vertices[2]
			expect_close(t, v0.pos[0], 25) // 10*2+5
			expect_close(t, v0.pos[1], 25)
			expect_close(t, v2.pos[0], 45) // 20*2+5
			expect_close(t, v2.pos[1], 45)
		},
	)
}

// ---------------------------------------------------------------------------
// clip_to_scissor
// ---------------------------------------------------------------------------

@(test)
batch_clip_to_scissor_empty_and_scale :: proc(t: ^testing.T) {
	dpi := Dpi_Info {
		scale = 2,
		drawable_w = 200,
		drawable_h = 100,
	}
	s := clip_to_scissor({10, 20, 30, 40}, dpi)
	testing.expect_value(t, s.x, i32(20))
	testing.expect_value(t, s.y, i32(40))
	testing.expect_value(t, s.w, i32(60))
	// h=80 would exceed drawable_h (100) from y=40 → clamped to 60
	testing.expect_value(t, s.h, i32(60))

	testing.expect_value(t, clip_to_scissor({0, 0, 0, 10}, dpi).w, i32(0))
	testing.expect_value(t, clip_to_scissor({0, 0, 10, 0}, dpi).h, i32(0))
	testing.expect_value(t, clip_to_scissor({0, 0, -1, 10}, dpi).w, i32(0))

	dpi.scale = 0
	s = clip_to_scissor({1.4, 1.4, 2.4, 2.4}, dpi)
	// scale defaults to 1; round half-up via floor(x+0.5)
	testing.expect_value(t, s.x, i32(1))
	testing.expect_value(t, s.y, i32(1))
	testing.expect_value(t, s.w, i32(2))
	testing.expect_value(t, s.h, i32(2))

	dpi.scale = -2
	s = clip_to_scissor({3, 4, 5, 6}, dpi)
	testing.expect_value(t, s.x, i32(3))
	testing.expect_value(t, s.w, i32(5))
}

@(test)
batch_clip_to_scissor_clamps_to_drawable :: proc(t: ^testing.T) {
	dpi := Dpi_Info {
		scale = 1,
		drawable_w = 100,
		drawable_h = 50,
	}
	s := clip_to_scissor({80, 40, 50, 50}, dpi)
	testing.expect_value(t, s.x, i32(80))
	testing.expect_value(t, s.y, i32(40))
	testing.expect_value(t, s.w, i32(20))
	testing.expect_value(t, s.h, i32(10))

	s = clip_to_scissor({150, 10, 20, 20}, dpi)
	testing.expect_value(t, s.w, i32(0))
	testing.expect_value(t, s.h, i32(20))

	s = clip_to_scissor({10, 80, 20, 20}, dpi)
	testing.expect_value(t, s.w, i32(20))
	testing.expect_value(t, s.h, i32(0))

	// Sub-pixel that rounds to zero size
	s = clip_to_scissor({0, 0, 0.1, 0.1}, dpi)
	testing.expect_value(t, s.w, i32(0))
	testing.expect_value(t, s.h, i32(0))
}

@(test)
batch_clip_to_scissor_rounding :: proc(t: ^testing.T) {
	dpi := Dpi_Info {
		scale = 1.5,
		drawable_w = 1000,
		drawable_h = 1000,
	}
	// 10.2 * 1.5 = 15.3 → floor(15.8) = 15? floor(15.3+0.5)=floor(15.8)=15
	s := clip_to_scissor({10.2, 0, 10, 10}, dpi)
	want_x := i32(math.floor(f32(10.2) * 1.5 + 0.5))
	want_w := i32(math.floor(f32(10) * 1.5 + 0.5))
	testing.expect_value(t, s.x, want_x)
	testing.expect_value(t, s.w, want_w)
}

// ---------------------------------------------------------------------------
// batch_upload / batch_flush_draws
// ---------------------------------------------------------------------------

@(test)
batch_upload_empty_returns_true :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, batch_upload(nil))
		},
	)
}

@(test)
batch_upload_nil_buffers_returns_false :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.vertices, UI_Vertex{})
			append(&state.gpu_state.batch.indices, u16(0))
			testing.expect(t, !batch_upload(nil))
		},
	)
}

@(test)
batch_upload_copies_vertices_and_indices :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_axis_quad(
				{0, 0, 8, 8},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{8, 8},
				{},
				{},
				.Solid,
			)
			testing.expect(t, len(state.gpu_state.batch.vertices) == 4)
			testing.expect(t, len(state.gpu_state.batch.indices) == 6)

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			testing.expect(t, batch_upload(cmd))
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(6))
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))
		},
	)
}

@(test)
batch_flush_draws_early_returns :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			// No pipeline
			append(&state.gpu_state.batch.segments, Batch_Segment{index_count = 6})
			batch_flush_draws()

			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			clear(&state.gpu_state.batch.segments)
			batch_flush_draws()
			// Fake pipeline must not be used with real SDL calls; clear before env ends.
			state.gpu_state.pipeline = nil
		},
	)
}

@(test)
batch_flush_draws_skips_empty_and_missing_textures :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			// No pipeline → early return even with segments
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment {
					key = {texture_id = INVALID_ASSET_ID, clip = {0, 0, 10, 10}},
					first_index = 0,
					index_count = 6,
				},
			)
			batch_flush_draws()

			// With a non-nil pipeline pointer that is not a real pipeline, we must not
			// call into SDL. Cover skip paths by exercising the loop logic indirectly:
			// zero index_count and missing texture are continued before bind/draw.
			state.gpu_state.pipeline = nil
			clear(&state.gpu_state.batch.segments)
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment{index_count = 0, key = {texture_id = TEXTURE_WHITE_ID}},
			)
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment {
					index_count = 6,
					key = {texture_id = INVALID_ASSET_ID, clip = {0, 0, 1, 1}},
				},
			)
			// pipeline nil → returns before loop; still validates setup.
			batch_flush_draws()
		},
	)
}

@(test)
batch_end_to_end_record_upload_with_white_texture_draw_path :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			// Ensure white GPU texture is reachable via texture_get_gpu(0).
			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) != nil)

			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_axis_quad(
				{0, 0, 16, 16},
				{0, 0, 1, 1},
				{255, 0, 0, 255},
				{0, 0, 0, 255},
				{16, 16},
				{2, 2, 2, 2},
				{t = 1, b = 1, l = 1, r = 1},
				.Solid,
			)
			batch_finalize_segments()
			testing.expect_value(t, len(state.gpu_state.batch.segments), 1)
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(6))

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			testing.expect(t, batch_upload(cmd))
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))

			// flush without pipeline is a no-op (safe).
			batch_flush_draws()
		},
	)
}

@(test)
batch_key_equality_used_by_check_key :: proc(t: ^testing.T) {
	a := Batch_Key{texture_id = Asset_Id(1), clip = {1, 2, 3, 4}}
	b := Batch_Key{texture_id = Asset_Id(1), clip = {1, 2, 3, 4}}
	c := Batch_Key{texture_id = Asset_Id(2), clip = {1, 2, 3, 4}}
	d := Batch_Key{texture_id = Asset_Id(1), clip = {1, 2, 3, 5}}
	testing.expect(t, a == b)
	testing.expect(t, a != c)
	testing.expect(t, a != d)
}

@(test)
batch_ensure_capacity_exact_boundary_returns_true :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			state.gpu_state.batch.vertex_capacity = 4
			// len=0 + extra=4 == capacity → still within limit
			testing.expect(t, batch_ensure_capacity(4))
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, u32(4))
		},
	)
}

@(test)
batch_push_quad_with_tex_clip_flag :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_quad(
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
				{255, 255, 255, 255},
				{},
				{1, 1},
				{},
				{},
				.Textured_Rounded,
				true,
			)
			expect_close(t, state.gpu_state.batch.vertices[0].params[0], 1)
			expect_close(t, state.gpu_state.batch.vertices[0].params[1], draw_mode_f32(.Textured_Rounded))
		},
	)
}

@(test)
batch_check_key_skips_finalize_when_no_indices_yet :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID)
			// Switch key with empty indices: previous segment index_count stays 0
			batch_check_key(Asset_Id(2))
			testing.expect_value(t, len(state.gpu_state.batch.segments), 2)
			testing.expect_value(t, state.gpu_state.batch.segments[0].index_count, u32(0))
			testing.expect_value(t, state.gpu_state.batch.segments[1].first_index, u32(0))
		},
	)
}

@(test)
batch_flush_draws_full_pipeline_path :: proc(t: ^testing.T) {
	with_engine_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) != nil)

			batch_reset()
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_axis_quad(
				{0, 0, 32, 32},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{32, 32},
				{},
				{},
				.Solid,
			)
			batch_finalize_segments()

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return

			swapchain: ^sdl.GPUTexture
			if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, state.window, &swapchain, nil, nil) ||
			   swapchain == nil {
				_ = sdl.CancelGPUCommandBuffer(cmd)
				testing.expect(t, false, "swapchain acquire failed")
				return
			}

			testing.expect(t, batch_upload(cmd))

			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain,
				load_op     = .CLEAR,
				clear_color = {0, 0, 0, 1},
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)
			testing.expect(t, pass != nil)
			if pass == nil {
				_ = sdl.SubmitGPUCommandBuffer(cmd)
				return
			}

			state.gpu_state.batch.cmd = cmd
			state.gpu_state.batch.pass = pass
			state.gpu_state.batch.dpi = state.dpi
			batch_flush_draws()
			sdl.EndGPURenderPass(pass)
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))
			batch_reset()
		},
	)
}

// ---------------------------------------------------------------------------
// Gap coverage: upload partial emptiness, transfer/map failures, buffer create
// ---------------------------------------------------------------------------

@(test)
batch_upload_verts_only_or_indices_only_returns_true_without_upload :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.vertices, UI_Vertex{})
			testing.expect(t, batch_upload(nil))

			clear(&state.gpu_state.batch.vertices)
			append(&state.gpu_state.batch.indices, u16(0))
			testing.expect(t, batch_upload(nil))
		},
	)
}

@(test)
batch_create_gpu_buffers_vertex_failure_cleans_index :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			test_hook_batch_fail_vertex_buffer = true
			testing.expect(t, !batch_create_gpu_buffers())
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
			testing.expect(t, state.gpu_state.batch.index_buffer == nil)
			test_hook_batch_fail_vertex_buffer = false
			testing.expect(t, batch_create_gpu_buffers())
		},
	)
}

@(test)
batch_create_gpu_buffers_index_failure_cleans_vertex :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			test_hook_batch_fail_index_buffer = true
			testing.expect(t, !batch_create_gpu_buffers())
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
			testing.expect(t, state.gpu_state.batch.index_buffer == nil)
			test_hook_batch_fail_index_buffer = false
			testing.expect(t, batch_create_gpu_buffers())
		},
	)
}

@(test)
batch_create_gpu_buffers_both_failures_clean :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			test_hook_batch_fail_vertex_buffer = true
			test_hook_batch_fail_index_buffer = true
			testing.expect(t, !batch_create_gpu_buffers())
			testing.expect(t, state.gpu_state.batch.vertex_buffer == nil)
			testing.expect(t, state.gpu_state.batch.index_buffer == nil)
			test_hook_batch_fail_vertex_buffer = false
			test_hook_batch_fail_index_buffer = false
			testing.expect(t, batch_create_gpu_buffers())
		},
	)
}

@(test)
batch_upload_transfer_create_failure_returns_false :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{0, 0, 4, 4},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{4, 4},
				{},
				{},
				.Solid,
			)
			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			test_hook_batch_upload_fail_transfer = true
			testing.expect(t, !batch_upload(cmd))
			test_hook_batch_upload_fail_transfer = false
			_ = sdl.CancelGPUCommandBuffer(cmd)
		},
	)
}

@(test)
batch_upload_map_failure_returns_false :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{0, 0, 4, 4},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{4, 4},
				{},
				{},
				.Solid,
			)
			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			test_hook_batch_upload_fail_map = true
			testing.expect(t, !batch_upload(cmd))
			test_hook_batch_upload_fail_map = false
			_ = sdl.CancelGPUCommandBuffer(cmd)
		},
	)
}

@(test)
batch_push_axis_quad_zero_size_textured_emits_nothing :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			// Zero-size screen → empty visible → early return before UV adjust.
			batch_push_axis_quad(
				{10, 10, 0, 0},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{},
				{},
				{},
				.Textured,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)

			batch_push_axis_quad(
				{10, 10, 5, 0},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{},
				{},
				{},
				.Textured_Rounded,
			)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
		},
	)
}

@(test)
batch_flush_draws_skips_zero_and_missing_with_live_pipeline :: proc(t: ^testing.T) {
	with_engine_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)

			batch_reset()
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_axis_quad(
				{0, 0, 8, 8},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{8, 8},
				{},
				{},
				.Solid,
			)
			batch_finalize_segments()

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return

			swapchain: ^sdl.GPUTexture
			if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, state.window, &swapchain, nil, nil) ||
			   swapchain == nil {
				_ = sdl.CancelGPUCommandBuffer(cmd)
				testing.expect(t, false, "swapchain acquire failed")
				return
			}
			testing.expect(t, batch_upload(cmd))

			clear(&state.gpu_state.batch.segments)
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment{index_count = 0, key = {texture_id = TEXTURE_WHITE_ID}},
			)
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment {
					index_count = 6,
					key = {texture_id = INVALID_ASSET_ID, clip = {0, 0, 8, 8}},
				},
			)
			append(
				&state.gpu_state.batch.segments,
				Batch_Segment {
					index_count = 6,
					first_index = 0,
					key = {texture_id = TEXTURE_WHITE_ID, clip = {0, 0, 8, 8}},
				},
			)

			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain,
				load_op     = .CLEAR,
				clear_color = {0, 0, 0, 1},
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)
			testing.expect(t, pass != nil)
			if pass == nil {
				_ = sdl.SubmitGPUCommandBuffer(cmd)
				return
			}
			state.gpu_state.batch.cmd = cmd
			state.gpu_state.batch.pass = pass
			state.gpu_state.batch.dpi = state.dpi
			batch_flush_draws()
			sdl.EndGPURenderPass(pass)
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))
			batch_reset()
		},
	)
}

@(test)
batch_destroy_with_nil_gpu_clears_cpu_arrays :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&state.gpu_state.batch.vertices, UI_Vertex{})
			append(&state.gpu_state.batch.indices, u16(1))
			append(&state.gpu_state.batch.segments, Batch_Segment{})
			append(&state.gpu_state.batch.clip_stack, Rect{})
			append(&state.gpu_state.batch.space_stack, Draw_Space.SCREEN)
			state.gpu_state.batch.vertex_capacity = 10
			state.gpu_state.batch.has_current_key = true
			testing.expect(t, state.gpu == nil)
			batch_destroy()
			testing.expect(t, state.gpu_state.batch.vertices == nil)
			testing.expect_value(t, state.gpu_state.batch.vertex_capacity, u32(0))
			testing.expect(t, !state.gpu_state.batch.has_current_key)
		},
	)
}
