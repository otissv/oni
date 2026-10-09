package oni

import "core:math"

SLIDER_MAX_THUMBS :: 2
SLIDER_DEFAULT_MIN :: f32(0)
SLIDER_DEFAULT_MAX :: f32(100)
SLIDER_DEFAULT_STEP :: f32(1)
SLIDER_DEFAULT_THUMB_SIZE :: f32(16)
SLIDER_DEFAULT_TRACK_THICKNESS :: f32(6)
SLIDER_DEFAULT_WIDTH :: f32(200)
SLIDER_DEFAULT_HEIGHT :: f32(20)

/*
Normalizes a slider range so min <= max.
*/
slider_normalize_bounds :: proc(min_v, max_v: f32) -> (f32, f32) {
	if max_v < min_v {
		return max_v, min_v
	}

	return min_v, max_v
}

/*
Returns a finite step used for snapping and keyboard increments.

Non-positive `step` means continuous values (no snap); keyboard still nudges by
1% of the span (or 1 when the span is zero).
*/
slider_effective_step :: proc(min_v, max_v, step: f32) -> f32 {
	lo, hi := slider_normalize_bounds(min_v, max_v)

	if step > 0 {
		return step
	}

	span := hi - lo

	if span <= 0 {
		return 1
	}

	return span * 0.01
}

/*
Snaps `value` into [min, max] on `step` boundaries.

When `step <= 0`, only clamping is applied.
*/
slider_snap :: proc(value, min_v, max_v, step: f32) -> f32 {
	lo, hi := slider_normalize_bounds(min_v, max_v)
	v := clamp(value, lo, hi)

	if step <= 0 {
		return v
	}

	n := math.round((v - lo) / step)

	return clamp(lo + n * step, lo, hi)
}

/*
Maps a normalized track position `t` in [0, 1] to a value in [min, max].
*/
slider_value_from_t :: proc(t, min_v, max_v: f32, inverted: bool) -> f32 {
	lo, hi := slider_normalize_bounds(min_v, max_v)
	nt := clamp(t, 0, 1)

	if inverted {
		nt = 1 - nt
	}

	return lo + nt * (hi - lo)
}

/*
Maps a value in [min, max] to a normalized track position `t` in [0, 1].
*/
slider_t_from_value :: proc(value, min_v, max_v: f32, inverted: bool) -> f32 {
	lo, hi := slider_normalize_bounds(min_v, max_v)
	span := hi - lo

	if span <= 0 {
		return inverted ? 1 : 0
	}

	t := clamp((value - lo) / span, 0, 1)

	if inverted {
		return 1 - t
	}

	return t
}

/*
Maps a pointer position along the track to a normalized `t` in [0, 1].

`grab_offset` is the pointer offset from the thumb's leading edge (left/top).
*/
slider_t_from_pointer :: proc(
	pointer, track_origin, track_len, thumb_size, grab_offset: f32,
) -> f32 {
	if track_len <= 0 {
		return 0
	}

	if track_len <= thumb_size {
		return 0
	}

	travel := track_len - thumb_size
	pos := pointer - track_origin - grab_offset

	return clamp(pos / travel, 0, 1)
}

/*
Thumb leading-edge offset along the track for a normalized `t`.
*/
slider_thumb_pos_from_t :: proc(track_len, thumb_size, t: f32) -> f32 {
	if track_len <= 0 {
		return 0
	}

	size := clamp(thumb_size, 0, track_len)
	travel := track_len - size

	return clamp(t, 0, 1) * travel
}

/*
Minimum gap between adjacent thumbs from `min_steps_between_thumbs` and `step`.
*/
slider_min_thumb_gap :: proc(step, min_steps_between_thumbs: f32) -> f32 {
	if min_steps_between_thumbs <= 0 {
		return 0
	}

	unit := step > 0 ? step : 1

	return min_steps_between_thumbs * unit
}

/*
Copies caller values into a fixed buffer, clamping count to [0, SLIDER_MAX_THUMBS].
*/
slider_copy_values :: proc(values: []f32, out: ^[SLIDER_MAX_THUMBS]f32) -> int {
	if out == nil {
		return 0
	}

	n := len(values)

	if n <= 0 {
		return 0
	}

	if n > SLIDER_MAX_THUMBS {
		n = SLIDER_MAX_THUMBS
	}

	for i in 0 ..< n {
		out[i] = values[i]
	}

	return n
}

/*
Clamps, snaps, and enforces min-gap / ordering on a working value buffer.
*/
slider_normalize_values :: proc(
	values: ^[SLIDER_MAX_THUMBS]f32,
	count: int,
	min_v, max_v, step, min_steps_between_thumbs: f32,
) -> int {
	if values == nil || count <= 0 {
		return 0
	}

	n := count

	if n > SLIDER_MAX_THUMBS {
		n = SLIDER_MAX_THUMBS
	}

	lo, hi := slider_normalize_bounds(min_v, max_v)
	gap := slider_min_thumb_gap(step, min_steps_between_thumbs)

	for i in 0 ..< n {
		values[i] = slider_snap(values[i], lo, hi, step)
	}

	if n >= 2 {
		if values[0] > values[1] {
			values[0], values[1] = values[1], values[0]
		}

		if gap > 0 && values[1] - values[0] < gap {
			mid := slider_snap((values[0] + values[1]) * 0.5, lo, hi, step)
			values[0] = slider_snap(mid - gap * 0.5, lo, hi, step)
			values[1] = slider_snap(values[0] + gap, lo, hi, step)

			if values[1] > hi {
				values[1] = hi
				values[0] = slider_snap(values[1] - gap, lo, hi, step)
			}

			if values[0] < lo {
				values[0] = lo
				values[1] = slider_snap(values[0] + gap, lo, hi, step)
			}
		}
	}

	return n
}

