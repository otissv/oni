# Native vector drawing

The implementation provides mesh scenes, retained paths, strokes, paints, SVG import, controlled SVG/vector widgets and independent instance editing. The supported import profile is defined in [SVG-SUPPORTED-PROFILE.md](SVG-SUPPORTED-PROFILE.md). Lifecycle, reload, device recreation and the dense-scene release gate are documented under [M8 acceptance](#m8-acceptance-status--2026-11-01) below.

## Frame integration

Call `Draw_Vector_Scene` or `Draw_Vector_Path` during Oni's Draw pass, using positions derived from solved layout rectangles. Layout remains responsible for sizing and placement. Drawing during Layout emits no vector commands. The engine copies borrowed mesh data into the current frame before returning, so the app can subsequently modify or release its source data.

Frames containing vectors use a **shared 4× MSAA scene target**: vectors and UI (including LCD text) draw interleaved in one clear/resolve pass so batch order stays correct. Frames without vectors retain the existing single-sample path. Opacity groups and masks use separate bounded GPU targets. Group preparation happens before the shared MSAA pass, and the swapchain is acquired only after successful scene encoding. A failed group submission cancels the unsubmitted command buffer; recording is replayed without that submission.

The MSAA root is **content-bounded to the union of vector geometry and UI vertices** (plus one physical pixel of AA padding), quantized for stable allocation, with a frozen view origin for the life of that allocation. Mesh-only MSAA roots stay colour-only so five in-flight GPU slots fit the 256 MiB budget; frames that need groups/masks/clips attach depth on the MSAA/pool path only. Present clears the swapchain to the theme background, then blits the resolved root at its origin.

## Mesh scenes

`Vector_Scene` contains borrowed `Vector_Node` slices. A mesh node supplies logical-coordinate vertices, 32-bit triangle indices, colour and opacity. Group nodes supply children and isolated opacity. Clip nodes supply a rectangular clip and children. Mask nodes supply content children and mask children. Set scene and node opacity explicitly: these data structures have Odin's ordinary zero defaults.

```odin
points := [3]o.Vec2{{20, 20}, {120, 20}, {20, 120}}
indices := [3]u32{0, 1, 2}
nodes := [1]o.Vector_Node{{
    kind = .Mesh,
    mesh = {vertices = points[:], indices = indices[:]},
    colour = {255, 80, 80, 255},
    opacity = 1,
}}
err := o.Draw_Vector_Scene({nodes = nodes[:], opacity = 1})
```

Check the returned `Vector_Error` before treating a submission as recorded. `Vector_Last_Error` reports a later GPU preparation failure. Clips accept a rectangle, a geometric mesh, or both: rectangles scissor, meshes push/pop stencil levels (max depth 64; tree nesting is separate up to 256) so nested path clips intersect correctly. Masks support `.Alpha` and `.Luminance` (`mask-type`), with optional `mask_units` / `mask_content_units` (`.User_Space_On_Use` or `.Object_Bounding_Box`) and `mask_region`. Object-bounding-box mapping uses unpadded geometric bounds, including through nested groups, and validates mapped device coordinates transactionally. Luminance coverage unpremultiplies the mask sample, converts to linearized sRGB, then multiplies by alpha once. Group and mask intermediates stay 4× MSAA and pooled with peak-overlap GPU budget checks. Scene nodes may be `.Path` entries (`Vector_Path_Draw`) so retained fills/strokes/gradients participate in the same clips, masks and opacity groups. Frame vertex uploads track a per-frame geometry revision so animated scene meshes cannot reuse stale GPU buffers. Encode replay is capped at three attempts with cumulative sample-work and command-visit budgets.

## Retained paths

The independent `oni/vector` package supplies `Path`, path commands, affine transforms, curve flattening and fill tessellation. `Rectangle` (including elliptical corner radii), `Ellipse`, `Circle` and `Polyline` append basic shapes transactionally. `Path_Bounds` returns conservative transformed bounds padded by the requested flattening tolerance; empty paths set `empty`. Call `Destroy_Path`, `Destroy_Flat_Path` and `Destroy_Mesh` for owned CPU results. `Tessellate_Into` reuses mesh capacity. Its optional scratch allocator must be bulk-released by its caller; scratch storage never becomes part of the returned mesh.

`Vector_Create_Path` copies a complete command slice and returns a generation-checked engine handle. `Vector_Update_Path` validates the replacement before changing the source and invalidates derived geometry. `Vector_Destroy_Path` releases its commands and cache. Old handles are rejected after release, and already-recorded frames retain their copied geometry.

Retained command buffers remember their allocation owner, including when updates or shutdown run with a different `context.allocator`. A custom allocator used to create a retained path must outlive that path; source command slices may still be frame scratch because they are copied. The standalone CPU tessellator frees its internally owned scratch blocks on success and on allocation failure. Explicitly supplied scratch allocators remain the caller's responsibility to bulk-release.

`Draw_Vector_Path` accepts either a solid `RGBA` or a `Vector_Paint` (`Solid_Paint`, `None_Paint`, `Current_Color_Paint`, `Linear_Paint`, `Radial_Paint`). Defaults: fill (`.Fill`), identity transforms, nonzero fill rule and opacity 1. Pass `current_color` when the paint uses `currentColor`. Pass `op = .Stroke` with a `Vector_Stroke` for width, cap, join, miter limit, dash array/offset, `path_length` and `non_scaling`. `instance_morph` composes with any path-level morph from `Vector_Set_Path_Morph` / affine `Vector_Update_Path` edits so fill draws can share one basis mesh (GPU morph). Stroke draws bake that morph into the tessellated outline and record with identity GPU morph, so `Vector_Set_Path_Morph` and affine updates invalidate stroke slots only. The transform is a six-component SVG affine matrix `[a, b, c, d, e, f]`. Geometry is cached by fill-versus-stroke operation, fill rule (fills only; strokes always use nonzero coverage), complete stroke settings, stroke morph, approximation policy revision and the exact linear transform; translation and paint stay separate. Gradient stop slices are sampled into an immutable frame ramp at record time so callers may mutate or free them immediately. Stroke setting changes allocate separate cache slots; path topology updates invalidate every slot for that handle.

`libs:colors.svg_color_parse` accepts SVG/CSS hex, named colours, `transparent`, `rgb()`/`rgba()` and `hsl()`/`hsla()`; empty or malformed function arguments are rejected. Paint keywords `none` and `currentColor` are paint values, not colour parses. Gradients support pad/reflect/repeat spread, objectBoundingBox/userSpaceOnUse units, gradient transforms (sampled via the inverse, with objectBoundingBox axes from path-local bounds), and sRGB or linearRGB stop interpolation. Retained GPU ramp textures keep allocated-height accounting when a frame uses fewer gradients. Vector fragments emit premultiplied RGBA and use `gpu_vector_blend_state()`; UI pipelines keep straight-alpha `gpu_blend_state()`.

Cache misses on a single `Draw_Vector_Path` tessellate on the owner thread. `Vector_Prefetch_Paths` / `Vector_Ensure_Path_Meshes` and `Draw_Vector_Paths` collect unique misses (deduplicated) and, when there are at least four, fan out through a bounded worker pool (font-style sync burst): workers run `Tessellate_Into` or `Tessellate_Stroke_Into`; the owner installs meshes, frame budgets, cache bytes and `geometry_epoch` after join. Bursts admit at most 4,096 unique jobs and keep snapshot + worker-scratch memory under 128 MiB; each job gets an exclusive share of the remaining frame segment/triangle budget. Shutdown joins the pool before releasing path caches (including owned stroke dash copies). Warm all-hit `Draw_Vector_Paths` batches skip miss-map allocation.

The fill renderer accepts multiple contours, both fill rules, holes and self-intersections. Its general solver sweeps edges by height, uses quantized input coordinates, canonical rational intersection heights and exact comparison fallback, then emits disjoint filled intervals between events. Simple contours also use exact ear clipping after proving that nonadjacent edges neither touch nor cross. The convex fast path checks winding and axis direction reversals so a self-intersecting star is not mistaken for a convex boundary. Quantization displacement is included in the 0.25-physical-pixel curve error budget.

Strokes expand to outlines (caps/joins/dashes, closed seams, zero-length caps, `pathLength` dash normalization, non-scaling width) then tessellate combined coverage with nonzero fill so overlapping stroke pieces do not accumulate opacity. CPU package entry points are `Validate_Stroke`, `Stroke_Bounds`, `Tessellate_Stroke` / `Tessellate_Stroke_Into` in `oni/vector`.

CPU `Limits` separately bound source commands, flattened points, intersections, events, candidate edge-pair tests, solver work and output mesh capacity. The default solver-work budget is 16,000,000 operations. The engine additionally counts new flattened points and triangles across every build in the frame, including failed builds, against 1,000,000 and 4,000,000 respectively. Cache hits consume no construction budget. Cache accounting includes mesh capacities and cache-entry arrays, and bounds mesh growth before allocation within the 64 MiB cache budget. Recorded frame snapshots remain independent of cache eviction.

## SVG instances and controlled widgets (M7)

The CPU path builder is available through Oni: `Vector_Path`, `Vector_Move_To`, `Vector_Line_To`, `Vector_Quadratic_To`, `Vector_Cubic_To`, `Vector_Arc_To`, `Vector_Close`, `Vector_Rectangle`, `Vector_Circle`, `Vector_Ellipse`, `Vector_Polyline` and `Vector_Geometry_Bounds`. Release builder commands with `Vector_Destroy_Path_Data`. Retained `Vector_Create_Path` handles copy those commands and have a separate `Vector_Destroy_Path` lifetime.

`Svg_Lookup_Element` returns a definition handle. `Svg_Lookup_Occurrence(asset, use_sites, terminal)` accepts the ordered outer-to-inner use-site definition handles and the terminal element handle. Handles are values with no borrowed chain storage; hidden/zero-size branches have structural addresses too. An address for a use element itself excludes that use from its chain; an address inside its target includes it. Missing, forged and foreign/stale revisions fail validation.

`Load_Svg_File` / `Load_Svg_Memory` import SVG documents. `Reload_Svg_File` / `Reload_Svg_Memory` replace an existing asset transactionally. `Destroy_Svg_Asset` releases CPU-side arenas. `Get_Vector_Stats` reports live path counts, CPU cache bytes, vector GPU bytes, encode timings and frame budgets for the stress gallery and diagnostics.

`Draw_Svg_Asset(asset, transform, opacity, overrides, diagnostics)` accepts an affine instance transform (identity by default), opacity (one by default) and a borrowed `[]Svg_Override`. Reusing the optional diagnostics output destroys any prior heap entries first; destroy the final result with `Destroy_Svg_Load_Result`. Each override selects either `target` (definition) or `occurrence`, one property and that property's value. Definition overrides affect all occurrences in this drawing instance; occurrence overrides win for the same property. Duplicate target/property pairs fail independently of slice order. Overrides apply after the CSS cascade, before descendant inheritance, transforms, object bounds, clipping, masks and geometry are recomputed. The asset and other instances never change.

| Override property | Value field | Applicability |
|---|---|---|
| Transform | transform | svg, g, symbol, use, shapes, clipPath, mask; replaces the local affine, including an explicit singular matrix |
| Fill, Stroke | paint | Same elements; validates paint geometry, stops and interpolation |
| Color | color | Same elements; descendant currentColor resolves using the resulting inherited colour |
| Opacity, Fill_Opacity, Stroke_Opacity | opacity | Same elements; finite [0,1], following SVG inheritance/isolation rules |
| Stroke_Settings | stroke | Shapes only; complete settings including dash data, pathLength and non-scaling mode |
| Path | commands | Shapes only; replaces geometry/topology, including empty geometry |

Each compilation has a bounded owning arena. The engine additionally limits all instance compilations in one frame to 100,000 visited nodes, 16,000,000 selector/address/input-validation operations and 64 MiB of decoded blocks, including failed attempts. Structural address and path/gradient/dash payload validation are charged before inspecting or copying caller inputs. These allowances supplement per-asset XML/reference/command limits and frame mesh budgets. Invalid targets, duplicates, numeric failures and allocation exhaustion omit the entire submission and return an error; requested diagnostics retain source element/property details when available.

`Prepare_Svg_Instance` creates a self-contained immutable snapshot; `Draw_Svg_Instance` records it and `Destroy_Svg_Instance` releases it. Explicitly destroy heap-backed instances and their independently owned diagnostic results. Frame-arena-backed snapshots are bulk released with their arena. Preparation copies paths, paints, gradient stops and dash arrays; no asset pointer or caller slice survives in the prepared scene. Recording copies geometry and ramps into the existing frame machinery, so callers may release inputs, instances and assets immediately after recording, including before GPU execution or replay.

`w.Svg_Config` contains asset, overrides and fit together with `Widget_Config`. `w.Vector_Config` contains an explicit logical viewport and fit together with `Widget_Config`. Props contain drawing/error/event procedures and composable children; domain values stay app-owned. Both share rectangle chrome, mount/unmount, focus, scrolling and event dispatch. Fit defaults to `Contain`; `Cover`, `Fill`, `None` and `Scale_Down` are explicit alternatives, centered and clipped to the content box.

Layout captures a self-contained SVG scene or vector viewport in the layout frame arena, measures intrinsic dimensions (including one definite axis with an auto aspect-ratio axis), then finalizes fitting using the solved rectangle. Draw consumes that snapshot even if earlier callbacks changed props or released the asset. Zero-sized SVGs paint nothing. `Vector.draw` runs during Draw only and receives `Vector_Canvas` with the Layout viewport, destination rect and affine transform to pass to `Draw_Vector_Path`. Children run in both passes. `on_error` receives a `Vector_Error` and a borrowed diagnostic slice valid during the callback; failures preserve children and subsequent widgets.

```odin
w.Svg({config = {id = "icon", asset = app.icon, width = set.Width(24), height = set.Height(24),
    overrides = []o.Svg_Override{{target = app.icon_body, property = .Fill, paint = o.Solid_Paint(app.tint)}}}})
w.Vector({
    config = {id = "canvas", viewport = {0, 0, 200, 100}, width = set.Width(400), height = set.Height(200)},
    draw = proc(_: w.Vector_State, canvas: w.Vector_Canvas) {
        _ = o.Draw_Vector_Path(app.path, o.Solid_Paint(app.tint), canvas.transform)
    },
})
```

The standalone gallery demonstrates SVGs inside buttons, grid/flex containers, a scrollport, artboard and overlay, and two independently edited copies of one asset. Four app-owned Tengu tweens advance once in `m7_tick(dt)` using seconds; both UI passes consume the same transform/colour/stroke/path values. On-demand pacing calls `Request_Frame` while animation is active; Pause stops continuing demand. Path sliders pause animation for manual edits. The artboard/overlay toggle snapshots visibility for both passes.

Run `bash scripts/test_all.sh --asan --require-vector-gpu` for package and real-GPU coverage. `bash scripts/test_vector_gallery.sh` runs the tick regression and optimized production build; append `--smoke` with display/GPU access to exercise three frames and normal cleanup, including artboard/overlay examples. The script uses an isolated temporary consumer and removes it on exit.

M7 acceptance evidence (2026-11-01): the full five-package AddressSanitizer/leak-tracked suite passed with required GPU validation. Final regressions passed 101 CPU vector tests, 454 widget tests, 190 Tengu tests and seven focused engine/API/GPU tests, including independent instance colours, caller-data release, failed-sibling replay, diagnostics and the public path builder. The gallery tick regression and optimized `-disable-assert` production smoke build passed. Allocation-failure sweeps and repeated instance teardown returned owned memory to baseline; Layout snapshots use bulk frame cleanup. No M7 acceptance gaps remain against this contract.

## Textures (async IO)

`Load_Texture` returns immediately with a generation-checked handle that may be `Pending`, `Ready`, or `Failed` (`Texture_Status`). `bool` means the request was accepted into the resource table, not that pixels are ready. Path keys are lexically cleaned (symlink aliases stay distinct); workers receive an absolute request path. Decode admission bounds encoded size (32 MiB), edge (8,192), decoded bytes (64 MiB), and in-flight decoded surfaces (128 MiB). The owner drains up to 16 completions and about 16 MiB of uploads per frame, then requests another frame while work remains. `Ready` is published only after upload commands are submitted (`texture_uploads_flush`). Duplicate paths share one handle and acquire one reference (`Unload_Texture` releases). Failed records stay Failed until explicit `Retry_Texture`. `Texture_Error` returns a caller-owned diagnostic (`Texture_Error_Free`). Do not bind Pending/Failed handles for sampling; Image measures zero intrinsic size until Ready.

## Validation

Run `bash scripts/test_all.sh vector oni widgets` for debug, vet, strict-style and allocation checks. Add `--require-vector-gpu` to make unavailable MSAA/LCD GPU validation fail rather than skip. The GPU tests write composition and failure-replay PNGs under `build/test/`.

Run `bash scripts/benchmark_vector.sh --smoke` to check the workload and timing harness. This is not the performance gate. Run `bash scripts/benchmark_vector.sh` for the M2 programmatic-path gate (120 warm-up, 1,800 measured frames). Run `bash scripts/benchmark_vector.sh --m8` for the imported-SVG dense scene plus composition workloads defined in `fixtures/vector/benchmark/manifest.toml`. The JSON reports record completed throughput, CPU p95/p99, manifest hash, and encode breakdown. Full runs fail below 60 fps or above 4 ms CPU p95.

The standalone gallery source is `templates/vector_gallery.odin`. Copy it to a consumer project as `main.odin`, with Oni imported as `./oni`, and build using the framework's collection and linker flags. It includes a controlled curve editor, rings, holes, nonzero/even-odd stars, zoom and fractional-position sliders, an M3 stroke laboratory (caps, joins, miter limit, dashes/`pathLength`, zero-length round caps, non-scaling strokes), an M4 paint laboratory (linear/radial gradients with animated stops, themed `currentColor`, nested transforms, translucent solids), and an M5 composition laboratory (nested geometric clips, alpha/luminance masks, isolated group opacity on contrasting grounds). `--smoke` presents three frames and exits through normal cleanup. The gallery is separate from the hot-reload starter host.

Pinned independent librsvg references and regeneration commands live under `fixtures/vector/`. The real-GPU path test compares opaque and translucent fills at 1× and 2× DPI, including a half-pixel feature, fractional translation, shear and reflection. It checks interior channels, silhouette displacement and integrated coverage, and writes actual/difference PNGs under `build/test/`. GPU stroke tests cover translucent self-overlap (single coverage) and non-scaling/reflection. CPU tests independently check winding against triangle coverage, curve error, stroke degeneracies, dash/`pathLength`, bounded output, capacity reuse and repeated retained-handle lifecycle cleanup.

## M5 acceptance status — 2026-11-01

Clipping, masks and group opacity completed: nested geometric stencil clips (depth ≤ 64; node nesting ≤ 256) with rectangular scissor AABBs, alpha and luminance masks with objectBoundingBox/userSpaceOnUse region and content units over unpadded geometric bounds, isolated opacity groups with pooled tightly bounded 4× MSAA targets, peak-overlap GPU budget accounting, cumulative encode replay limits (≤3 attempts), retained `.Path` nodes inside composition trees, parent stencil restoration for sibling draws, and partially offscreen groups clamped without leaking into later UI. Gallery composition panels show nested clips + alpha masks and luminance + group fades on contrasting blue/amber grounds. CPU/GPU suites cover recording, depth limits, units, nested clips, luminance (including translucent white), MSAA mask edges, mask×clip, nested groups, offscreen bounds, sibling restoration, stale-geometry reupload, path-in-group drawing and budget/replay caps.

## M4 acceptance status — 2026-11-01

Paints and gradients landed: CPU `vector` paint model (`none` / solid / `currentColor` / linear / radial), SVG colour parsing in `libs/colors`, frame-owned stop ramps, premultiplied vector blending via `gpu_vector_blend_state()`, objectBoundingBox and userSpaceOnUse units, pad/reflect/repeat spread, SVG-correct gradientTransform sampling, interpolating-circle radials (including off-centre foci), sRGB and linearRGB stop interpolation, and nested affine composition in the gallery. Independent instances share geometry while using different paints. GPU reference fixtures (`fixtures/vector/gradients-*.png`) cover linear/radial, pad/reflect/repeat, transforms, off-centre radials and half-opacity interiors.

## M3 acceptance status — 2026-10-31

Production strokes landed: outline generation with butt/round/square caps, miter/round/bevel joins on the **outside** of turns (miter-limit bevel fallback), dash progression with `pathLength`-space lengths **and** dash offset (odd-length arrays doubled per SVG; offset period is the full cycle; `pathLength` scales the whole path and dash state continues across subpaths), zero-sum dash arrays as solid, seam-wrapped dashes merged as open polylines (full-loop dashes stay closed), zero-length caps, non-scaling width, and combined-coverage tessellation. Ordinary strokes flatten with a scale-tightened tolerance then transform the outline; round caps/joins use the same user-space tolerance so device-space curve error stays within 0.25 px. Dash/outline expansion respects configured command and flattened-segment limits. Stroke draws bake `entry.morph` / `instance_morph` into tessellation and never GPU-morph an expanded stroke mesh (so non-scaling width cannot be scaled by morph). Engine cache keys include fill-versus-stroke, full linear transform, stroke settings, stroke morph and `VECTOR_GEOMETRY_POLICY_REVISION`; paint-only and translation changes share geometry; stroke-setting edits use separate slots; morph/affine updates invalidate stroke slots while keeping fill; topology updates invalidate all slots for that path. Gallery stroke laboratory (caps, joins, dashes/`pathLength`, zero-length, scale vs non-scaling) and CPU/GPU leak-checked suites accompany the path.

## M6 acceptance status — 2026-11-01

M6 is complete against the normative [`SVG supported profile`](SVG-SUPPORTED-PROFILE.md). Loading validates the entire document, including unused definitions and hidden content, before producing an immutable, arena-owned scene. Namespaces, local reference graphs, CSS cascade and inheritance, geometry, viewport sizing, paints, strokes, clipping, masks and isolated opacity use one transactional drawing path. Source bytes may be released immediately after loading; recorded drawing survives asset release. Complexity, allocation and GPU conversion failures return structured diagnostics and omit the entire submission.

The [fixture manifest](../fixtures/vector/m6/manifest.toml) contains 38 positive/negative cases, supplemented by parser, styling, geometry, limit, allocation-failure and repeated ownership tests. Thirteen independently rendered SVG fixtures are compared at 1× and 2× DPI; the original fill references and thin-feature coverage gate also pass unchanged. The full five-package suite passed AddressSanitizer, allocation tracking and required GPU validation; final SVG regressions cover the completed non-scaling stroke DPI conversion. Reference provenance and reproduction commands are documented in [fixtures/vector/README.md](../fixtures/vector/README.md).

The standalone gallery begins with a selectable imported SVG beside its independent reference, a measured difference toggle, and readable load/render diagnostics and negative examples. Run `bash scripts/test_all.sh --require-vector-gpu oni` before launching it to generate the difference images under `build/test/`. The gallery selects the corresponding 1×/2× images and releases its assets, diagnostics and textures on shutdown. `--smoke` exercises its production lifecycle.

## M2 acceptance status — 2026-10-31

M2 landed affine morphs as GPU instance transforms over shared basis meshes; frames that only change instance data reuse previously uploaded vertex/index buffers. The dense-scene harness draws 2,048 icons with ordinary text in the same frame via `Draw_Vector_Paths`, advances 512 icons through independent morph affines, coalesces submissions, and keeps fence-confirmed completion well above 60 fps.

Production encode path: shared content-bounded grow-only 4× MSAA root for vectors and UI (single CLEAR/RESOLVE pass), five colour-only in-flight GPU slots (`frames: [5]`), depth only when groups/masks/clips require it, encode fence/upload/record instrumentation, present from `root.resolved`, and a 256 MiB vector GPU budget with transactional target replace. Cooled UHD 770 gate (four consecutive full runs after process teardown) stayed under the ≤4 ms CPU p95 ceiling; representative artifact below is the last of those runs.

| Measurement | Required | Shared 4× MSAA (5 slots) |
|---|---:|---:|
| Warm-up / measured frames | 120 / 1,800 | 120 / 1,800 |
| Fence-confirmed completed throughput | ≥60 fps | 302.5 fps |
| Full CPU frame p95 | ≤4 ms | 3.701 ms (cooled set: 3.975 / 3.592 / 3.675 / 3.701) |
| Encode fence / upload / record p95 | Report | 2.067 / 0.310 / 0.172 ms |
| App updates / UI and geometry p95 | Report | update 0.045 / paint 1.154 / encode 2.702 ms |

Hardware for the table: Intel UHD Graphics 770 (ADL-S GT1), Mesa 26.2.5 Vulkan, 1920×1080, 4× samples, 2048 icons × 4 paths × 32 curves, 512 independent morphs. Full `scripts/test_all.sh --require-vector-gpu oni` (1105 tests, leak checks) passed after this path landed.

Raw artifacts: `build/test/vector-benchmark.json`, `build/test/vector-benchmark-m8.json`, `build/test/vector-benchmark-composition.json`.

## M8 acceptance status — 2026-11-01

M8 completes lifecycle hardening and the release performance gates. Public APIs add `Reload_Svg_File`, `Reload_Svg_Memory`, and `Get_Vector_Stats`. Failed reload transactions preserve the prior asset revision and element handles; successful reload bumps `Svg_Asset.revision` and rejects stale handles. `gpu_reload` / hot reload call `vector_after_gpu_recreate` to bump `geometry_epoch` while retaining CPU path caches; `Migrate_State` joins tessellation workers and moves retained vector state like other subsystems.

The stress gallery adds workload counters, reload controls, and deliberate draw errors (`templates/vector_gallery.odin`). Frozen benchmark SVGs live under `fixtures/vector/benchmark/` with `scripts/generate_benchmark_svgs.py`. Opt-in harnesses `vector_dense_scene_svg_benchmark` and `vector_composition_dense_benchmark` enforce the same 120/1,800-frame, 60 fps, 4 ms CPU p95 gates as M2 using imported SVG `Draw_Svg_Asset` (2048 icons, 512 path morph overrides) and 256 nested opacity/mask instances respectively.

Automated coverage includes CPU reload tests (`vector/svg_reload_test.odin`), engine lifecycle tests (`vector_lifecycle_test.odin`), existing GPU cycle tests (`vector_memory_gpu_test.odin`), and migration/tess-pool shutdown tests. Regenerate benchmark assets only via the checked-in generator; hash the manifest in benchmark JSON output.

**Exit:** reload/revise semantics, stats, hot-reload GPU rebinding, 100-cycle load/reload/destroy tests, stress gallery, and benchmark harnesses are implemented with matching diagnostics and memory cleanup. Compare `vector-benchmark-ui-baseline.json` against vector-enabled runs for the 5% warmed ordinary-UI regression allowance. Run `./scripts/test_all.sh vector oni --asan` and `./scripts/benchmark_vector.sh --m8` on reference hardware to record release timing artifacts.
