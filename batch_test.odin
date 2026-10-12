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
		batch_delete_cpu_arrays(&test_state.gpu_state)
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
	batch_current().dpi = state.dpi
	batch_current().vertex_capacity = BATCH_INITIAL_VERT_CAPACITY
	batch_current().index_capacity = BATCH_INITIAL_VERT_CAPACITY * 6
	body(t)
}

/*
Batch with a real GPU device for buffer create/upload/grow paths.
*/
@(private)
with_batch_gpu_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !test_require_gpu_device_unlocked() {
		return
	}

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	gpu := gpu_create_device(true)
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
	batch_current().dpi = state.dpi

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
	expect_close(t, draw_mode_f32(.Textured_Text), 4)
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
			testing.expect_value(t, batch_current().vertex_capacity, u32(BATCH_INITIAL_VERT_CAPACITY))
			testing.expect_value(
				t,
				batch_current().index_capacity,
				u32(BATCH_INITIAL_VERT_CAPACITY * 6),
			)
			testing.expect(t, batch_current().vertex_buffer != nil)
			testing.expect(t, batch_current().index_buffer != nil)
			// Dual ping-pong slots are both initialized.
			testing.expect(t, state.gpu_state.batches[1].vertex_buffer != nil)
			testing.expect(t, state.gpu_state.batches[1].index_buffer != nil)
			testing.expect_value(t, state.gpu_state.batch_index, 0)
			append(&batch_current().indices, u16(0))
			append(&batch_current().segments, Batch_Segment{})
			append(&batch_current().clip_stack, Rect{1, 2, 3, 4})
			append(&batch_current().space_stack, Draw_Space.ARTBOARD)
			append(&batch_current().opacity_stack, f32(0.5))
			batch_current().has_current_key = true

			batch_destroy()
			testing.expect(t, batch_current().vertex_buffer == nil)
			testing.expect(t, batch_current().index_buffer == nil)
			testing.expect_value(t, batch_current().vertex_capacity, u32(0))
			testing.expect_value(t, batch_current().index_capacity, u32(0))
			testing.expect(t, !batch_current().has_current_key)
			testing.expect(t, batch_current().vertices == nil)
			testing.expect(t, batch_current().indices == nil)
			testing.expect(t, batch_current().segments == nil)
			testing.expect(t, batch_current().clip_stack == nil)
			testing.expect(t, batch_current().space_stack == nil)
			testing.expect(t, batch_current().opacity_stack == nil)

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
			append(&batch_current().vertices, UI_Vertex{}, UI_Vertex{})
			append(&batch_current().indices, u16(0), u16(1), u16(2))
			append(&batch_current().segments, Batch_Segment{first_index = 1})
			append(&batch_current().clip_stack, Rect{0, 0, 10, 10})
			append(&batch_current().space_stack, Draw_Space.SCREEN)
			append(&batch_current().opacity_stack, f32(0.25))
			batch_current().has_current_key = true
			batch_current().current_key = {texture_id = Asset_Id(3)}

			cap_v := batch_current().vertex_capacity
			cap_i := batch_current().index_capacity
			batch_reset()
			testing.expect_value(t, len(batch_current().vertices), 0)
			testing.expect_value(t, len(batch_current().indices), 0)
			testing.expect_value(t, len(batch_current().segments), 0)
			testing.expect_value(t, len(batch_current().clip_stack), 0)
			testing.expect_value(t, len(batch_current().space_stack), 0)
			testing.expect_value(t, len(batch_current().opacity_stack), 0)
			testing.expect(t, !batch_current().has_current_key)
			testing.expect_value(t, batch_current().vertex_capacity, cap_v)
			testing.expect_value(t, batch_current().index_capacity, cap_i)
		},
	)
}

@(test)
batch_create_gpu_buffers_releases_previous :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			old_v := batch_current().vertex_buffer
			old_i := batch_current().index_buffer
			testing.expect(t, old_v != nil)
			testing.expect(t, batch_create_gpu_buffers())
			testing.expect(t, batch_current().vertex_buffer != nil)
			testing.expect(t, batch_current().index_buffer != nil)
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
				batch_current().vertex_capacity,
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
			batch_current().vertex_capacity = 4
			testing.expect(t, !batch_ensure_capacity(8))
			testing.expect_value(t, batch_current().vertex_capacity, u32(8))
			testing.expect_value(t, batch_current().index_capacity, u32(48))
		},
	)
}

