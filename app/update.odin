package app

import "oni:engine"

ZOOM_WHEEL_STEP :: engine.VIEW_ZOOM_STEP

app_tick :: proc(dt: f32) {
	_ = dt

	if persistent.engine.input.mouse_wheel_y == 0 do return

	mouse := engine.Input_Mouse_Screen()
	factor := ZOOM_WHEEL_STEP
	if persistent.engine.input.mouse_wheel_y < 0 {
		factor = 1 / ZOOM_WHEEL_STEP
	}
	engine.View_Zoom_By_Screen(mouse, factor)
}
