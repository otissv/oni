#+test
package oni

// Isolation runs diagnose costs; none can satisfy the release workload.
@(private)
Vector_Benchmark_Isolation :: enum { Full, Transform_Only, Morph_Only, Svg_Prepare_Only, Svg_Paint_Only }

@(private)
vector_benchmark_isolation :: proc(name: string) -> (Vector_Benchmark_Isolation, bool) {
	switch name {
	case "full": return .Full, true
	case "transform-only": return .Transform_Only, true
	case "morph-only": return .Morph_Only, true
	case "svg-prepare-only": return .Svg_Prepare_Only, true
	case "svg-paint-only": return .Svg_Paint_Only, true
	}
	return .Full, false
}

@(private)
vector_benchmark_icon_count :: proc(mode: Vector_Benchmark_Isolation) -> int {
	return 512 if mode == .Morph_Only else 2048
}

@(private)
vector_benchmark_source_icon :: proc(mode: Vector_Benchmark_Isolation, icon: int) -> int {
	return icon + 1536 if mode == .Morph_Only else icon
}

@(private)
vector_benchmark_uses_morph :: proc(mode: Vector_Benchmark_Isolation, icon: int) -> bool {
	return (mode == .Full || mode == .Morph_Only) && icon >= 1536
}

@(private)
vector_benchmark_isolated_transform :: proc(mode: Vector_Benchmark_Isolation, frame, icon: int, x, y: f64) -> Vector_Transform {
	if mode == .Morph_Only || mode == .Svg_Prepare_Only || mode == .Svg_Paint_Only { return {1, 0, 0, 1, x, y} }
	return vector_benchmark_transform(frame, icon, x, y)
}
