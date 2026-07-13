package oni

import "core:testing"

@(test)
style_length_resolve_and_definite :: proc(t: ^testing.T) {
	expect_close(t, length_resolve({kind = .FIXED, value = 42}, 100), 42)
	expect_close(t, length_resolve({kind = .PERCENT, value = 50}, 200), 100)
	expect_close(t, length_resolve({kind = .INHERIT}, 77), 77)
	expect_close(t, length_resolve({kind = .AUTO}, 100), 0)

	testing.expect(t, length_is_definite({kind = .FIXED, value = 1}))
	testing.expect(t, length_is_definite({kind = .PERCENT, value = 10}))
	testing.expect(t, !length_is_definite({kind = .AUTO}))
}

@(test)
style_cfg_helpers_and_width_height_set :: proc(t: ^testing.T) {
	testing.expect(t, !cfg_style_bool({}))
	testing.expect(t, cfg_style_bool({mode = .Value, value = true}))
	testing.expect(t, !cfg_style_bool({mode = .Value, value = false}))
	testing.expect(t, !cfg_style_bool({mode = .Value, value = Inherit.INHERIT}))

	expect_close(t, cfg_style_f32({}), 0)
	expect_close(t, cfg_style_f32({}, 5), 5)
	expect_close(t, cfg_style_f32({mode = .Value, value = f32(3.5)}, 5), 3.5)
	expect_close(t, cfg_style_f32({mode = .Value, value = Inherit.INHERIT}, 5), 5)

	testing.expect(t, !cfg_width_is_set(struct{}{}))
	testing.expect(t, cfg_width_is_set(f32(10)))
	testing.expect(t, cfg_width_is_set(Width_Mode.AUTO))

	testing.expect(t, !cfg_height_is_set(struct{}{}))
	testing.expect(t, cfg_height_is_set(f32(20)))
	testing.expect(t, cfg_height_is_set(Height_Mode.INHERIT))
}

@(test)
style_merge_cfg_and_merge_widget_config :: proc(t: ^testing.T) {
	dst := Cfg(Style_F32) {
		mode  = .Value,
		value = f32(1),
	}
	merge_cfg(Style_F32, &dst, Cfg(Style_F32){})
	expect_close(t, cfg_style_f32(dst), 1)

	merge_cfg(Style_F32, &dst, Cfg(Style_F32){mode = .Value, value = f32(9)})
	expect_close(t, cfg_style_f32(dst), 9)

	unset_w: Width
	unset_h: Height
	testing.expect(t, !cfg_width_is_set(unset_w))
	testing.expect(t, !cfg_width_is_set(Width(struct{}{})))
	testing.expect(t, cfg_width_is_set(Width(f32(10))))
	testing.expect(t, !cfg_height_is_set(unset_h))
	testing.expect(t, !cfg_height_is_set(Height(struct{}{})))
	testing.expect(t, cfg_height_is_set(Height(f32(10))))

	base := Widget_Config {
		id = "base",
		flex = {mode = .Value, value = f32(1)},
		gap_x = {mode = .Value, value = u16(2)},
		tabbable = {mode = .Value, value = true},
	}
	base.width = f32(100)
	base.height = f32(50)

	override := Widget_Config {
		id = "child",
		flex = {mode = .Value, value = f32(3)},
		disabled = {mode = .Value, value = true},
	}
	override.width = f32(200)

	merged := merge_widget_config(base, override)
	testing.expect_value(t, merged.id, "child")
	expect_close(t, cfg_style_f32(merged.flex), 3)
	testing.expect_value(t, merged.gap_x.value.(u16), u16(2))
	mw, mw_ok := merged.width.(f32)
	testing.expect(t, mw_ok)
	expect_close(t, mw, 200)
	mh, mh_ok := merged.height.(f32)
	testing.expect(t, mh_ok)
	expect_close(t, mh, 50)
	testing.expect(t, cfg_style_bool(merged.disabled))
	testing.expect(t, cfg_style_bool(merged.tabbable))

	keep := Widget_Config {
		id = "keep-size",
	}
	no_size := merge_widget_config(base, keep)
	nsw, nsw_ok := no_size.width.(f32)
	testing.expect(t, nsw_ok)
	expect_close(t, nsw, 100)
	nsh, nsh_ok := no_size.height.(f32)
	testing.expect(t, nsh_ok)
	expect_close(t, nsh, 50)
}

@(test)
style_root_and_child_context_insets :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			root := style_root(.ARTBOARD, {0, 0, 400, 300})
			testing.expect(t, root.style.space == .ARTBOARD)
			expect_close(t, root.content_w, 400)
			expect_close(t, root.content_h, 300)

			config := Resolved_Widget_Config {
				style = {
					padding = Pd{t = 10, b = 5, l = 2, r = 3},
					border = Bd{t = 1, b = 1, l = 4, r = 6},
				},
			}
			child := style_child_context(config)
			expect_close(t, child.content_w, 800 - (2 + 3 + 4 + 6))
			expect_close(t, child.content_h, 600 - (10 + 5 + 1 + 1))
			testing.expect(t, child.content_w >= 0)
		},
	)
}

