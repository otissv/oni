#+test
package oni

import "core:testing"
import "core:slice"

@(test)
vector_svg_flat_direct_recording_matches_generic_paths :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M0 0L10 0L0 10Z" fill="red"/><path d="M5 5L15 5L5 15Z" fill="blue"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		state.ui.pass = .Draw
		transform := Vector_Transform{1, .25, -.5, 2, 13, 17}
		testing.expect_value(t, Draw_Svg_Asset(asset, transform, .7), Vector_Error.None)
		instances := slice.clone(vector_frame().instances[:])
		defer delete(instances)
		commands := slice.clone(vector_frame().commands[:])
		defer delete(commands)
		vertices := slice.clone(vector_frame().vertices[:])
		defer delete(vertices)
		batch_reset()
		items := make([dynamic]Vector_Path_Draw, context.temp_allocator)
		testing.expect(t, draw_svg_collect_paths(asset.roots, transform, .7, &items))
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().instances), len(instances))
		testing.expect_value(t, len(vector_frame().commands), len(commands))
		testing.expect_value(t, len(vector_frame().vertices), len(vertices))
		for instance, i in instances { testing.expect_value(t, vector_frame().instances[i], instance) }
		for command, i in commands { testing.expect_value(t, vector_frame().commands[i], command) }
		for vertex, i in vertices { testing.expect_value(t, vector_frame().vertices[i], vertex) }
	})
}
