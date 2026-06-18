package engine

import "core:c"

hb_font_t :: distinct rawptr
hb_buffer_t :: distinct rawptr
hb_bool_t :: c.int
hb_codepoint_t :: c.uint32_t
hb_position_t :: c.int32_t
hb_direction_t :: c.uint

HB_DIRECTION_INVALID :: hb_direction_t(0)
HB_DIRECTION_LTR :: hb_direction_t(4)
HB_DIRECTION_RTL :: hb_direction_t(5)

hb_var_int_t :: c.uint32_t

hb_glyph_info_t :: struct {
	codepoint: hb_codepoint_t,
	mask:      c.uint32_t,
	cluster:   c.uint32_t,
	var1:      hb_var_int_t,
	var2:      hb_var_int_t,
}

hb_glyph_position_t :: struct {
	x_advance: hb_position_t,
	y_advance: hb_position_t,
	x_offset:  hb_position_t,
	y_offset:  hb_position_t,
	var:       hb_var_int_t,
}

when ODIN_OS == .Windows {
	foreign import lib "system:harfbuzz.lib"
} else {
	foreign import lib "system:harfbuzz"
}

@(default_calling_convention = "c", link_prefix = "hb_")
foreign lib {
	buffer_create :: proc() -> hb_buffer_t ---
	buffer_destroy :: proc(buffer: hb_buffer_t) ---
	buffer_reset :: proc(buffer: hb_buffer_t) ---
	buffer_add_utf8 :: proc(
		buffer: hb_buffer_t,
		text: cstring,
		text_length: c.int,
		item_offset: c.uint,
		item_length: c.int,
	) ---
	buffer_set_direction :: proc(buffer: hb_buffer_t, direction: hb_direction_t) ---
	buffer_guess_segment_properties :: proc(buffer: hb_buffer_t) ---
	buffer_get_length :: proc(buffer: hb_buffer_t) -> c.uint ---
	buffer_get_glyph_infos :: proc(buffer: hb_buffer_t, length: ^c.uint) -> [^]hb_glyph_info_t ---
	buffer_get_glyph_positions :: proc(
		buffer: hb_buffer_t,
		length: ^c.uint,
	) -> [^]hb_glyph_position_t ---

	shape :: proc(
		font: hb_font_t,
		buffer: hb_buffer_t,
		features: rawptr,
		num_features: c.uint,
	) -> hb_bool_t ---
	font_destroy :: proc(font: hb_font_t) ---

	ft_font_create_referenced :: proc(ft_face: FT_Face) -> hb_font_t ---
}

hb_to_direction :: proc(direction: Text_Direction) -> hb_direction_t {
	switch direction {
	case .LTR:
		return HB_DIRECTION_LTR
	case .RTL:
		return HB_DIRECTION_RTL
	}
	return HB_DIRECTION_LTR
}

hb_pos_to_px :: proc(v: hb_position_t) -> f32 {
	return f32(v) / 64.0
}