@(test)
style_stack_push_pop_current :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			cur := ui_style_current()
			expect_close(t, cur.content_w, 800)

			ui_push_style(Style_Context{content_w = 100, content_h = 50})
			cur = ui_style_current()
			expect_close(t, cur.content_w, 100)
			expect_close(t, cur.content_h, 50)

			ui_pop_style()
			cur = ui_style_current()
			expect_close(t, cur.content_w, 800)
		},
	)
}

@(test)
style_resolve_widget_config_overrides_and_theme_defaults :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			resolved := resolve_widget_config(
				{},
				{
					id = "w",
					flex = {mode = .Value, value = f32(2)},
					gap_x = {mode = .Value, value = u16(8)},
					gap_y = {mode = .Value, value = u16(4)},
					direction = {mode = .Value, value = Direction_Layout.HORIZONTAL},
					justify = {mode = .Value, value = Justify_Align.CENTER},
					padding = {mode = .Value, value = f32(6)},
					border = {mode = .Value, value = f32(2)},
					radius = {mode = .Value, value = f32(3)},
					width = f32(120),
					height = f32(40),
					min_w = {mode = .Value, value = f32(10)},
					max_w = {mode = .Value, value = f32(200)},
					disabled = {mode = .Value, value = true},
					tabbable = {mode = .Value, value = true},
					auto_focus = {mode = .Value, value = true},
					line_height = {mode = .Value, value = f32(1.5)},
					letter_spacing = {mode = .Value, value = f32(0.5)},
					z_index = {mode = .Value, value = f32(3)},
					texture_fit = {mode = .Value, value = Texture_Fit.COVER},
				},
				&frame,
				event,
			)

			testing.expect_value(t, resolved.id, "w")
			expect_close(t, resolved.flex, 2)
			testing.expect_value(t, resolved.gap_x, u16(8))
			testing.expect_value(t, resolved.gap_y, u16(4))
			testing.expect(t, resolved.direction == .HORIZONTAL)
			testing.expect(t, resolved.justify.x == Justify_Align.CENTER)
			testing.expect(t, resolved.disabled)
			testing.expect(t, resolved.tabbable)
			testing.expect(t, resolved.auto_focus)
			expect_close(t, resolved.line_height, 1.5)
			expect_close(t, resolved.letter_spacing, 0.5)
			expect_close(t, resolved.z_index, 3)
			testing.expect(t, resolved.texture_fit == Texture_Fit.COVER)
			testing.expect(t, resolved.width.kind == .FIXED)
			expect_close(t, resolved.width.value, 120)
			testing.expect(t, resolved.height.kind == .FIXED)
			expect_close(t, resolved.height.value, 40)

			pad, pok := resolve_padding_value(resolved.padding)
			testing.expect(t, pok)
			expect_pd(t, pad, {6, 6, 6, 6})
			border, bok := resolve_border_value(resolved.border)
			testing.expect(t, bok)
			expect_bd(t, border, {2, 2, 2, 2})
		},
	)
}

@(test)
style_resolve_widget_config_inherits_from_parent_stack :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			parent := resolve_widget_config(
				{},
				{
					padding = {mode = .Value, value = f32(10)},
					gap_x = {mode = .Value, value = u16(5)},
					color = {mode = .Value, value = RGBA{1, 0, 0, 1}},
					direction = {mode = .Value, value = Direction_Layout.HORIZONTAL},
				},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			child := resolve_widget_config(
				{},
				{
					padding = {mode = .Value, value = Inherit.INHERIT},
					gap_x = {mode = .Value, value = Inherit.INHERIT},
					color = {mode = .Value, value = Color.INHERIT},
					direction = {mode = .Value, value = Inherit.INHERIT},
					flex = {mode = .Value, value = Inherit.INHERIT},
				},
				&frame,
				event,
			)

			pad, ok := resolve_padding_value(child.padding)
			testing.expect(t, ok)
			expect_pd(t, pad, {10, 10, 10, 10})
			testing.expect_value(t, child.gap_x, u16(5))
			testing.expect(t, child.direction == .HORIZONTAL)
			expect_close(t, child.flex, parent.flex)
		},
	)
}