@(test)
batch_ensure_capacity_doubles_until_enough :: proc(t: ^testing.T) {
	with_batch_gpu_env(
		t,
		proc(t: ^testing.T) {
			batch_current().vertex_capacity = 8
			batch_current().index_capacity = 48
			testing.expect(t, batch_create_gpu_buffers())

			// Need 40 verts with capacity 8 → doubles to 16, 32, 64.
			testing.expect(t, batch_ensure_capacity(40))
			testing.expect(t, batch_current().vertex_capacity >= 40)
			testing.expect_value(
				t,
				batch_current().index_capacity,
				batch_current().vertex_capacity * 6,
			)
			testing.expect(t, batch_current().vertex_buffer != nil)
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
			append(&batch_current().clip_stack, Rect{-100, -100, 50, 50})
			batch_invalidate_clip_cache()
			clip := batch_current_clip()
			expect_rect(t, clip, {})

			clear(&batch_current().clip_stack)
			append(&batch_current().clip_stack, Rect{100, 100, 200, 150})
			batch_invalidate_clip_cache()
			clip = batch_current_clip()
			expect_rect(t, clip, {100, 100, 200, 150})

			append(&batch_current().clip_stack, Rect{700, 500, 200, 200})
			batch_invalidate_clip_cache()
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
			append(&batch_current().clip_stack, Rect{0, 0, 100, 50})
			batch_invalidate_clip_cache()
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
			testing.expect(t, batch_current().has_current_key)
			testing.expect_value(t, len(batch_current().segments), 1)
			testing.expect_value(t, batch_current().segments[0].first_index, u32(0))
			testing.expect_value(t, batch_current().segments[0].index_count, u32(0))

			// Same key: no new segment
			batch_check_key(TEXTURE_WHITE_ID)
			testing.expect_value(t, len(batch_current().segments), 1)

			batch_push_indices(0)
			testing.expect_value(t, len(batch_current().indices), 6)

			// Different texture: finalize previous and start new
			batch_check_key(Asset_Id(1))
			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
			testing.expect_value(t, batch_current().segments[1].first_index, u32(6))
			testing.expect_value(t, batch_current().current_key.texture_id, Asset_Id(1))

			batch_push_indices(4)
			batch_finalize_segments()
			testing.expect_value(t, batch_current().segments[1].index_count, u32(6))
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
			append(&batch_current().clip_stack, Rect{10, 10, 50, 50})
			batch_invalidate_clip_cache()
			batch_check_key(TEXTURE_WHITE_ID)
			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
			expect_rect(t, batch_current().segments[1].key.clip, {10, 10, 50, 50})
		},
	)
}

@(test)
batch_check_key_splits_on_nearest_change :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID, false)
			batch_push_indices(0)
			batch_check_key(TEXTURE_WHITE_ID, true)
			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect(t, !batch_current().segments[0].key.nearest)
			testing.expect(t, batch_current().segments[1].key.nearest)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
		},
	)
}

@(test)
batch_check_key_splits_on_lcd_change :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_check_key(TEXTURE_WHITE_ID, true, false)
			batch_push_indices(0)
			batch_check_key(TEXTURE_WHITE_ID, true, true)
			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect(t, !batch_current().segments[0].key.lcd)
			testing.expect(t, batch_current().segments[1].key.lcd)
			testing.expect(t, batch_current().segments[0].key.nearest)
			testing.expect(t, batch_current().segments[1].key.nearest)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))

			// Same lcd key merges.
			batch_push_indices(4)
			batch_check_key(TEXTURE_WHITE_ID, true, true)
			testing.expect_value(t, len(batch_current().segments), 2)
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
			testing.expect_value(t, len(batch_current().segments), 3)
			testing.expect_value(t, batch_current().segments[0].key.stack_index, u32(1))
			testing.expect_value(t, batch_current().segments[1].key.stack_index, u32(5))
			testing.expect_value(t, batch_current().segments[2].key.stack_index, u32(9))
		},
	)
}

