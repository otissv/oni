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
Compound_Mix_Params :: struct {
	dst, a, b: rawptr,
	t:         f32,
}

Compound_Add_Params :: struct($T: typeid) {
	a, b:      T,
	entries:   []Compound_Field_Entry,
}

Compound_Sub_Params :: struct($T: typeid) {
	a, b:      T,
	entries:   []Compound_Field_Entry,
}

Compound_Scale_Params :: struct($T: typeid) {
	v:         T,
	s:         f32,
	entries:   []Compound_Field_Entry,
}

Compound_Mix_Ops_Params :: struct($T: typeid) {
	a, b:      T,
	t:         f32,
	entries:   []Compound_Field_Entry,
}

Compound_Distance_Params :: struct($T: typeid) {
	a, b:      T,
	entries:   []Compound_Field_Entry,
}

Compound_Bind_Params :: struct($T: typeid) {
	zero:             proc() -> T,
	add:              proc(a, b: T) -> T,
	sub:              proc(a, b: T) -> T,
	scale:            proc(v: T, s: f32) -> T,
	mix:              proc(p: Mix_Params(T)) -> T,
	distance:         proc(a, b: T) -> f32,
	velocity_support: Velocity_Support,
}

Compound_Field_Entry :: struct {
	offset:       uintptr,
	size:         int,
	has_velocity: bool,
	zero:         proc(dst: rawptr),
	add:          proc(dst, a, b: rawptr),
	sub:          proc(dst, a, b: rawptr),
	scale:        proc(dst, src: rawptr, s: f32),
	mix:          proc(p: Compound_Mix_Params),
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
		mix = proc(p: Compound_Mix_Params) {
			(^f32)(p.dst)^ = mix_f32(Mix_Params(f32){a = (^f32)(p.a)^, b = (^f32)(p.b)^, t = p.t})
		},
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
		mix = proc(p: Compound_Mix_Params) {
			(^Vec2)(p.dst)^ = mix_vec2(Mix_Params(Vec2){a = (^Vec2)(p.a)^, b = (^Vec2)(p.b)^, t = p.t})
		},
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
		mix = proc(p: Compound_Mix_Params) {
			(^Vec3)(p.dst)^ = mix_vec3(Mix_Params(Vec3){a = (^Vec3)(p.a)^, b = (^Vec3)(p.b)^, t = p.t})
		},
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
		mix = proc(p: Compound_Mix_Params) {
			(^Vec4)(p.dst)^ = mix_vec4(Mix_Params(Vec4){a = (^Vec4)(p.a)^, b = (^Vec4)(p.b)^, t = p.t})
		},
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
		mix = proc(p: Compound_Mix_Params) {
			(^RGBA)(p.dst)^ = mix_rgba(Mix_Params(RGBA){a = (^RGBA)(p.a)^, b = (^RGBA)(p.b)^, t = p.t})
		},
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
		mix = proc(p: Compound_Mix_Params) {
			(^Rect)(p.dst)^ = mix_rect(Mix_Params(Rect){a = (^Rect)(p.a)^, b = (^Rect)(p.b)^, t = p.t})
		},
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

compound_add :: proc(p: Compound_Add_Params($T)) -> T {
	a_value := p.a
	b_value := p.b
	result: T
	for entry in p.entries {
		entry.add(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
		)
	}
	return result
}

compound_sub :: proc(p: Compound_Sub_Params($T)) -> T {
	a_value := p.a
	b_value := p.b
	result: T
	for entry in p.entries {
		entry.sub(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&a_value, entry.offset),
			compound_field_ptr(&b_value, entry.offset),
		)
	}
	return result
}

compound_scale :: proc(p: Compound_Scale_Params($T)) -> T {
	v_value := p.v
	result: T
	for entry in p.entries {
		entry.scale(
			compound_field_ptr(&result, entry.offset),
			compound_field_ptr(&v_value, entry.offset),
			p.s,
		)
	}
	return result
}

compound_mix :: proc(p: Compound_Mix_Ops_Params($T)) -> T {
	a_value := p.a
	b_value := p.b
	result: T
	for entry in p.entries {
		entry.mix(Compound_Mix_Params{
			dst = compound_field_ptr(&result, entry.offset),
			a = compound_field_ptr(&a_value, entry.offset),
			b = compound_field_ptr(&b_value, entry.offset),
			t = p.t,
		})
	}
	return result
}

compound_distance :: proc(p: Compound_Distance_Params($T)) -> f32 {
	a_value := p.a
	b_value := p.b
	sum_sq: f32 = 0
	for entry in p.entries {
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
compound_bind :: proc(p: Compound_Bind_Params($T)) -> Animatable(T) {
	return Animatable(T) {
		zero             = p.zero,
		add              = p.add,
		sub              = p.sub,
		scale            = p.scale,
		mix              = p.mix,
		distance         = p.distance,
		velocity_support = p.velocity_support,
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
	return compound_add(Compound_Add_Params(Panel_Style){a = a, b = b, entries = entries[:]})
}

panel_style_sub :: proc(a, b: Panel_Style) -> Panel_Style {
	entries := panel_style_entries()
	return compound_sub(Compound_Sub_Params(Panel_Style){a = a, b = b, entries = entries[:]})
}

panel_style_scale :: proc(v: Panel_Style, s: f32) -> Panel_Style {
	entries := panel_style_entries()
	return compound_scale(Compound_Scale_Params(Panel_Style){v = v, s = s, entries = entries[:]})
}

panel_style_mix :: proc(p: Mix_Params(Panel_Style)) -> Panel_Style {
	entries := panel_style_entries()
	return compound_mix(Compound_Mix_Ops_Params(Panel_Style){a = p.a, b = p.b, t = p.t, entries = entries[:]})
}

panel_style_distance :: proc(a, b: Panel_Style) -> f32 {
	entries := panel_style_entries()
	return compound_distance(Compound_Distance_Params(Panel_Style){a = a, b = b, entries = entries[:]})
}

Panel_Style_Animatable :: proc() -> Animatable(Panel_Style) {
	entries := panel_style_entries()
	return compound_bind(Compound_Bind_Params(Panel_Style){
		zero = panel_style_zero,
		add = panel_style_add,
		sub = panel_style_sub,
		scale = panel_style_scale,
		mix = panel_style_mix,
		distance = panel_style_distance,
		velocity_support = compound_entries_have_velocity(entries[:]) ? .VALUE_TYPE : .NONE,
	})
}
