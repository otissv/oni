package oni

import "core:testing"

@(private)
App_Type_Test_Enum :: enum {
	Tool,
	Game,
}

@(test)
app_type_get_set :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			testing.expect_value(t, int(app_type()), 0)
			app_type_set(App_Type_Id(1))
			testing.expect_value(t, int(app_type()), 1)
			app_type_set_enum(App_Type_Test_Enum, App_Type_Test_Enum.Game)
			testing.expect_value(t, int(app_type_as(App_Type_Test_Enum)), int(App_Type_Test_Enum.Game))
		},
	)
}
