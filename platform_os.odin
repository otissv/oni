package oni

import "core:strings"
import sdl "vendor:sdl3"

/*
Maximum accepted length for URLs passed to `open_url`.
*/
OPEN_URL_MAX_LEN :: 2048

/*
Returns whether `url` is safe to hand to the OS URL opener.

Rejects empty strings, oversized values, embedded NUL bytes, and schemes outside
the allowlist (`http`, `https`, `mailto`). Scheme matching is ASCII case-insensitive.
*/
url_is_openable :: proc(url: string) -> bool {
	if len(url) == 0 || len(url) > OPEN_URL_MAX_LEN {
		return false
	}

	for i in 0 ..< len(url) {
		if url[i] == 0 {
			return false
		}
	}

	return url_has_allowed_open_scheme(url)
}

@(private)
url_has_allowed_open_scheme :: proc(url: string) -> bool {
	schemes := [?]string{"https://", "http://", "mailto:"}

	for scheme in schemes {
		if url_has_prefix_ascii_ci(url, scheme) {
			return true
		}
	}

	return false
}

@(private)
url_has_prefix_ascii_ci :: proc(s, prefix: string) -> bool {
	if len(s) < len(prefix) {
		return false
	}

	for i in 0 ..< len(prefix) {
		a := s[i]
		b := prefix[i]

		if a >= 'A' && a <= 'Z' {
			a += 32
		}

		if a != b {
			return false
		}
	}

	return true
}

/*
Opens a validated absolute URL with the OS default handler (`SDL_OpenURL`).

Returns false when validation fails or the OS call fails. Does not allocate
beyond a temp-allocator cstring for the SDL call.
*/
open_url :: proc(url: string) -> bool {
	if !url_is_openable(url) {
		return false
	}

	cstr := strings.clone_to_cstring(url, context.temp_allocator)

	return sdl.OpenURL(cstr)
}

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