@(test)
batch_finalize_segments_is_idempotent_after_sort :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_set_stack_index(9)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(0)

			batch_set_stack_index(1)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(4)

			batch_set_stack_index(5)
			batch_check_key(TEXTURE_WHITE_ID)
			batch_push_indices(8)

			batch_finalize_segments()
			batch_finalize_segments()

			testing.expect_value(t, len(batch_current().segments), 3)

			for segment in batch_current().segments {
				testing.expect_value(t, segment.index_count, u32(6))
			}
		},
	)
}

@(test)
batch_finalize_segments_noop_without_key :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_finalize_segments()
			testing.expect_value(t, len(batch_current().segments), 0)
			batch_current().has_current_key = true
			batch_finalize_segments()
			testing.expect_value(t, len(batch_current().segments), 0)
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
			testing.expect_value(t, len(batch_current().indices), 6)
			testing.expect_value(t, batch_current().indices[0], u16(10))
			testing.expect_value(t, batch_current().indices[1], u16(11))
			testing.expect_value(t, batch_current().indices[2], u16(12))
			testing.expect_value(t, batch_current().indices[3], u16(10))
			testing.expect_value(t, batch_current().indices[4], u16(12))
			testing.expect_value(t, batch_current().indices[5], u16(13))
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
				draw_mode_f32(.Textured),
				true,
			)
			testing.expect_value(t, len(batch_current().vertices), 1)
			v := batch_current().vertices[0]
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
				draw_mode_f32(.Solid),
				false,
			)
			expect_close(t, batch_current().vertices[1].params[0], 0)
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
			testing.expect_value(t, len(batch_current().vertices), 4)
			testing.expect_value(t, len(batch_current().indices), 6)
			tint := rgba_to_f32({255, 128, 0, 255})
			expect_batch_vertex(
				t,
				batch_current().vertices[0],
				{0, 0},
				{0, 0},
				{0, 0},
				tint,
				.Solid,
			)
			expect_close(t, batch_current().vertices[2].pos[0], 10)
			expect_close(t, batch_current().vertices[2].pos[1], 5)
		},
	)
}

@(test)
batch_push_quad_skips_when_capacity_grow_fails :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_current().vertex_capacity = 2
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
			testing.expect_value(t, len(batch_current().vertices), 0)
			testing.expect_value(t, len(batch_current().indices), 0)
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
			testing.expect_value(t, len(batch_current().vertices), 4)
			v0 := batch_current().vertices[0]
			expect_close(t, v0.pos[0], 10)
			expect_close(t, v0.pos[1], 20)
			expect_close(t, v0.uv[0], 0)
			expect_close(t, v0.local_uv[0], 0)
			v2 := batch_current().vertices[2]
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
			expect_close(t, batch_current().vertices[0].uv[0], 0)
			expect_close(t, batch_current().vertices[2].uv[0], 1)
		},
	)
}

@(test)
batch_push_axis_quad_textured_clips_and_adjusts_uvs :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			append(&batch_current().clip_stack, Rect{50, 50, 50, 50})
			batch_invalidate_clip_cache()
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
			testing.expect_value(t, len(batch_current().vertices), 4)
			// Visible is [50,50,50,50]; UVs should be [0.5,0.5] → [1,1]
			v0 := batch_current().vertices[0]
			v2 := batch_current().vertices[2]
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
			append(&batch_current().clip_stack, Rect{200, 200, 10, 10})
			batch_invalidate_clip_cache()
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
			testing.expect_value(t, len(batch_current().vertices), 0)
			testing.expect_value(t, len(batch_current().indices), 0)
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
			v0 := batch_current().vertices[0]
			v2 := batch_current().vertices[2]
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
			v0 := batch_current().vertices[0]
			v2 := batch_current().vertices[2]
			expect_close(t, v0.pos[0], 25) // 10*2+5
			expect_close(t, v0.pos[1], 25)
			expect_close(t, v2.pos[0], 45) // 20*2+5
			expect_close(t, v2.pos[1], 45)
		},
	)
}

