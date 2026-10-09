package oni

import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
platform_os_url_is_openable_allowlist_and_rejects :: proc(t: ^testing.T) {
	testing.expect(t, url_is_openable("https://example.com"))
	testing.expect(t, url_is_openable("HTTP://EXAMPLE.COM/path"))
	testing.expect(t, url_is_openable("mailto:user@example.com"))
	testing.expect(t, !url_is_openable(""))
	testing.expect(t, !url_is_openable("/relative"))
	testing.expect(t, !url_is_openable("javascript:alert(1)"))
	testing.expect(t, !url_is_openable("file:///tmp/x"))
	testing.expect(t, !url_is_openable("https://exa\x00mple.com"))

	buf: [OPEN_URL_MAX_LEN + 16]u8
	prefix := "https://example.com/"
	copy(buf[:], prefix)

	for i in len(prefix) ..< len(buf) {
		buf[i] = 'a'
	}

	oversized := string(buf[:OPEN_URL_MAX_LEN + 1])
	testing.expect(t, !url_is_openable(oversized))
	testing.expect(t, url_is_openable(string(buf[:OPEN_URL_MAX_LEN])))
}

@(test)
platform_os_clipboard_round_trip :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %v", sdl.GetError())
		return
	}
	defer sdl.Quit()

	sample := "oni clipboard test"
	ok := clipboard_set_text(sample)
	testing.expect(t, ok)

	got, got_ok := clipboard_get_text()
	defer delete(got)

	testing.expect(t, got_ok)
	testing.expect_value(t, got, sample)
}
