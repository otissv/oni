package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
scroll_bar_test_notified_y: f32

@(test)
rectangle_scrollport_layout_applies_scroll_y :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			ov_scroll: o.Overflow = .SCROLL

			widget_test_begin_layout()
			Rectangle({
				config = {
					id = "vp",
					width = set.Width(f32(120)),
					height = set.Height(f32(100)),
					overflow_x = set.Overflow_X(.HIDDEN),
					overflow_y = set.Overflow_Y(ov_scroll),
					scroll_y = set.Scroll_Y(30),
					direction = set.Direction(.VERTICAL),
				},
				child = proc(_: Rectangle_State) {
					Rectangle({
						config = {
							id = "tall",
							width = set.Width(f32(100)),
							height = set.Height(f32(240)),
						},
					})
				},
			})
			widget_test_finish_layout()

			vp_id := o.ui_id("vp")
			metrics, ok := o.Scrollport_Metrics_Get(vp_id)
			testing.expect(t, ok)
			testing.expect(t, metrics.max_scroll.y > 0)
			expect_close(t, metrics.scroll.y, 30)
			expect_close(t, o.widget_scroll_get("vp").y, 30)

			// Jump via config.scroll_y override into widget context
			widget_test_end_frame()

			widget_test_begin_layout()
			Rectangle({
				config = {
					id = "vp",
					width = set.Width(f32(120)),
					height = set.Height(f32(100)),
					overflow_x = set.Overflow_X(.HIDDEN),
					overflow_y = set.Overflow_Y(ov_scroll),
					scroll_y = set.Scroll_Y(60),
					direction = set.Direction(.VERTICAL),
				},
				child = proc(_: Rectangle_State) {
					Rectangle({
						config = {
							id = "tall",
							width = set.Width(f32(100)),
							height = set.Height(f32(240)),
						},
					})
				},
			})
			widget_test_finish_layout()
			metrics, ok = o.Scrollport_Metrics_Get(vp_id)
			testing.expect(t, ok)
			expect_close(t, metrics.scroll.y, 60)
			expect_close(t, o.widget_scroll_get("vp").y, 60)
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_scrollport_persists_scroll_without_on_scroll :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			ov_scroll: o.Overflow = .SCROLL
			o.widget_scroll_set("vp", {0, 45})

			widget_test_begin_layout()
			Rectangle({
				config = {
					id = "vp",
					width = set.Width(f32(120)),
					height = set.Height(f32(100)),
					overflow_x = set.Overflow_X(.HIDDEN),
					overflow_y = set.Overflow_Y(ov_scroll),
					direction = set.Direction(.VERTICAL),
				},
				child = proc(_: Rectangle_State) {
					Rectangle({
						config = {
							id = "tall",
							width = set.Width(f32(100)),
							height = set.Height(f32(240)),
						},
					})
				},
			})
			widget_test_finish_layout()

			metrics, ok := o.Scrollport_Metrics_Get(o.ui_id("vp"))
			testing.expect(t, ok)
			expect_close(t, metrics.scroll.y, 45)

			// No config.scroll_y: context value persists across frames
			widget_test_end_frame()
			widget_test_begin_layout()
			Rectangle({
				config = {
					id = "vp",
					width = set.Width(f32(120)),
					height = set.Height(f32(100)),
					overflow_x = set.Overflow_X(.HIDDEN),
					overflow_y = set.Overflow_Y(ov_scroll),
					direction = set.Direction(.VERTICAL),
				},
				child = proc(_: Rectangle_State) {
					Rectangle({
						config = {
							id = "tall",
							width = set.Width(f32(100)),
							height = set.Height(f32(240)),
						},
					})
				},
			})
			widget_test_finish_layout()
			metrics, ok = o.Scrollport_Metrics_Get(o.ui_id("vp"))
			testing.expect(t, ok)
			expect_close(t, metrics.scroll.y, 45)
			widget_test_end_frame()
		},
	)
}

@(test)
scroll_bar_layout_owns_thumb_geometry :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		scroll_x: f32
		scroll_y: f32

		widget_test_begin_layout()
		defer widget_test_end_frame()

		Scroll_Bar({
			config = {
				id = "bar-chrome",
				width = set.Width(f32(12)),
				height = set.Height(f32(100)),
			},
			axis = .Y,
			parent_scroll_x = &scroll_x,
			parent_scroll_y = &scroll_y,
			viewport = 50,
			content = 200,
		})
		widget_test_finish_layout()

		chrome := o.layout_scroll_bar_result(o.ui_id("bar-chrome"))
		testing.expect(t, chrome != nil)

		if chrome != nil {
			testing.expect(t, chrome.active)
			testing.expect(t, chrome.thumb.h >= o.SCROLL_BAR_MIN_THUMB || chrome.thumb.h > 0)
		}
	})
}

