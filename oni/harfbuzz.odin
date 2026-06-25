package oni

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

/*
HarfBuzz glyph info entry matching the C hb_glyph_info_t struct.
*/
hb_glyph_info_t :: struct {
	codepoint: hb_codepoint_t,
	mask:      c.uint32_t,
	cluster:   c.uint32_t,
	var1:      hb_var_int_t,
	var2:      hb_var_int_t,
}

/*
HarfBuzz glyph position entry matching the C hb_glyph_position_t struct.
*/
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
	/*
	Allocates a new HarfBuzz shaping buffer.

	Binds to hb_buffer_create.
	*/
	buffer_create :: proc() -> hb_buffer_t ---

	/*
	Releases a shaping buffer and its contents.

	Binds to hb_buffer_destroy.
	*/
	buffer_destroy :: proc(buffer: hb_buffer_t) ---

	/*
	Clears all text and shaping state from a buffer for reuse.

	Binds to hb_buffer_reset.
	*/
	buffer_reset :: proc(buffer: hb_buffer_t) ---

	/*
	Appends a UTF-8 text run to a shaping buffer.

	Binds to hb_buffer_add_utf8.
	*/
	buffer_add_utf8 :: proc(
		buffer: hb_buffer_t,
		text: cstring,
		text_length: c.int,
		item_offset: c.uint,
		item_length: c.int,
	) ---

	/*
	Sets the base text direction on a shaping buffer.

	Binds to hb_buffer_set_direction.
	*/
	buffer_set_direction :: proc(buffer: hb_buffer_t, direction: hb_direction_t) ---

	/*
	Infers script, language, and direction from buffer content when possible.

	Binds to hb_buffer_guess_segment_properties.
	*/
	buffer_guess_segment_properties :: proc(buffer: hb_buffer_t) ---

	/*
	Returns the number of glyph infos currently stored in the buffer.

	Binds to hb_buffer_get_length.
	*/
	buffer_get_length :: proc(buffer: hb_buffer_t) -> c.uint ---

	/*
	Returns shaped glyph info records and writes the count through length.

	Binds to hb_buffer_get_glyph_infos.
	*/
	buffer_get_glyph_infos :: proc(buffer: hb_buffer_t, length: ^c.uint) -> [^]hb_glyph_info_t ---

	/*
	Returns shaped glyph position records and writes the count through length.

	Binds to hb_buffer_get_glyph_positions.
	*/
	buffer_get_glyph_positions :: proc(
		buffer: hb_buffer_t,
		length: ^c.uint,
	) -> [^]hb_glyph_position_t ---

	/*
	Runs HarfBuzz shaping on the buffer using the given font.

	Binds to hb_shape; returns non-zero on success.
	*/
	shape :: proc(
		font: hb_font_t,
		buffer: hb_buffer_t,
		features: rawptr,
		num_features: c.uint,
	) -> hb_bool_t ---

	/*
	Releases a HarfBuzz font object.

	Binds to hb_font_destroy.
	*/
	font_destroy :: proc(font: hb_font_t) ---

	/*
	Creates a HarfBuzz font that references an existing FreeType face.

	Binds to hb_ft_font_create_referenced; does not take ownership of the face.
	*/
	ft_font_create_referenced :: proc(ft_face: FT_Face) -> hb_font_t ---
}

/*
Maps oni Text_Direction to the corresponding HarfBuzz direction constant.
*/
hb_to_direction :: proc(direction: Text_Direction) -> hb_direction_t {
	switch direction {
	case .LTR:
		return HB_DIRECTION_LTR
	case .RTL:
		return HB_DIRECTION_RTL
	}
	return HB_DIRECTION_LTR
}

/*
Converts a HarfBuzz 26.6 fixed-point position value to logical pixels.
*/
hb_pos_to_px :: proc(v: hb_position_t) -> f32 {
	return f32(v) / 64.0
}
