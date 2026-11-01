package oni_vector

import "core:mem"

// Intersects the union of each mesh's triangles through the exact sweep solver.
// Input meshes remain borrowed; output owns its buffers on the caller allocator.
Intersect_Meshes_Into :: proc(out: ^Mesh, a, b: Mesh, limits := DEFAULT_LIMITS, usage: ^Build_Usage = nil) -> (err: Error) {
	if out == nil { return .Invalid_Path }
	if usage != nil { usage^ = {} }
	clear(&out.vertices)
	clear(&out.indices)
	if len(a.indices) == 0 || len(b.indices) == 0 { return .None }
	if len(a.indices) % 3 != 0 || len(b.indices) % 3 != 0 { return .Invalid_Path }
	arena := Scratch_Arena{backing = context.allocator}
	defer scratch_arena_destroy(&arena)
	scratch := mem.Allocator{procedure = scratch_allocator_proc, data = &arena}
	ca, ea := svg_mesh_commands(a, limits, scratch)
	if ea != .None { return ea }
	cb, eb := svg_mesh_commands(b, limits, scratch)
	if eb != .None { return eb }
	mesh: Mesh
	mesh, err = tessellate_impl(ca, IDENTITY, .Nonzero, limits, out^, scratch, usage, cb)
	out^ = mesh
	if usage != nil { usage.triangles = len(mesh.indices) / 3 }
	if err != .None { clear(&out.vertices); clear(&out.indices) }
	return err
}
@(private)
svg_mesh_commands :: proc(mesh: Mesh, limits: Limits, allocator: mem.Allocator) -> ([]Command, Error) {
	context.allocator = allocator
	commands := make([dynamic]Command)
	if len(mesh.indices) / 3 > limits.max_commands / 4 { return nil, .Limit_Exceeded }
	if err := reserve(&commands, len(mesh.indices) / 3 * 4); err != nil { return nil, .Allocation_Failed }
	for i := 0; i < len(mesh.indices); i += 3 {
		points: [3]Point
		for n in 0 ..< 3 {
			index := mesh.indices[i + n]
			if u64(index) >= u64(len(mesh.vertices)) { return nil, .Invalid_Path }
			p := mesh.vertices[index]
			points[n] = {f64(p.x), f64(p.y)}
		}
		u, v := points[1] - points[0], points[2] - points[0]
		cross := u.x * v.y - u.y * v.x
		if !finite(cross) { return nil, .Invalid_Value }
		if cross == 0 { continue }
		if cross < 0 { points[1], points[2] = points[2], points[1] }
		append(&commands, Command{kind = .Move, points = {points[0], {}, {}}}, Command{kind = .Line, points = {points[1], {}, {}}}, Command{kind = .Line, points = {points[2], {}, {}}}, Command{kind = .Close})
	}
	return commands[:], .None
}

