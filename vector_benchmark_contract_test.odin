#+test
package oni

import "core:math"
import "core:testing"
import v "./vector"

@(test)
vector_benchmark_isolation_keeps_distinct_morphs_and_static_transforms :: proc(t: ^testing.T) {
	for mode in Vector_Benchmark_Isolation {
		count := vector_benchmark_icon_count(mode)
		testing.expect_value(t, count, 512 if mode == .Morph_Only else 2048)
		for icon in 0 ..< count {
			source := vector_benchmark_source_icon(mode, icon)
			if mode == .Morph_Only {
				testing.expect_value(t, source, icon + 1536)
			}
			transform := vector_benchmark_isolated_transform(mode, 123, source, 10, 20)
			if mode == .Morph_Only || mode == .Svg_Paint_Only || mode == .Svg_Prepare_Only {
				testing.expect_value(t, transform, Vector_Transform{1, 0, 0, 1, 10, 20})
			} else {
				testing.expect_value(t, transform, vector_benchmark_transform(123, source, 10, 20))
			}
			testing.expect_value(t, vector_benchmark_uses_morph(mode, source), (mode == .Full || mode == .Morph_Only) && source >= 1536)
		}
	}
	_, valid := vector_benchmark_isolation("typo")
	testing.expect(t, !valid)
}

@(private)
vector_benchmark_transform :: proc(frame, icon: int, x, y: f64) -> Vector_Transform {
	phase := f64(frame) / 60 + f64(icon) * .0137
	sx, sy := 1 + .25 * math.sin(phase), 1 + .25 * math.cos(phase * .7)
	c, s := math.cos(phase), math.sin(phase)
	return {c * sx, s * sx, -s * sy, c * sy, x + 12 - 12 * c * sx + 12 * s * sy + 2 * math.sin(phase), y + 12 - 12 * s * sx - 12 * c * sy + 2 * math.cos(phase * .7)}
}

@(private)
vector_benchmark_bases: [8][4][36]Vector_Path_Command
@(private)
vector_benchmark_bases_ready: bool

@(private)
vector_benchmark_factors: [8][4][36][3][2]v.Point

@(private)
vector_benchmark_ensure_bases :: proc() {
	if vector_benchmark_bases_ready {
		return
	}
	for variant in 0 ..< 8 {
		for part in 0 ..< 4 {
			vector_benchmark_bases[variant][part] = vector_benchmark_circle(part, 3.5, f64(variant))
			for command, i in vector_benchmark_bases[variant][part] {
				for point, j in command.points {
					vector_benchmark_factors[variant][part][i][j] = {
						{.45 * math.cos(point.y * .7), .45 * math.cos(point.x * .7)},
						{.45 * math.sin(point.y * .7), .45 * math.sin(point.x * .7)},
					}
				}
			}
		}
	}
	vector_benchmark_bases_ready = true
}

@(private)
vector_benchmark_morph_into :: proc(frame, icon, part: int, commands: []Vector_Path_Command) {
	assert(len(commands) >= 36)
	vector_benchmark_ensure_bases()
	variant := icon % 8
	copy(commands, vector_benchmark_bases[variant][part][:])
	factors := &vector_benchmark_factors[variant][part]
	phase := f64(frame) / 60 + f64(icon) * .0137 + f64(part) * .17
	s, c := math.sin(phase), math.cos(phase)
	s83, c83 := math.sin(phase * .83), math.cos(phase * .83)
	a, b := v.Point{s, c83}, v.Point{c, -s83}
	for &command, i in commands[:36] {
		count := command.kind == .Cubic ? 3 : command.kind == .Move ? 1 : 0
		for &point, j in command.points[:count] {
			factor := factors[i][j]
			point += a * factor[0] + b * factor[1]
		}
	}
}


@(private)
vector_benchmark_morph :: proc(frame, icon, part: int) -> (commands: [36]Vector_Path_Command) {
	vector_benchmark_morph_into(frame, icon, part, commands[:])
	return
}

@(test)
vector_benchmark_contract_has_32_cubics_and_nonaffine_morphs :: proc(t: ^testing.T) {
	for variant in 0 ..< 8 {
		for part in 0 ..< 4 {
			commands := vector_benchmark_circle(part, 3.5, f64(variant))
			cubics := 0
			for command in commands { if command.kind == .Cubic { cubics += 1 } }
			testing.expect_value(t, cubics, 32)
			morph := vector_benchmark_morph(123, variant + 1536, part)
			_, affine := v.Commands_Affine(commands[:], morph[:])
			testing.expect(t, !affine)
		}
	}
}
