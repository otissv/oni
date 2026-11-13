#+test
package oni

import "core:math"
import "core:fmt"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(test)
debug_overlay_shortcut_toggle_repeat_and_rebind :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		testing.expect(t, !debug_overlay_visible())
		shortcut_test_press(.F3)
		testing.expect(t, debug_overlay_visible())
		testing.expect(t, shortcut_key_consumed(.F3))
		testing.expect(t, state.frame_dirty)
		state.shortcuts.processed = false
		w_ctx.keys[int(Scancode.F3)].pressed = false
		w_ctx.keys[int(Scancode.F3)].repeat = true
		shortcut_process()
		testing.expect(t, debug_overlay_visible(), "held F3 must not toggle repeatedly")
		shortcut_rebind_builtin_actions()
		shortcut_test_press(.F3)
		testing.expect(t, !debug_overlay_visible())
	})
}

@(test)
debug_overlay_frame_stats_publish_only_submitted_work :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		debug_overlay_begin_present()
		debug_overlay_record_draw(1)
		debug_overlay_record_draw(7)
		state.debug_overlay.current.batch_flushes = 2
		state.debug_overlay.current.presented = true
		debug_overlay_end_present(1_000_000_000)
		stats := render_stats()
		testing.expect_value(t, stats.draw_calls, u64(2))
		testing.expect_value(t, stats.draw_commands, u64(8))
		testing.expect_value(t, stats.batch_flushes, u64(2))
		testing.expect(t, stats.presented)
		debug_overlay_begin_present()
		debug_overlay_record_draw(99)
		debug_overlay_end_present(1_250_000_000)
		stats = render_stats()
		testing.expect(t, !stats.presented)
		testing.expect_value(t, stats.draw_calls, u64(0))
		testing.expect_value(t, stats.draw_commands, u64(0))
		debug_overlay_record_draw(1)
		testing.expect_value(t, render_stats().draw_calls, u64(0))
	})
}

@(test)
debug_overlay_fps_uses_unclamped_presentation_intervals :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		for i in 0 ..< 6 {
			debug_overlay_begin_present()
			state.debug_overlay.current.presented = true
			debug_overlay_end_present(1_000_000_000 + u64(i) * 100_000_000)
		}
		testing.expect(t, math.abs(render_stats().fps - 10) < 0.001)
		testing.expect(t, math.abs(render_stats().frame_ms - 100) < 0.001)
		debug_overlay_begin_present()
		state.debug_overlay.current.presented = true
		debug_overlay_end_present(3_000_000_000)
		testing.expect(t, math.abs(render_stats().frame_ms - 1500) < 0.001)
		testing.expect(t, render_stats().fps < 2, "idle time must not be capped at MAX_FRAME_TIME")
		debug_overlay_begin_present()
		debug_overlay_end_present(4_000_000_000)
		testing.expect_value(t, render_stats().fps, f64(0))
	})
}

@(test)
debug_overlay_refresh_preserves_pacing_and_stops_when_hidden_or_minimized :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		frame_mode_set(.On_Demand)
		debug_overlay_set_visible(true)
		testing.expect(t, state.frame_dirty)
		testing.expect(t, debug_overlay_refresh_due(1))
		debug_overlay_begin_present()
		debug_overlay_end_present(1_000_000_000)
		testing.expect(t, !debug_overlay_refresh_due(1_100_000_000))
		testing.expect(t, debug_overlay_refresh_due(1_250_000_000))
		testing.expect_value(t, debug_overlay_wait_timeout(1_100_000_000, 500), i32(150))
		testing.expect_value(t, frame_mode(), Frame_Mode.On_Demand)
		state.can_render = false
		testing.expect(t, !debug_overlay_refresh_due(2_000_000_000))
		testing.expect_value(t, debug_overlay_wait_timeout(2_000_000_000, 500), i32(500))
		state.can_render = true
		debug_overlay_set_visible(false)
		testing.expect(t, !debug_overlay_refresh_due(2_000_000_000))
	})
}

