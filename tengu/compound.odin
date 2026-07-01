package tengu

import "core:math"

/*
Type-erased field operations for building compound Animatable adapters without
runtime reflection. Each field is animated independently; compound distance is
the Euclidean norm of per-field distances.

Because Odin procedure values cannot close over local state, each compound type
declares a module-local `[N]Compound_Field_Entry` table and binds top-level
procedures with `compound_bind`.
*/
Compound_Field_Entry :: struct {
	offset:       uintptr,
	size:         int,
	has_velocity: bool,
	zero:         proc(dst: rawptr),
	add:          proc(dst, a, b: rawptr),
	sub:          proc(dst, a, b: rawptr),
	scale:        proc(dst, src: rawptr, s: f32),
	mix:          proc(dst, a, b: rawptr, t: f32),
	distance:     proc(a, b: rawptr) -> f32,
}

compound_field_ptr :: proc(parent: rawptr, offset: uintptr) -> rawptr {
	return rawptr(uintptr(parent) + offset)
}

compound_entry_f32 :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(f32),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^f32)(dst)^ = f32_zero()},
		add = proc(dst, a, b: rawptr) {(^f32)(dst)^ = add_f32((^f32)(a)^, (^f32)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^f32)(dst)^ = sub_f32((^f32)(a)^, (^f32)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^f32)(dst)^ = scale_f32((^f32)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^f32)(dst)^ = mix_f32((^f32)(a)^, (^f32)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_f32((^f32)(a)^, (^f32)(b)^)},
	}
}

compound_entry_vec2 :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(Vec2),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^Vec2)(dst)^ = vec2_zero()},
		add = proc(dst, a, b: rawptr) {(^Vec2)(dst)^ = add_vec2((^Vec2)(a)^, (^Vec2)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^Vec2)(dst)^ = sub_vec2((^Vec2)(a)^, (^Vec2)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^Vec2)(dst)^ = scale_vec2((^Vec2)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^Vec2)(dst)^ = mix_vec2((^Vec2)(a)^, (^Vec2)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_vec2((^Vec2)(a)^, (^Vec2)(b)^)},
	}
}

compound_entry_vec3 :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(Vec3),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^Vec3)(dst)^ = vec3_zero()},
		add = proc(dst, a, b: rawptr) {(^Vec3)(dst)^ = add_vec3((^Vec3)(a)^, (^Vec3)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^Vec3)(dst)^ = sub_vec3((^Vec3)(a)^, (^Vec3)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^Vec3)(dst)^ = scale_vec3((^Vec3)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^Vec3)(dst)^ = mix_vec3((^Vec3)(a)^, (^Vec3)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_vec3((^Vec3)(a)^, (^Vec3)(b)^)},
	}
}

compound_entry_vec4 :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(Vec4),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^Vec4)(dst)^ = vec4_zero()},
		add = proc(dst, a, b: rawptr) {(^Vec4)(dst)^ = add_vec4((^Vec4)(a)^, (^Vec4)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^Vec4)(dst)^ = sub_vec4((^Vec4)(a)^, (^Vec4)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^Vec4)(dst)^ = scale_vec4((^Vec4)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^Vec4)(dst)^ = mix_vec4((^Vec4)(a)^, (^Vec4)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_vec4((^Vec4)(a)^, (^Vec4)(b)^)},
	}
}

compound_entry_rgba :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(RGBA),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^RGBA)(dst)^ = rgba_zero()},
		add = proc(dst, a, b: rawptr) {(^RGBA)(dst)^ = add_rgba((^RGBA)(a)^, (^RGBA)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^RGBA)(dst)^ = sub_rgba((^RGBA)(a)^, (^RGBA)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^RGBA)(dst)^ = scale_rgba((^RGBA)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^RGBA)(dst)^ = mix_rgba((^RGBA)(a)^, (^RGBA)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_rgba((^RGBA)(a)^, (^RGBA)(b)^)},
	}
}

compound_entry_rect :: proc(offset: uintptr) -> Compound_Field_Entry {
	return {
		offset = offset,
		size = size_of(Rect),
		has_velocity = true,
		zero = proc(dst: rawptr) {(^Rect)(dst)^ = rect_zero()},
		add = proc(dst, a, b: rawptr) {(^Rect)(dst)^ = add_rect((^Rect)(a)^, (^Rect)(b)^)},
		sub = proc(dst, a, b: rawptr) {(^Rect)(dst)^ = sub_rect((^Rect)(a)^, (^Rect)(b)^)},
		scale = proc(dst, src: rawptr, s: f32) {(^Rect)(dst)^ = scale_rect((^Rect)(src)^, s)},
		mix = proc(dst, a, b: rawptr, t: f32) {(^Rect)(dst)^ = mix_rect((^Rect)(a)^, (^Rect)(b)^, t)},
		distance = proc(a, b: rawptr) -> f32 {return distance_rect((^Rect)(a)^, (^Rect)(b)^)},
	}
}