@(test)
style_resolve_length_from_width_height_modes :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			w_auto := resolve_length_from_width(Width_Mode.AUTO, 100, &frame, event)
			testing.expect(t, w_auto.kind == .AUTO)

			w_inh := resolve_length_from_width(Width_Mode.INHERIT, 100, &frame, event)
			testing.expect(t, w_inh.kind == .INHERIT)

			w_fixed := resolve_length_from_width(f32(55), 100, &frame, event)
			testing.expect(t, w_fixed.kind == .FIXED)
			expect_close(t, w_fixed.value, 55)

			w_pct := resolve_length_from_width(Dim_struct{percent = 25}, 100, &frame, event)
			testing.expect(t, w_pct.kind == .PERCENT)
			expect_close(t, w_pct.value, 25)

			w_min := resolve_length_from_width(Dim_struct{min = 30}, 100, &frame, event)
			testing.expect(t, w_min.kind == .FIXED)
			expect_close(t, w_min.value, 30)

			w_max := resolve_length_from_width(Dim_struct{max = 40}, 100, &frame, event)
			testing.expect(t, w_max.kind == .FIXED)
			expect_close(t, w_max.value, 40)

			w_empty := resolve_length_from_width(struct{}{}, 100, &frame, event)
			testing.expect(t, w_empty.kind == .AUTO)

			h_fixed := resolve_length_from_height(f32(22), 50, &frame, event)
			testing.expect(t, h_fixed.kind == .FIXED)
			expect_close(t, h_fixed.value, 22)

			width_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Width {
				_ = frame_state
				_ = event
				return f32(77)
			}
			w_proc := resolve_length_from_width(Width(width_proc), 100, &frame, event)
			testing.expect(t, w_proc.kind == .FIXED)
			expect_close(t, w_proc.value, 77)
		},
	)
}

@(test)
style_resolve_self_and_partial_justify :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			unset := resolve_cfg_self(Cfg(Justify){}, &frame, event)
			_, unset_x_ok := justify_align_from_x(unset.x)
			testing.expect(t, !unset_x_ok)

			self := resolve_cfg_self(
				{mode = .Value, value = Justify_Pos{x = Justify_Align.END}},
				&frame,
				event,
			)
			testing.expect(t, self.x == Justify_Align.END)

			full := resolve_cfg_self(
				{mode = .Value, value = Justify_Align.CENTER},
				&frame,
				event,
			)
			testing.expect(t, full.x == Justify_Align.CENTER)
			testing.expect(t, full.y == Justify_Align.CENTER)
		},
	)
}

@(private)
style_children_called: bool
@(private)
style_children_scope_len: int
@(private)
style_children_content_w: f32

@(private)
style_children_builder :: proc(frame_state: Widget_Frame_State) {
	_ = frame_state
	style_children_called = true
	style_children_scope_len = len(state.ui.scope_stack)
	style_children_content_w = ui_style_current().content_w
}

@(test)
style_children_scopes_layout_and_style :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			defer layout_end_space()

			frame, event := ui_test_frame_event()
			config := resolve_widget_config(
				{},
				{
					id = "parent",
					padding = {mode = .Value, value = f32(10)},
					width = f32(200),
					height = f32(100),
				},
				&frame,
				event,
			)
			parent_id := ui_id("parent")

			style_children_called = false
			Children(style_children_builder, parent_id, config, frame)
			testing.expect(t, style_children_called)
			testing.expect_value(t, style_children_scope_len, 1)
			expect_close(t, style_children_content_w, 800 - 20)
			testing.expect_value(t, len(state.ui.scope_stack), 0)
			testing.expect(t, ui_has_layout_node(parent_id))
		},
	)
}

@(test)
style_resolve_private_text_and_overflow_helpers :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			align, aok := resolve_text_align(Text_Align_Kind.CENTER, &frame, event)
			testing.expect(t, aok)
			testing.expect(t, align == Text_Align_Kind.CENTER)

			wrap, wok := resolve_text_wrap(Text_Wrap_Kind.NONE, &frame, event)
			testing.expect(t, wok)
			testing.expect(t, wrap == Text_Wrap_Kind.NONE)

			deco, dok := resolve_text_decoration(Text_Decoration_Lines{.UNDERLINE}, &frame, event)
			testing.expect(t, dok)
			testing.expect(t, .UNDERLINE in deco.(Text_Decoration_Lines))

			style, sok := resolve_text_decoration_style(
				Text_Decoration_Style_Kind.DASHED,
				&frame,
				event,
			)
			testing.expect(t, sok)
			testing.expect(t, style == Text_Decoration_Style_Kind.DASHED)

			dir, dir_ok := resolve_text_direction(Text_Direction_Kind.RTL, &frame, event)
			testing.expect(t, dir_ok)
			testing.expect(t, dir == Text_Direction_Kind.RTL)

			weight, wok2 := resolve_font_weight(Font_Weights.Bold, &frame, event)
			testing.expect(t, wok2)
			testing.expect(t, weight == Font_Weights.Bold)

			weight_f, wok3 := resolve_font_weight(f32(600), &frame, event)
			testing.expect(t, wok3)
			expect_close(t, weight_f.(f32), 600)

			fs, fok := resolve_font_style(Font_Styles.ITALIC, &frame, event)
			testing.expect(t, fok)
			testing.expect(t, fs == Font_Styles.ITALIC)

			_, inherit_ok := resolve_font_weight(Inherit.INHERIT, &frame, event)
			testing.expect(t, !inherit_ok)

			hidden_overflow: Overflow = .HIDDEN
			overflow, ook := resolve_overflow(hidden_overflow, &frame, event)
			testing.expect(t, ook)
			testing.expect(t, overflow == hidden_overflow)

			_, oinh := resolve_overflow(Inherit.INHERIT, &frame, event)
			testing.expect(t, !oinh)

			hidden_vis: Visibility = .HIDDEN
			vis, vok := resolve_visibility(hidden_vis, &frame, event)
			testing.expect(t, vok)
			testing.expect(t, vis == hidden_vis)

			abs_pos: Position = .ABSOLUTE
			pos, pok := resolve_position(abs_pos, &frame, event)
			testing.expect(t, pok)
			testing.expect(t, pos == abs_pos)
		},
	)
}

