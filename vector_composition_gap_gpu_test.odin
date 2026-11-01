#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"
import v "./vector"

@(test)
vector_gpu_luminance_half_alpha_white_is_half_coverage :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 16, 16) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 16, 16}, {0, 0, 255, 255})
		content := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		// Premultiplied store of white @ 0.5 alpha is RGB≈128; coverage must still be 0.5.
		mask := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 255, 255, 128})}
		nodes := [1]Vector_Node{{
			kind = .Mask,
			opacity = 1,
			children = content[:],
			mask = mask[:],
			mask_kind = .Luminance,
		}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 16, 16)
		if !ok {
			return
		}

		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 16, 8, 8, {128, 0, 128, 255}, "half-alpha white luminance")
	})
}

@(test)
vector_gpu_mask_msaa_keeps_diagonal_coverage :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 0, 255})
		content := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {255, 255, 255, 255})}
		tri := vector_test_triangle({0, 32}, {32, 0}, {32, 32})
		mask := [1]Vector_Node{tri}
		nodes := [1]Vector_Node{{kind = .Mask, opacity = 1, children = content[:], mask = mask[:], mask_kind = .Alpha}}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		// On the diagonal, MSAA coverage must be partial — not binary 0/255.
		edge := pixels[(15 * 32 + 16) * 4]
		testing.expect(t, edge > 8 && edge < 248, "mask diagonal retains antialiased coverage")
		testing.expect(t, vector_gpu_frame().pool[vector_gpu_frame().outputs[vector_frame().draws[0].first].mask].msaa)
	})
}

@(test)
vector_gpu_target_replace_reserves_peak_overlap :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 64, 64) {
			return
		}

		testing.expect(t, vector_gpu_init(.R8G8B8A8_UNORM))
		target: Vector_Target
		testing.expect(t, vector_target_ensure(&target, {0, 0, 64, 64}, true, true, true))
		old_bytes := target.bytes
		// Grow so a second allocation is required while the old target is still live.
		state.vector.gpu.bytes = VECTOR_GPU_BUDGET - old_bytes + 1
		state.vector.gpu.pool_bytes = VECTOR_TARGET_POOL_BUDGET - old_bytes + 1
		testing.expect(t, !vector_target_ensure(&target, {0, 0, 128, 128}, true, true, true))
		testing.expect(t, target.colour != nil)
		testing.expect_value(t, target.alloc_w, f32(64))
		vector_target_release(&target, true)
	})
}

@(test)
vector_gpu_prepare_frame_caps_encode_attempts_at_three :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 16, 16) {
			return
		}

		draw_record_begin(state.dpi)
		for i in 0 ..< 4 {
			fill := [1]Vector_Node{vector_test_rect({f32(i * 4), 0, 4, 4}, {255, 0, 0, 255})}
			group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = fill[:]}}
			testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)
		}
		draw_record_end()
		testing.expect(t, len(vector_frame().draws) >= 4)
		// Fail the first group pass; remaining submissions must still encode within the
		// fixed three-attempt budget (not draws+1).
		test_hook_vector_fail_pass_after = 1
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		testing.expect_value(t, Vector_Last_Error(), Vector_Error.GPU_Failed)
		failed := 0
		for draw in vector_frame().draws {
			if draw.failed {
				failed += 1
			}
		}
		testing.expect(t, failed >= 1)
		testing.expect(t, failed <= VECTOR_MAX_ENCODE_ATTEMPTS)
		if cmd != nil {
			_ = sdl.CancelGPUCommandBuffer(cmd)
		}
	})
}

@(test)
vector_gpu_sample_work_accumulates_across_replay_attempts :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) {
			return
		}

		draw_record_begin(state.dpi)
		fill := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {255, 0, 0, 255})}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = fill[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)
		fill2 := [1]Vector_Node{vector_test_rect({0, 0, 32, 32}, {0, 255, 0, 255})}
		group2 := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = fill2[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group2[:], opacity = 1}), Vector_Error.None)
		draw_record_end()

		test_hook_vector_fail_pass_after = 1
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		if cmd != nil {
			_ = sdl.CancelGPUCommandBuffer(cmd)
		}
		// After a failed attempt that prepared group targets, cumulative sample work stays.
		testing.expect(t, state.vector.gpu.sample_work > 0)
	})
}

@(test)
vector_gpu_animated_scene_geometry_reuploads :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 16) {
			return
		}

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 16}, {0, 0, 255, 255})
		nodes := [1]Vector_Node{vector_test_rect({0, 0, 16, 16}, {255, 0, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		testing.expect(t, fence != nil)
		if fence == nil {
			return
		}
		testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &fence, 1))
		sdl.ReleaseGPUFence(state.gpu, fence)
		vector_gpu_advance_frame()
		batch_reset()

		// Same vertex/index counts, different positions — must not reuse stale upload.
		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 16}, {0, 0, 255, 255})
		moved := [1]Vector_Node{vector_test_rect({16, 0, 16, 16}, {0, 255, 0, 255})}
		testing.expect_value(t, draw_vector_scene({nodes = moved[:], opacity = 1}), Vector_Error.None)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 16)
		if !ok {
			return
		}

		defer delete(pixels)
		vector_composition_expect_rgba(t, pixels, 32, 8, 8, {0, 0, 255, 255}, "stale red geometry not reused")
		vector_composition_expect_rgba(t, pixels, 32, 24, 8, {0, 255, 0, 255}, "moved geometry uploaded")
	})
}

@(test)
vector_gpu_path_inside_opacity_group_readback :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 32, 32) {
			return
		}

		path: v.Path
		defer v.Destroy_Path(&path)
		testing.expect_value(t, v.Rectangle(&path, {0, 0}, {20, 20}), v.Error.None)
		handle, err := Vector_Create_Path(path.commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		defer Vector_Destroy_Path(handle)

		draw_record_begin(state.dpi)
		draw_rect({0, 0, 32, 32}, {0, 0, 255, 255})
		child := [1]Vector_Node{{
			kind = .Path,
			opacity = 1,
			path = {
				handle = handle,
				paint = Solid_Paint({255, 0, 0, 255}),
				transform = {1, 0, 0, 1, 6, 6},
				opacity = 1,
			},
		}}
		group := [1]Vector_Node{{kind = .Group, opacity = 0.5, children = child[:]}}
		testing.expect_value(t, draw_vector_scene({nodes = group[:], opacity = 1}), Vector_Error.None)
		root := vector_frame().records[vector_frame().draws[0].first]
		testing.expect_value(t, root.kind, Vector_Node_Kind.Group)
		testing.expect(t, abs(root.opacity - 0.5) < 0.001)
		testing.expect(t, root.first_child >= 0)
		path_rec := vector_frame().records[root.first_child]
		testing.expect_value(t, path_rec.kind, Vector_Node_Kind.Path)
		testing.expect(t, path_rec.bounds.w > 10 && path_rec.bounds.h > 10)
		draw_record_end()
		if !vector_composition_gpu_submit(t) {
			return
		}

		pixels, ok := gpu_test_download_vector_framebuffer(t, 32, 32)
		if !ok {
			return
		}

		defer delete(pixels)
		px := pixels[(12 * 32 + 12) * 4:]
		testing.expectf(t, px[0] > 80 && px[0] < 180, "path group red got %d", px[0])
		testing.expectf(t, px[2] > 80 && px[2] < 180, "path group blue got %d", px[2])
	})
}
