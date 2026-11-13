# Debug overlay

Press **F3** to toggle engine diagnostics. The universal `debug.toggle_overlay` shortcut is installed for both application and game products. It fires once per press, participates in normal shortcut consumption, can be remapped or disabled through the existing shortcut settings, and is rebound after hot reload. The overlay is available in development and production builds and starts hidden.

Applications can use `o.Set_Debug_Overlay(true)` or `o.Set_Debug_Overlay(false)` from their own settings UI. `o.Debug_Overlay_Visible()` returns the selected visibility; `o.Get_Render_Stats()` returns a value snapshot of the last presentation attempt. Visibility and diagnostics live in `State`, survive persistent-state migration and hot reload, and do not require app-owned widget state.

`o.Render(main_ui)` appends the overlay automatically in its existing Layout and Draw passes. It uses logical screen coordinates above ordinary UI and popovers, clips to the viewport, and ignores artboard pan/zoom. The panel does not participate in pointer hit-testing or tab order. Layout captures its text and visibility so an F3 shortcut or application callback between passes cannot change the tree halfway through a frame. The resulting visibility change requests another frame.

## Metrics

| Field | Meaning |
| --- | --- |
| `fps` | Successful presentation intervals per second, sampled over at least 250 ms of real elapsed SDL time. Includes idle time; does not use the capped simulation timestep. |
| `frame_ms` | Time between the last two successful presentations, including swapchain waits and idle time. Zero until two presentations exist. |
| `draw_calls` | Actual SDL indexed primitive API calls encoded into the submitted frame, including UI, LCD, vector geometry, composition and the overlay itself. |
| `draw_commands` | Primitive commands in those calls. An indirect call containing N commands adds one draw call and N commands. |
| `batch_flushes` | Nonempty UI batch traversals with a live pipeline, including traversals of ordered vector submissions. Empty batches do not increment it. |
| `blits` | SDL texture blit calls in the submitted frame; the vector renderer's final resolve-to-swapchain blit is counted separately from primitive draws. |
| `presented` | Whether the last attempt successfully submitted a swapchain frame. This reports submission, not a display scanout timestamp. |
| `atlas` | Existing `Atlas_Stats` snapshot: primary sheet dimensions and generation, total occupied/capacity bytes across sheets, occupancy percentage, sheet/overflow count, glyph-cache count, slots and draw mode. |
| `memory` | Memory snapshot, sampled at most every 250 ms while the overlay is visible. The last sample is retained when hidden. |

### Memory readout

All sizes are MiB (1,048,576 bytes). Linux process measurements come from `/proc/self/status`; inaccessible or unsupported process measurements display `unavailable`, never a misleading zero. The snapshot is available as `o.Get_Render_Stats().memory`.

The panel also identifies debug/release builds, the SDL GPU backend, drawable pixel dimensions and DPI scale so screenshots preserve the rendering context.

| Panel row | Meaning |
| --- | --- |
| RAM / Peak | Current resident RAM (`VmRSS`) and process lifetime high-water mark (`VmHWM`). These include application allocations, loaded libraries, allocator retention and resident driver mappings. |
| Anon/file/shared | Resident anonymous, file-backed and shared-memory pages (`RssAnon`, `RssFile`, `RssShmem`). These are components of RAM, not additional allocations. |
| Layout used/cap | Current bump offset versus retained backing allocation capacity across all layout arena blocks. |
| Scratch used/cap | The same measurements for render scratch. Capacity remains allocated between frames. |
| Textures CPU/GPU | Retained SDL surface bytes (pitch × height) and estimated live GPU RGBA texture bytes. Includes the glyph atlas; the atlas rows below are a breakdown, not additional memory. Count includes records with a live surface or GPU texture. |
| Batch CPU/GPU | CPU vertex/index/segment array capacities and live GPU vertex/index buffer capacities, across both frame slots. Excludes small state stacks and allocator metadata. |
| Uploads (batch) | Live reusable UI batch transfer buffer capacities across both slots. Excludes transient texture transfers and backend-managed cycling copies. |
| Vector GPU/pool | Renderer-tracked GPU resource bytes, including vector upload buffers; the intermediate target pool is a subset of that figure. Includes both frame slots. |
| Vector path cache | Retained path mesh cache and SVG path command bytes tracked by the vector renderer. Excludes other vector state and temporary worker allocations. |

Resource counters are a partial breakdown, not a complete heap census. GPU figures are estimates of requested resource sizes: driver allocation blocks, alignment, pipelines, swapchain images, deferred releases and cycling copies can add overhead. GPU resources may use dedicated VRAM or system RAM; do not add the GPU rows to process RAM or subtract them to infer untracked heap usage. The startup capability-probe texture is transient and is not included in live resource counters.

The sampler uses a bounded stack buffer for Linux process status and closes its file on every path. It does not install a tracking allocator, retain sample histories or acquire GPU resources. Sampling stops while hidden or minimized.

The panel displays the preceding presentation's snapshot so recording it cannot recursively change its own displayed counters. The first frame starts at zero. Cancelled vector encodes are rolled back before retries; failed or unavailable swapchain submissions publish zero draw/flush/blit counters with `presented=false`. Atlas occupancy is still sampled after an attempted frame. Counts describe the renderer's actual calls, including repeated flushes; they are not estimated from widget count or layout nodes.

With the overlay visible, on-demand pacing schedules diagnostics at most every 250 ms while otherwise idle. It still waits for events between refreshes and retains the selected frame mode. The diagnostic refreshes themselves contribute to the reported FPS. Hiding the overlay or minimizing the drawable stops diagnostic wakeups. Continuous apps retain their normal presentation rate.

All overlay-owned storage is inline in engine state, including a fixed formatting buffer. Changing diagnostic text bypasses the persistent shape cache and uses normal layout frame storage, preventing text-cache growth over a long session. Heap-owned shapes in non-arena callers retain the existing `font_shape_lines_release` / layout cleanup paths; UI shutdown frees the layout arenas. The overlay introduces no additional GPU resources or shutdown-owned allocations.

## Verification

`./scripts/test_all.sh --gpu-backend vulkan` runs the overlay tests along with the normal engine/widget suites and allocator leak checks. Coverage includes F3 toggling/repeat suppression/rebinding, migration, raw-time FPS, refresh deadlines, minimized/hidden pacing, pass-stable visibility, pointer transparency, atlas formatting, successful and failed presentation, vector draw/blit accounting, stable shape-cache size, and uncached heap-shape cleanup. Real GPU readbacks at 1× and 2× DPI verify that glyphs appear over vector content and leave pixels outside the panel unchanged. Those tests save `build/test/debug-overlay-1x.png` and `debug-overlay-2x.png` for visual inspection.