@(test)
style_length_inherit_is_definite_and_unknown_kind_zero :: proc(t: ^testing.T) {
	testing.expect(t, length_is_definite({kind = .INHERIT}))
	testing.expect(t, length_is_definite({kind = .FIXED}))
	// Exhaustive switch covers all kinds; zero-value Length is FIXED with 0.
	expect_close(t, length_resolve({}, 50), 0)
}

@(test)
style_resolve_length_from_height_modes_and_empty_dim :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			h_auto := resolve_length_from_height(Height_Mode.AUTO, 80, &frame, event)
			testing.expect(t, h_auto.kind == .AUTO)

			h_inh := resolve_length_from_height(Height_Mode.INHERIT, 80, &frame, event)
			testing.expect(t, h_inh.kind == .INHERIT)

			h_pct := resolve_length_from_height(Dim_struct{percent = 40}, 80, &frame, event)
			testing.expect(t, h_pct.kind == .PERCENT)
			expect_close(t, h_pct.value, 40)

			h_min := resolve_length_from_height(Dim_struct{min = 12}, 80, &frame, event)
			testing.expect(t, h_min.kind == .FIXED)
			expect_close(t, h_min.value, 12)

			h_max := resolve_length_from_height(Dim_struct{max = 18}, 80, &frame, event)
			testing.expect(t, h_max.kind == .FIXED)
			expect_close(t, h_max.value, 18)

			h_empty := resolve_length_from_height(Dim_struct{}, 80, &frame, event)
			testing.expect(t, h_empty.kind == .AUTO)

			w_empty := resolve_length_from_width(Dim_struct{}, 100, &frame, event)
			testing.expect(t, w_empty.kind == .AUTO)

			height_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Height {
				_ = frame_state
				_ = event
				return f32(33)
			}
			h_proc := resolve_length_from_height(Height(height_proc), 80, &frame, event)
			testing.expect(t, h_proc.kind == .FIXED)
			expect_close(t, h_proc.value, 33)

			nil_w: Width
			nil_h: Height
			testing.expect(t, !cfg_width_is_set(nil_w))
			testing.expect(t, !cfg_height_is_set(nil_h))
			testing.expect(t, resolve_length_from_width(nil_w, 10, &frame, event).kind == .AUTO)
			testing.expect(t, resolve_length_from_height(nil_h, 10, &frame, event).kind == .AUTO)
		},
	)
}

@(test)
style_theme_defaults_and_unset_fields_from_theme :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			theme.gap_x = u16(7)
			theme.gap_y = u16(9)
			theme.direction = Direction_Layout.HORIZONTAL
			theme.justify = Justify_Pos{x = .END, y = .CENTER}
			theme.border_color = Color.DESTRUCTIVE
			theme.background = Color.PRIMARY

			root := style_root(.ARTBOARD, {0, 0, 100, 50})
			testing.expect(t, root.style.space == .ARTBOARD)
			testing.expect_value(t, root.style.gap_x, u16(7))
			testing.expect_value(t, root.style.gap_y, u16(9))
			testing.expect(t, root.style.direction == .HORIZONTAL)
			testing.expect(t, root.style.justify.x == Justify_Align.END)
			testing.expect(t, root.style.justify.y == Justify_Align.CENTER)
			testing.expect(t, root.style.wrap == .BALANCE)
			testing.expect(t, root.style.align == .LEFT)
			testing.expect(t, root.style.texture_fit == .FILL)
			expect_close(t, root.style.line_height, 1)

			ui_push_style(root)
			defer ui_pop_style()

			frame, event := ui_test_frame_event()
			resolved := resolve_widget_config({}, {}, &frame, event)
			testing.expect_value(t, resolved.gap_x, u16(7))
			testing.expect_value(t, resolved.gap_y, u16(9))
			testing.expect(t, resolved.direction == .HORIZONTAL)
			testing.expect(t, resolved.justify.x == Justify_Align.END)
			testing.expect(t, resolved.width.kind == .AUTO)
			testing.expect(t, resolved.height.kind == .AUTO)

			bg, bg_ok := resolved.background.(RGBA)
			testing.expect(t, bg_ok)
			primary, _ := to_rgba(Color.PRIMARY, &frame, event)
			testing.expect_value(t, bg.r, primary.r)
			testing.expect_value(t, bg.g, primary.g)
			testing.expect_value(t, bg.b, primary.b)
		},
	)
}

