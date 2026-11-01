package oni

import v "./vector"

// CPU path data owns its command buffer; retained GPU paths copy these commands
// through Vector_Create_Path. Destroy each owner independently.
Vector_Path :: v.Path
Vector_Point :: v.Point
Vector_Bounds :: v.Bounds
Vector_Path_Error :: v.Error
Vector_Move_To :: v.Move_To
Vector_Line_To :: v.Line_To
Vector_Quadratic_To :: v.Quadratic_To
Vector_Cubic_To :: v.Cubic_To
Vector_Arc_To :: v.Arc_To
Vector_Close :: v.Close
Vector_Rectangle :: v.Rectangle
Vector_Circle :: v.Circle
Vector_Ellipse :: v.Ellipse
Vector_Polyline :: v.Polyline
Vector_Geometry_Bounds :: v.Geometry_Bounds
Vector_Destroy_Path_Data :: v.Destroy_Path
