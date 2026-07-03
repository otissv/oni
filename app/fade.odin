package app

import oni "../oni"
import tengu "../tengu"
import fmt "core:fmt"

frame_dt: f32

Route_Fade :: struct {
	opacity: f32,
	tween:   tengu.Tween_State(f32),
}

@(private)
active_route_fade :: proc() -> ^Route_Fade {
	switch Route {
	case .Home:
		return &home_fade
	case .About:
		return &about_fade
	}
	return &home_fade
}

route_fade_step :: proc(fade: ^Route_Fade, mounting: oni.Mount) -> oni.Mount {
	if mounting == .UNSET {
		tengu.tween_init(
			&fade.tween,
			tengu.Tween_Config(f32) {
				start = 0,
				target = 1,
				duration = tengu.Seconds(3),
				easing = tengu.Ease.LINEAR,
				repeat_count = 1,
			},
		)
		fade.opacity = 0
	}

	result := tengu.tween_step(
		tengu.Step_Params(f32) {
			state = &fade.tween,
			dt = frame_dt,
			anim = tengu.F32_Animatable(),
			completion = tengu.DEFAULT_COMPLETION_POLICY,
		},
	)
	fade.opacity = result.value
	return result.done ? .COMPLETED : .RUNNING
}

route_fade_elapsed_text :: proc() -> string {
	fade := active_route_fade()
	if tengu.tween_is_finished(fade.tween) do return ""
	return fmt.tprintf("%.2f s", fade.tween.elapsed)
}


route_fade_color :: proc(base: oni.RGBA, opacity: f32) -> oni.Colors {
	alpha := u8(min(max(opacity, 0), 1) * 255)
	return oni.RGBA{base.r, base.g, base.b, alpha}
}
