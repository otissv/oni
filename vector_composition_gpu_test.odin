#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(private)
vector_composition_gpu_setup :: proc(t: ^testing.T, w, h: i32) -> bool {
	state.ui.pass = .Draw
	state.dpi = {logical_w = w, logical_h = h, drawable_w = w, drawable_h = h, scale = 1}
	state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
	state.gpu_state.sampler = gpu_create_sampler(state.gpu)
	state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
	testing.expect(t, state.gpu_state.pipeline != nil && state.gpu_state.sampler != nil && state.gpu_state.white_texture != nil)
	if state.gpu_state.pipeline == nil || state.gpu_state.sampler == nil || state.gpu_state.white_texture == nil {
		return false
	}

	gpu_update_projection(state.dpi)
	batch_init()
	return true
}

@(private)
vector_composition_gpu_submit :: proc(t: ^testing.T) -> bool {
	cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
	testing.expect(t, cmd != nil)
	if cmd == nil {
		return false
	}

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	testing.expect(t, fence != nil)
	if fence == nil {
		return false
	}

	defer sdl.ReleaseGPUFence(state.gpu, fence)
	testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
	return true
}

@(private)
vector_composition_expect_rgba :: proc(t: ^testing.T, pixels: []u8, w, x, y: int, want: [4]u8, label: string) {
	base := (y * w + x) * 4
	for channel in 0 ..< 4 {
		gpu_test_expect_u8_near(t, pixels[base + channel], want[channel], label)
	}
}

@(test)
vector_gpu_nested_geometric_clips_intersect :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})
		fill := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {255, 0, 0, 255})}
		// Nested half-planes: left 20px ∩ bottom 20px → bottom-left block.
		inner := vector_test_rect({0, 12, 32, 20}, {255, 255, 255, 255})
		outer := vector_test_rect({0, 0, 20, 32}, {255, 255, 255, 255})
		clipped_inner := [1]Vector_Node{{kind = .Clip, opacity = 1, mesh = inner.mesh, children = fill[:]}}
		clipped := [1]Vector_Node{{kind = .Clip, opacity = 1, mesh = outer.mesh, children = clipped_inner[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = clipped[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 32, 8, 4, {0, 0, 255, 255}, "above inner clip stays blue")
		vector_composition_expect_rgba(t, pixels, 32, 28, 24, {0, 0, 255, 255}, "right of outer clip stays blue")
		vector_composition_expect_rgba(t, pixels, 32, 8, 24, {255, 0, 0, 255}, "intersection is red")
	})
}

@(test)
vector_gpu_luminance_mask_uses_linear_luma_times_alpha :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 16) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 16}, {0, 0, 255, 255})
		content := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		// Opaque mid-grey: alpha mask keeps full coverage; luminance softens via linear sRGB.
		alpha_mask := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {128, 128, 128, 255})}
		alpha_node := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = alpha_mask[:],
			mask_kind = .Alpha,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = alpha_node[:], opacity = 1}), Vector_Error.None)

		content_r := [1]Vector_Node{vector_test_rect({16, 0, 16, 16}, {255, 0, 0, 255})}
		lum_mask := [1]Vector_Node{vector_test_rect({16, 0, 16, 16}, {128, 128, 128, 255})}
		lum_node := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content_r[:],
			mask = lum_mask[:],
			mask_kind = .Luminance,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = lum_node[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 16)
		if !ok {
			return
		}

		defer delete(pixels)
		alpha := pixels[(8 * 32 + 8) * 4:]
		luma := pixels[(8 * 32 + 24) * 4:]
		vector_composition_expect_rgba(t, pixels, 32, 8, 8, {255, 0, 0, 255}, "alpha mask ignores rgb")
		testing.expect(t, luma[0] < alpha[0] - 40, "luminance mid-grey covers less than opaque alpha")
		testing.expect(t, luma[2] > 40, "luminance reveals blue backdrop")
	})
}

