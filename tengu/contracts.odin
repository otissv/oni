package tengu

import "core:math"

/*
The animation core always operates in seconds. Callers own state and provide `dt`
for every step; the package keeps no hidden scheduler or global animation state.
*/
Seconds :: distinct f32

/*
Built-in standalone value types so the package stays independent from `oni`.
Additional caller types can participate through custom Animatable adapters.
*/
Vec2 :: struct {
	x, y: f32,
}

Vec3 :: struct {
	x, y, z: f32,
}

Vec4 :: struct {
	x, y, z, w: f32,
}

/*
Normalized RGBA in straight color space. Interpolation uses premultiplied alpha.
*/
RGBA :: struct {
	r, g, b, a: f32,
}

Rect :: struct {
	x, y, w, h: f32,
}

Velocity_Support :: enum {
	NONE,
	VALUE_TYPE,
}

/*
Final value contract for any animatable domain used by future primitives.
When `velocity_support == .VALUE_TYPE`, velocity values are represented by `T`.
*/
Animatable :: struct($T: typeid) {
	zero:             proc() -> T,
	add:              proc(a, b: T) -> T,
	sub:              proc(a, b: T) -> T,
	scale:            proc(v: T, s: f32) -> T,
	mix:              proc(a, b: T, t: f32) -> T,
	distance:         proc(a, b: T) -> f32,
	velocity_support: Velocity_Support,
}

/*
Minimal caller-owned state for duration-based primitives.
*/
Value_State :: struct($T: typeid) {
	value: T,
}

/*
Minimal caller-owned state for motion primitives that track velocity.
*/
Motion_State :: struct($T: typeid) {
	value:    T,
	velocity: T,
}

/*
Canonical step result shared by future primitives. Tweens can leave
`has_velocity` false and velocity at the zero value for `T`.
*/
Step_Result :: struct($T: typeid) {
	value:        T,
	velocity:     T,
	has_velocity: bool,
	done:         bool,
}

/*
Completion becomes true when the value is close enough to the target and, for
velocity-aware motion, moving slowly enough to be considered at rest.
*/
Completion_Policy :: struct {
	distance_epsilon:     f32,
	rest_speed_threshold: f32,
	snap_to_target:       bool,
}

/*
Large frame times are split into deterministic substeps. The total effective dt
is capped to `max_dt * max_substeps`; negative dt never steps.
*/
Time_Policy :: struct {
	max_dt:       f32,
	max_substeps: int,
}

DEFAULT_DISTANCE_EPSILON :: f32(1e-4)
DEFAULT_REST_SPEED_THRESHOLD :: f32(1e-4)
DEFAULT_MAX_DT :: f32(1.0 / 30.0)
DEFAULT_MAX_SUBSTEPS :: 8

DEFAULT_COMPLETION_POLICY :: Completion_Policy {
	distance_epsilon     = DEFAULT_DISTANCE_EPSILON,
	rest_speed_threshold = DEFAULT_REST_SPEED_THRESHOLD,
	snap_to_target       = true,
}

DEFAULT_TIME_POLICY :: Time_Policy {
	max_dt       = DEFAULT_MAX_DT,
	max_substeps = DEFAULT_MAX_SUBSTEPS,
}

Substep_Plan :: struct {
	total_dt:   f32,
	substep_dt: f32,
	steps:      int,
}

value_result :: proc(value: $T, done: bool) -> Step_Result(T) {
	return Step_Result(T){value = value, velocity = {}, has_velocity = false, done = done}
}

motion_result :: proc(value, velocity: $T, done: bool) -> Step_Result(T) {
	return Step_Result(T){value = value, velocity = velocity, has_velocity = true, done = done}
}

/*
Returns the deterministic stepping plan for a frame in seconds.
*/
plan_substeps :: proc(dt: f32, policy: Time_Policy = DEFAULT_TIME_POLICY) -> Substep_Plan {
	safe_dt := sanitize_dt(dt)
	if safe_dt <= 0 || policy.max_dt <= 0 || policy.max_substeps <= 0 {
		return {}
	}

	max_total_dt := policy.max_dt * f32(policy.max_substeps)
	total_dt := math.min(safe_dt, max_total_dt)
	steps := int(math.ceil(total_dt / policy.max_dt))
	if steps < 1 do steps = 1

	return Substep_Plan{total_dt = total_dt, substep_dt = total_dt / f32(steps), steps = steps}
}

/*
True when the value is close enough to the target and the velocity, when
relevant, is slow enough to be treated as resting.
*/
is_done :: proc(
	distance_to_target: f32,
	speed: f32,
	policy: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> bool {
	return distance_to_target <= policy.distance_epsilon && speed <= policy.rest_speed_threshold
}

/*
Applies the package-wide completion snap rule.
*/
snap_if_done :: proc(
	value, target: $T,
	done: bool,
	policy: Completion_Policy = DEFAULT_COMPLETION_POLICY,
) -> T {
	if done && policy.snap_to_target {
		return target
	}
	return value
}