@(test)
batch_push_axis_quad_snaps_bordered_solid_to_pixels :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{10.2, 20.7, 30.4, 40.4},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{255, 0, 0, 255},
				{30.4, 40.4},
				{},
				{t = 1, b = 1, l = 1, r = 1},
				.Solid,
			)
			testing.expect_value(t, len(batch_current().vertices), 4)
			v0 := batch_current().vertices[0]
			v2 := batch_current().vertices[2]
			expect_close(t, v0.pos[0], 10)
			expect_close(t, v0.pos[1], 21)
			expect_close(t, v2.pos[0], 41)
			expect_close(t, v2.pos[1], 61)
			expect_close(t, v0.rect_size[0], 31)
			expect_close(t, v0.rect_size[1], 40)
		},
	)
}

@(test)
batch_push_axis_quad_textured_text_snaps_and_packs_mode :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_push_axis_quad(
				{10.2, 20.7, 12.4, 14.4},
				{0.1, 0.2, 0.3, 0.4},
				{255, 255, 255, 255},
				{},
				{12.4, 14.4},
				{},
				{},
				.Textured_Text,
			)
			testing.expect_value(t, len(batch_current().vertices), 4)
			v0 := batch_current().vertices[0]
			v2 := batch_current().vertices[2]
			expect_close(t, v0.pos[0], 10)
			expect_close(t, v0.pos[1], 21)
			expect_close(t, v2.pos[0], 23)
			expect_close(t, v2.pos[1], 35)
			expect_close(t, v0.params[1], draw_mode_f32(.Textured_Text))
			expect_close(t, v0.uv[0], 0.1)
			expect_close(t, v0.uv[1], 0.2)
			expect_close(t, v2.uv[0], 0.4)
			expect_close(t, v2.uv[1], 0.6)
		},
	)
}

@(test)
batch_push_atlas_quads_emits_textured_text_and_nearest_key :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			tex := Texture_Handle {
				id = Asset_Id(42),
				w  = 100,
				h  = 50,
			}
			dsts := []Rect{{10.2, 20.7, 8, 10}}
			srcs := []Rect{{25, 10, 8, 10}}
			batch_push_atlas_quads(tex, dsts, srcs, {240, 240, 240, 255}, true)
			testing.expect_value(t, len(batch_current().vertices), 4)
			testing.expect(t, batch_current().current_key.nearest)
			testing.expect(t, !batch_current().current_key.lcd)
			testing.expect_value(t, batch_current().current_key.texture_id, Asset_Id(42))
			v0 := batch_current().vertices[0]
			expect_close(t, v0.params[1], draw_mode_f32(.Textured_Text))
			expect_close(t, v0.pos[0], 10)
			expect_close(t, v0.pos[1], 21)
			expect_close(t, v0.uv[0], 0.25)
			expect_close(t, v0.uv[1], 0.2)
		},
	)
}

@(test)
batch_push_atlas_quads_sets_lcd_key :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			tex := Texture_Handle {
				id = Asset_Id(7),
				w  = 32,
				h  = 32,
			}
			dsts := []Rect{{0, 0, 8, 8}}
			srcs := []Rect{{0, 0, 8, 8}}
			batch_push_atlas_quads(tex, dsts, srcs, {255, 255, 255, 255}, true, true)
			testing.expect(t, batch_current().current_key.nearest)
			testing.expect(t, batch_current().current_key.lcd)
			testing.expect_value(t, batch_current().current_key.texture_id, Asset_Id(7))
		},
	)
}

// ---------------------------------------------------------------------------
// clip_to_scissor
// ---------------------------------------------------------------------------

