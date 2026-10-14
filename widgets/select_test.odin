package oni_widgets

import o ".."
import set "../set"
import "core:strings"
import "core:testing"

@(private)
select_test_value: string

@(private)
select_test_open: bool

@(private)
select_test_values: [dynamic]string

@(private)
select_test_trigger_clicks: int

@(private)
select_test_option_clicks: int

@(private)
select_test_replace_values :: proc(values: []string) {
	for value in select_test_values {
		delete(value)
	}

	clear(&select_test_values)

	for value in values {
		append(&select_test_values, strings.clone(value))
	}
}

@(private)
select_test_find_trigger_and_popover_content :: proc(
	root: ^o.Layout_Node,
) -> (
	trigger: ^o.Layout_Node,
	content: ^o.Layout_Node,
) {
	if root == nil {
		return
	}

	stack: [64]int
	depth := 0

	for child_index in root.child_indices {
		if depth >= len(stack) {
			break
		}

		stack[depth] = child_index
		depth += 1
	}

	for depth > 0 {
		depth -= 1
		node := &o.state.ui.layout.nodes[stack[depth]]

		if node.kind == .SELECT_TRIGGER {
			trigger = node
		} else if node.space == .POPOVER && node.kind == .RECT {
			content = node
		}

		for child_index in node.child_indices {
			if depth >= len(stack) {
				break
			}

			stack[depth] = child_index
			depth += 1
		}
	}

	return
}

@(private)
select_test_anchor_trigger_child :: proc(_: Select_Trigger_State) {
	Select_Value({config = {id = "anchor-value"}, placeholder = "Pick"})
}

@(private)
select_test_anchor_child :: proc(_: Select_State) {
	Select_Trigger(
		{
			config = {
				id = "anchor-trigger",
				width = set.Width(f32(240)),
				height = set.Height(f32(40)),
			},
			child = select_test_anchor_trigger_child,
		},
	)
}

@(private)
select_test_anchor_content :: proc(_: Select_State) {
	Option({config = {id = "anchor-option"}, value = "one", text = "One"})
}

@(private)
select_test_click_content :: proc(_: Select_State) {
	Option(
		{
			config = {id = "click-option"},
			value = "one",
			text = "One",
			on_click = select_test_on_option_click,
		},
	)
}

@(private)
select_test_sized_content :: proc(_: Select_State) {
	Option(
		{
			config = {id = "sized-option-1", height = set.Height(f32(20))},
			value = "one",
			text = "One",
		},
	)
	Option(
		{
			config = {id = "sized-option-2", height = set.Height(f32(40))},
			value = "two",
			text = "Two",
		},
	)
	Option(
		{
			config = {id = "sized-option-3", height = set.Height(f32(60))},
			value = "three",
			text = "Three",
		},
	)
}

@(private)
select_test_on_value :: proc(value: string) {
	select_test_value = value
}

@(private)
select_test_on_open :: proc(open: bool) {
	select_test_open = open
}

@(private)
select_test_on_trigger_click :: proc(_: Select_Trigger_Event) {
	select_test_trigger_clicks += 1
}

@(private)
select_test_on_option_click :: proc(_: Option_Event) {
	select_test_option_clicks += 1
}

@(test)
select_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Select_State{}
	base := select_theme_base(&frame)
	testing.expect(t, base.kind == .SELECT)
}

@(test)
select_trigger_theme_base_sets_kind_and_tabbable :: proc(t: ^testing.T) {
	frame := Select_Trigger_State{}
	base := select_trigger_theme_base(&frame)
	testing.expect(t, base.kind == .SELECT_TRIGGER)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
	hidden: o.Overflow = .HIDDEN
	testing.expect(t, base.overflow_x.value == hidden)
	testing.expect(t, base.overflow_y.value == hidden)
}

@(test)
select_value_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Select_Value_State{}
	base := select_value_theme_base(&frame)
	testing.expect(t, base.kind == .SELECT_VALUE)
}

