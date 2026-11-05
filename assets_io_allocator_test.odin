#+test
package oni

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
assets_io_result_releases_path_with_its_origin_allocator :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	result := Asset_IO_Result{path = strings.clone("worker-owned request", allocator), path_allocator = allocator}
	context.allocator = mem.nil_allocator()
	assets_io_free_result(&result)
	testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	testing.expect_value(t, result.path, "")
}
