#+test
package oni

import "core:fmt"
import "core:slice"
import "core:testing"
import "core:time"

@(test)
vector_generation_diagnostic :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_GENERATION_BENCHMARK, false) { return }
	commands := new([512][4][36]Vector_Path_Command)
	defer free(commands)
	times := make([]f64, 1800)
	defer delete(times)
	vector_benchmark_ensure_bases()
	checksum := f64(0)
	for frame in 0 ..< 1920 {
		start := time.tick_now()
		for icon in 0 ..< 512 {
			for part in 0 ..< 4 { vector_benchmark_morph_into(frame, icon + 1536, part, commands[icon][part][:]) }
		}
		elapsed := time.duration_milliseconds(time.tick_since(start))
		if frame >= 120 { times[frame - 120] = elapsed }
		for &icon in commands { for &part in icon { for command in part { checksum += command.points[0].x } } }
	}
	slice.sort(times)
	fmt.printf("Morph generation alone: p50 %.3f ms, p95 %.3f ms, p99 %.3f ms; checksum %.3f\n", times[899], times[1709], times[1781], checksum)
	testing.expect(t, checksum > 0)
}
