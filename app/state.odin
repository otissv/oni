package app

import "oni:engine"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Odin + SDL3"

MIN_WINDOW_W :: 320
MIN_WINDOW_H :: 180

App_State :: struct {
	theme: engine.Theme,
}
