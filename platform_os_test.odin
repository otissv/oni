package oni

import "core:testing"
import sdl "vendor:sdl3"

@(test)
platform_os_clipboard_round_trip :: proc(t: ^testing.T) {
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