@(test)
option_group_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Option_Group_State{}
	base := option_group_theme_base(&frame)
	testing.expect(t, base.kind == .OPTION_GROUP)
}

@(test)
option_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Option_State{}
	base := option_theme_base(&frame)
	testing.expect(t, base.kind == .OPTION)
}

@(test)
select_layout_registers_compound_kinds :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		Select({
			config = {id = "fruit", width = set.Width(f32(200)), height = set.Height(f32(40))},
			open = true,
			on_open_change = select_test_on_open,
			child = proc(_: Select_State) {
				Select_Trigger({
					config = {id = "fruit-trigger", width = set.Width(f32(160)), height = set.Height(f32(32))},
					child = proc(_: Select_Trigger_State) {
						Select_Value({config = {id = "fruit-value"}, placeholder = "Pick"})
					},
				})
			},
			content = proc(_: Select_State) {
				Option_Group({
					config = {id = "fruit-group"},
					child = proc(_: Option_Group_State) {
						Option({config = {id = "fruit-apple"}, value = "apple", text = "Apple"})
					},
				})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "fruit")
		expect_layout_kind(t, "fruit", .SELECT)
		expect_registered_id(t, "fruit/__select_popover")
		expect_registered_id(t, "fruit-trigger")
		expect_registered_id(t, "fruit-value")
		expect_registered_id(t, "fruit-group")
		expect_registered_id(t, "fruit-apple")

		root, root_ok := widget_test_layout_node("fruit")
		testing.expect(t, root_ok)
		if !root_ok do return

		testing.expect(t, len(root.child_indices) >= 1)
		if len(root.child_indices) < 1 do return

		popover := &o.state.ui.layout.nodes[root.child_indices[0]]
		testing.expect(t, popover.kind == .POPOVER)

		trigger_ok := false

		for child_index in popover.child_indices {
			child := &o.state.ui.layout.nodes[child_index]

			if child.kind == .SELECT_TRIGGER {
				trigger_ok = true

				break
			}
		}

		testing.expect(t, trigger_ok)
	})
}

@(test)
select_trigger_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		Select({
			config = {id = "sel-tab"},
			child = proc(_: Select_State) {
				Select_Trigger({config = {id = "sel-tab-trigger"}})
			},
		})
		expect_in_tab_order(t, "sel-tab-trigger", true)
		widget_test_finish_layout()
	})
}

@(test)
select_single_value_callback_updates_cache_and_closes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_test_value = ""
		select_test_open = true
		select_ctx_push(
			{
				select_key = "pick",
				open = true,
				on_value_change = select_test_on_value,
				on_open_change = select_test_on_open,
			},
		)
		defer select_ctx_pop()

		select_set_value("red", "Red")
		testing.expect_value(t, select_test_value, "red")
		testing.expect(t, !select_test_open)

		rt := select_runtime_ensure("pick")
		testing.expect(t, rt != nil)
		if rt == nil do return
		testing.expect_value(t, rt.cache_value, "red")
		testing.expect_value(t, rt.value_label, "Red")
	})
}

@(test)
select_set_value_updates_runtime_label_cache :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push(
			{
				select_key = "runtime-sel",
				open = true,
			},
		)
		defer select_ctx_pop()

		select_set_value("banana", "Banana")
		testing.expect_value(t, Select_Get_Value(), "banana")
		testing.expect(t, !Select_Is_Open())

		ctx := select_ctx_top()
		testing.expect_value(t, select_resolve_value_label(ctx), "Banana")
	})
}

