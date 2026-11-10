# Native file and folder dialogs

`Open_File_Dialog`, `Save_File_Dialog`, and `Pick_Folder` use SDL3's native file-dialog backend. They select paths only: opening a dialog never reads, creates, or overwrites a file. They require initialized SDL video and the SDL main thread. When an engine window is bound, it is supplied as the modal parent. Presentation details remain subject to the native backend.

These are modal calls. Oni pumps SDL events while waiting, including the Linux portal event loop, but pauses application tick, draw, and hot reload until completion. Call from an input handler or other deliberate main-thread action, never unconditionally while building Layout. There are no retained request handles, application completion callbacks, or pending allocations to migrate on reload or shutdown. A nested dialog request fails with `Busy`. On return, queued keyboard, mouse and gamepad input is discarded and current input latches are cleared, so dialog-time actions cannot trigger app commands. Window, quit, device and application events are preserved; the engine requests a repaint and resets its timing baseline.

## API and results

All three functions accept `File_Dialog_Options` and an optional result allocator, defaulting to `context.allocator`. `File_Dialog_Result.status` is `Selected`, `Cancelled`, or `Failed`. Cancellation is not an error and returns no paths. A successful single selection has one path; an open-file or folder picker with `allow_many = true` may return several. Save dialogs reject `allow_many`; folder pickers reject file filters rather than silently ignoring them.

The result owns its path array, every path string, and any error text. Always call `Destroy_File_Dialog_Result(&result)`, including on cancellation and failure. It uses the allocator stored in the result, so changing `context.allocator` before destruction is safe. The allocator itself must remain valid. Do not shallow-copy ownership or independently delete paths. Clone a path before retaining it in `Persistent.app`, and delete that retained string when replacing it or shutting down the app. Destruction is idempotent and accepts nil or zero results.

`error_code` distinguishes invalid options, uninitialized SDL, wrong-thread calls, reentrant calls, native backend errors, invalid results, allocation failures, and selection limits. `error` is an owned diagnostic when allocation succeeds; check the code even if the diagnostic is empty. Native callback data is copied using SDL allocations, then transferred into the requested allocator exclusively on the calling thread. Partial results are released on every failure path.

```odin
result := o.Open_File_Dialog({
    title = "Open document",
    location = "documents/",
    filters = []o.File_Dialog_Filter{
        {name = "Text documents", pattern = "txt;md"},
        {name = "All files", pattern = "*"},
    },
})
defer o.Destroy_File_Dialog_Result(&result)

switch result.status {
case .Selected:
    // Retain this copy in Persistent.app and release it on replacement/shutdown.
    next_path, err := strings.clone(result.paths[0])
    if err == nil && len(next_path) > 0 {
        delete(app.selected_path)
        app.selected_path = next_path
    } else {
        o.Error_Report("Could not retain the selected path")
    }
case .Cancelled:
    // Leave the current document/path unchanged.
case .Failed:
    o.Error_Reportf("Open dialog failed (%v): %v", result.error_code, result.error)
}
```

For a controlled text field, pass `app.selected_path` as `Text_Input`'s `config.text`. Invoke the selection code from a neighboring Button's `on_click`; both the field and dialog write back to app-owned state. A save picker uses `o.Save_File_Dialog({location = "documents/new.txt"})`; a folder picker uses `o.Pick_Folder({location = "documents/", allow_many = true})`. Handle and destroy their results identically.

## Options and path semantics

`title`, `accept_label`, and `cancel_label` customize native chrome where supported. An empty value leaves the native default. `location` supplies a default directory or filename; a directory for a file picker should end in a path separator. Folder pickers always interpret it as a directory. No path normalization or extension rewriting is performed.

Each filter contains a nonempty display `name` and a `pattern`. A pattern is either the single asterisk `*` or a semicolon-separated list of extensions such as `png;jpg` or `tar.gz`. Extension characters are ASCII letters, digits, hyphens, underscores, and periods. Empty extensions and glob expressions such as `*.png` are rejected. `selected_filter` is a zero-based index into the supplied filters, or `-1` if the backend does not report a usable index. Filters are native UI hints; applications must validate selected content themselves.

Inputs must be valid UTF-8 and contain no embedded NULs. Labels and filter strings are limited to 16 KiB, locations and selected paths to `FILE_DIALOG_MAX_PATH_BYTES` (128 KiB), filters to `FILE_DIALOG_MAX_FILTERS` (128), selected paths to `FILE_DIALOG_MAX_SELECTIONS` (1024), and combined selected-path bytes to `FILE_DIALOG_MAX_RESULT_BYTES` (16 MiB). Oversized selections fail as a whole; nothing is silently truncated.

Native backends can allow nonexistent paths, ignore filters, or ignore multi-selection and presentation hints. Save selection does not guarantee that writing will succeed, append an extension, or implement an atomic replacement policy. Applications own content validation and actual I/O. On Android SDL can return `content://` URIs, which should be opened with SDL's I/O APIs rather than assuming an ordinary filesystem path.

Linux needs a working SDL native-dialog backend, normally XDG Desktop Portal/DBus or Zenity. Backend unavailability returns `Failed` with `Backend`; no shell command is constructed by Oni and no custom picker is substituted. SDL handles native backend selection and Windows/macOS integration.

The backend contract follows SDL's [file-dialog properties](https://wiki.libsdl.org/SDL3/SDL_ShowFileDialogWithProperties), [callback ownership and threading](https://wiki.libsdl.org/SDL3/SDL_DialogFileCallback), and [filter syntax](https://wiki.libsdl.org/SDL3/SDL_DialogFileFilter).
