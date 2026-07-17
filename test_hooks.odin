package oni

/*
Test-only injection points for branches that cannot be forced through real SDL /
FreeType failures in CI. Default false; no effect outside tests that set them.
*/
@(private)
Test_Create_Window_Fail :: enum {
	None,
	Init,
	Window,
	Gpu,
	Claim,
	Swapchain,
}

@(private)
test_hook_dpi_sync_fail_get_size: bool
@(private)
test_hook_dpi_sync_fail_get_pixels: bool
@(private)
test_hook_dpi_sync_force_logical_w_zero: bool
@(private)
test_hook_dpi_sync_force_drawable_zero: bool
@(private)
test_hook_set_fullscreen_fail: bool
@(private)
test_hook_create_window_fail: Test_Create_Window_Fail
@(private)
test_hook_font_init_fail: bool
@(private)
test_hook_keyboard_override: bool
@(private)
test_hook_keyboard_f5: bool
@(private)
test_hook_keyboard_f6: bool
@(private)
test_hook_batch_fail_vertex_buffer: bool
@(private)
test_hook_batch_fail_index_buffer: bool
@(private)
test_hook_batch_upload_fail_transfer: bool
@(private)
test_hook_batch_upload_fail_map: bool
@(private)
test_hook_gpu_fail_vert_shader: bool
@(private)
test_hook_gpu_fail_frag_shader: bool
@(private)
test_hook_gpu_fail_pipeline: bool
@(private)
test_hook_gpu_fail_sampler: bool
@(private)
test_hook_gpu_fail_create_texture: bool
@(private)
test_hook_gpu_fail_transfer_buffer: bool
@(private)
test_hook_gpu_fail_map_transfer: bool
@(private)
test_hook_gpu_fail_acquire_cmd: bool
@(private)
test_hook_gpu_fail_submit_cmd: bool
@(private)
test_hook_present_fail_acquire_cmd: bool
@(private)
test_hook_present_fail_swapchain: bool
@(private)
test_hook_present_nil_swapchain: bool
@(private)
test_hook_present_fail_cancel: bool
@(private)
test_hook_present_fail_render_pass: bool
@(private)
test_hook_present_fail_submit: bool

/*
When true, gamepad open/enumerate/sync/close use stubbed SDL I/O instead of real devices.
*/
@(private)
test_hook_gamepad_override: bool
@(private)
test_hook_gamepad_ids_nil: bool
@(private)
test_hook_gamepad_ids_count: i32
@(private)
test_hook_gamepad_ids: [4]u32
@(private)
test_hook_gamepad_open_fail: bool
@(private)
test_hook_gamepad_close_called: bool
@(private)
test_hook_gamepad_axes: [6]i16
@(private)
test_hook_gamepad_buttons: [GAMEPAD_BUTTON_COUNT]bool

@(private)
clear_test_hooks :: proc() {
	test_hook_dpi_sync_fail_get_size = false
	test_hook_dpi_sync_fail_get_pixels = false
	test_hook_dpi_sync_force_logical_w_zero = false
	test_hook_dpi_sync_force_drawable_zero = false
	test_hook_set_fullscreen_fail = false
	test_hook_create_window_fail = .None
	test_hook_font_init_fail = false
	test_hook_keyboard_override = false
	test_hook_keyboard_f5 = false
	test_hook_keyboard_f6 = false
	test_hook_batch_fail_vertex_buffer = false
	test_hook_batch_fail_index_buffer = false
	test_hook_batch_upload_fail_transfer = false
	test_hook_batch_upload_fail_map = false
	test_hook_gpu_fail_vert_shader = false
	test_hook_gpu_fail_frag_shader = false
	test_hook_gpu_fail_pipeline = false
	test_hook_gpu_fail_sampler = false
	test_hook_gpu_fail_create_texture = false
	test_hook_gpu_fail_transfer_buffer = false
	test_hook_gpu_fail_map_transfer = false
	test_hook_gpu_fail_acquire_cmd = false
	test_hook_gpu_fail_submit_cmd = false
	test_hook_present_fail_acquire_cmd = false
	test_hook_present_fail_swapchain = false
	test_hook_present_nil_swapchain = false
	test_hook_present_fail_cancel = false
	test_hook_present_fail_render_pass = false
	test_hook_present_fail_submit = false
	test_hook_gamepad_override = false
	test_hook_gamepad_ids_nil = false
	test_hook_gamepad_ids_count = 0
	test_hook_gamepad_ids = {}
	test_hook_gamepad_open_fail = false
	test_hook_gamepad_close_called = false
	test_hook_gamepad_axes = {}
	test_hook_gamepad_buttons = {}
}
