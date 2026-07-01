/*
Benchmark harness for tengu stepping performance.

Run:
  odin run tengu/bench -o:speed
*/

package tengu_bench

import "core:fmt"
import "core:time"
import tengu "../"

print_result :: proc(name: string, iterations: int, elapsed: time.Duration) {
	ns_per_op := f64(elapsed) / f64(iterations)
	fmt.printf(
		"%-40s %8d ops  %10.1f ns/op\n",
		name,
		iterations,
		ns_per_op,
	)
}

main :: proc() {
	iterations := 100_000
	fmt.println("tengu benchmarks (release build recommended)")
	fmt.println("------------------------------------------")

	{
		state: tengu.Tween_State(f32)
		tengu.tween_init(
			&state,
			tengu.Tween_Config(f32){start = 0, target = 10, duration = 1.0, easing = tengu.Ease.LINEAR},
		)
		anim := tengu.F32_Animatable()
		start := time.now()
		for _ in 0 ..< iterations {
			tengu.tween_step(&state, 1.0 / 60.0, anim)
		}
		print_result("tween_step f32", iterations, time.since(start))
	}

	{
		state: tengu.Spring_State(f32)
		tengu.spring_init(&state, tengu.spring_config(f32(10)), 0)
		anim := tengu.F32_Animatable()
		start := time.now()
		for _ in 0 ..< iterations {
			tengu.spring_step(&state, 1.0 / 60.0, anim)
		}
		print_result("spring_step f32", iterations, time.since(start))
	}

	{
		state: tengu.Decay_State(f32)
		tengu.decay_init(&state, tengu.decay_config(f32(100)), 0)
		anim := tengu.F32_Animatable()
		start := time.now()
		for _ in 0 ..< iterations {
			tengu.decay_step(&state, 1.0 / 60.0, anim)
		}
		print_result("decay_step f32", iterations, time.since(start))
	}

	{
		stops := []tengu.Keyframe_Stop(f32) {
			tengu.keyframes_stop_duration(f32(10), 1.0),
			tengu.keyframes_stop_duration(f32(20), 1.0),
		}
		spec := tengu.keyframes_spec_duration(f32(0), stops)
		config, err := tengu.keyframes_compile(spec)
		if err != .NONE do return
		defer tengu.keyframes_config_destroy(config)

		state: tengu.Keyframes_State(f32)
		tengu.keyframes_init(&state, config)
		anim := tengu.F32_Animatable()
		start := time.now()
		for _ in 0 ..< iterations {
			tengu.keyframes_step(&state, 1.0 / 60.0, anim)
		}
		print_result("keyframes_step f32", iterations, time.since(start))
	}

	{
		slot: tengu.Slot(f32)
		tengu.slot_init(&slot, 0, .SPRING)
		options := tengu.spring_slot_options(f32(0))
		anim := tengu.F32_Animatable()
		start := time.now()
		for _ in 0 ..< iterations {
			tengu.spring_to(&slot, 10, 1.0 / 60.0, options, anim)
		}
		print_result("spring_to slot f32", iterations, time.since(start))
	}

	{
		start := time.now()
		for _ in 0 ..< iterations {
			_ = tengu.ease(.IN_OUT_CUBIC, 0.37)
		}
		print_result("ease IN_OUT_CUBIC", iterations, time.since(start))
	}

	{
		start := time.now()
		for _ in 0 ..< iterations {
			_ = tengu.plan_substeps(0.016)
		}
		print_result("plan_substeps", iterations, time.since(start))
	}
}