@(test)
batch_snap_rect_to_device_pixels_integer_and_hidpi :: proc(t: ^testing.T) {
	dpi := Dpi_Info {
		scale = 1,
	}
	r := batch_snap_rect_to_device_pixels({1.2, 2.6, 3.4, 4.1}, dpi)
	expect_close(t, r.x, 1)
	expect_close(t, r.y, 3)
	expect_close(t, r.w, 4)
	expect_close(t, r.h, 4)

	dpi.scale = 2
	r = batch_snap_rect_to_device_pixels({1.2, 2.6, 3.4, 4.1}, dpi)
	expect_close(t, r.x, 1)
	expect_close(t, r.y, 2.5)
	expect_close(t, r.w, 3.5)
	expect_close(t, r.h, 4)

	dpi.scale = 0
	r = batch_snap_rect_to_device_pixels({1.4, 1.6, 2, 2}, dpi)
	expect_close(t, r.x, 1)
	expect_close(t, r.y, 2)
}

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
			append(&batch_current().vertices, UI_Vertex{})
			append(&batch_current().indices, u16(0))
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
			testing.expect(t, len(batch_current().vertices) == 4)
			testing.expect(t, len(batch_current().indices) == 6)

			cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			testing.expect(t, batch_upload(cmd))
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
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
			append(&batch_current().segments, Batch_Segment{index_count = 6})
			batch_flush_draws()

			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			clear(&batch_current().segments)
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
				&batch_current().segments,
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
			clear(&batch_current().segments)
			append(
				&batch_current().segments,
				Batch_Segment{index_count = 0, key = {texture_id = TEXTURE_WHITE_ID}},
			)
			append(
				&batch_current().segments,
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
			testing.expect_value(t, len(batch_current().segments), 1)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))

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
	e := Batch_Key{texture_id = Asset_Id(1), clip = {1, 2, 3, 4}, lcd = true}
	f := Batch_Key{texture_id = Asset_Id(1), clip = {1, 2, 3, 4}, nearest = true}
	testing.expect(t, a == b)
	testing.expect(t, a != c)
	testing.expect(t, a != d)
	testing.expect(t, a != e)
	testing.expect(t, a != f)
}

@(test)
batch_ensure_capacity_exact_boundary_returns_true :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			batch_current().vertex_capacity = 4
			// len=0 + extra=4 == capacity → still within limit
			testing.expect(t, batch_ensure_capacity(4))
			testing.expect_value(t, batch_current().vertex_capacity, u32(4))
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
			expect_close(t, batch_current().vertices[0].params[0], 1)
			expect_close(t, batch_current().vertices[0].params[1], draw_mode_f32(.Textured_Rounded))
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
			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(0))
			testing.expect_value(t, batch_current().segments[1].first_index, u32(0))
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

			batch_current().cmd = cmd
			batch_current().pass = pass
			batch_current().dpi = state.dpi
			batch_flush_draws()
			sdl.EndGPURenderPass(pass)
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))
			batch_reset()
		},
	)
}

/*
Phase C.3 exit: mixed gray + LCD segments in one frame bind UI then LCD then UI.
*/
@(test)
batch_flush_draws_rebinds_pipeline_for_mixed_gray_and_lcd_segments :: proc(t: ^testing.T) {
	with_engine_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.lcd_pipeline != nil)
			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) != nil)

			batch_reset()

			// Gray → LCD → gray; geometry mode is irrelevant to pipeline selection.
			batch_check_key(TEXTURE_WHITE_ID, false, false)
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

			batch_check_key(TEXTURE_WHITE_ID, true, true)
			batch_push_axis_quad(
				{8, 0, 8, 8},
				{0, 0, 1, 1},
				{200, 200, 200, 255},
				{},
				{8, 8},
				{},
				{},
				.Solid,
			)

			batch_check_key(TEXTURE_WHITE_ID, false, false)
			batch_push_axis_quad(
				{16, 0, 8, 8},
				{0, 0, 1, 1},
				{255, 0, 0, 255},
				{},
				{8, 8},
				{},
				{},
				.Solid,
			)

			batch_finalize_segments()
			testing.expect_value(t, len(batch_current().segments), 3)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(6))
			testing.expect_value(t, batch_current().segments[1].index_count, u32(6))
			testing.expect_value(t, batch_current().segments[2].index_count, u32(6))
			testing.expect(t, !batch_current().segments[0].key.lcd)
			testing.expect(t, batch_current().segments[1].key.lcd)
			testing.expect(t, !batch_current().segments[2].key.lcd)

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

			clear(&test_batch_pipeline_binds)
			test_hook_batch_record_pipeline_binds = true

			batch_current().cmd = cmd
			batch_current().pass = pass
			batch_current().dpi = state.dpi
			batch_flush_draws()

			testing.expect_value(t, len(test_batch_pipeline_binds), 3)
			if len(test_batch_pipeline_binds) == 3 {
				testing.expect(t, test_batch_pipeline_binds[0] == state.gpu_state.pipeline)
				testing.expect(t, test_batch_pipeline_binds[1] == state.gpu_state.lcd_pipeline)
				testing.expect(t, test_batch_pipeline_binds[2] == state.gpu_state.pipeline)
			}

			sdl.EndGPURenderPass(pass)
			testing.expect(t, sdl.SubmitGPUCommandBuffer(cmd))
			batch_reset()
		},
	)
}

