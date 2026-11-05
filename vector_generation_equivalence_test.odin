#+test
package oni

import "core:math"
import "core:slice"
import "core:testing"
import v "./vector"

@(private)
vector_benchmark_morph_reference_into :: proc(frame, icon, part: int, commands: []Vector_Path_Command) {
	assert(len(commands) >= 36)
	vector_benchmark_ensure_bases()
	copy(commands, vector_benchmark_bases[icon % 8][part][:])
	phase := f64(frame) / 60 + f64(icon) * .0137 + f64(part) * .17
	for &command in commands[:36] {
		count := command.kind == .Cubic ? 3 : command.kind == .Move ? 1 : 0
		for &point in command.points[:count] {
			x, y := point.x, point.y
			point.x += .45 * math.sin(phase + y * .7)
			point.y += .45 * math.cos(phase * .83 + x * .7)
		}
	}
}

@(test)
vector_generator_preserves_frozen_equations_and_geometry :: proc(t: ^testing.T) {
	for frame in ([5]int{0, 1, 120, 1000, 1919}) {
		for icon in 0 ..< 512 {
			for part in 0 ..< 4 {
				a, b: [36]Vector_Path_Command
				vector_benchmark_morph_into(frame, 1536 + icon, part, a[:])
				vector_benchmark_morph_reference_into(frame, 1536 + icon, part, b[:])
				for command, i in a { for point, j in command.points { testing.expect(t, math.abs(point.x - b[i].points[j].x) < 3e-14 && math.abs(point.y - b[i].points[j].y) < 3e-14) } }
				limits := v.DEFAULT_LIMITS
				limits.uniform_subdivision = -1
				fa, ea := v.Flatten(a[:], v.IDENTITY, limits)
				fb, eb := v.Flatten(b[:], v.IDENTITY, limits)
				testing.expect_value(t, ea, v.Error.None)
				testing.expect_value(t, eb, v.Error.None)
				testing.expect_value(t, len(fa.contours), len(fb.contours))
				for contour, ci in fa.contours {
					sa, sb: [512]v.Point
					na := vector_benchmark_normalize_contour(fa.points[contour.first:][:contour.count], sa[:])
					other := fb.contours[ci]
					nb := vector_benchmark_normalize_contour(fb.points[other.first:][:other.count], sb[:])
					testing.expectf(t, slice.equal(sa[:na], sb[:nb]), "frame %d icon %d part %d", frame, icon, part)
				}
				v.Destroy_Flat_Path(&fa); v.Destroy_Flat_Path(&fb)
			}
		}
	}
}

@(private)
vector_benchmark_normalize_contour :: proc(points: []v.Point, storage: []v.Point) -> (count: int) {
	for point in points { if count == 0 || storage[count - 1] != point { storage[count] = point; count += 1 } }
	if count > 1 && storage[count - 1] == storage[0] { count -= 1 }
	return
}
