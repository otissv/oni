package oni

import "core:strings"
import sdl "vendor:sdl3"

/*
Returns UTF-8 clipboard text copied to the heap, or false when empty/unavailable.
*/
clipboard_get_text :: proc(allocator := context.allocator) -> (text: string, ok: bool) {
	raw := sdl.GetClipboardText()
	if raw == nil do return {}, false

	text = strings.clone_from_cstring(cstring(raw), allocator)
	sdl.free(raw)

	return text, len(text) > 0
}

/*
Writes UTF-8 text to the system clipboard.
*/
clipboard_set_text :: proc(text: string) -> bool {
	if len(text) == 0 do return sdl.SetClipboardText("")

	cstr := strings.clone_to_cstring(text, context.temp_allocator)

	return sdl.SetClipboardText(cstr)
}
