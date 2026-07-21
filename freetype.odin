package oni

import "core:c"
import "core:math"

FT_Library :: distinct rawptr
FT_Face :: distinct rawptr
FT_GlyphSlot :: distinct rawptr
FT_Error :: c.int
FT_Pos :: c.long

FT_LOAD_DEFAULT :: 0
FT_LOAD_RENDER :: 1 << 2
FT_LOAD_NO_BITMAP :: 1 << 3

FT_RENDER_MODE_NORMAL :: 0

FT_PIXEL_MODE_MONO :: 1
FT_PIXEL_MODE_GRAY :: 2
FT_PIXEL_MODE_BGRA :: 7

FT_TAG_WGHT :: u32(0x77676874) // 'wght'
FT_TAG_OPSZ :: u32(0x6F70737A) // 'opsz'

FT_FACE_OFFSET_UNITS_PER_EM :: 136
FT_FACE_OFFSET_UNDERLINE_POSITION :: 148
FT_FACE_OFFSET_UNDERLINE_THICKNESS :: 150

FT_Glyph_Format :: enum c.int {
	BITMAP = 1651078259,
}

/*
FreeType bitmap layout matching the C FT_Bitmap struct.
*/
FT_Bitmap :: struct {
	rows:         c.uint,
	width:        c.uint,
	pitch:        c.int,
	buffer:       [^]c.uchar,
	num_grays:    c.ushort,
	pixel_mode:   c.uchar,
	palette_mode: c.uchar,
	palette:      rawptr,
}

FT_Fixed :: c.long
FT_Short :: c.short
FT_UShort :: c.ushort

/*
FreeType 2x2 affine transform matching the C FT_Matrix struct.
*/
FT_Matrix :: struct {
	xx, xy: FT_Fixed,
	yx, yy: FT_Fixed,
}

/*
FreeType 2D vector matching the C FT_Vector struct.
*/
FT_Vector :: struct {
	x, y: FT_Pos,
}

/*
One axis of a Multiple Master / variable font (FT_Var_Axis).
*/
FT_Var_Axis :: struct {
	name:    cstring,
	minimum: FT_Fixed,
	def:     FT_Fixed,
	maximum: FT_Fixed,
	tag:     c.ulong,
	strid:   c.uint,
}

/*
Variable font descriptor returned by FT_Get_MM_Var (partial layout).
*/
FT_MM_Var :: struct {
	num_axis:        c.uint,
	num_designs:     c.uint,
	num_namedstyles: c.uint,
	axis:            [^]FT_Var_Axis,
	namedstyle:      rawptr,
}

/*
FreeType generic pointer/finalizer pair matching the C FT_Generic struct.
*/
FT_Generic :: struct {
	data:      rawptr,
	finalizer: rawptr,
}

/*
FreeType size metrics matching the C FT_Size_Metrics struct.
*/
FT_Size_Metrics :: struct {
	x_ppem, y_ppem: c.ushort,
	x_scale, y_scale: FT_Fixed,
	ascender, descender, height, max_advance: FT_Pos,
}

/*
FreeType size record matching the C FT_SizeRec struct.
*/
FT_SizeRec :: struct {
	face:     FT_Face,
	generic:  FT_Generic,
	metrics:  FT_Size_Metrics,
	internal: rawptr,
}

/*
Opaque FreeType glyph slot record; layout is accessed via offsetof constants.
*/
FT_GlyphSlotRec :: struct {
	_data: [304]u8,
}

FT_FACE_OFFSET_GLYPH :: 152
FT_FACE_OFFSET_SIZE :: 160
FT_SLOT_OFFSET_FORMAT :: 144
FT_SLOT_OFFSET_BITMAP :: 152
FT_SLOT_OFFSET_BITMAP_LEFT :: 192
FT_SLOT_OFFSET_BITMAP_TOP :: 196
FT_SLOT_OFFSET_METRICS :: 48

/*
FreeType horizontal/vertical glyph metrics in 26.6 fixed-point pixels.
*/
FT_Glyph_Metrics :: struct {
	width, height:             FT_Pos,
	hori_bearing_x, hori_bearing_y: FT_Pos,
	hori_advance:              FT_Pos,
	vert_bearing_x, vert_bearing_y: FT_Pos,
	vert_advance:              FT_Pos,
}

when ODIN_OS == .Windows {
	foreign import lib "system:freetype.lib"
} else {
	foreign import lib "system:freetype"
}

