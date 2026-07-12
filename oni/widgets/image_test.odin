package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
image_theme_base_sets_rect_kind :: proc(t: ^testing.T) {
	frame := Image_State{}
	base := image_theme_base(&frame)
	testing.expect(t, base.kind == .RECT)
}

@(test)
image_config_applies_fit_and_pos_overrides :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Image_Props {
				config = {id = "img"},
				texture_fit = set.Texture_Fit(o.Texture_Fit.CONTAIN),
				texture_pos = set.Texture_Pos(o.Texture_Pos_X_Y{x = 0, y = 0}),
			}
			frame := Image_State{}
			config := image_config(props, &frame)
			testing.expect_value(t, config.id, "img")

			fit, fit_ok := o.resolve_texture_fit(config.texture_fit, &frame, widget_event(frame))
			testing.expect(t, fit_ok)
			testing.expect(t, fit == .CONTAIN)
		},
	)
}

@(test)
texture_src_size_prefers_src_then_texture_handle :: proc(t: ^testing.T) {
	w, h := texture_src_size({src = {0, 0, 64, 32}})
	expect_close(t, w, 64)
	expect_close(t, h, 32)

	w, h = texture_src_size({texture = {w = 128, h = 96}})
	expect_close(t, w, 128)
	expect_close(t, h, 96)

	w, h = texture_src_size({})
	expect_close(t, w, 0)
	expect_close(t, h, 0)
}

@(test)
texture_measure_size_adds_insets_for_auto_axes :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Image_Props {
				src = {0, 0, 50, 25},
				texture_fit = set.Texture_Fit(o.Texture_Fit.NONE),
			}
			frame := Image_State{}
			config := image_config(props, &frame)
			config.padding = o.padding_px_to_pd({t = 1, b = 2, l = 3, r = 4})
			config.border = o.border_px_to_bd({t = 1, b = 1, l = 1, r = 1})

			event := widget_event(frame)
			measure := texture_measure_size(props, config, &frame, event)
			expect_close(t, measure.x, 50 + 3 + 4 + 1 + 1)
			expect_close(t, measure.y, 25 + 1 + 2 + 1 + 1)
		},
	)
}

@(test)
texture_measure_size_empty_when_both_axes_definite :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Image_Props {
				src = {0, 0, 50, 25},
			}
			frame := Image_State{}
			config := image_config(props, &frame)
			config.width = len_fixed(100)
			config.height = len_fixed(80)
			event := widget_event(frame)
			measure := texture_measure_size(props, config, &frame, event)
			expect_close(t, measure.x, 0)
			expect_close(t, measure.y, 0)
		},
	)
}

@(test)
image_layout_registers_node_and_sets_image_input :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Image(
				{
					config = {
						id = "photo",
						width = set.Width(f32(100)),
						height = set.Height(f32(50)),
					},
					src = {0, 0, 200, 100},
					texture_fit = set.Texture_Fit(o.Texture_Fit.CONTAIN),
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "photo")
			node, ok := widget_test_layout_node("photo")
			testing.expect(t, ok)
			if ok {
				testing.expect(t, node.image_input.active)
				expect_close(t, node.image_input.src.w, 200)
				expect_close(t, node.image_input.src.h, 100)
				testing.expect(t, node.image_input.fit == .CONTAIN)
			}
		},
	)
}

@(test)
image_tabbable_disabled_and_unmount :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Image(
				{
					config = {
						id = "img-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					src = {0, 0, 40, 20},
				},
			)
			expect_in_tab_order(t, "img-tab", true)

			Image(
				{
					config = {
						id = "img-dis",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					src = {0, 0, 40, 20},
				},
			)
			expect_in_tab_order(t, "img-dis", false)

			Image(
				{
					config = {id = "img-gone", width = set.Width(f32(40)), height = set.Height(f32(20))},
					unmount = true,
					on_unmount = proc(frame_state: Image_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("img-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}
