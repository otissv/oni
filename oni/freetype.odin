package oni

import "core:c"

FT_Library :: distinct rawptr
FT_Face :: distinct rawptr
FT_GlyphSlot :: distinct rawptr
FT_Error :: c.int
FT_Pos :: c.long

FT_LOAD_DEFAULT :: 0
FT_LOAD_RENDER :: 1 << 2

FT_RENDER_MODE_NORMAL :: 0

FT_PIXEL_MODE_MONO :: 1
FT_PIXEL_MODE_GRAY :: 2
FT_PIXEL_MODE_BGRA :: 7

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
Returns size metrics for the active size on a face, or nil when unavailable.

Follows the FT_FaceRec size pointer at a known layout offset.
*/
ft_face_size_metrics :: proc(face: FT_Face) -> ^FT_Size_Metrics {
	size_ptr := cast(^^FT_SizeRec)(uintptr(face) + FT_FACE_OFFSET_SIZE)
	size := size_ptr^
	if size == nil do return nil
	return &size.metrics
}