@(test)
vector_gpu_mask_crosses_clip_and_group_opacity_is_isolated :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 48, 32) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 48, 32}, {0, 0, 0, 255})
		// Overlapping reds faded as one group → single 50% coverage, not stacked 75%.
		reds := [2]Vector_Node{
			vector_test_rect({0, 0, 24, 24}, {255, 0, 0, 255}),
			vector_test_rect({8, 0, 24, 24}, {255, 0, 0, 255}),
		}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = reds[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)

		// Green fill masked by a triangle that extends above the clip rect.
		green := [1]Vector_Node{vector_test_rect({24, 0, 24, 32}, {0, 255, 0, 255})}
		tri := vector_test_triangle({24, 32}, {36, -8}, {48, 32})
		mask := [1]Vector_Node{tri}
		masked := [1]Vector_Node{{kind = .Mask, opacity = 1, children = green[:], mask = mask[:], mask_kind = .Alpha}}
		clipped := [1]Vector_Node{{kind = .Clip, opacity = 1, clip = {24, 8, 24, 16}, children = masked[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = clipped[:], opacity = 1}), Vector_Error.None)
		draw_rect({44, 28, 4, 4}, {255, 255, 255, 255})
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 48, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		surface := sdl.CreateSurfaceFrom(48, 32, .RGBA8888, raw_data(pixels), 48 * 4)
		if surface != nil {
			_ = img.SavePNG(surface, "build/test/vector-m5-composition.png")
			sdl.DestroySurface(surface)
		}

		vector_composition_expect_rgba(t, pixels, 48, 12, 4, {128, 0, 0, 255}, "isolated group opacity")
		vector_composition_expect_rgba(t, pixels, 48, 4, 28, {0, 0, 0, 255}, "below group stays clear")
		vector_composition_expect_rgba(t, pixels, 48, 36, 4, {0, 0, 0, 255}, "above clip stays clear despite mask overhang")
		vector_composition_expect_rgba(t, pixels, 48, 36, 16, {0, 255, 0, 255}, "mask inside clip is green")
		vector_composition_expect_rgba(t, pixels, 48, 36, 28, {0, 0, 0, 255}, "below clip stays clear")
		vector_composition_expect_rgba(t, pixels, 48, 46, 30, {255, 255, 255, 255}, "later UI is not clipped by vector mask")
	})
}

@(test)
vector_gpu_nested_groups_multiply_opacity_once_each :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 16, 16) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 16, 16}, {0, 0, 255, 255})
		inner_fill := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		inner := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = inner_fill[:]}}
		outer := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = inner[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = outer[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 16, 16)
		if !ok {
			return
		}

		defer delete(pixels)
		// 0.5 * 0.5 over blue → 25% red / 75% blue.
		vector_composition_expect_rgba(t, pixels, 16, 8, 8, {64, 0, 191, 255}, "nested group opacity")
	})
}

@(test)
vector_gpu_partially_offscreen_group_stays_bounded :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})
		fill := [1]Vector_Node{vector_test_rect({-16, 8, 32, 16}, {255, 0, 0, 255})}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = fill[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		testing.expect(t, state.vector.gpu.pool_bytes <= VECTOR_TARGET_POOL_BUDGET)
		vector_composition_expect_rgba(t, pixels, 32, 4, 16, {128, 0, 128, 255}, "visible half of offscreen group")
		vector_composition_expect_rgba(t, pixels, 32, 28, 4, {0, 0, 255, 255}, "outside group stays backdrop")
	})
}

@(test)
vector_gpu_mask_object_bounding_box_content_units_readback :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 40, 20) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 40, 20}, {0, 0, 255, 255})
		content := [1]Vector_Node{vector_test_rect({0, 0, 40, 20}, {255, 0, 0, 255})}
		mask := [1]Vector_Node{vector_test_rect({0, 0, 0.5, 1}, {255, 255, 255, 255})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = mask[:],
			mask_kind = .Alpha,
			mask_content_units = .Object_Bounding_Box,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 40, 20)
		if !ok {
			return
		}

		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 40, 8, 10, {255, 0, 0, 255}, "left half masked in")
		vector_composition_expect_rgba(t, pixels, 40, 30, 10, {0, 0, 255, 255}, "right half masked out")
	})
}

@(test)
vector_gpu_geometric_clip_restores_parent_for_sibling_draw :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 16) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 16}, {0, 0, 255, 255})
		left_fill := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		tri := vector_test_triangle({0, 16}, {8, 0}, {16, 16})
		left := [1]Vector_Node{{kind = .Clip, opacity = 1, mesh = tri.mesh, children = left_fill[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = left[:], opacity = 1}), Vector_Error.None)
		right := [1]Vector_Node{vector_test_rect({16, 0, 16, 16}, {0, 255, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = right[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 16)
		if !ok {
			return
		}

		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 32, 2, 2, {0, 0, 255, 255}, "outside first clip stays blue")
		vector_composition_expect_rgba(t, pixels, 32, 8, 10, {255, 0, 0, 255}, "inside first clip is red")
		vector_composition_expect_rgba(t, pixels, 32, 24, 8, {0, 255, 0, 255}, "sibling draw after clip pop is green")
	})
}