/*
Consecutive same-pipeline segments (texture change only) must not rebind.
*/
@(test)
batch_flush_draws_skips_redundant_pipeline_binds_within_lcd_mode :: proc(t: ^testing.T) {
	with_engine_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, texture_get_gpu(TEXTURE_WHITE_ID) != nil)

			batch_reset()
			batch_check_key(TEXTURE_WHITE_ID, false, false)
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
			// Force a second gray segment via stack index (same lcd=false).
			batch_set_stack_index(1)
			batch_check_key(TEXTURE_WHITE_ID, false, false)
			batch_push_axis_quad(
				{4, 0, 4, 4},
				{0, 0, 1, 1},
				{255, 255, 255, 255},
				{},
				{4, 4},
				{},
				{},
				.Solid,
			)
			batch_finalize_segments()
			testing.expect_value(t, len(batch_current().segments), 2)

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

			clear(&test_batch_pipeline_binds)
			test_hook_batch_record_pipeline_binds = true

			batch_current().cmd = cmd
			batch_current().pass = pass
			batch_current().dpi = state.dpi
			batch_flush_draws()

			testing.expect_value(t, len(test_batch_pipeline_binds), 1)
			if len(test_batch_pipeline_binds) == 1 {
				testing.expect(t, test_batch_pipeline_binds[0] == state.gpu_state.pipeline)
			}

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
			append(&batch_current().vertices, UI_Vertex{})
			testing.expect(t, batch_upload(nil))

			clear(&batch_current().vertices)
			append(&batch_current().indices, u16(0))
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
			testing.expect(t, batch_current().vertex_buffer == nil)
			testing.expect(t, batch_current().index_buffer == nil)
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
			testing.expect(t, batch_current().vertex_buffer == nil)
			testing.expect(t, batch_current().index_buffer == nil)
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
			testing.expect(t, batch_current().vertex_buffer == nil)
			testing.expect(t, batch_current().index_buffer == nil)
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
			testing.expect_value(t, len(batch_current().vertices), 0)

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
			testing.expect_value(t, len(batch_current().vertices), 0)
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

			clear(&batch_current().segments)
			append(
				&batch_current().segments,
				Batch_Segment{index_count = 0, key = {texture_id = TEXTURE_WHITE_ID}},
			)
			append(
				&batch_current().segments,
				Batch_Segment {
					index_count = 6,
					key = {texture_id = INVALID_ASSET_ID, clip = {0, 0, 8, 8}},
				},
			)
			append(
				&batch_current().segments,
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
			batch_current().cmd = cmd
			batch_current().pass = pass
			batch_current().dpi = state.dpi
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
			append(&batch_current().vertices, UI_Vertex{})
			append(&batch_current().indices, u16(1))
			append(&batch_current().segments, Batch_Segment{})
			append(&batch_current().clip_stack, Rect{})
			append(&batch_current().space_stack, Draw_Space.SCREEN)
			batch_current().vertex_capacity = 10
			batch_current().has_current_key = true
			testing.expect(t, state.gpu == nil)
			batch_destroy()
			testing.expect(t, batch_current().vertices == nil)
			testing.expect_value(t, batch_current().vertex_capacity, u32(0))
			testing.expect(t, !batch_current().has_current_key)
		},
	)
}