@(test)
debug_overlay_minimize_events_suspend_refresh_even_with_nonzero_drawable :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		engine_test_drain_events()
		debug_overlay_set_visible(true)
		testing.expect(t, state.can_render)
		testing.expect(t, engine_test_push(t, sdl.Event{window = {type = .WINDOW_MINIMIZED}}))
		poll_events()
		testing.expect(t, !debug_overlay_refresh_due(sdl.GetTicksNS()))
		testing.expect_value(t, debug_overlay_wait_timeout(sdl.GetTicksNS(), 500), i32(500))
		testing.expect(t, engine_test_push(t, sdl.Event{window = {type = .WINDOW_RESTORED}}))
		poll_events()
		testing.expect(t, debug_overlay_refresh_due(sdl.GetTicksNS()))
	})
}

@(test)
debug_overlay_layout_is_noninteractive_and_visibility_is_stable_between_passes :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		debug_overlay_set_visible(true)
		ui_begin_frame()
		debug_overlay_ui()
		id := ui_id(DEBUG_OVERLAY_ID)
		testing.expect(t, ui_has_layout_node(id))
		node := &state.ui.layout.nodes[state.ui.layout.id_to_node[id]]
		testing.expect(t, layout_pointer_events_none(node.config.pointer_events))
		testing.expect_value(t, node.space, Draw_Space.OVERLAY)
		debug_overlay_set_visible(false)
		ui_end_layout_pass()
		debug_overlay_ui()
		testing.expect(t, state.debug_overlay.frame_visible)
		testing.expect(t, len(batch_current().vertices) > 0)
		ui_begin_frame()
		debug_overlay_ui()
		testing.expect(t, !ui_has_layout_node(ui_id(DEBUG_OVERLAY_ID)))
	})
}

@(test)
debug_overlay_text_includes_live_atlas_snapshot :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		state.textures.atlas = {width = 64, height = 32, bytes_used = 1024, slot_count = 3}
		state.debug_overlay.stats.atlas = atlas_stats()
		debug_overlay_format()
		text := string(state.debug_overlay.text[:state.debug_overlay.text_length])
		testing.expect(t, strings.contains(text, "FPS"))
		testing.expect(t, strings.contains(text, "Draw calls"))
		testing.expect(t, strings.contains(text, "Batch flushes"))
		testing.expect(t, strings.contains(text, "64x32"))
		testing.expect(t, strings.contains(text, "12.5%"))
	})
}

@(test)
debug_overlay_gpu_present_and_failure_publish_correct_stats :: proc(t: ^testing.T) {
	with_present_env(t, proc(t: ^testing.T) {
		font, ok := font_register_family("debug-test", []Font_Face_Desc{{path = "fixtures/fonts/PixelOperator8-Bold.ttf"}})
		testing.expect(t, ok)
		theme.font_body = font_with_size(font, 13)
		debug_overlay_set_visible(true)
		ui_begin_frame()
		present_frame(proc() { render(present_test_quad_draw) })
		stats := render_stats()
		testing.expect(t, stats.presented)
		testing.expect(t, stats.draw_calls > 0 && stats.batch_flushes > 0)
		laid := layout_text_result(ui_id(DEBUG_OVERLAY_ID))
		testing.expect(t, laid != nil && len(laid.glyphs) > 20, "overlay text must actually be shaped and painted")
		if laid != nil do testing.expect(t, !laid.lines_borrowed, "changing diagnostics must not accumulate persistent shape-cache entries")
		cache_count := len(state.fonts.shape_cache)
		for _ in 0 ..< 3 {
			ui_begin_frame()
			present_frame(proc() { render(present_test_quad_draw) })
		}
		testing.expect_value(t, len(state.fonts.shape_cache), cache_count)
		testing.expect(t, stats.atlas.bytes_total > 0 && stats.atlas.cache_count > 0)
		ui_begin_frame()
		present_frame(proc() {
			render(proc() {
				if ui_pass() != .Draw do return
				nodes := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {0, 100, 0, 255})}
				_ = draw_vector_scene({nodes = nodes[:], opacity = 1})
			})
		})
		testing.expect(t, render_stats().presented)
		testing.expect_value(t, render_stats().blits, u64(1))
		testing.expect(t, render_stats().draw_calls >= 3)
		ui_begin_frame()
		test_hook_present_fail_render_pass = true
		present_frame(proc() { render(present_test_quad_draw) })
		testing.expect(t, render_stats().presented, "a successful swapchain submit is counted even when the render pass failed")
		testing.expect_value(t, render_stats().draw_calls, u64(0))
		test_hook_present_fail_render_pass = false
		ui_begin_frame()
		test_hook_present_nil_swapchain = true
		present_frame(proc() { render(present_test_quad_draw) })
		testing.expect(t, !render_stats().presented)
		testing.expect_value(t, render_stats().draw_calls, u64(0))
	})
}

