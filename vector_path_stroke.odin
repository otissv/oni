package oni

import v "./vector"
import "core:hash"
import "core:mem"

Vector_Path_Op :: enum u8 {
	Fill,
	Stroke,
}

Vector_Stroke :: v.Stroke
Vector_Line_Cap :: v.Line_Cap
Vector_Line_Join :: v.Line_Join
Vector_Default_Stroke :: v.DEFAULT_STROKE

@(private)
vector_stroke_same :: proc(a, b: Vector_Stroke) -> bool {
	if a.width != b.width ||
	   a.cap != b.cap ||
	   a.join != b.join ||
	   a.miter_limit != b.miter_limit ||
	   a.dash_offset != b.dash_offset ||
	   a.path_length != b.path_length ||
	   a.non_scaling != b.non_scaling ||
	   len(a.dash) != len(b.dash) {
		return false
	}

	for value, i in a.dash {
		if value != b.dash[i] {
			return false
		}
	}

	return true
}

@(private)
vector_stroke_fingerprint :: proc(op: Vector_Path_Op, stroke: Vector_Stroke, morph: Vector_Transform = Vector_Identity) -> [2]u64 {
	if op != .Stroke {
		return {}
	}

	// Fixed layout of every stroke/morph scalar, then the dash array. Two FNV
	// streams with different seeds keep batch miss-map collisions negligible.
	header := [14]u64{
		transmute(u64)stroke.width,
		u64(stroke.cap),
		u64(stroke.join),
		transmute(u64)stroke.miter_limit,
		transmute(u64)stroke.dash_offset,
		transmute(u64)stroke.path_length,
		1 if stroke.non_scaling else 0,
		u64(len(stroke.dash)),
		transmute(u64)morph[0],
		transmute(u64)morph[1],
		transmute(u64)morph[2],
		transmute(u64)morph[3],
		transmute(u64)morph[4],
		transmute(u64)morph[5],
	}
	h0 := hash.fnv64a(mem.slice_to_bytes(header[:]))
	h0 = hash.fnv64a(mem.slice_to_bytes(stroke.dash), h0)

	seeded := header
	seeded[0] ~= 0x9e3779b97f4a7c15
	h1 := hash.fnv64a(mem.slice_to_bytes(seeded[:]))
	h1 = hash.fnv64a(mem.slice_to_bytes(stroke.dash), h1)

	return {h0, h1}
}

@(private)
vector_stroke_draw_morph :: proc(entry: ^Vector_Path_Entry, instance_morph: Vector_Transform) -> Vector_Transform {
	morph := vector_path_normalize_morph(instance_morph)
	if entry == nil {
		return morph
	}

	return v.Affine_Compose(entry.morph, morph)
}

@(private)
vector_stroke_tess_transform :: proc(linear: [4]f64, morph: Vector_Transform) -> Vector_Transform {
	linear_affine := Vector_Transform{linear[0], linear[1], linear[2], linear[3], 0, 0}
	if morph == Vector_Identity {
		return linear_affine
	}

	return v.Affine_Compose(linear_affine, morph)
}

@(private)
vector_stroke_copy_dash :: proc(stroke: Vector_Stroke, allocator: mem.Allocator) -> (Vector_Stroke, Vector_Error) {
	out := stroke
	out.dash = nil
	if len(stroke.dash) == 0 {
		return out, .None
	}

	owned, err := make([]f64, len(stroke.dash), allocator)
	if err != nil {
		return {}, .Allocation_Failed
	}

	copy(owned, stroke.dash)
	out.dash = owned

	return out, .None
}

@(private)
vector_stroke_release_dash :: proc(stroke: ^Vector_Stroke, allocator := context.allocator) {
	if stroke == nil || stroke.dash == nil {
		return
	}

	owner := allocator
	if owner.procedure == nil { owner = context.allocator }
	delete(stroke.dash, owner)
	stroke.dash = nil
}

@(private)
vector_stroke_validate_draw :: proc(op: Vector_Path_Op, #by_ptr stroke: Vector_Stroke) -> Vector_Error {
	if op == .Fill {
		return .None
	}

	if err := v.Validate_Stroke(stroke); err != .None {
		return vector_path_error(err)
	}

	if stroke.width == 0 {
		return .Invalid_Value
	}

	return .None
}