@(test)
select_multiple_toggles_without_closing :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()
		defer {
			for value in select_test_values {
				delete(value)
			}

			delete(select_test_values)
			select_test_values = nil
		}

		select_ctx_push(
			{
				select_key = "multi",
				multiple = true,
				listbox = true,
				open = true,
				on_values_change = select_test_replace_values,
			},
		)
		defer select_ctx_pop()

		select_set_value("a", "A")
		select_set_value("b", "B")
		testing.expect(t, Select_Is_Open())
		testing.expect_value(t, len(select_test_values), 2)

		select_set_value("a", "A")
		testing.expect_value(t, len(select_test_values), 1)

		if len(select_test_values) == 1 {
			testing.expect_value(t, select_test_values[0], "b")
		}
	})
}

@(test)
select_controlled_multiple_callback_does_not_alias_source_values :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()
		defer {
			for value in select_test_values {
				delete(value)
			}

			delete(select_test_values)
			select_test_values = nil
		}

		append(&select_test_values, strings.clone("a"), strings.clone("b"))
		select_ctx_push(
			{
				select_key = "controlled-multi",
				multiple = true,
				listbox = true,
				open = true,
				on_values_change = select_test_replace_values,
			},
		)
		defer select_ctx_pop()

		ctx := select_ctx_top()
		select_copy_values_into_ctx(ctx, select_test_values[:])
		select_set_value("a", "A")

		testing.expect_value(t, len(select_test_values), 1)
		testing.expect_value(t, ctx.value_count, 1)
		testing.expect_value(t, ctx.values[0], "b")

		if len(select_test_values) == 1 {
			testing.expect_value(t, select_test_values[0], "b")
		}
	})
}

@(test)
select_is_listbox_for_multiple_or_size :: proc(t: ^testing.T) {
	testing.expect(t, select_is_listbox(true, 0))
	testing.expect(t, select_is_listbox(false, 2))
	testing.expect(t, !select_is_listbox(false, 0))
	testing.expect(t, !select_is_listbox(false, 1))
	testing.expect_value(t, select_visible_rows(true, 0), u8(4))
	testing.expect_value(t, select_visible_rows(false, 3), u8(3))
}

@(test)
select_open_dropdown_height_hugs_options_not_viewport :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		Select(
			{
				config = {id = "hug-select", x = set.F32(40), y = set.F32(80)},
				open = true,
				child = select_test_anchor_child,
				content = select_test_anchor_content,
			},
		)
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("hug-select")
		testing.expect(t, root_ok)

		if !root_ok do return

		trigger, content := select_test_find_trigger_and_popover_content(root)
		testing.expect(t, trigger != nil)
		testing.expect(t, content != nil)

		if trigger == nil || content == nil do return

		widget_test_begin_draw()

		viewport_h := f32(o.state.dpi.logical_h)
		testing.expect(t, content.rect.h > 0)
		testing.expect(t, content.rect.h < viewport_h * 0.5)
		testing.expect(t, content.rect.y + content.rect.h < trigger.rect.y + trigger.rect.h + 200)
	})
}

@(test)
select_content_anchors_below_trigger_and_trigger_clips_children :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		Select({config = {id = "anchor-select", x = set.F32(35), y = set.F32(60)}, open = true, on_open_change = select_test_on_open, child = select_test_anchor_child, content = select_test_anchor_content})
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("anchor-select")
		testing.expect(t, root_ok)

		if !root_ok do return

		trigger, content := select_test_find_trigger_and_popover_content(root)
		trigger_ok := trigger != nil
		content_ok := content != nil
		testing.expect(t, trigger_ok)
		testing.expect(t, content_ok)

		if !trigger_ok || !content_ok do return

		widget_test_begin_draw()

		expect_close(t, content.rect.x, trigger.rect.x)
		expect_close(t, content.rect.y, trigger.rect.y + trigger.rect.h + 4)
		testing.expect(t, content.rect.w >= trigger.rect.w)
		testing.expect(t, trigger.has_clip)
		testing.expect(t, trigger.clip_rect.y > trigger.rect.y)
		testing.expect(t, trigger.clip_rect.y + trigger.clip_rect.h < trigger.rect.y + trigger.rect.h)
	})
}

