#+test
package oni

import "core:fmt"
import "core:slice"
import "core:testing"
import "core:time"

// Diagnostic only; acceptance remains the complete GPU benchmark.
@(test)
vector_cpu_stage_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_CPU_STAGE_PROFILE, false) { return }
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		handles := make([]Vector_Path_Handle, 2048)
		defer delete(handles)
		specs := make([]Vector_Path_Tess_Spec, len(handles))
		defer delete(specs)
		items := make([]Vector_Path_Draw, len(handles))
		defer delete(items)
		for i in 0 ..< len(handles) {
			commands := vector_benchmark_morph(0, 1536 + i / 4, i % 4)
			handles[i], _ = Vector_Create_Path(commands[:])
			specs[i] = {handle = handles[i], transform = Vector_Identity}
			items[i] = {handle = handles[i], paint = Solid_Paint({255, 0, 0, 255}), transform = Vector_Identity, opacity = 1}
		}
		times: [3][600]f64
		for frame in 0 ..< 720 {
			free_all(context.temp_allocator)
			vector_scene_reset()
			state.ui.pass = .Draw
			state.ui.frame += 1
			start := time.tick_now()
			for handle, i in handles {
				commands, _ := Vector_Borrow_Path_Commands(handle)
				vector_benchmark_morph_into(frame, 1536 + i / 4, i % 4, commands)
			}
			testing.expect_value(t, Vector_Path_Geometry_Changed_Many(handles), Vector_Error.None)
			generated := time.tick_now()
			testing.expect_value(t, Vector_Prefetch_Paths(specs), Vector_Error.None)
			prefetched := time.tick_now()
			testing.expect_value(t, Draw_Vector_Paths(items), Vector_Error.None)
			if frame >= 120 {
				i := frame - 120
				times[0][i] = time.duration_milliseconds(time.tick_diff(start, generated))
				times[1][i] = time.duration_milliseconds(time.tick_diff(generated, prefetched))
				times[2][i] = time.duration_milliseconds(time.tick_since(prefetched))
			}
		}
		for &stage, i in times {
			slice.sort(stage[:])
			fmt.printf("CPU stage %d: p50 %.3f ms, p95 %.3f ms\n", i, stage[299], stage[569])
		}
	})
}
