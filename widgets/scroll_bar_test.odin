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
rectangle_scroll_bar_style_sets_size_and_track_background :: proc(t: ^testing.T) {
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
					overflow_y = set.Overflow_Y(ov_scroll),
					direction = set.Direction(.VERTICAL),
				},
				scroll_bar = {
					size = set.F32(20),
					background = set.Colors(o.Color.ACCENT),
					radius = set.Radius(f32(8)),
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

			vp, ok := widget_test_layout_node("vp")
			testing.expect(t, ok)
			bar: ^o.Layout_Node
			for child_index in vp.child_indices {
				child := &o.state.ui.layout.nodes[child_index]
				if child.kind == .SCROLL_BAR {
					bar = child
					break
				}
			}
			testing.expect(t, bar != nil)
			expect_close(t, bar.rect.w, 20)
			#partial switch v in bar.config.background {
			case o.Color:
				testing.expect_value(t, v, o.Color.ACCENT)
			case o.RGBA:
				testing.expect_value(t, v, o.RGBA{64, 64, 64, 255})
			case:
				testing.expectf(t, false, "expected ACCENT background, got %v", bar.config.background)
			}
			widget_test_end_frame()
		},
	)
}

@(test)
rectangle_scroll_bar_style_visible_false_skips_bars :: proc(t: ^testing.T) {
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
					overflow_y = set.Overflow_Y(ov_scroll),
					direction = set.Direction(.VERTICAL),
				},
				scroll_bar = {
					visible = set.Bool(false),
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

			vp, ok := widget_test_layout_node("vp")
			testing.expect(t, ok)
			for child_index in vp.child_indices {
				child := &o.state.ui.layout.nodes[child_index]
				testing.expect(t, child.kind != .SCROLL_BAR)
			}
			widget_test_end_frame()
		},
	)
}

@(test)
scroll_bar_style_min_thumb_floors_geometry :: proc(t: ^testing.T) {
	thumb_len, _ := o.scroll_bar_thumb_geometry(100, 10, 1000, 0, 40)
	expect_close(t, thumb_len, 40)
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
scroll_bar_test_auto_port :: proc(child: proc(_: Rectangle_State)) {
	ov_auto: o.Overflow = .AUTO
	Rectangle({
		config = {
			id = "vp",
			width = set.Width(f32(120)),
			height = set.Height(f32(100)),
			overflow_y = set.Overflow_Y(ov_auto),
			direction = set.Direction(.VERTICAL),
		},
		child = child,
	})
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

	testing.expect(t, widget_scroll_overflow_shows_bar(ov_scroll, 0, false))
	testing.expect(t, widget_scroll_overflow_shows_bar(ov_scroll, 10, false))
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
rectangle_overflow_scroll_always_shows_bar :: proc(t: ^testing.T) {
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
					overflow_y = set.Overflow_Y(ov_scroll),
					direction = set.Direction(.VERTICAL),
				},
				child = scroll_bar_test_tall_child,
			})
			widget_test_finish_layout()

			testing.expect(t, scroll_bar_test_find_bar("vp") != nil)
			widget_test_end_frame()
		},
	)
}