@(test)
scroll_bar_writes_parent_scroll_y_on_track_press :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			scroll_x: f32
			scroll_y: f32
			scroll_bar_test_notified_y = -1

			widget_test_begin_layout()
			Scroll_Bar({
				config = {
					id = "bar",
					width = set.Width(f32(12)),
					height = set.Height(f32(100)),
				},
				axis = .Y,
				parent_scroll_x = &scroll_x,
				parent_scroll_y = &scroll_y,
				viewport = 50,
				content = 200,
				on_scroll = proc(sx, sy: f32) {
					_ = sx
					scroll_bar_test_notified_y = sy
				},
			})
			widget_test_finish_layout()

			bar_id := o.ui_id("bar")
			rect := o.ui_layout_rect(bar_id)
			testing.expect(t, rect.h > 0)

			widget_test_begin_draw()
			o.w_ctx.mouse_x = rect.x + rect.w * 0.5
			o.w_ctx.mouse_y = rect.y + rect.h - 2
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true
			o.layout_resolve_pointer_hit()

			Scroll_Bar({
				config = {
					id = "bar",
					width = set.Width(f32(12)),
					height = set.Height(f32(100)),
				},
				axis = .Y,
				parent_scroll_x = &scroll_x,
				parent_scroll_y = &scroll_y,
				viewport = 50,
				content = 200,
				on_scroll = proc(sx, sy: f32) {
					_ = sx
					scroll_bar_test_notified_y = sy
				},
			})
			widget_test_end_frame()

			testing.expect(t, scroll_y > 0)
			testing.expect(t, scroll_bar_test_notified_y == scroll_y)
		},
	)
}

@(test)
scroll_bar_config_sets_track_background :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			scroll_x: f32 = 0
			scroll_y: f32 = 0
			widget_test_begin_layout()
			Scroll_Bar(
				{
					config = {
						id = "bar",
						width = set.Width(f32(20)),
						height = set.Height(f32(100)),
						background = set.Colors(o.Color.ACCENT),
						radius = set.Radius(f32(8)),
					},
					axis = .Y,
					parent_scroll_x = &scroll_x,
					parent_scroll_y = &scroll_y,
					viewport = 50,
					content = 200,
				},
			)
			widget_test_finish_layout()

			bar, ok := widget_test_layout_node("bar")
			testing.expect(t, ok)

			if ok {
				expect_close(t, bar.rect.w, 20)
				#partial switch v in bar.config.background {
				case o.Color:
					testing.expect_value(t, v, o.Color.ACCENT)
				case o.RGBA:
					testing.expect_value(t, v, o.RGBA{64, 64, 64, 255})
				case:
					testing.expectf(t, false, "expected ACCENT background, got %v", bar.config.background)
				}
			}

			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_auto_scroll_bar_uses_default_size :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			widget_test_end_frame()

			o.widget_scroll_auto_reveal_set("vp", true)

			widget_test_begin_layout()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()

			bar := scroll_bar_test_find_bar("vp")
			testing.expect(t, bar != nil)

			if bar != nil {
				expect_close(t, bar.rect.w, o.SCROLL_BAR_DEFAULT_SIZE)
			}

			widget_test_end_frame()
		},
	)
}

@(test)
scroll_bar_min_thumb_floors_geometry :: proc(t: ^testing.T) {
	thumb_len, _ := o.scroll_bar_thumb_geometry(100, 10, 1000, 0, 40)
	expect_close(t, thumb_len, 40)

	with_widget_env(
		t,
		proc(t: ^testing.T) {
			scroll_x: f32 = 0
			scroll_y: f32 = 0
			widget_test_begin_layout()
			Scroll_Bar(
				{
					config = {
						id = "bar-min-thumb",
						width = set.Width(f32(10)),
						height = set.Height(f32(100)),
					},
					min_thumb = set.F32(f32(40)),
					axis = .Y,
					parent_scroll_x = &scroll_x,
					parent_scroll_y = &scroll_y,
					viewport = 10,
					content = 1000,
					child = proc(_: Scroll_Bar_State) {
						Scroll_Bar_Thumb(
							{
								config = {
									background = set.Colors(o.Color.PRIMARY),
									radius = set.Radius(f32(6)),
								},
							},
						)
					},
				},
			)
			widget_test_finish_layout()

			chrome := o.layout_scroll_bar_result(o.ui_id("bar-min-thumb"))
			testing.expect(t, chrome != nil)

			if chrome != nil {
				expect_close(t, chrome.thumb.h, 40)
			}

			Scroll_Bar(
				{
					config = {
						id = "bar-min-thumb",
						width = set.Width(f32(10)),
						height = set.Height(f32(100)),
					},
					min_thumb = set.F32(f32(40)),
					axis = .Y,
					parent_scroll_x = &scroll_x,
					parent_scroll_y = &scroll_y,
					viewport = 10,
					content = 1000,
					child = proc(_: Scroll_Bar_State) {
						Scroll_Bar_Thumb(
							{
								config = {
									background = set.Colors(o.Color.PRIMARY),
									radius = set.Radius(f32(6)),
								},
							},
						)
					},
				},
			)
			widget_test_end_frame()
		},
	)
}