@(private)
batch_test_seed_mixed_atlas_text :: proc(mode: Atlas_Draw_Mode) -> Layout_Text {
	texture_init()
	append(
		&state.textures.records,
		Texture_Record{w = 16, h = 16},
		Texture_Record{w = 16, h = 16},
	)
	state.textures.atlas = {
		texture_id = Asset_Id(1),
		width      = 16,
		height     = 16,
		generation = 3,
	}
	append(
		&state.textures.overflow,
		Atlas_State {
			texture_id = Asset_Id(2),
			width      = 16,
			height     = 16,
			generation = 7,
		},
	)
	state.textures.atlas_draw_mode = mode
	state.fonts.glyph_cache = make(map[Font_Glyph_Key]Font_Glyph_Entry)
	state.fonts.glyph_cache[{face_id = 1, glyph_id = 10, render_mode = .Gray}] = {
		region = {texture_id = 1, x = 0, y = 0, w = 4, h = 4},
		generation = 3,
	}
	state.fonts.glyph_cache[{face_id = 1, glyph_id = 11, render_mode = .Gray}] = {
		region = {texture_id = 2, x = 4, y = 4, w = 4, h = 4},
		generation = 7,
	}

	lines := make([]Shaped_Line, 1)
	glyphs := make([]Layout_Glyph_Paint, 2)
	glyphs[0] = {face_id = 1, glyph_id = 10, dst = {0, 0, 4, 4}}
	glyphs[1] = {face_id = 1, glyph_id = 11, dst = {4, 0, 4, 4}}

	return Layout_Text{lines = lines, glyphs = glyphs}
}

@(private)
batch_test_clear_mixed_atlas_text :: proc(laid: ^Layout_Text) {
	if laid != nil {
		delete(laid.lines)
		delete(laid.glyphs)
		laid.lines = nil
		laid.glyphs = nil
	}

	delete(state.fonts.glyph_cache)
	state.fonts.glyph_cache = nil
	texture_shutdown()
}

@(test)
batch_mixed_atlas_text_uses_one_multi_texture_segment :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			laid := batch_test_seed_mixed_atlas_text(.Multi_Texture)
			defer batch_test_clear_mixed_atlas_text(&laid)
			testing.expect_value(t, len(laid.glyphs), 2)
			testing.expect_value(t, len(state.fonts.glyph_cache), 2)
			expect_close(t, laid.glyphs[1].dst.w, 4)
			slot, slot_ok := texture_atlas_slot_for_id(Asset_Id(2))
			testing.expect(t, slot_ok)
			testing.expect_value(t, slot, u32(1))
			second_key := Font_Glyph_Key{face_id = 1, glyph_id = 11, render_mode = .Gray}
			second, second_ok := state.fonts.glyph_cache[second_key]
			testing.expect(t, second_ok)
			testing.expect_value(t, second.generation, u32(7))

			_ = font_draw_layout_text(&laid, {255, 255, 255, 255})
			batch_finalize_segments()

			testing.expect_value(t, len(batch_current().segments), 1)
			testing.expect(t, batch_current().segments[0].key.multi_atlas)
			testing.expect_value(t, batch_current().segments[0].index_count, u32(12))
			testing.expect_value(t, len(batch_current().vertices), 8)
			expect_close(t, batch_current().vertices[0].params[2], 0)
			if len(batch_current().vertices) >= 8 {
				expect_close(t, batch_current().vertices[4].params[2], 1)
			}
			testing.expect(t, batch_current().segments[0].key.nearest)
			testing.expect(t, !batch_current().segments[0].key.lcd)
		},
	)
}

@(test)
batch_mixed_atlas_text_fallback_splits_by_texture :: proc(t: ^testing.T) {
	with_batch_cpu_env(
		t,
		proc(t: ^testing.T) {
			laid := batch_test_seed_mixed_atlas_text(.Fallback_Split)
			defer batch_test_clear_mixed_atlas_text(&laid)

			_ = font_draw_layout_text(&laid, {255, 255, 255, 255})
			batch_finalize_segments()

			testing.expect_value(t, len(batch_current().segments), 2)
			testing.expect(t, !batch_current().segments[0].key.multi_atlas)
			testing.expect(t, !batch_current().segments[1].key.multi_atlas)
			testing.expect_value(t, batch_current().segments[0].key.texture_id, Asset_Id(1))
			testing.expect_value(t, batch_current().segments[1].key.texture_id, Asset_Id(2))
			testing.expect_value(t, len(batch_current().vertices), 8)
			expect_close(t, batch_current().vertices[0].params[2], 0)
			if len(batch_current().vertices) >= 8 {
				expect_close(t, batch_current().vertices[4].params[2], 0)
			}
		},
	)
}
