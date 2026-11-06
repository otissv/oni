#+test
package oni_vector

import "core:testing"
import "core:thread"

@(private)
Svg_Instance_Test_Worker :: struct {
	asset: ^Svg_Asset,
	target: Svg_Element_Handle,
	color: Color,
	failed: bool,
}

@(private)
svg_instance_test_worker :: proc(data: rawptr) {
	worker := cast(^Svg_Instance_Test_Worker)data
	commands := make_circleish()
	defer delete(commands)
	expected_hash := Commands_Hash(commands[:])
	overrides := [2]Svg_Override{{target = worker.target, property = .Fill, paint = Solid_Paint(worker.color)},
		{target = worker.target, property = .Path, commands = commands[:]}}
	for _ in 0 ..< 128 {
		first, a := Svg_Prepare_Instance(worker.asset, overrides[:], allocator = worker.asset.allocator)
		second, b := Svg_Prepare_Instance(worker.asset, allocator = worker.asset.allocator)
		if !a.ok || !b.ok || first == nil || second == nil {
			worker.failed = true
		} else if first == second || first.roots[0].item.commands_hash != expected_hash || first.roots[0].item.fill.solid != worker.color ||
		          second.roots[0].item.fill.solid != (Color{255, 0, 0, 255}) {
			worker.failed = true
		}
		Destroy_Svg_Instance(first)
		Destroy_Svg_Instance(second)
		Destroy_Svg_Load_Result(&a)
		Destroy_Svg_Load_Result(&b)
	}
}

@(test)
svg_instance_storage_reuse_keeps_concurrent_snapshots_independent :: proc(t: ^testing.T) {
	asset, loaded := svg_test_load(`<path id="p" d="M0 0L10 0L0 10Z" fill="red"/>`)
	defer Destroy_Svg_Asset(asset)
	defer Destroy_Svg_Load_Result(&loaded)
	testing.expect(t, loaded.ok)
	if !loaded.ok { return }
	target, _ := Svg_Asset_Lookup(asset, "p")
	workers: [4]Svg_Instance_Test_Worker
	threads: [4]^thread.Thread
	for &worker, i in workers {
		worker = {asset = asset, target = target, color = {u8(i), 200, 100, 255}}
		threads[i] = thread.create_and_start_with_data(&worker, svg_instance_test_worker)
		testing.expect(t, threads[i] != nil)
	}
	for worker_thread, i in threads {
		if worker_thread == nil { continue }
		thread.join(worker_thread)
		thread.destroy(worker_thread)
		testing.expect(t, !workers[i].failed)
	}
}