@(test)
style_resolve_space_font_and_color_inherit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			font := Font_Handle {
				size_px = 18,
			}
			parent := resolve_widget_config(
				{},
				{
					space = {mode = .Value, value = Draw_Space.ARTBOARD},
					font = {mode = .Value, value = font},
					font_size = {mode = .Value, value = f32(18)},
					color = {mode = .Value, value = RGBA{10, 20, 30, 255}},
					background = {mode = .Value, value = RGBA{1, 2, 3, 255}},
					border_color = {mode = .Value, value = RGBA{4, 5, 6, 255}},
				},
				&frame,
				event,
			)
			testing.expect(t, parent.space == .ARTBOARD)
			testing.expect_value(t, parent.font.size_px, f32(18))
			expect_close(t, parent.font_size, 18)

			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			child := resolve_widget_config(
				{},
				{
					space = {mode = .Value, value = Inherit.INHERIT},
					font = {mode = .Value, value = Inherit.INHERIT},
					font_size = {mode = .Value, value = Inherit.INHERIT},
					color = {mode = .Value, value = Color.INHERIT},
					background = {mode = .Value, value = Color.INHERIT},
					border_color = {mode = .Value, value = Color.INHERIT},
				},
				&frame,
				event,
			)
			testing.expect(t, child.space == .ARTBOARD)
			testing.expect_value(t, child.font.size_px, f32(18))
			expect_close(t, child.font_size, 18)

			color, cok := child.color.(RGBA)
			testing.expect(t, cok)
			testing.expect_value(t, color.r, u8(10))
			bg, bok := child.background.(RGBA)
			testing.expect(t, bok)
			testing.expect_value(t, bg.g, u8(2))
			bc, bcok := child.border_color.(RGBA)
			testing.expect(t, bcok)
			testing.expect_value(t, bc.b, u8(6))
		},
	)
}

@(test)
style_child_context_clamps_when_insets_exceed_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_push_style(Style_Context{content_w = 20, content_h = 10})
			defer ui_pop_style()

			config := Resolved_Widget_Config {
				style = {
					padding = Pd{t = 8, b = 8, l = 8, r = 8},
					border = Bd{t = 5, b = 5, l = 5, r = 5},
				},
			}
			child := style_child_context(config)
			expect_close(t, child.content_w, 0)
			expect_close(t, child.content_h, 0)
		},
	)
}

@(test)
style_merge_widget_config_covers_layout_and_text_fields :: proc(t: ^testing.T) {
	ov_auto: Overflow = .AUTO
	ov_hidden: Overflow = .HIDDEN
	ov_scroll: Overflow = .SCROLL
	vis_visible: Visibility = .VISIBLE
	vis_hidden: Visibility = .HIDDEN
	pos_rel: Position = .RELATIVE
	pos_abs: Position = .ABSOLUTE

	base := Widget_Config {
		id = "base",
		overflow_x = {mode = .Value, value = ov_auto},
		visibility = {mode = .Value, value = vis_visible},
		position = {mode = .Value, value = pos_rel},
		space = {mode = .Value, value = Draw_Space.SCREEN},
		wrap = {mode = .Value, value = Text_Wrap_Kind.BALANCE},
		align = {mode = .Value, value = Text_Align_Kind.LEFT},
		z_index = {mode = .Value, value = f32(1)},
		texture_fit = {mode = .Value, value = Texture_Fit.FILL},
	}
	override := Widget_Config {
		overflow_x = {mode = .Value, value = ov_hidden},
		overflow_y = {mode = .Value, value = ov_scroll},
		visibility = {mode = .Value, value = vis_hidden},
		position = {mode = .Value, value = pos_abs},
		space = {mode = .Value, value = Draw_Space.ARTBOARD},
		wrap = {mode = .Value, value = Text_Wrap_Kind.NONE},
		align = {mode = .Value, value = Text_Align_Kind.CENTER},
		z_index = {mode = .Value, value = f32(9)},
		x = {mode = .Value, value = f32(3)},
		y = {mode = .Value, value = f32(4)},
		self = {mode = .Value, value = Justify_Align.END},
		texture_fit = {mode = .Value, value = Texture_Fit.CONTAIN},
		text_direction = {mode = .Value, value = Text_Direction_Kind.RTL},
		letter_spacing = {mode = .Value, value = f32(0.25)},
	}

	merged := merge_widget_config(base, override)
	testing.expect_value(t, merged.id, "base")
	testing.expect(t, merged.overflow_x.value == ov_hidden)
	testing.expect(t, merged.overflow_y.value == ov_scroll)
	testing.expect(t, merged.visibility.value == vis_hidden)
	testing.expect(t, merged.position.value == pos_abs)
	testing.expect(t, merged.space.value.(Draw_Space) == .ARTBOARD)
	testing.expect(t, merged.wrap.value.(Text_Wrap_Kind) == .NONE)
	testing.expect(t, merged.align.value.(Text_Align_Kind) == .CENTER)
	expect_close(t, cfg_style_f32(merged.z_index), 9)
	expect_close(t, cfg_style_f32(merged.x), 3)
	expect_close(t, cfg_style_f32(merged.y), 4)
	testing.expect(t, merged.texture_fit.value.(Texture_Fit) == .CONTAIN)
	testing.expect(t, merged.text_direction.value.(Text_Direction_Kind) == .RTL)
	expect_close(t, cfg_style_f32(merged.letter_spacing), 0.25)
}

