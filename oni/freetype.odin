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

FT_Generic :: struct {
	data:      rawptr,
	finalizer: rawptr,
}

FT_Size_Metrics :: struct {
	x_ppem, y_ppem: c.ushort,
	x_scale, y_scale: FT_Fixed,
	ascender, descender, height, max_advance: FT_Pos,
}

FT_SizeRec :: struct {
	face:     FT_Face,
	generic:  FT_Generic,
	metrics:  FT_Size_Metrics,
	internal: rawptr,
}

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
	Init_FreeType :: proc(library: ^FT_Library) -> FT_Error ---
	Done_FreeType :: proc(library: FT_Library) -> FT_Error ---

	New_Face :: proc(
		library: FT_Library,
		filepathname: cstring,
		face_index: c.long,
		aface: ^FT_Face,
	) -> FT_Error ---
	Done_Face :: proc(face: FT_Face) -> FT_Error ---

	Set_Pixel_Sizes :: proc(face: FT_Face, pixel_width, pixel_height: c.uint) -> FT_Error ---
	Load_Glyph :: proc(face: FT_Face, glyph_index: c.uint, load_flags: c.int) -> FT_Error ---
	Render_Glyph :: proc(slot: ^FT_GlyphSlotRec, render_mode: c.int) -> FT_Error ---
}

ft_ok :: proc(err: FT_Error) -> bool {
	return err == 0
}

ft_glyph_slot :: proc(face: FT_Face) -> ^FT_GlyphSlotRec {
	glyph_ptr := cast(^FT_GlyphSlot)(uintptr(face) + FT_FACE_OFFSET_GLYPH)
	return cast(^FT_GlyphSlotRec)glyph_ptr^
}

ft_slot_format :: proc(slot: ^FT_GlyphSlotRec) -> FT_Glyph_Format {
	return (cast(^FT_Glyph_Format)(uintptr(slot) + FT_SLOT_OFFSET_FORMAT))^
}

ft_slot_bitmap :: proc(slot: ^FT_GlyphSlotRec) -> ^FT_Bitmap {
	return cast(^FT_Bitmap)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP)
}

ft_slot_bitmap_left :: proc(slot: ^FT_GlyphSlotRec) -> c.int {
	return (cast(^c.int)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP_LEFT))^
}

ft_slot_bitmap_top :: proc(slot: ^FT_GlyphSlotRec) -> c.int {
	return (cast(^c.int)(uintptr(slot) + FT_SLOT_OFFSET_BITMAP_TOP))^
}

ft_face_size_metrics :: proc(face: FT_Face) -> ^FT_Size_Metrics {
	size_ptr := cast(^^FT_SizeRec)(uintptr(face) + FT_FACE_OFFSET_SIZE)
	size := size_ptr^
	if size == nil do return nil
	return &size.metrics
}