@(private)
scroll_bar_test_find_bar :: proc(parent_id: string) -> ^o.Layout_Node {
	vp, ok := widget_test_layout_node(parent_id)
	if !ok do return nil
	for child_index in vp.child_indices {
		child := &o.state.ui.layout.nodes[child_index]
		if child.kind == .SCROLL_BAR do return child
	}
	return nil
}

@(private)
scroll_bar_test_port :: proc(overflow: o.Overflow, child: proc(_: Rectangle_State)) {
	Rectangle({
		config = {
			id = "vp",
			width = set.Width(f32(120)),
			height = set.Height(f32(100)),
			overflow_y = set.Overflow_Y(overflow),
			direction = set.Direction(.VERTICAL),
		},
		child = child,
	})
}

@(private)
scroll_bar_test_auto_port :: proc(child: proc(_: Rectangle_State)) {
	ov_auto: o.Overflow = .AUTO
	scroll_bar_test_port(ov_auto, child)
}

@(private)
scroll_bar_test_scroll_port :: proc(child: proc(_: Rectangle_State)) {
	ov_scroll: o.Overflow = .SCROLL
	scroll_bar_test_port(ov_scroll, child)
}

@(private)
scroll_bar_test_tall_child :: proc(_: Rectangle_State) {
	Rectangle({
		config = {
			id = "tall",
			width = set.Width(f32(100)),
			height = set.Height(f32(240)),
		},
	})
}

@(test)
widget_scroll_overflow_shows_bar_rules :: proc(t: ^testing.T) {
	ov_scroll: o.Overflow = .SCROLL
	ov_auto: o.Overflow = .AUTO
	ov_hidden: o.Overflow = .HIDDEN

	testing.expect(t, !widget_scroll_overflow_shows_bar(ov_scroll, 0, true))
	testing.expect(t, !widget_scroll_overflow_shows_bar(ov_scroll, 10, false))
	testing.expect(t, widget_scroll_overflow_shows_bar(ov_scroll, 10, true))
	testing.expect(t, !widget_scroll_overflow_shows_bar(ov_auto, 10, false))
	testing.expect(t, widget_scroll_overflow_shows_bar(ov_auto, 10, true))
	testing.expect(t, !widget_scroll_overflow_shows_bar(ov_auto, 0, true))
	testing.expect(t, !widget_scroll_overflow_shows_bar(ov_hidden, 10, true))
}

@(test)
rectangle_overflow_auto_hides_bar_without_reveal :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()

			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)
			testing.expect(t, !o.widget_scroll_auto_reveal_get("vp"))
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_overflow_auto_shows_bar_when_reveal_set :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			// Seed previous-frame metrics (AUTO emit reads the store during layout).
			widget_test_begin_layout()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			widget_test_end_frame()

			o.widget_scroll_auto_reveal_set("vp", true)

			widget_test_begin_layout()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()

			testing.expect(t, scroll_bar_test_find_bar("vp") != nil)
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_overflow_auto_reveal_on_port_hover :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)

			widget_test_begin_draw()
			vp_rect := o.ui_layout_rect(o.ui_id("vp"))
			o.w_ctx.mouse_x = vp_rect.x + vp_rect.w * 0.5
			o.w_ctx.mouse_y = vp_rect.y + vp_rect.h * 0.5
			o.layout_resolve_pointer_hit()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_end_frame()

			testing.expect(t, o.widget_scroll_auto_reveal_get("vp"))

			widget_test_begin_layout()
			scroll_bar_test_auto_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") != nil)
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_overflow_scroll_hides_bar_without_reveal :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()

			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)
			testing.expect(t, !o.widget_scroll_auto_reveal_get("vp"))
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_overflow_scroll_shows_bar_on_port_hover :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)

			widget_test_begin_draw()
			vp_rect := o.ui_layout_rect(o.ui_id("vp"))
			o.w_ctx.mouse_x = vp_rect.x + vp_rect.w * 0.5
			o.w_ctx.mouse_y = vp_rect.y + vp_rect.h * 0.5
			o.layout_resolve_pointer_hit()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_end_frame()

			testing.expect(t, o.widget_scroll_auto_reveal_get("vp"))

			widget_test_begin_layout()
			scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") != nil)
			widget_test_end_frame()
		},
	)
}