@(test)
style_resolve_percent_minmax_and_self_inherit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			resolved := resolve_widget_config(
				{},
				{
					width = Dim_struct{percent = 50},
					height = Dim_struct{percent = 25},
					min_w = {mode = .Value, value = f32(11)},
					max_w = {mode = .Value, value = f32(400)},
					min_h = {mode = .Value, value = f32(9)},
					max_h = {mode = .Value, value = f32(300)},
					self = {mode = .Value, value = Inherit.INHERIT},
					justify = {mode = .Value, value = Inherit.INHERIT},
				},
				&frame,
				event,
			)

			testing.expect(t, resolved.width.kind == .PERCENT)
			expect_close(t, resolved.width.value, 50)
			testing.expect(t, resolved.height.kind == .PERCENT)
			expect_close(t, resolved.height.value, 25)
			expect_close(t, resolved.min_w, 11)
			expect_close(t, resolved.max_w, 400)
			expect_close(t, resolved.min_h, 9)
			expect_close(t, resolved.max_h, 300)

			_, self_x_ok := justify_align_from_x(resolved.self.x)
			testing.expect(t, !self_x_ok)
			// Unset justify inherits theme START via parent stack root.
			testing.expect(t, resolved.justify.x == Justify_Align.START)
		},
	)
}

@(test)
style_finalize_resolves_text_overflow_visibility_position_texture :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			ov_hidden: Overflow = .HIDDEN
			ov_scroll: Overflow = .SCROLL
			vis_hidden: Visibility = .HIDDEN
			pos_abs: Position = .ABSOLUTE

			resolved := resolve_widget_config(
				{},
				{
					align = {mode = .Value, value = Text_Align_Kind.RIGHT},
					wrap = {mode = .Value, value = Text_Wrap_Kind.NONE},
					text_decoration = {mode = .Value, value = Text_Decoration_Lines{.LINE_THROUGH}},
					text_decoration_style = {
						mode = .Value,
						value = Text_Decoration_Style_Kind.DOTTED,
					},
					text_decoration_color = {mode = .Value, value = Color.INHERIT},
					text_direction = {mode = .Value, value = Text_Direction_Kind.RTL},
					font_weight = {mode = .Value, value = Font_Weights.Bold},
					font_style = {mode = .Value, value = Font_Styles.ITALIC},
					overflow_x = {mode = .Value, value = ov_hidden},
					overflow_y = {mode = .Value, value = ov_scroll},
					visibility = {mode = .Value, value = vis_hidden},
					position = {mode = .Value, value = pos_abs},
					texture_fit = {mode = .Value, value = Texture_Fit.COVER},
					color = {mode = .Value, value = Color.SUCCESS},
				},
				&frame,
				event,
			)

			testing.expect(t, resolved.align == Text_Align_Kind.RIGHT)
			testing.expect(t, resolved.wrap == Text_Wrap_Kind.NONE)
			testing.expect(t, .LINE_THROUGH in resolved.text_decoration.(Text_Decoration_Lines))
			testing.expect(t, resolved.text_decoration_style == Text_Decoration_Style_Kind.DOTTED)
			// INHERIT decoration color must remain Color.INHERIT through finalize.
			deco_c, deco_ok := resolved.text_decoration_color.(Color)
			testing.expect(t, deco_ok)
			testing.expect(t, deco_c == .INHERIT)
			testing.expect(t, resolved.text_direction == Text_Direction_Kind.RTL)
			testing.expect(t, resolved.font_weight == Font_Weights.Bold)
			testing.expect(t, resolved.font_style == Font_Styles.ITALIC)
			testing.expect(t, resolved.overflow_x == ov_hidden)
			testing.expect(t, resolved.overflow_y == ov_scroll)
			testing.expect(t, resolved.visibility == vis_hidden)
			testing.expect(t, resolved.position == pos_abs)
			testing.expect(t, resolved.texture_fit == Texture_Fit.COVER)

			color, cok := resolved.color.(RGBA)
			testing.expect(t, cok)
			success, _ := to_rgba(Color.SUCCESS, &frame, event)
			testing.expect_value(t, color.g, success.g)
		},
	)
}