compound_entries_have_velocity :: proc(entries: []Compound_Field_Entry) -> bool {
	for entry in entries {
		if !entry.has_velocity do return false
	}
	return true
}

compound_zero :: proc($T: typeid, entries: []Compound_Field_Entry) -> T {
	result: T
	for entry in entries {
		entry.zero(compound_field_ptr(&result, entry.offset))
	}
	return result
}

compound_add :: proc(a, b: $T, entries: []Compound_Field_Entry) -> T {
	a_value := a
	b_value := b
	result: T
	for entry in entries {
		entry.add(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
		)
	}
	return result
}

compound_sub :: proc(a, b: $T, entries: []Compound_Field_Entry) -> T {
	a_value := a
	b_value := b
	result: T
	for entry in entries {
		entry.sub(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
		)
	}
	return result
}

compound_scale :: proc(v: $T, s: f32, entries: []Compound_Field_Entry) -> T {
	v_value := v
	result: T
	for entry in entries {
		entry.scale(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&v_value, entry.offset),
			s,
		)
	}
	return result
}

compound_mix :: proc(a, b: $T, t: f32, entries: []Compound_Field_Entry) -> T {
	a_value := a
	b_value := b
	result: T
	for entry in entries {
		entry.mix(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
			t,
		)
	}
	return result
}

compound_distance :: proc(a, b: $T, entries: []Compound_Field_Entry) -> f32 {
	a_value := a
	b_value := b
	sum_sq: f32 = 0
	for entry in entries {
		d := entry.distance(
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
		)
		sum_sq += d * d
	}
	return math.sqrt(sum_sq)
}

/*
Binds top-level compound procedures into an Animatable adapter.
*/
compound_bind :: proc(
	zero: proc() -> $T,
	add: proc(a, b: T) -> T,
	sub: proc(a, b: T) -> T,
	scale: proc(v: T, s: f32) -> T,
	mix: proc(a, b: T, t: f32) -> T,
	distance: proc(a, b: T) -> f32,
	velocity_support: Velocity_Support,
) -> Animatable(T) {
	return Animatable(T) {
		zero             = zero,
		add              = add,
		sub              = sub,
		scale            = scale,
		mix              = mix,
		distance         = distance,
		velocity_support = velocity_support,
	}
}

/*
Reference compound type used in tests and documentation.
*/
Panel_Style :: struct {
	opacity: f32,
	offset:  Vec2,
	scale:   f32,
}

panel_style_entries :: proc() -> [3]Compound_Field_Entry {
	return {
		compound_entry_f32(offset_of(Panel_Style, opacity)),
		compound_entry_vec2(offset_of(Panel_Style, offset)),
		compound_entry_f32(offset_of(Panel_Style, scale)),
	}
}

panel_style_zero :: proc() -> Panel_Style {
	entries := panel_style_entries()
	return compound_zero(Panel_Style, entries[:])
}

panel_style_add :: proc(a, b: Panel_Style) -> Panel_Style {
	entries := panel_style_entries()
	return compound_add(a, b, entries[:])
}

panel_style_sub :: proc(a, b: Panel_Style) -> Panel_Style {
	entries := panel_style_entries()
	return compound_sub(a, b, entries[:])
}

panel_style_scale :: proc(v: Panel_Style, s: f32) -> Panel_Style {
	entries := panel_style_entries()
	return compound_scale(v, s, entries[:])
}

panel_style_mix :: proc(a, b: Panel_Style, t: f32) -> Panel_Style {
	entries := panel_style_entries()
	return compound_mix(a, b, t, entries[:])
}

panel_style_distance :: proc(a, b: Panel_Style) -> f32 {
	entries := panel_style_entries()
	return compound_distance(a, b, entries[:])
}

Panel_Style_Animatable :: proc() -> Animatable(Panel_Style) {
	entries := panel_style_entries()
	return compound_bind(
		panel_style_zero,
		panel_style_add,
		panel_style_sub,
		panel_style_scale,
		panel_style_mix,
		panel_style_distance,
		compound_entries_have_velocity(entries[:]) ? .VALUE_TYPE : .NONE,
	)
}
