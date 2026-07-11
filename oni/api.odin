package oni

Bind :: bind

Init_Window_Only :: init_window_only
Init_Runtime :: init_runtime
Shutdown :: shutdown
Should_Run :: should_run
Run_Frame :: run_frame
On_Reload :: on_reload
Migrate_State :: migrate_state
After_Realloc :: after_realloc
Realloc_Failed :: realloc_failed

Init_Window :: init_window
Init :: init
Can_Render :: can_render
Frame_Time :: frame_time
Input_Begin_Frame :: input_begin_frame
Poll_Events :: poll_events
Begin_Frame :: ui_begin_frame
End_Frame :: end_frame
Present_Frame :: present_frame
On_Hot_Reload :: on_hot_reload
Reset_Input_State :: reset_input_state
Take_Force_Reload :: take_force_reload
Take_Force_Restart :: take_force_restart
Peek_Force_Reload :: peek_force_reload
Peek_Force_Restart :: peek_force_restart
Consume_Force_Reload :: consume_force_reload
Consume_Force_Restart :: consume_force_restart
Dpi_Sync :: dpi_sync

Log_Error :: log_error
Log_Errorf :: log_errorf
Log_Debug :: log
Log_Debugf :: logf

Draw_Rectangle :: draw_rect
Draw_Line :: draw_line
Draw_Texture :: draw_texture
Draw_Texture_Fitted :: draw_texture_fitted
Draw_Atlas :: draw_atlas_region

Begin_Artboard :: begin_artboard
End_Artboard :: end_artboard
Begin_Screen :: draw_push_screen
End_Screen :: draw_pop_screen
Render :: render

Load_Texture :: assets_load_texture
Get_Texture :: assets_get_texture
Register_Font_Family :: font_register_family
Font_With_Size :: font_with_size
Font_Face_From :: font_face_from_handle
Font_Resolve :: font_resolve

View_Set_Zoom :: view_set_zoom
View_Set_Pan :: view_set_pan
View_Pan_By :: view_pan_by
View_Zoom_At_Screen :: view_zoom_at_screen
View_Zoom_By_Screen :: view_zoom_by_screen
View_Zoom_In_Screen :: view_zoom_in_screen
View_Zoom_Out_Screen :: view_zoom_out_screen
View_Reset :: view_reset
View_Effective_Zoom :: view_effective_zoom
View_Screen_To_World :: view_screen_to_world
View_World_To_Screen :: view_world_to_screen
Input_Mouse_Screen :: input_mouse_screen
Input_Mouse_World :: input_mouse_world