@(test)
style_resolve_helpers_evaluate_proc_callbacks :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			align_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Text_Align {
				_ = frame_state
				_ = event
				return Text_Align_Kind.RIGHT
			}
			align, aok := resolve_text_align(Text_Align(align_proc), &frame, event)
			testing.expect(t, aok)
			testing.expect(t, align == Text_Align_Kind.RIGHT)

			wrap_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Text_Wrap {
				_ = frame_state
				_ = event
				return Text_Wrap_Kind.BALANCE
			}
			wrap, wok := resolve_text_wrap(Text_Wrap(wrap_proc), &frame, event)
			testing.expect(t, wok)
			testing.expect(t, wrap == Text_Wrap_Kind.BALANCE)

			weight_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Font_Weight {
				_ = frame_state
				_ = event
				return Font_Weights.Light
			}
			weight, wok2 := resolve_font_weight(Font_Weight(weight_proc), &frame, event)
			testing.expect(t, wok2)
			testing.expect(t, weight == Font_Weights.Light)

			style_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Font_Style {
				_ = frame_state
				_ = event
				return Font_Styles.ITALIC
			}
			fs, fok := resolve_font_style(Font_Style(style_proc), &frame, event)
			testing.expect(t, fok)
			testing.expect(t, fs == Font_Styles.ITALIC)

			overflow_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Overflow {
				_ = frame_state
				_ = event
				return .SCROLL
			}
			overflow, ook := resolve_overflow(Overflow(overflow_proc), &frame, event)
			testing.expect(t, ook)
			testing.expect(t, overflow == .SCROLL)

			vis_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Visibility {
				_ = frame_state
				_ = event
				return .HIDDEN
			}
			vis, vok := resolve_visibility(Visibility(vis_proc), &frame, event)
			testing.expect(t, vok)
			testing.expect(t, vis == .HIDDEN)

			pos_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Position {
				_ = frame_state
				_ = event
				return .FIXED
			}
			pos, pok := resolve_position(Position(pos_proc), &frame, event)
			testing.expect(t, pok)
			testing.expect(t, pos == .FIXED)

			deco_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Text_Decoration {
				_ = frame_state
				_ = event
				return Text_Decoration_Lines{.OVERLINE}
			}
			deco, dok := resolve_text_decoration(Text_Decoration(deco_proc), &frame, event)
			testing.expect(t, dok)
			testing.expect(t, .OVERLINE in deco.(Text_Decoration_Lines))

			deco_style_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Text_Decoration_Style {
				_ = frame_state
				_ = event
				return Text_Decoration_Style_Kind.WAVY
			}
			deco_style, dsok := resolve_text_decoration_style(
				Text_Decoration_Style(deco_style_proc),
				&frame,
				event,
			)
			testing.expect(t, dsok)
			testing.expect(t, deco_style == Text_Decoration_Style_Kind.WAVY)

			dir_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Text_Direction {
				_ = frame_state
				_ = event
				return Text_Direction_Kind.RTL
			}
			dir, dir_ok := resolve_text_direction(Text_Direction(dir_proc), &frame, event)
			testing.expect(t, dir_ok)
			testing.expect(t, dir == Text_Direction_Kind.RTL)
		},
	)
}

@(test)
style_being_and_end_children_push_pop_scope_and_style :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			defer layout_end_space()

			frame, event := ui_test_frame_event()
			config := resolve_widget_config(
				{},
				{
					id = "box",
					padding = {mode = .Value, value = f32(5)},
					width = f32(100),
					height = f32(80),
				},
				&frame,
				event,
			)
			id := ui_id("box")

			testing.expect(t, ui_pass() == .Layout)
			before_style := len(state.ui.style_stack)
			before_scope := len(state.ui.scope_stack)

			being_children(id, config)
			testing.expect_value(t, len(state.ui.style_stack), before_style + 1)
			testing.expect_value(t, len(state.ui.scope_stack), before_scope + 1)
			expect_close(t, ui_style_current().content_w, 800 - 10)
			testing.expect(t, ui_has_layout_node(id))

			end_children()
			testing.expect_value(t, len(state.ui.style_stack), before_style)
			testing.expect_value(t, len(state.ui.scope_stack), before_scope)
		},
	)
}

@(test)
style_children_nil_builder_still_scopes :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			defer layout_end_space()

			frame, event := ui_test_frame_event()
			config := resolve_widget_config(
				{},
				{id = "empty", padding = {mode = .Value, value = f32(2)}},
				&frame,
				event,
			)
			id := ui_id("empty")
			before := len(state.ui.scope_stack)
			Children(proc(_: Widget_Frame_State) {}, id, config, frame)
			// nil-equivalent empty proc still runs; stack restored.
			testing.expect_value(t, len(state.ui.scope_stack), before)
			testing.expect(t, ui_has_layout_node(id))
		},
	)
}