@(test)
select_dropdown_measures_options_and_flips_above_viewport_edge :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer {
				select_shutdown()
				widget_test_end_frame()
			}

			Select(
				{
					config = {id = "sized-select", y = set.F32(540)},
					open = true,
					on_open_change = select_test_on_open,
					child = select_test_anchor_child,
					content = select_test_sized_content,
				},
			)
			widget_test_finish_layout()

			root, root_ok := widget_test_layout_node("sized-select")
			testing.expect(t, root_ok)

			if !root_ok do return

			trigger, content := select_test_find_trigger_and_popover_content(root)
			trigger_ok := trigger != nil
			content_ok := content != nil
			testing.expect(t, trigger_ok)
			testing.expect(t, content_ok)

			if !trigger_ok || !content_ok do return

			widget_test_begin_draw()

			// Three measured rows (20 + 40 + 60), two 2px gaps, 8px padding,
			// and a 1px border on each edge.
			expect_close(t, content.rect.h, 134)
			expect_close(
				t,
				content.rect.y,
				trigger.rect.y - SELECT_DROPDOWN_GAP_PX - content.rect.h,
			)
			testing.expect(t, content.rect.y >= SELECT_DROPDOWN_VIEWPORT_MARGIN_PX)
		},
	)
}

@(test)
select_listbox_size_uses_measured_option_rows :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer {
				select_shutdown()
				widget_test_end_frame()
			}

			Select(
				{
					config = {id = "sized-listbox"},
					size = 2,
					child = select_test_anchor_child,
					content = select_test_sized_content,
				},
			)
			widget_test_finish_layout()

			root, root_ok := widget_test_layout_node("sized-listbox")
			content: ^o.Layout_Node

			if root_ok {
				for child_index in root.child_indices {
					child := &o.state.ui.layout.nodes[child_index]

					if child.kind == .RECT && child.space != .POPOVER {
						content = child
					}
				}
			}

			ok := content != nil
			testing.expect(t, root_ok)
			testing.expect(t, ok)

			if !ok do return

			widget_test_begin_draw()

			// The first two measured rows plus one gap and container chrome.
			expect_close(t, content.rect.h, 72)
		},
	)
}

@(test)
select_public_queries_are_empty_outside_context :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		testing.expect(t, !Select_Is_Open())
		testing.expect_value(t, Select_Get_Value(), "")
		testing.expect_value(t, len(Select_Get_Values()), 0)
	})
}

@(test)
select_public_queries_cover_single_and_multiple_values :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push({value = "one", open = true})
		testing.expect(t, Select_Is_Open())
		testing.expect_value(t, Select_Get_Value(), "one")
		values := Select_Get_Values()
		testing.expect_value(t, len(values), 1)

		if len(values) == 1 {
			testing.expect_value(t, values[0], "one")
		}

		select_ctx_pop()
		select_ctx_push({multiple = true, listbox = true})
		ctx := select_ctx_top()
		select_copy_values_into_ctx(ctx, []string{"one", "", "one", "two"})
		testing.expect(t, Select_Is_Open())
		testing.expect_value(t, Select_Get_Value(), "one")
		values = Select_Get_Values()
		testing.expect_value(t, len(values), 2)

		if len(values) == 2 {
			testing.expect_value(t, values[0], "one")
			testing.expect_value(t, values[1], "two")
		}

		select_ctx_pop()
	})
}

@(test)
select_runtime_initializes_and_shutdown_resets_state :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		testing.expect(t, select_runtime_ensure("") == nil)
		rt := select_runtime_ensure("runtime")
		testing.expect(t, rt != nil)

		if rt != nil {
			testing.expect_value(t, rt.highlight, -1)
			select_runtime_set_string(&rt.cache_value, "alpha")
			aliased_tail := rt.cache_value[1:]
			select_runtime_set_string(&rt.cache_value, aliased_tail)
			testing.expect_value(t, rt.cache_value, "lpha")
		}

		select_ctx_push({select_key = "runtime"})
		select_shutdown()
		testing.expect(t, select_runtimes == nil)
		testing.expect_value(t, select_ctx_depth, 0)
		testing.expect(t, !select_ctx_ok())
	})
}