@(test)
debug_overlay_uncached_shapes_release_heap_storage :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, _: Font_Handle, t: ^testing.T) {
		face, handle, ok := font_test_face(inter, 13)
		testing.expect(t, ok)
		if !ok do return
		for i in 0 ..< 4 {
			shaped := font_shape_line_build(face, handle.id, fmt.tprintf("FPS: %d\nDraw calls: %d", i, i + 1), 0, 0, 0, DEFAULT_TAB_SIZE, .NEWLINES, .LTR, cache = false)
			testing.expect(t, len(shaped.lines) == 2 && !shaped.borrowed)
			font_shape_lines_release(shaped)
		}
		testing.expect_value(t, len(state.fonts.shape_cache), 0)
	})
}

@(test)
debug_overlay_vector_render_readback_at_multiple_dpi_scales :: proc(t: ^testing.T) {
	with_present_env(t, proc(t: ^testing.T) {
		font, ok := font_register_family("debug-readback", []Font_Face_Desc{{path = "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf"}})
		testing.expect(t, ok)
		theme.font_body = font_with_size(font, 13)
		debug_overlay_set_visible(true)
		for scale in 1 ..= 2 {
			state.dpi = {logical_w = 420, logical_h = 240, drawable_w = 420 * i32(scale), drawable_h = 240 * i32(scale), scale = f32(scale)}
			gpu_update_projection(state.dpi)
			state.view.zoom = 3
			state.view.pan = {50, 25}
			ui_begin_frame()
			debug_overlay_begin_present()
			draw_record_begin(state.dpi)
			render(proc() {
				if ui_pass() != .Draw do return
				nodes := [1]Vector_Node{vector_test_rect({0, 0, 420, 240}, {0, 100, 0, 255})}
				_ = draw_vector_scene({nodes = nodes[:], opacity = 1})
			})
			draw_record_end()
			testing.expect(t, texture_uploads_flush(state.gpu))
			cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
			testing.expect(t, cmd != nil)
			if cmd == nil do return
			testing.expect(t, state.debug_overlay.current.draw_calls >= 3)
			testing.expect(t, state.debug_overlay.current.draw_commands >= state.debug_overlay.current.draw_calls)
			fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
			testing.expect(t, fence != nil)
			if fence == nil do return
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
			sdl.ReleaseGPUFence(state.gpu, fence)
			w, h := u32(state.dpi.drawable_w), u32(state.dpi.drawable_h)
			pixels, downloaded := gpu_test_download_vector_framebuffer(t, w, h)
			if !downloaded do return
			defer delete(pixels)
			bright := 0
			for y in 10 * scale ..< 175 * scale {
				for x in 10 * scale ..< 395 * scale {
					i := (y * int(w) + x) * 4
					if pixels[i] > 150 && pixels[i + 1] > 150 && pixels[i + 2] > 150 do bright += 1
				}
			}
			testing.expect(t, bright > 250 * scale, "overlay glyphs must appear in the vector framebuffer")
			outside := ((230 * scale) * int(w) + 410 * scale) * 4
			testing.expect_value(t, pixels[outside], u8(0))
			testing.expect_value(t, pixels[outside + 1], u8(100))
			surface := sdl.CreateSurfaceFrom(i32(w), i32(h), .ABGR8888, raw_data(pixels), i32(w * 4))
			testing.expect(t, surface != nil)
			if surface != nil {
				testing.expect(t, bool(img.SavePNG(surface, fmt.ctprintf("build/test/debug-overlay-%dx.png", scale))))
				sdl.DestroySurface(surface)
			}
			state.debug_overlay.current.presented = true
			debug_overlay_end_present(sdl.GetTicksNS())
			batch_reset()
			batch_flip()
		}
	})
}
