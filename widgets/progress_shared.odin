package oni_widgets

import o ".."
import "core:fmt"
import "core:math"

PROGRESS_DEFAULT_MIN :: f32(0)
PROGRESS_DEFAULT_MAX :: f32(100)
PROGRESS_DEFAULT_TRACK_THICKNESS :: f32(4)
PROGRESS_DEFAULT_WIDTH :: f32(200)
PROGRESS_INDETERMINATE_RATIO :: f32(0.25)

/*
Completion status for a progress value, matching Base UI / shadcn semantics.
*/
Progress_Status :: enum {
	PROGRESSING,
	COMPLETE,
	INDETERMINATE,
}

@(private)
PROGRESS_CTX_STACK_MAX :: 16

/*
Live compound context pushed by `Progress` for Label / Value / Track / Indicator.
*/
@(private)
Progress_Ctx :: struct {
	value:           f32,
	min:             f32,
	max:             f32,
	ratio:           f32,
	indeterminate:   bool,
	inverted:        bool,
	disabled:        bool,
	status:          Progress_Status,
	track_thickness: f32,
	track_layout_id: o.UI_Id,
	track_rect:      o.Rect,
	parent_key:      string,
}

@(private)
progress_ctx_stack: [PROGRESS_CTX_STACK_MAX]Progress_Ctx

@(private)
progress_ctx_depth: int

/*
Releases progress context stack.

Called from widget `Shutdown`.
*/
progress_shutdown :: proc() {
	progress_ctx_depth = 0
	progress_ctx_stack = {}
}

@(private)
progress_ctx_push :: proc(ctx: Progress_Ctx) {
	assert(progress_ctx_depth < PROGRESS_CTX_STACK_MAX)
	progress_ctx_stack[progress_ctx_depth] = ctx
	progress_ctx_depth += 1
}

@(private)
progress_ctx_pop :: proc() {
	assert(progress_ctx_depth > 0)
	progress_ctx_depth -= 1
	progress_ctx_stack[progress_ctx_depth] = {}
}

@(private)
progress_ctx_ok :: proc() -> bool {
	return progress_ctx_depth > 0
}

@(private)
progress_ctx_top :: proc() -> ^Progress_Ctx {
	assert(progress_ctx_depth > 0)

	return &progress_ctx_stack[progress_ctx_depth - 1]
}

@(private)
progress_resolve_bounds :: proc(min_v, max_v: f32) -> (f32, f32) {
	lo := min_v
	hi := max_v

	if lo == 0 && hi == 0 {
		lo = PROGRESS_DEFAULT_MIN
		hi = PROGRESS_DEFAULT_MAX
	}

	if hi < lo {
		return hi, lo
	}

	return lo, hi
}

@(private)
progress_resolve_track_thickness :: proc(cfg: Progress_Config) -> f32 {
	return o.cfg_style_f32(cfg.track_thickness, PROGRESS_DEFAULT_TRACK_THICKNESS)
}

/*
Normalized 0..1 progress ratio for `value` within `[min_v, max_v]`.
*/
Progress_Ratio :: proc(value, min_v, max_v: f32) -> f32 {
	lo, hi := progress_resolve_bounds(min_v, max_v)
	span := hi - lo

	if span <= 0 {
		if value >= hi {
			return 1
		}

		return 0
	}

	return clamp((value - lo) / span, 0, 1)
}

/*
Status derived from value bounds and the indeterminate flag.
*/
Progress_Resolve_Status :: proc(value, min_v, max_v: f32, indeterminate: bool) -> Progress_Status {
	if indeterminate {
		return .INDETERMINATE
	}

	_, hi := progress_resolve_bounds(min_v, max_v)

	if value >= hi {
		return .COMPLETE
	}

	return .PROGRESSING
}

/*
Indicator fill rect inside a track for the given ratio / indeterminate / inverted flags.
*/
Progress_Indicator_Rect :: proc(
	track: o.Rect,
	ratio: f32,
	indeterminate: bool,
	inverted: bool,
) -> o.Rect {
	if track.w <= 0 || track.h <= 0 {
		return {}
	}

	fill_ratio := clamp(ratio, 0, 1)

	if indeterminate {
		fill_ratio = PROGRESS_INDETERMINATE_RATIO
	}

	w := track.w * fill_ratio

	if w <= 0 {
		return {}
	}

	if inverted {
		return {x = track.x + track.w - w, y = track.y, w = w, h = track.h}
	}

	return {x = track.x, y = track.y, w = w, h = track.h}
}

/*
Default value text: percent of the range, or empty when indeterminate.
*/
Progress_Format_Default :: proc(value: f32, min_v, max_v: f32, indeterminate: bool) -> string {
	if indeterminate {
		return ""
	}

	pct := int(math.round(f64(Progress_Ratio(value, min_v, max_v) * 100)))

	return fmt.tprintf("%d%%", pct)
}

@(private)
progress_part_id :: proc(parent_key, suffix: string) -> string {
	if parent_key == "" {
		return fmt.tprintf("progress-%s", suffix)
	}

	return fmt.tprintf("%s/%s", parent_key, suffix)
}

/*
Returns whether the active `Progress` root is indeterminate.
*/
Progress_Is_Indeterminate :: proc() -> bool {
	if !progress_ctx_ok() {
		return false
	}

	return progress_ctx_top().indeterminate
}

/*
Returns the active `Progress` root status.
*/
Progress_Current_Status :: proc() -> Progress_Status {
	if !progress_ctx_ok() {
		return .PROGRESSING
	}

	return progress_ctx_top().status
}

/*
Returns the active `Progress` root normalized ratio (0 when indeterminate).
*/
Progress_Current_Ratio :: proc() -> f32 {
	if !progress_ctx_ok() {
		return 0
	}

	ctx := progress_ctx_top()

	if ctx.indeterminate {
		return 0
	}

	return ctx.ratio
}