@(test)
select_value_text_resolves_placeholder_labels_and_multiple_fallbacks :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		text, has_value := select_value_resolve_text({placeholder = "Pick"})
		testing.expect_value(t, text, "Pick")
		testing.expect(t, !has_value)

		select_ctx_push({select_key = "labels", value = "a"})
		text, has_value = select_value_resolve_text({placeholder = "Pick"})
		testing.expect_value(t, text, "a")
		testing.expect(t, has_value)
		_ = select_register_option("a", "Alpha", "option-a", false)
		text, has_value = select_value_resolve_text({placeholder = "Pick"})
		testing.expect_value(t, text, "Alpha")
		testing.expect(t, has_value)
		ctx := select_ctx_top()
		ctx.value = "b"
		ctx.value_label = ""
		text, has_value = select_value_resolve_text({placeholder = "Pick"})
		testing.expect_value(t, text, "b")
		testing.expect(t, has_value)
		select_ctx_pop()

		select_ctx_push({select_key = "multi-labels", multiple = true})
		ctx = select_ctx_top()
		select_copy_values_into_ctx(ctx, []string{"a", "b"})
		_ = select_register_option("a", "Alpha", "option-a", false)
		testing.expect_value(t, select_resolve_value_label(ctx), "Alpha, b")
		select_ctx_pop()
	})
}

@(test)
select_open_state_honors_disabled_listbox_and_highlight :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_test_open = false
		select_ctx_push(
			{
				select_key = "open-controlled",
				on_open_change = select_test_on_open,
			},
		)
		ctx := select_ctx_top()
		_ = select_register_option("a", "A", "a", false)
		_ = select_register_option("b", "B", "b", true)
		ctx.value = "a"
		select_set_open(true)
		testing.expect(t, ctx.open)
		testing.expect(t, select_test_open)
		testing.expect_value(t, ctx.highlight, 0)
		rt := select_runtime_ensure("open-controlled")
		testing.expect(t, rt != nil)

		if rt != nil {
			testing.expect_value(t, rt.highlight, 0)
		}

		select_ctx_pop()

		select_ctx_push({disabled = true})
		select_set_open(true)
		testing.expect(t, !select_ctx_top().open)
		select_ctx_pop()

		select_ctx_push({listbox = true, open = true})
		select_set_open(false)
		testing.expect(t, select_ctx_top().open)
		select_ctx_pop()
	})
}

@(test)
select_single_value_controlled_callback_closes_and_disabled_blocks :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_test_value = ""
		select_test_open = true
		select_ctx_push(
			{
				select_key = "controlled-value",
				open = true,
				on_value_change = select_test_on_value,
				on_open_change = select_test_on_open,
			},
		)
		select_set_value("a", "")
		ctx := select_ctx_top()
		testing.expect_value(t, select_test_value, "a")
		testing.expect_value(t, ctx.value_label, "a")
		testing.expect(t, !ctx.open)
		testing.expect(t, !select_test_open)
		select_ctx_pop()

		select_test_value = ""
		select_ctx_push({disabled = true, on_value_change = select_test_on_value})
		select_set_value("blocked", "Blocked")
		testing.expect_value(t, select_test_value, "")
		testing.expect_value(t, select_ctx_top().value, "")
		select_ctx_pop()
	})
}

