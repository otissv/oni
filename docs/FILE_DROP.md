# Native file drops

Oni receives incoming files from the operating system through SDL3 drop events. A native selection is one transaction: paths are copied while SDL owns the event data, retained across event polls, and published only after `DROP_COMPLETE`. Text drops and empty or cancelled transactions produce no file result. Oni never opens, moves, deletes, or executes a dropped file. Paths can name files, directories, or platform URIs; the consumer decides what it accepts and which asynchronous importer to use.

## Composable targets

`w.File_Drop_Target` is a container with data-only `File_Drop_Target_Config` and procedure-only props. Use a stable `config.id`, ordinary `set.*` styling, and `child` to compose its contents. The child receives `File_Drop_Target_State`, including `drag` and `is_drag_over`. Use those values for visual feedback while keeping the same child tree in Layout and Draw. `on_drag_enter` and `on_drag_leave` report target transitions during Draw.

```odin
w.File_Drop_Target({
    config = {
        id = "imports",
        width = set.Width(.GROW),
        height = set.Height(160),
    },
    child = build_import_contents,
    accept = proc(paths: []string) -> bool {
        // Metadata policy only; do not perform synchronous file I/O here.
        return len(paths) <= 32
    },
    on_drop = proc(event: w.File_Drop_Event) {
        switch event.status {
        case .Selected:
            // event.paths is borrowed until this callback returns.
            // Clone paths retained by app state, and free previous copies.
            // Load_Texture accepts asynchronous image requests.
        case .Failed:
            report_import_error(event.error_code)
        case .None:
        }
    },
})
```

Layout registers targets without capturing callbacks in retained state. After layout and stacking are solved, the engine finds the foremost hittable node at each drop's own position and walks its ancestors to the nearest registered target. This honors ancestor overflow clips, hidden elements, pointer-event rules, overlay/popover occlusion, and artboard zoom and pan. A disabled nested target blocks its parent. Disabled targets and targets without `on_drop` do not consume selections. An unrelated foreground node prevents delivery to a target behind it. Completed results are routed once, so a later page cannot receive an old drop merely because it appeared at the same coordinates.

The widget dispatches after its children during Draw, once per completed result. `accept` validates the entire selection; false produces `.Failed` with `.Rejected`. `on_drop` also receives capture, allocation, limit, and overflow failures. The widget always destroys its owned result after the callback. The consumer owns domain data, imports, and any retained copies; there is no widget-owned file list or decoder.

## Window-level ownership

`o.Take_File_Drop()` transfers the oldest completed result, including selections outside targets and system-open events without a window position. It returns `(File_Drop_Result, bool)`. Destroy every transferred result with `o.Destroy_File_Drop_Result(&result)`, including failures. Destruction is idempotent and uses the origin allocator. Do not shallow-copy ownership; the allocator must remain valid until destruction. Transferred results can outlive engine shutdown.

```odin
for {
    result, ok := o.Take_File_Drop()
    if !ok do break
    defer o.Destroy_File_Drop_Result(&result)
    if result.status == .Selected {
        enqueue_imports(result.paths) // Copy paths before returning.
    }
}
```

If the app also uses targets, consume the window queue after `o.Render` so targets have first access. An app that exclusively handles window drops can consume in its update callback. `Take_File_Drop(target_id)` is the lower-level Draw-only target operation used by the widget. Custom containers can register numeric IDs with `File_Drop_Register_Target` during Layout and query `File_Drop_Target_Hovered`. Registration returns false if allocation fails or the published target limit is reached; unclaimed results remain available to the window consumer. All input, registration, and delivery operations run on the engine owner thread.

`Get_File_Drag_State` returns the current native drag snapshot. Drop positions are logical screen coordinates converted from SDL window coordinates through the drawable/window ratio and engine DPI scale. `has_position` is false for system-open requests with window ID zero or invalid native coordinates. Those requests are delivered only through the window API. Native drag-position events do not reveal the payload format, so a hover preview can precede a text-only transaction that is subsequently ignored.

## Bounds and frame cost

Each native transaction permits 1,024 paths of up to 128 KiB each. Total unconsumed engine-owned path bytes are limited to 16 MiB, with at most 32 completed batches and 1,024 registered targets. String headers, the reusable pending array, and the target map are bounded separately by those counts. A path or aggregate-limit violation rejects and releases the whole in-progress batch. No partially captured batch is reported as successful. Invalid or empty UTF-8 paths produce `.Invalid_Data`; failed copies or array growth produce `.Allocation_Failed`.

A full queue preserves its completed results and releases incoming selections. One additional, allocation-free failure reports `.Queue_Full` and the number of `omitted_batches`. Apps should surface that failure instead of claiming all files were imported. Taking a result transfers its memory out of the engine's budget; consumers must bound their own import queues and retention.

Event polling yields after 64 drop events or 256 KiB of scanned path data and requests another frame. An unfinished transaction survives across those frames in FIFO order, so large selections cannot consume an unbounded polling iteration. Native input wakes on-demand rendering; consumption requests another frame for application feedback. Hovering and idle drop handling allocate nothing. No filesystem validation, decoding, directory traversal, or importer runs in this path. Blocking work in a consumer callback, or inside an OS/SDL backend, can still exceed a frame budget; measure on the deployment hardware.

## Lifecycle and validation

Completed and in-progress allocations belong to `State.file_drop`. Persistent reallocation moves ownership and zeros the source. Input reset cancels the unfinished transaction while preserving completed selections. Shutdown frees every unconsumed path, result array, reusable buffer, and target map. Normal DLL reload retains data without retaining widget callbacks. Stored allocators retain the same lifetime requirement as transferred results. Changes to the initial engine-state layout require rebuilding the host and app together.

The consumer's File Drop documentation page imports files into app-owned bounded path labels and uses the existing asynchronous texture loader for an image preview. Replacement, reset, persistent reallocation, and shutdown release its retained strings and texture reference. Engine and widget tests cover native polling, event budgeting, on-demand wakeups, UTF-8, DPI, FIFO delivery, atomic limits, allocator failure boundaries, cancellation, migration, disabled/nested targets, clipping, modal occlusion, artboard transforms, callback timing, policy rejection, and cleanup. Run `./oni/scripts/test_all.sh` and `odin test app/docs` with the standard collection and font linker flags.

SDL event definitions and ownership are provided by [SDL_DropEvent](https://wiki.libsdl.org/SDL3/SDL_DropEvent) and the pinned SDL implementation in `build/SDL/src/events/SDL_dropevents.c` and `SDL_events.c`. SDL3 owns its event strings; Oni frees only its explicit retained copies.

The consumer repository includes `scripts/profile_file_drop.sh` and `tools/file_drop_profile/` for repeatable performance verification. The script builds an optimized host, creates a generated image fixture under `build/`, and measures the existing widget page, drop-page idle/hover, repeated 512-file bursts, and asynchronous image preview. Its own window is briefly kept visible to avoid compositor throttling and closes afterward. Each phase reports average FPS, average/p95/maximum frame milliseconds, CPU UI p95, and draw calls. With immediate presentation, the benchmark fails if any measured frame exceeds the 60 FPS budget; otherwise it checks CPU UI p95 separately from the display's presentation limit. It writes only temporary benchmark preferences, leaving consumer settings unchanged.
