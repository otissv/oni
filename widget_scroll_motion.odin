package oni

import "core:math"

SCROLL_SMOOTH_RATE :: f64(24)
SCROLL_SMOOTH_EPSILON :: f32(0.01)

// Stored with the offset so normal widget pruning and shutdown own its lifetime.
Scroll_Motion :: struct {
	offset:         Vec2,
	target:         Vec2,
	last_update_ns: u64,
}

// Exponential decay composes across frame intervals without overshooting.
scroll_smooth_axis :: proc(current, target: f32, dt: f64) -> f32 {
	if dt <= 0 || math.is_nan(dt) {
		return current
	}

	next := target + (current - target) * f32(math.exp(-SCROLL_SMOOTH_RATE * dt))

	if abs(next - target) <= SCROLL_SMOOTH_EPSILON {
		return target
	}

	return next
}

/*
Advances the previous wheel target, then accepts new wheel distance. Returns
whether wheel input was accepted, independently of ongoing animated movement.
The first input starts the clock here so time spent idle cannot skip smoothing.
*/
widget_scroll_update :: proc(
	key: string,
	max_scroll, wheel: Vec2,
	overflow_x, overflow_y: Overflow,
	now_ns: u64 = 0,
) -> bool {
	now_ns := now_ns

	if now_ns == 0 {
		now_ns = frame_now_ns()
	}

	motion := widget_scroll_motion_ensure(key)

	if motion == nil {
		return false
	}

	limit := Vec2{
		layout_node_scrolls_axis(overflow_x) ? max_scroll.x : 0,
		layout_node_scrolls_axis(overflow_y) ? max_scroll.y : 0,
	}
	motion.offset = {scroll_clamp_axis(motion.offset.x, limit.x), scroll_clamp_axis(motion.offset.y, limit.y)}
	motion.target = {scroll_clamp_axis(motion.target.x, limit.x), scroll_clamp_axis(motion.target.y, limit.y)}

	if motion.last_update_ns != 0 && now_ns > motion.last_update_ns {
		dt := f64(now_ns - motion.last_update_ns) / 1_000_000_000.0
		motion.offset.x = scroll_smooth_axis(motion.offset.x, motion.target.x, dt)
		motion.offset.y = scroll_smooth_axis(motion.offset.y, motion.target.y, dt)
	}

	accepted := scroll_apply_wheel(&motion.target.x, &motion.target.y, limit, wheel.x, wheel.y, overflow_x, overflow_y)
	motion.last_update_ns = now_ns

	if motion.offset != motion.target {
		request_frame()
	}

	return accepted
}