@(private)
scroll_bar_test_padded_port :: proc(_: Rectangle_State) {
	ov_scroll: o.Overflow = .SCROLL
	Rectangle({
		config = {
			id = "vp",
			width = set.Width(f32(160)),
			height = set.Height(f32(120)),
			padding = set.Padding(f32(24)),
			overflow_y = set.Overflow_Y(ov_scroll),
			direction = set.Direction(.VERTICAL),
		},
		child = scroll_bar_test_tall_child,
	})
}

@(test)
rectangle_overflow_padded_port_bar_on_padding_edge :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			bar_size := o.SCROLL_BAR_DEFAULT_SIZE

			widget_test_begin_layout()
			scroll_bar_test_padded_port({})
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)

			widget_test_begin_draw()
			vp_rect := o.ui_layout_rect(o.ui_id("vp"))
			o.w_ctx.mouse_x = vp_rect.x + vp_rect.w * 0.5
			o.w_ctx.mouse_y = vp_rect.y + vp_rect.h * 0.5
			o.layout_resolve_pointer_hit()
			scroll_bar_test_padded_port({})
			widget_test_end_frame()
			testing.expect(t, o.widget_scroll_auto_reveal_get("vp"))

			widget_test_begin_layout()
			scroll_bar_test_padded_port({})
			widget_test_finish_layout()
			o.layout_finalize_stack_order()

			vp, vp_ok := widget_test_layout_node("vp")
			testing.expect(t, vp_ok)
			bar := scroll_bar_test_find_bar("vp")
			testing.expect(t, bar != nil)

			if vp_ok && bar != nil {
				// Bars sit on the padding-box edge (widget inner edge), not the
				// content-box edge — padding must not inset chrome.
				pad := o.layout_padding_box(vp)
				content := o.layout_clip_box(vp)

				expect_close(t, bar.rect.w, bar_size)
				expect_close(t, bar.rect.x + bar.rect.w, pad.x + pad.w)
				testing.expect(t, bar.rect.x + bar.rect.w > content.x + content.w + 1e-3)
				testing.expect(t, bar.has_clip)
				testing.expect(t, bar.rect.x >= bar.clip_rect.x - 1e-3)
				testing.expect(
					t,
					bar.rect.x + bar.rect.w <= bar.clip_rect.x + bar.clip_rect.w + 1e-3,
				)
			}

			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_overflow_padded_port_reveal_on_padding_hover :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			scroll_bar_test_padded_port({})
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") == nil)

			widget_test_begin_draw()
			vp, vp_ok := widget_test_layout_node("vp")
			testing.expect(t, vp_ok)
			if !vp_ok {
				widget_test_end_frame()
				return
			}

			pad := o.layout_padding_box(vp)
			content := o.layout_clip_box(vp)
			// Hover the padding corridor between content and the overlay bar —
			// reveal must stick so the bar remains reachable to drag.
			o.w_ctx.mouse_x = content.x + content.w + 8
			o.w_ctx.mouse_y = pad.y + pad.h * 0.5
			testing.expect(t, o.w_ctx.mouse_x < pad.x + pad.w)
			testing.expect(t, o.w_ctx.mouse_x >= content.x + content.w)
			o.layout_resolve_pointer_hit()
			testing.expect(t, o.w_ctx.pointer_hit_valid)
			testing.expect(t, o.w_ctx.pointer_hit_ui_id == vp.ui_id)

			scroll_bar_test_padded_port({})
			widget_test_end_frame()
			testing.expect(t, o.widget_scroll_auto_reveal_get("vp"))

			widget_test_begin_layout()
			scroll_bar_test_padded_port({})
			widget_test_finish_layout()
			testing.expect(t, scroll_bar_test_find_bar("vp") != nil)
			widget_test_end_frame()
		},
	)
}
