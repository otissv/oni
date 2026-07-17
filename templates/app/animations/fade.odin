package animations

import o "../../oni"
import tengu "libs:tengu"
import g "../globlas"

Route_Fade :: struct {
	opacity: f32,
	tween:   tengu.Tween_State(f32),
}

route_fade_step :: proc(fade: ^Route_Fade, mounting: o.Mount) -> o.Mount {
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
			dt = g.app.frame_dt,
			anim = tengu.F32_Animatable(),
			completion = tengu.DEFAULT_COMPLETION_POLICY,
		},
	)
	fade.opacity = result.value
	return result.done ? .COMPLETED : .RUNNING
}

route_fade_color :: proc(base: o.RGBA, opacity: f32) -> o.Colors {
	alpha := u8(min(max(opacity, 0), 1) * 255)
	return o.RGBA{base.r, base.g, base.b, alpha}
}