@(test)
select_highlight_navigation_wraps_skips_disabled_and_commits :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push({select_key = "keyboard", open = true, highlight = -1})
		ctx := select_ctx_top()
		_ = select_register_option("a", "A", "a", false)
		_ = select_register_option("b", "B", "b", true)
		_ = select_register_option("c", "C", "c", false)

		select_move_highlight(1)
		testing.expect_value(t, ctx.highlight, 0)
		select_move_highlight(1)
		testing.expect_value(t, ctx.highlight, 2)
		select_move_highlight(1)
		testing.expect_value(t, ctx.highlight, 0)
		select_move_highlight(-1)
		testing.expect_value(t, ctx.highlight, 2)
		select_commit_highlight()
		testing.expect_value(t, ctx.value, "c")
		testing.expect_value(t, ctx.value_label, "C")
		testing.expect(t, !ctx.open)
		select_ctx_pop()
	})
}

@(test)
select_keyboard_open_navigate_commit_and_escape_consume_keys :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push({select_key = "keys"})
		ctx := select_ctx_top()
		_ = select_register_option("a", "A", "a", false)

		widget_test_press_shortcut(.DOWN)
		select_handle_typing_keys()
		testing.expect(t, ctx.open)
		testing.expect(t, o.shortcut_key_consumed(.DOWN))

		widget_test_press_shortcut(.DOWN)
		select_handle_typing_keys()
		testing.expect_value(t, ctx.highlight, 0)

		widget_test_press_shortcut(.RETURN)
		select_handle_typing_keys()
		testing.expect_value(t, ctx.value, "a")
		testing.expect(t, !ctx.open)
		testing.expect(t, o.shortcut_key_consumed(.RETURN))

		select_set_open(true)
		widget_test_press_shortcut(.ESCAPE)
		select_handle_typing_keys()
		testing.expect(t, !ctx.open)
		testing.expect(t, o.shortcut_key_consumed(.ESCAPE))
		select_ctx_pop()
	})
}

@(test)
select_wrapper_callbacks_preserve_user_handlers :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_test_trigger_clicks = 0
		select_test_option_clicks = 0
		select_ctx_push(
			{
				select_key = "wrappers",
				trigger_user_click = select_test_on_trigger_click,
				option_user_click = select_test_on_option_click,
			},
		)
		select_trigger_on_click({})
		testing.expect(t, select_ctx_top().open)
		testing.expect_value(t, select_test_trigger_clicks, 1)

		option_on_click({frame_state = {value = "a", text = "A"}})
		testing.expect_value(t, select_ctx_top().value, "a")
		testing.expect_value(t, select_test_option_clicks, 1)
		select_ctx_pop()
	})
}

@(test)
select_resolve_open_value_uses_props_and_cached_label :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		rt := select_runtime_ensure("resolve")
		testing.expect(t, rt != nil)

		if rt == nil do return

		select_runtime_set_string(&rt.cache_value, "runtime")
		select_runtime_set_string(&rt.value_label, "Runtime")

		open, value, label := select_resolve_open_value({open = true, value = "runtime"}, "resolve")
		testing.expect(t, open)
		testing.expect_value(t, value, "runtime")
		testing.expect_value(t, label, "Runtime")

		open, value, label = select_resolve_open_value({open = false, value = "controlled"}, "resolve")
		testing.expect(t, !open)
		testing.expect_value(t, value, "controlled")
		testing.expect_value(t, label, "")

		_, value, label = select_resolve_open_value({multiple = true, values = []string{"a"}}, "resolve")
		testing.expect_value(t, value, "")
		testing.expect_value(t, label, "")
	})
}