@(test)
style_resolve_gap_direction_justify_from_parent_and_explicit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			parent := resolve_widget_config(
				{},
				{
					gap_x = {mode = .Value, value = u16(12)},
					gap_y = {mode = .Value, value = u16(6)},
					direction = {mode = .Value, value = Direction_Layout.HORIZONTAL},
					justify = {
						mode = .Value,
						value = Justify_Pos{x = .SPACE_BETWEEN, y = .END},
					},
				},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			inherited := resolve_widget_config(
				{},
				{
					gap_x = {mode = .Value, value = Inherit.INHERIT},
					gap_y = {mode = .Value, value = Inherit.INHERIT},
					direction = {mode = .Value, value = Inherit.INHERIT},
					justify = {mode = .Value, value = Inherit.INHERIT},
				},
				&frame,
				event,
			)
			testing.expect_value(t, inherited.gap_x, u16(12))
			testing.expect_value(t, inherited.gap_y, u16(6))
			testing.expect(t, inherited.direction == .HORIZONTAL)
			testing.expect(t, inherited.justify.x == Justify_Align.SPACE_BETWEEN)
			testing.expect(t, inherited.justify.y == Justify_Align.END)

			override := resolve_widget_config(
				{},
				{
					gap_x = {mode = .Value, value = u16(1)},
					gap_y = {mode = .Value, value = u16(2)},
					direction = {mode = .Value, value = Direction_Layout.VERTICAL},
					justify = {mode = .Value, value = Justify_Align.CENTER},
				},
				&frame,
				event,
			)
			testing.expect_value(t, override.gap_x, u16(1))
			testing.expect_value(t, override.gap_y, u16(2))
			testing.expect(t, override.direction == .VERTICAL)
			testing.expect(t, override.justify.x == Justify_Align.CENTER)
			testing.expect(t, override.justify.y == Justify_Align.CENTER)
		},
	)
}

@(test)
style_resolve_bool_and_f32_unset_use_theme_or_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			parent := resolve_widget_config(
				{},
				{
					disabled = {mode = .Value, value = true},
					tabbable = {mode = .Value, value = true},
					auto_focus = {mode = .Value, value = true},
					flex = {mode = .Value, value = f32(2.5)},
					z_index = {mode = .Value, value = f32(4)},
				},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			// Unset → theme defaults (false / 0), not parent — only Value+INHERIT inherits.
			unset := resolve_widget_config({}, {}, &frame, event)
			testing.expect(t, !unset.disabled)
			testing.expect(t, !unset.tabbable)
			testing.expect(t, !unset.auto_focus)
			expect_close(t, unset.flex, 0)
			expect_close(t, unset.z_index, 0)

			inherited := resolve_widget_config(
				{},
				{
					disabled = {mode = .Value, value = Inherit.INHERIT},
					tabbable = {mode = .Value, value = Inherit.INHERIT},
					auto_focus = {mode = .Value, value = Inherit.INHERIT},
					flex = {mode = .Value, value = Inherit.INHERIT},
					z_index = {mode = .Value, value = Inherit.INHERIT},
				},
				&frame,
				event,
			)
			testing.expect(t, inherited.disabled)
			testing.expect(t, inherited.tabbable)
			testing.expect(t, inherited.auto_focus)
			expect_close(t, inherited.flex, 2.5)
			expect_close(t, inherited.z_index, 4)
		},
	)
}

@(test)
style_resolve_cfg_self_partial_and_full_align :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			partial := resolve_cfg_self(
				{mode = .Value, value = Justify_Pos{y = Justify_Align.END}},
				&frame,
				event,
			)
			testing.expect(t, partial.y == Justify_Align.END)
			_, x_ok := justify_align_from_x(partial.x)
			testing.expect(t, !x_ok)

			full := resolve_widget_config(
				{},
				{self = {mode = .Value, value = Justify_Align.CENTER}},
				&frame,
				event,
			)
			testing.expect(t, full.self.x == Justify_Align.CENTER)
			testing.expect(t, full.self.y == Justify_Align.CENTER)
		},
	)
}

@(test)
style_resolve_order_and_z_index_callbacks :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			order_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Style_F32 {
				_ = frame_state
				_ = event
				return f32(7)
			}
			z_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Style_F32 {
				_ = frame_state
				_ = event
				return f32(11)
			}

			resolved := resolve_widget_config(
				{},
				{
					order = {mode = .Value, value = order_proc},
					z_index = {mode = .Value, value = z_proc},
				},
				&frame,
				event,
			)
			expect_close(t, resolved.order, 7)
			expect_close(t, resolved.z_index, 11)

			unset := resolve_widget_config({}, {}, &frame, event)
			expect_close(t, unset.order, 0)
			expect_close(t, unset.z_index, 0)
		},
	)
}

@(test)
style_merge_order_overrides_base :: proc(t: ^testing.T) {
	base := Widget_Config {
		order = {mode = .Value, value = f32(1)},
		z_index = {mode = .Value, value = f32(2)},
	}
	override := Widget_Config {
		order = {mode = .Value, value = f32(9)},
		z_index = {mode = .Value, value = f32(8)},
	}
	merged := merge_widget_config(base, override)
	expect_close(t, cfg_style_f32(merged.order), 9)
	expect_close(t, cfg_style_f32(merged.z_index), 8)
}