@(default_calling_convention = "c", link_prefix = "FT_")
foreign lib {
	/*
	Initializes a FreeType library instance.

	Binds to FT_Init_FreeType in the system FreeType library.
	*/
	Init_FreeType :: proc(library: ^FT_Library) -> FT_Error ---

	/*
	Releases a FreeType library instance and its internal resources.

	Binds to FT_Done_FreeType.
	*/
	Done_FreeType :: proc(library: FT_Library) -> FT_Error ---

	/*
	Opens a font file and returns a new face at the given index.

	Binds to FT_New_Face.
	*/
	New_Face :: proc(
		library: FT_Library,
		filepathname: cstring,
		face_index: c.long,
		aface: ^FT_Face,
	) -> FT_Error ---

	/*
	Releases a face and all resources attached to it.

	Binds to FT_Done_Face.
	*/
	Done_Face :: proc(face: FT_Face) -> FT_Error ---

	/*
	Sets the target pixel width and height for glyph rasterization on a face.

	Binds to FT_Set_Pixel_Sizes.
	*/
	Set_Pixel_Sizes :: proc(face: FT_Face, pixel_width, pixel_height: c.uint) -> FT_Error ---

	/*
	Loads a glyph by index into the face's active glyph slot.

	Binds to FT_Load_Glyph; load_flags control hinting and rendering behavior.
	*/
	Load_Glyph :: proc(face: FT_Face, glyph_index: c.uint, load_flags: c.int) -> FT_Error ---

	/*
	Rasterizes the glyph currently loaded in the slot to a bitmap.

	Binds to FT_Render_Glyph.
	*/
	Render_Glyph :: proc(slot: ^FT_GlyphSlotRec, render_mode: c.int) -> FT_Error ---

	/*
	Queries Multiple Master / variable-font axis data for a face.

	Binds to FT_Get_MM_Var. Caller must release with Done_MM_Var.
	*/
	Get_MM_Var :: proc(face: FT_Face, amaster: ^^FT_MM_Var) -> FT_Error ---

	/*
	Frees an FT_MM_Var allocated by Get_MM_Var.

	Binds to FT_Done_MM_Var.
	*/
	Done_MM_Var :: proc(library: FT_Library, amaster: ^FT_MM_Var) -> FT_Error ---

	/*
	Sets design coordinates for all variable axes on a face.

	Binds to FT_Set_Var_Design_Coordinates. Values are 16.16 FT_Fixed.
	*/
	Set_Var_Design_Coordinates :: proc(
		face: FT_Face,
		num_coords: c.uint,
		coords: [^]FT_Fixed,
	) -> FT_Error ---

	/*
	Applies an affine transform to subsequent glyph loads on a face.

	Binds to FT_Set_Transform. Pass nil matrix/delta for identity.
	*/
	Set_Transform :: proc(face: FT_Face, xform: ^FT_Matrix, delta: ^FT_Vector) ---

	/*
	Emboldens the outline or bitmap currently in a glyph slot.

	Binds to FT_GlyphSlot_Embolden (synthetic bold).
	*/
	GlyphSlot_Embolden :: proc(slot: ^FT_GlyphSlotRec) ---
}

/*
Returns true when a FreeType error code indicates success (zero).
*/
ft_ok :: proc(err: FT_Error) -> bool {
	return err == 0
}

/*
Returns the active glyph slot for a face via known FT_FaceRec layout offsets.

Avoids linking against FreeType internal headers while still accessing the slot.
*/
ft_glyph_slot :: proc(face: FT_Face) -> ^FT_GlyphSlotRec {
	glyph_ptr := cast(^FT_GlyphSlot)(uintptr(face) + FT_FACE_OFFSET_GLYPH)
	return cast(^FT_GlyphSlotRec)glyph_ptr^
}

/*
Reads the glyph format field from a glyph slot using a fixed struct offset.
*/
ft_slot_format :: proc(slot: ^FT_GlyphSlotRec) -> FT_Glyph_Format {
	return (cast(^FT_Glyph_Format)(uintptr(slot) + FT_SLOT_OFFSET_FORMAT))^
}

/*
Returns a pointer to the bitmap sub-structure inside a glyph slot.
*/
ft_slot_bitmap :: proc(slot: ^FT_GlyphSlotRec) -> ^FT_Bitmap {
	return cast(^FT_Bitmap)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP)
}

/*
Reads the horizontal bitmap bearing (left) from a glyph slot in pixels.
*/
ft_slot_bitmap_left :: proc(slot: ^FT_GlyphSlotRec) -> c.int {
	return (cast(^c.int)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP_LEFT))^
}

/*
Reads the vertical bitmap bearing (top) from a glyph slot in pixels.
*/
ft_slot_bitmap_top :: proc(slot: ^FT_GlyphSlotRec) -> c.int {
	return (cast(^c.int)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP_TOP))^
}

/*
Returns the metrics sub-structure inside a glyph slot.
*/
ft_slot_metrics :: proc(slot: ^FT_GlyphSlotRec) -> ^FT_Glyph_Metrics {
	return cast(^FT_Glyph_Metrics)(uintptr(slot) + FT_SLOT_OFFSET_METRICS)
}

/*
Converts 26.6 FT_Pos to floating-point pixels.
*/
ft_pos_to_f32 :: proc(v: FT_Pos) -> f32 {
	return f32(v) / 64.0
}

/*
Returns size metrics for the active size on a face, or nil when unavailable.

Follows the FT_FaceRec size pointer at a known layout offset.
*/
ft_face_size_metrics :: proc(face: FT_Face) -> ^FT_Size_Metrics {
	size_ptr := cast(^^FT_SizeRec)(uintptr(face) + FT_FACE_OFFSET_SIZE)
	size := size_ptr^
	if size == nil do return nil
	return &size.metrics
}

/*
Reads units_per_EM from FT_FaceRec.
*/
ft_face_units_per_em :: proc(face: FT_Face) -> FT_UShort {
	return (cast(^FT_UShort)(uintptr(face) + FT_FACE_OFFSET_UNITS_PER_EM))^
}

/*
Reads underline_position (font units) from FT_FaceRec.
*/
ft_face_underline_position :: proc(face: FT_Face) -> FT_Short {
	return (cast(^FT_Short)(uintptr(face) + FT_FACE_OFFSET_UNDERLINE_POSITION))^
}

/*
Reads underline_thickness (font units) from FT_FaceRec.
*/
ft_face_underline_thickness :: proc(face: FT_Face) -> FT_Short {
	return (cast(^FT_Short)(uintptr(face) + FT_FACE_OFFSET_UNDERLINE_THICKNESS))^
}

/*
Converts a floating design coordinate to 16.16 FT_Fixed.
*/
ft_fixed_from_f32 :: proc(v: f32) -> FT_Fixed {
	return FT_Fixed(math.round(v * 65536.0))
}

/*
Converts 16.16 FT_Fixed to floating design coordinate.
*/
ft_fixed_to_f32 :: proc(v: FT_Fixed) -> f32 {
	return f32(v) / 65536.0
}