@(test)
select_trigger_click_notifies_controlled_open_end_to_end :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		select_test_trigger_clicks = 0
		select_test_open = false
		props := Select_Props {
			config = {id = "click-trigger-select"},
			open = select_test_open,
			on_open_change = select_test_on_open,
			child = proc(_: Select_State) {
				Select_Trigger({config = {id = "click-trigger", width = set.Width(f32(160)), height = set.Height(f32(32))}, on_click = select_test_on_trigger_click})
			},
			content = select_test_anchor_content,
		}
		Select(props)
		widget_test_finish_layout()

		trigger: ^o.Layout_Node

		for i in 0 ..< len(o.state.ui.layout.nodes) {
			if o.state.ui.layout.nodes[i].kind == .SELECT_TRIGGER {
				trigger = &o.state.ui.layout.nodes[i]

				break
			}
		}

		testing.expect(t, trigger != nil)

		if trigger == nil do return

		widget_test_begin_draw()
		o.w_ctx.mouse_x = trigger.rect.x + trigger.rect.w / 2
		o.w_ctx.mouse_y = trigger.rect.y + trigger.rect.h / 2
		o.w_ctx.left_mouse = {
			pressed  = true,
			released = true,
		}
		o.layout_resolve_pointer_hit()
		Select(props)

		testing.expect(t, select_test_open)
		testing.expect_value(t, select_test_trigger_clicks, 1)
	})
}

@(test)
select_option_click_commits_value_and_closes_end_to_end :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		select_test_value = ""
		select_test_open = true
		select_test_option_clicks = 0
		props := Select_Props {
			config = {id = "click-option-select"},
			open = true,
			on_value_change = select_test_on_value,
			on_open_change = select_test_on_open,
			child = select_test_anchor_child,
			content = select_test_click_content,
		}
		Select(props)
		widget_test_finish_layout()

		option: ^o.Layout_Node

		for i in 0 ..< len(o.state.ui.layout.nodes) {
			if o.state.ui.layout.nodes[i].kind == .OPTION {
				option = &o.state.ui.layout.nodes[i]

				break
			}
		}

		testing.expect(t, option != nil)

		if option == nil do return

		widget_test_begin_draw()
		o.w_ctx.mouse_x = option.rect.x + option.rect.w / 2
		o.w_ctx.mouse_y = option.rect.y + option.rect.h / 2
		o.w_ctx.left_mouse = {
			pressed  = true,
			released = true,
		}
		o.layout_resolve_pointer_hit()
		Select(props)

		testing.expect_value(t, select_test_value, "one")
		testing.expect(t, !select_test_open)
		testing.expect_value(t, select_test_option_clicks, 1)
	})
}

@(test)
select_outside_press_dismisses_open_dropdown_end_to_end :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		select_test_open = true
		props := Select_Props {
			config = {id = "outside-select"},
			open = true,
			on_open_change = select_test_on_open,
			child = select_test_anchor_child,
			content = select_test_anchor_content,
		}
		Select(props)
		widget_test_finish_layout()

		widget_test_begin_draw()
		o.w_ctx.mouse_x = 760
		o.w_ctx.mouse_y = 560
		o.w_ctx.left_mouse = {
			pressed = true,
		}
		o.layout_resolve_pointer_hit()
		Select(props)

		testing.expect(t, !select_test_open)
	})
}

@(test)
select_content_press_is_owned_and_does_not_dismiss :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer {
			select_shutdown()
			widget_test_end_frame()
		}

		select_test_open = true
		props := Select_Props {
			config = {id = "inside-select"},
			open = true,
			on_open_change = select_test_on_open,
			child = select_test_anchor_child,
			content = select_test_anchor_content,
		}
		Select(props)
		widget_test_finish_layout()

		option: ^o.Layout_Node

		for i in 0 ..< len(o.state.ui.layout.nodes) {
			if o.state.ui.layout.nodes[i].kind == .OPTION {
				option = &o.state.ui.layout.nodes[i]

				break
			}
		}

		testing.expect(t, option != nil)

		if option == nil do return

		widget_test_begin_draw()
		o.w_ctx.mouse_x = option.rect.x + option.rect.w / 2
		o.w_ctx.mouse_y = option.rect.y + option.rect.h / 2
		o.w_ctx.left_mouse = {
			pressed = true,
		}
		o.layout_resolve_pointer_hit()
		Select(props)

		testing.expect(t, select_test_open)
	})
}