/*
Applies a new value to one thumb, preserving ordering and min-gap constraints.
*/
slider_set_thumb_value :: proc(
	values: ^[SLIDER_MAX_THUMBS]f32,
	count: int,
	thumb_index: int,
	raw: f32,
	min_v, max_v, step, min_steps_between_thumbs: f32,
) -> bool {
	if values == nil || count <= 0 {
		return false
	}

	n := count

	if n > SLIDER_MAX_THUMBS {
		n = SLIDER_MAX_THUMBS
	}

	idx := thumb_index

	if idx < 0 || idx >= n {
		return false
	}

	lo, hi := slider_normalize_bounds(min_v, max_v)
	gap := slider_min_thumb_gap(step, min_steps_between_thumbs)
	next := slider_snap(raw, lo, hi, step)

	if idx > 0 {
		floor := values[idx - 1] + gap
		if next < floor {
			next = slider_snap(floor, lo, hi, step)
		}
	}

	if idx + 1 < n {
		ceil := values[idx + 1] - gap
		if next > ceil {
			next = slider_snap(ceil, lo, hi, step)
		}
	}

	if next == values[idx] {
		return false
	}

	values[idx] = next

	return true
}

/*
Picks the thumb nearest to a normalized track position `t`.
*/
slider_nearest_thumb :: proc(
	values: [SLIDER_MAX_THUMBS]f32,
	count: int,
	t: f32,
	min_v, max_v: f32,
	inverted: bool,
) -> int {
	if count <= 0 {
		return 0
	}

	if count == 1 {
		return 0
	}

	best := 0
	best_dist := abs(slider_t_from_value(values[0], min_v, max_v, inverted) - t)

	for i in 1 ..< count {
		dist := abs(slider_t_from_value(values[i], min_v, max_v, inverted) - t)

		if dist < best_dist {
			best = i
			best_dist = dist
		}
	}

	return best
}

/*
Keyboard page increment: at least one step, otherwise ~10% of the span.
*/
slider_page_delta :: proc(min_v, max_v, step: f32) -> f32 {
	lo, hi := slider_normalize_bounds(min_v, max_v)
	unit := slider_effective_step(lo, hi, step)
	span := hi - lo

	if span <= 0 {
		return unit
	}

	return max(unit, span * 0.1)
}

/*
Returns existing slider drag state for a layout id, or nil.
*/
slider_drag_get :: proc(id: UI_Id) -> ^Slider_Drag {
	if state == nil || state.ui.slider_drags == nil {
		return nil
	}

	if _, ok := state.ui.slider_drags[id]; !ok {
		return nil
	}

	return &state.ui.slider_drags[id]
}

/*
Returns or creates slider drag state for a layout id.
*/
slider_drag_entry :: proc(id: UI_Id) -> ^Slider_Drag {
	if state == nil {
		return nil
	}

	if state.ui.slider_drags == nil {
		state.ui.slider_drags = make(map[UI_Id]Slider_Drag)
	}

	if _, ok := state.ui.slider_drags[id]; !ok {
		state.ui.slider_drags[id] = {}
	}

	return &state.ui.slider_drags[id]
}

/*
Clears active drag for a layout id while retaining the last thumb index.
*/
slider_drag_end :: proc(id: UI_Id) {
	drag := slider_drag_entry(id)

	if drag == nil {
		return
	}

	drag.active = false
	drag.grab_offset = 0
}

/*
Removes slider drag state for a layout id.
*/
slider_drag_clear :: proc(id: UI_Id) {
	if state == nil || state.ui.slider_drags == nil {
		return
	}

	delete_key(&state.ui.slider_drags, id)
}

/*
Stores the slider root rect after layout so the next frame can place custom thumbs.
*/
slider_root_rect_store :: proc(id: UI_Id, rect: Rect) {
	if state == nil {
		return
	}

	if state.ui.slider_root_rects == nil {
		state.ui.slider_root_rects = make(map[UI_Id]Rect)
	}

	state.ui.slider_root_rects[id] = rect
}

/*
Returns the cached slider root rect from the previous frame, if any.
*/
slider_root_rect_get :: proc(id: UI_Id) -> (Rect, bool) {
	if state == nil || state.ui.slider_root_rects == nil {
		return {}, false
	}

	rect, ok := state.ui.slider_root_rects[id]

	return rect, ok
}

/*
Removes a cached slider root rect.
*/
slider_root_rect_clear :: proc(id: UI_Id) {
	if state == nil || state.ui.slider_root_rects == nil {
		return
	}

	delete_key(&state.ui.slider_root_rects, id)
}

@(private)
slider_shutdown :: proc() {
	if state == nil {
		return
	}

	if state.ui.slider_drags != nil {
		delete(state.ui.slider_drags)
		state.ui.slider_drags = nil
	}

	if state.ui.slider_root_rects != nil {
		delete(state.ui.slider_root_rects)
		state.ui.slider_root_rects = nil
	}
}
