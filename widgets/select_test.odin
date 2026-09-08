package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
select_test_value: string

@(private)
select_test_open: bool

@(private)
select_test_on_value :: proc(value: string) {
	select_test_value = value
}

@(private)
select_test_on_open :: proc(open: bool) {
	select_test_open = open
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
			config = {
				id = "fruit",
				width = set.Width(f32(200)),
				height = set.Height(f32(40)),
			},
			open = true,
			on_open_change = select_test_on_open,
			child = proc(_: Select_State) {
				Select_Trigger({
					config = {
						id = "fruit-trigger",
						width = set.Width(f32(160)),
						height = set.Height(f32(32)),
					},
					child = proc(_: Select_Trigger_State) {
						Select_Value({
							config = {id = "fruit-value"},
							placeholder = "Pick",
						})
					},
				})
			},
			content = proc(_: Select_State) {
				Option_Group({
					config = {id = "fruit-group"},
					child = proc(_: Option_Group_State) {
						Option({
							config = {id = "fruit-apple"},
							value = "apple",
							text = "Apple",
						})
					},
				})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "fruit")
		expect_layout_kind(t, "fruit", .SELECT)
		expect_registered_id(t, "fruit-trigger")
		expect_registered_id(t, "fruit-value")
		expect_registered_id(t, "fruit-group")
		expect_registered_id(t, "fruit-apple")

		root, root_ok := widget_test_layout_node("fruit")
		testing.expect(t, root_ok)
		if !root_ok do return

		testing.expect(t, len(root.child_indices) >= 1)
		if len(root.child_indices) < 1 do return

		trigger := &o.state.ui.layout.nodes[root.child_indices[0]]
		testing.expect(t, trigger.kind == .SELECT_TRIGGER)
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
select_uncontrolled_option_sets_value_and_closes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push(
			{
				select_key = "pick",
				open = true,
				value_controlled = false,
				open_controlled = false,
			},
		)
		defer select_ctx_pop()

		select_set_value("red", "Red")
		testing.expect_value(t, Select_Get_Value(), "red")
		testing.expect(t, !Select_Is_Open())

		rt := select_runtime_ensure("pick")
		testing.expect(t, rt != nil)
		if rt == nil do return
		testing.expect_value(t, rt.value, "red")
		testing.expect_value(t, rt.value_label, "Red")
		testing.expect(t, rt.value_set)
	})
}

@(test)
select_set_value_updates_runtime_label :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer select_shutdown()

		select_ctx_push(
			{
				select_key = "runtime-sel",
				value_controlled = false,
				open_controlled = false,
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

		select_ctx_push(
			{
				select_key = "multi",
				multiple = true,
				listbox = true,
				open = true,
				value_controlled = false,
				open_controlled = false,
			},
		)
		defer select_ctx_pop()

		select_set_value("a", "A")
		select_set_value("b", "B")
		testing.expect(t, Select_Is_Open())
		testing.expect_value(t, len(Select_Get_Values()), 2)

		select_set_value("a", "A")
		testing.expect_value(t, len(Select_Get_Values()), 1)
		testing.expect_value(t, Select_Get_Value(), "b")
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
