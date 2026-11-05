#+test
package oni_vector

import "core:testing"

@(test)
exact_products_enforce_work_and_width_before_operations :: proc(t: ^testing.T) {
	for allowed in 0 ..= 40 {
		work := Exact_Work{allowed = allowed, width = 4096}
		order, err := exact_compare_products(i128(1) << 100, i128(1) << 100, (i128(1) << 100) + 1, i128(1) << 100, &work)
		testing.expect(t, work.used <= allowed)
		if err == .None { testing.expect(t, order < 0) } else { testing.expect_value(t, err, Error.Limit_Exceeded) }
	}
	work := Exact_Work{allowed = 100, width = 255}
	_, err := exact_product(u128(1) << 127, u128(1) << 127, &work)
	testing.expect_value(t, err, Error.Limit_Exceeded)
	testing.expect_value(t, work.used, 0)
}

@(test)
tessellation_reports_failed_pair_and_exact_work :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Polyline(&path, []Point{{0, 0}, {20, 20}, {0, 20}, {20, 0}}, true)
	limits := DEFAULT_LIMITS
	limits.max_pair_tests = 1
	usage: Build_Usage
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	err := Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits, usage = &usage)
	testing.expect_value(t, err, Error.Limit_Exceeded)
	testing.expect(t, usage.pair_tests > 0)
	limits = DEFAULT_LIMITS
	limits.max_exact_ops = 1
	err = Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits, usage = &usage)
	testing.expect_value(t, err, Error.Limit_Exceeded)
	testing.expect_value(t, usage.exact_ops, 1)
}
