# Native SVG and vector rendering for Oni

## 1. Goal and release contract

Build a production vector renderer in Odin on SDL_GPU, supporting imported SVG icons and programmatically created vector shapes. SVGs and custom shapes share the rendering pipeline. Tengu supplies app-owned animated values.

**Production-ready means complete and verified against the supported profile below.** It does not mean browser-level SVG compatibility. The 60 fps requirement is a measured release gate; feasibility must be demonstrated early.

### Supported SVG profile

| Feature | Required support |
|---|---|
| Geometry | All SVG path commands; rectangles, rounded rectangles, circles, ellipses, lines, polylines and polygons |
| Structure | Root/nested `svg`, groups, `defs`, `symbol`, local `use` references |
| Painting | Solid colours, `none`, `currentColor`, linear/radial gradients |
| Strokes | Width, butt/round/square caps, miter/round/bevel joins, miter limits, dashes, dash offset, `pathLength`, non-scaling strokes |
| Fill rules | Nonzero and even-odd, including holes and self-intersections |
| Gradients | Stops and stop opacity, spread modes, transforms, local inheritance, object-bounding-box/user-space units, sRGB/linearRGB interpolation |
| Composition | Fill/stroke opacity, isolated group opacity, nested clipping, alpha and luminance masks |
| Coordinates | Affine transforms, nested viewports, `viewBox`, `preserveAspectRatio`, unitless/px/physical lengths and percentages |
| Styles | Presentation attributes, inline styles and embedded stylesheets; element/class/ID/compound selectors, descendant/child combinators and selector lists |
| CSS cascade | Specificity, source order, inheritance and `!important` for supported properties |
| Namespaces | Default and prefixed SVG namespaces, namespace-aware attributes and `xlink:href` |
| Local reuse | Reference resolution, inherited styles, instance sizing and symbol viewports |
| Element access | Stable element lookup within an asset revision, with per-instance overrides |

Colours include SVG named colours, hexadecimal, RGB/RGBA, HSL/HSLA and transparent. Supported style properties control the geometry, painting, visibility, viewport overflow, clipping and masking listed above. Include `display`, `visibility`, fill/stroke `paint-order` and `mask-type`.

Text, images, `foreignObject`, patterns, markers and filters are deferred as listed at the end. Scripts, embedded animation, external resources, external stylesheets, CSS variables, pseudo-selectors and CSS at-rules remain outside this release.

Unsupported visual content produces a structured load error. Comments, `title`, `desc` and `metadata` are accepted without affecting rendering. Unknown content is ignored only inside metadata. Do not display silently incomplete artwork.

Use the SVG coordinate, painting, structure and masking specifications for supported semantics.

Before M2 begins, check in the normative element/attribute/property/value support matrix and its fixture manifest. Pin the dated SVG, CSS, colour and compositing specification editions and relevant sections used for each entry, including any deliberate profile restrictions. Record defaults, inheritance, percentage bases, invalid-value handling and diagnostic categories. Later milestones implement this contract; M6 must not introduce the first definition of supported semantics.

Malformed XML, malformed supported syntax and non-finite numeric values fail the load transaction with source diagnostics. Unsupported elements, attributes, properties or values outside metadata also fail, including inside unused definitions and `display:none` subtrees; validate the complete document before pruning rendering work. This deliberately strict import policy prevents a later override or reference from exposing content that was never validated. The matrix must distinguish accepted nonvisual annotations from unsupported content and specify CSS declaration-error behaviour explicitly.

## 2. Architecture and implementation contracts

### CPU core and public interfaces

Create a native CPU vector package independent of SDL and Tengu. It owns paths, paints, SVG parsing, scene descriptions, bounds and geometry preparation. Oni owns GPU execution and engine resource caches.

Expose these capabilities through Oni's PascalCase API:

- Build paths with move, line, quadratic/cubic curve, arc, close and basic-shape helpers.
- Create, update and destroy retained paths through generation-checked handles.
- Load SVGs from file or memory, inspect intrinsic dimensions, look up named elements, reload and release assets.
- Record vector paths or SVG scenes with paints, transforms and per-instance overrides.
- Return structured diagnostics identifying the source element/property and failure category.

Add `w.Svg` and `w.Vector` widgets. Follow Oni's Config/Props conventions: domain values and overrides belong in config; drawing and event procedures belong in props.

Shared SVG assets remain immutable. Override slices supplied by the app affect only that drawing instance. Overrides replace the selected element's local transform, paint, opacity or path while preserving ancestors and siblings. Element handles include the asset revision and reject stale use after reload.

Distinguish definition handles from occurrence handles. A definition-targeted override affects every occurrence of that element within the current drawing instance. An occurrence handle identifies one expanded element through its ordered chain of `<use>` sites and the terminal definition element; it affects only that occurrence. Both handle types are stable only within one asset revision. An occurrence-specific property takes precedence over the corresponding definition override. Duplicate overrides for the same target and property are an error, independent of slice order. Apply overrides after CSS resolution and before deriving inherited descendant values, bounds, clipping and geometry. Invalid targets or values reject the complete drawing submission.

Recording copies caller-owned override slices and all transitively borrowed data, including gradient stops and inline path data, into immutable frame-owned storage before the recording call returns. Handle-backed data instead pins its exact immutable revision. Callers may then mutate or free their inputs without changing deferred preparation or replay. Recording failure releases partial copies and pins; successful recordings retain them until frame cancellation or fence-safe retirement.

Programmatic path replacement may change topology. Tengu morph examples require compatible path structures; automatic correspondence between unrelated paths is excluded.

### Two-pass integration

Preserve the existing frame model:

```text
App tick: advance Tengu once
    → Layout: register, measure and declare fitting constraints
    → Layout finalization: solve viewport and placement
    → Draw: record vectors from solved geometry
    → Prepare resources and upload
    → Execute ordered GPU work
```

SVG intrinsic sizing follows the supported SVG/replaced-element sizing rules, including the 300×150 fallback when intrinsic information is insufficient. Icon examples explicitly request their intended size, such as 24×24.

`w.Vector` takes an explicit logical drawing viewport. Its drawing callback runs during Draw only. Its composable children follow the normal two-pass widget lifecycle.

### Rendering

Use CPU curve flattening and tessellation into nonoverlapping triangles, followed by GPU rendering with **4× MSAA**.

- Bound curve approximation error to 0.25 physical pixels after the complete linear transform, including shear.
- Resolve holes, intersections and winding on the CPU.
- Generate stroke outlines and tessellate their combined coverage so overlapping stroke pieces do not accumulate opacity.
- Use 32-bit indices for vector geometry.
- Cache geometry by immutable path identity/revision, fill-versus-stroke operation, effective fill/clip rule, complete stroke settings and the exact effective linear transform in physical pixels. Stroke settings include width, caps, joins, miter limit, dash array/offset, `pathLength` normalization and non-scaling mode. Include any resolved viewport or unit input that changes those values, plus the approximation/quantization policy revision. Keep translation separate so translated instances share geometry. Paint colours and opacity do not affect this key.

For topology, use a deterministic sweep arrangement. Quantize flattened input vertices in translation-free transformed coordinates to a 1/1024-pixel grid. Use canonical rational intersection identities and filtered exact predicates, with checked `i128` arithmetic and bounded big-integer fallback. Do not use epsilon-based sorting. Discard exact zero-area faces.

When vectors are present, draw vectors and existing widgets into a shared multisampled scene target, then resolve to the swapchain. Existing UI pipelines—including LCD text—need matching multisample variants. Frames without vectors retain their single-sample rendering path.

LCD text is permitted only when rendering against an opaque destination whose backdrop is already final, with no subsequent masking, opacity scaling, filtering or geometric resampling of that text. Use grayscale text for transparent intermediate targets and any composition path that cannot guarantee those conditions. Select this policy from the destination/composition context rather than glyph content. This is a defined text-compositing policy, not a fallback from the required vector MSAA quality. M1 must verify destination alpha and text appearance after final composition, including switching between opaque and transparent targets.

Order UI batches and atomic vector submissions by draw space, stack index and a shared submission sequence. Extend the current batch machinery rather than adding another UI traversal.

### Composition and resource lifetime

Use stencil levels for nested geometric clips, with a maximum depth of 64. Use tightly bounded intermediate targets for masks and isolated opacity groups.

- Include stroke extents and one physical pixel of antialiasing padding in target bounds.
- Complete and resolve a child target before sampling it.
- Composite premultiplied content with mask coverage and group opacity.
- Apply inherited clipping at the appropriate group boundary once.
- Resume the parent with preserved colour/stencil contents and fully rebound GPU state.

Recorded commands pin immutable resource versions. Asset release, path update, cache eviction and reload cannot invalidate recorded or in-flight work. Release pins on cancellation or after the submission fence completes. Use explicit fence-safe slot reuse or SDL resource cycling; swapchain acquisition alone is not the lifetime guarantee.

Prepare each vector submission transactionally. Resource or complexity failure omits that submission, reports a diagnostic and preserves subsequent UI drawing. Never emit half of an SVG.

For frames containing vectors, encode rendering into engine-owned scene targets before acquiring the swapchain. If command encoding fails after part of a vector submission was recorded, cancel that unsubmitted command buffer and replay the immutable frame from a cleared scene target, excluding the failed submission. Allow at most three encoding attempts in total, further bounded by the number of submissions plus one and the aggregate frame-work limits below. A further failure or exhausted replay budget terminates the frame with an explicit renderer error; a device-level or ordinary-UI failure does so immediately. Acquire the swapchain only after successful scene encoding, then resolve/composite the complete scene and submit. Test failures after an earlier SVG sibling has rendered. No partial scene is presented, and failed encoding must not consume or invalidate recorded resources needed for replay. Replay uses recorded UI commands without rerunning application callbacks, input events or either UI pass.

## 3. Feature milestones

Milestones are sequential. Each produces a persistent, inspectable gallery page and automated acceptance tests. Write tests before each implementation slice.

### M1 — Shared GPU rendering and visual test infrastructure

**Visible result:** coloured vector triangles between existing widgets and text, with working clipping, overlapping transparency, a simple opacity group and an alpha-mask example.

Implement the ordered command stream, multisampled scene target, pipeline variants, target restoration and GPU capture harness. Query colour/depth-stencil format and sample support; select a supported stencil format explicitly.

Before closing M1, freeze the support matrix and benchmark manifest required below. Record fixture hashes, the ordinary-UI baseline revision and the reference-image generator version/settings. These artifacts are prerequisites for comparable M2 and release measurements.

The first executable gate is successful creation and rendered readback of the combined 4× MSAA, depth/stencil and dual-source LCD pipeline configuration. Format queries alone do not satisfy this gate. Real GPU access is mandatory; unavailable hardware access blocks milestone completion.

**Exit:** existing UI remains visually correct, mixed ordering is correct, and capability/allocation failures leave the renderer in a defined state. Missing required capability is reported explicitly; do not silently substitute lower-quality rendering.

### M2 — Curves, filled paths and early performance proof

**Visible result:** editable curved shapes, rings, stars, holes and self-intersecting paths, with zoom and fractional-position controls.

Implement the path core, bounds, flattening, robust tessellation, geometry caching and retained handles. Cover coincident/reversed edges, tangent crossings, nearly parallel edges, duplicate points, reflections, singular transforms and extreme coordinates.

Run the M2 core variant of the frozen dense-scene workload defined below, including independently morphing instances. Use canonical programmatic paths and solid paints without depending on the M6 SVG importer or M7 widgets/Tengu integration. The M2 harness applies the same affine animation directly; M4 adds SVG transform/paint semantics. This proves geometry feasibility only; repeat the complete imported-SVG workload at M8.

**Exit:** geometry and image tests pass, and the core workload meets the performance gate. Failure blocks further expansion until the plan is revised; it does not justify silently reducing quality.

### M3 — Production strokes

**Visible result:** a stroke laboratory comparing caps, joins, miter limits, dashes, zero-length segments and non-scaling strokes.

Implement stroke outlines, curved joins/caps, dash progression, closed-contour seams and `pathLength` normalization. Validate behaviour under nonuniform scale and reflection.

**Exit:** overlapping stroke segments have correct coverage and opacity; stroke edits invalidate only affected geometry.

### M4 — Paints, gradients and transforms

**Visible result:** themed icons and custom shapes with transparent fills, linear/radial gradients, animated stops and nested transforms.

Implement paint data, colour parsing, gradient coordinate systems, spread modes and interpolation. Add separate premultiplied vector blending without changing existing UI shader conventions.

**Exit:** independent instances can use different colours and gradients while sharing geometry; gradient and transparency reference tests pass.

### M5 — Complete clipping, masks and group opacity

**Visible result:** nested clipped artwork, alpha/luminance masks and overlapping shapes faded as one group, shown against contrasting backgrounds.

Complete clip stacks, mask coordinate systems, nested group composition and pooled targets. Cover masks crossing clip boundaries and partially offscreen groups.

**Exit:** no double application of edge coverage or opacity, correct parent restoration, bounded target memory, and no leakage into later UI draws.

### M6 — SVG loading, styling, namespaces and local reuse

**Visible result:** actual SVG files beside reference images, with a selectable difference view, readable diagnostics, prefixed-namespace examples and multiple independently styled instances of one symbol.

Implement the supported XML/SVG profile, all path syntax, viewport rules and CSS cascade against the matrix frozen before M2. Complete its executable positive/negative fixtures and publish the verified matrix. Any profile change requires updating the contract and affected earlier acceptance tests explicitly.

Use a bounded UTF-8 SVG tokenizer. Support XML comments, processing instructions, CDATA where needed, predefined entities and numeric character references. Reject DTDs, external entities and external resource references.

**Namespace handling:**

- Resolve default and prefixed SVG namespaces by namespace URI rather than prefix spelling.
- Resolve namespace declarations with their proper scope, including nested declarations.
- Support local references through both `href` and namespace-qualified `xlink:href`; when both are present, `href` takes precedence.
- Distinguish editor metadata from renderable SVG elements.
- Ignore foreign elements only inside metadata; reject unsupported foreign content in the rendering tree.

**Local reuse:**

- Resolve local fragment references after indexing definitions, allowing forward references.
- Implement `<use>` placement, inherited values, referenced styles, instance sizing, and `<symbol>` viewport fitting.
- Preserve the distinction between the shared definition and each drawing instance.
- Ensure CSS scoping and inheritance follow SVG reuse semantics rather than simple node copying.
- Reject duplicate IDs, missing required references and reference cycles with source diagnostics.
- Apply the existing reference-depth and expansion limits before constructing expanded rendering data.

**Exit:** every supported feature has positive and negative fixtures. Tests cover equivalent default/prefixed namespace documents, nested namespace scope, `href` precedence, legacy `xlink:href`, editor metadata, forward references, differently styled symbol instances, sizing and cycles. Unsupported visual content fails explicitly.

Patterns and markers remain deferred; Stage 6 does not partially implement them.

### M7 — Widgets, editing and Tengu

**Visible result:** SVG icons inside buttons, flex/grid layouts, scrollports, artboards and overlays; a vector playground with Tengu-driven transforms, colours, strokes and path controls.

Complete the public asset/path APIs and controlled widgets. Demonstrate two copies of one SVG with independent named-element overrides.

Advance animations in the app tick. While animation is active under on-demand pacing, the app requests subsequent frames through Oni's existing wake API. Tengu remains independent.

**Exit:** Layout and Draw read consistent geometry, children remain composable, events follow existing conventions, and changing one instance never mutates another.

### M8 — Lifecycle, failure recovery and dense-scene release gate

**Visible result:** a stress gallery with workload controls, frame statistics, cache/resource counters, reload controls and deliberate error cases.

Complete asset reload, hot-reload rebinding, GPU recreation, resize/DPI handling, resource eviction and shutdown. Extend explicit engine-state migration for the vector subsystem.

A failed asset reload preserves the previous valid revision. Successful replacement invalidates old element lookups while retaining in-flight resources until safe retirement.

**Exit:** all release checks below pass, diagnostics remain actionable, and repeated load/release/reload cycles return resource counts to baseline.

## 4. Verification and performance acceptance

### Correctness

Extend the existing package runner with CPU vector tests. Use Oni's existing GPU readback infrastructure for rendered-image tests.

Required coverage includes:

- Geometry invariants, all path commands, stroke degeneracies and both fill rules.
- Cache separation for one path rendered with different fill/clip rules and stroke settings; paint-only changes retain geometry sharing.
- CSS cascade, namespace resolution, local reuse, inheritance, viewport sizing and reference cycles.
- Fractional translations of nearly coincident geometry, confirming cache correctness.
- Small icons at 1×/2× DPI, zoomed paths, nested transforms and transparent backgrounds.
- SVG/widget stack order, clipping, masks, opacity and existing LCD/gray text.
- Release or update after recording but before submission; cache eviction while resources are pinned.
- Definition/occurrence override precedence, nested `<use>` addressing, duplicate override errors and stale occurrence handles after reload.
- Mutation/free of caller-owned overrides, gradient stops and path data immediately after recording, including cancellation and replay.
- LCD/grayscale destination policy over opaque vector backdrops, transparent targets and final composition, checking colour and alpha.
- Failure injection at allocation, upload, pass creation and submission boundaries.
- Adversarial selector matching, big-integer growth, aggregate preparation/replay exhaustion and peak-memory accounting during resize/reload.

Generate pinned reference images using an independent renderer as development tooling only. Keep comparisons sensitive to thin strokes: do not exclude the entire edge region. Check interior colours, silhouette distance, visible thin features and integrated alpha coverage. Store actual/reference/difference artifacts for failures.

Use interior channel tolerance of 2/255; boundary displacement must remain within one physical pixel. Thin-feature integrated coverage must remain within the larger of one pixel of area or 5% of the reference. Analytic fixtures additionally verify topology and compositing independently of reference images.

### Bounded work and memory

Default limits are explicit and configurable:

| Resource | Default limit |
|---|---:|
| SVG source | 8 MiB |
| XML nesting / reference nesting | 64 / 32 |
| Elements / expanded references | 100,000 / 100,000 |
| Path commands / CSS rules | 1,000,000 / 4,096 |
| CSS selector work per asset load | 16,000,000 operations |
| Decoded asset memory | 64 MiB |
| Flattened segments / intersections per build | 262,144 / 262,144 |
| Sweep events / output triangles per build | 1,000,000 / 1,000,000 |
| Candidate edge-pair tests per build | 16,000,000 |
| Big-integer operand/result width | 4,096 bits |
| Exact-arithmetic work per build / frame | 16,000,000 / 32,000,000 limb operations |
| Candidate edge-pair tests across all frame builds | 32,000,000 |
| New flattened segments / triangles per frame | 1,000,000 / 4,000,000 |
| Recorded-command visits across encoding attempts | 1,000,000 |
| Total frame encoding attempts | 3 |
| CPU geometry cache | 64 MiB |
| Total vector GPU resources | 256 MiB |
| Intermediate-target pool, included above | 64 MiB |
| Group/mask sample work per frame | 64 million sample-pixels |

Count sample work across every actual rendering and compositing pass, including multisampling. Check limits before allocation or expansion. Pinned resources cannot be evicted to satisfy a new request; reject new work with a structured limit diagnostic.

A selector operation is one simple-selector test or one ancestor/child traversal step, including unsuccessful matches. An exact-arithmetic limb operation is one primitive operation on a fixed 64-bit limb; multiplication/division charge every inner-loop limb operation. Check width before constructing a result and work budgets before performing charged operations. These deterministic counters include failed preparation, cache misses and repeated attempts; replay never resets a frame budget. Count every visited recorded command, including ordinary UI commands, against the replay visit limit. Publish consumed/allowed values in limit diagnostics and test each limit at, below and above its boundary.

The 256 MiB GPU budget includes every allocation introduced by vector-enabled rendering: both frame slots' shared multisampled scene colour/depth-stencil attachments, resolve textures, vector buffers, upload/transfer buffers, intermediate targets, and old versions awaiting fence-safe retirement. The 64 MiB intermediate pool is a subset, not an additional allowance. Count live allocation sizes, including sample count, format size, array layers and mip levels; use backend allocation sizes where available and document conservative estimates otherwise. Existing ordinary-UI resources and OS-owned swapchain images are excluded from this incremental budget but reported separately. Resizing, reload and replay must reserve their peak overlap before allocation; unavailable headroom rejects the operation transactionally and retains the prior valid state. Report current and peak bytes per category and verify the two-slot 1920×1080 configuration fits before closing M1.

Validate finite coordinates and transforms. Bound translation-free transformed coordinates to ±2²⁰ physical pixels. Recursion, subdivision or arithmetic limits produce errors rather than truncated geometry.

### Performance gate

Reference hardware: **i9-12900K, Intel UHD 770, Linux/Vulkan, 1920×1080, release build, 4× MSAA**.

Freeze a checked-in benchmark manifest before M2. It contains the eight canonical path datasets and equivalent SVG files, content hashes, exact control points, animation equations, ordinary-UI declarations, fonts and sizes, sample configuration and deterministic seed `0x4F4E49`. No asset selection, animation or feature substitution is allowed between acceptance runs. Hash the manifest in every result. Fixture changes invalidate previous results and require repeating the affected gates.

The base workload contains exactly 2,048 icons in a 64×32 grid, each with a 24×24 logical viewport at 1× DPI and 28-pixel grid spacing, centred in the reference framebuffer. Cycle the eight assets by instance index. Each asset contains exactly four closed filled paths, each with 32 nondegenerate cubic segments; the corpus must include holes and self-intersections and record expected topology. The manifest fixes control points and motion amplitudes before the first timing run; flattened segment/triangle counts are reported so a degenerate corpus cannot stand in for the agreed geometry.

Index instances from zero. The first 1,536 instances (75%) animate transform, colour and opacity together, including continuous rotation, nonuniform scale spanning 0.75–1.25 and fractional translation of up to two physical pixels per axis. The remaining 512 instances (25%) independently morph all four paths with compatible command structures and distinct per-instance phases. The manifest specifies nonzero control-point displacement ranges and exact equations. Drive animation at `t = frame_index / 60` seconds, including warm-up frames; use the frozen seed for any generated phases. No quantized animation frames or phase grouping may enable shared morph geometry.

Include the same fixed ordinary UI in every vector benchmark: 32 labelled buttons and 96 text labels, with positions, strings, fonts, sizes and overlap order frozen in the manifest. Render the same ordinary UI alone for the no-vector comparison. M2 uses canonical programmatic paths and solid colours; M8 imports their equivalent SVG assets through the production scene API and uses the completed widget integration. Report these variants separately; passing M2 does not establish imported-SVG release performance.

After 120 warm-up frames, require **at least 60 fence-confirmed completed frames per second over 1,800 frames**, with full CPU frame time at p95 no greater than 4 ms. CPU timing includes preparation, both UI passes, uploads, submission and slot-reuse waits. The 4 ms threshold is the release gate enforced by `scripts/benchmark_vector.sh`. Results must include revision, build flags, OS/driver versions, manifest hash, counters and timing artifacts before any performance claim is marked proven.

Use a bounded two-slot offscreen harness so display refresh does not cap the test. Include final completion draining in wall time. Submission rate is not completion rate; fence observation latency is not reported as GPU execution time.

The separate composition workload contains exactly 256 instances in a 16×16 grid, with 64×48-pixel local viewports and 96×64-pixel grid spacing. Each instance contains two nested opacity groups, an alpha mask and a luminance mask enclosing overlapping curved fills, with animated mask transforms and group opacity. Freeze mask shapes, nesting order, clip bounds and equations in the same manifest. Require the same 120-frame warm-up, 1,800-frame measurement, completed-frame rate and CPU p95 thresholds as the base workload, with no omissions, limit errors or budget increases. Report actual group/mask sample work and peak target bytes.

No more than 5% CPU regression is allowed for warmed frames containing no vectors against the frozen ordinary-UI baseline revision, using identical content, settings, timing scope and hardware. Run baseline and candidate three times each and compare median run-level CPU p95 values; all vector acceptance runs must individually pass their thresholds. Do not introduce runtime pixel readbacks or per-frame GPU-idle waits to achieve these measurements.

## 5. Delivery and completion

Ship the visual gallery through Oni's starter documentation templates. Exercise it using an isolated consumer project outside the framework, without creating a framework-owned demo `app/`.

Every milestone includes memory cleanup and failure tests immediately; hardening is not deferred entirely to M8. Run the project's debug/vet/style/leak checks throughout, and ASAN plus required real-GPU tests before release. Release acceptance cannot treat skipped GPU tests as success.

Require 100 repeated lifecycle/reload cycles without growing live allocations, stale handles or GPU resource counts. Preserve retained CPU assets across ordinary hot reload and rebuild device-dependent resources when required.

Deliver API documentation, the supported SVG matrix, gallery instructions, benchmark results and explicit resource-limit diagnostics. Retain notices for adapted third-party algorithms or fixtures.

Implementation is complete only when every milestone's visible result and acceptance gate passes. Performance remains unproven until measured on the agreed hardware.

## 6. To be implemented later

These features are explicitly outside M1–M8. Until implemented, their use as visual content produces an unsupported-feature diagnostic.

| Feature | Future implementation |
|---|---|
| **`<text>`** | Font selection, shaping, positioning, anchoring, direction, spacing, fills and strokes |
| **`<tspan>`** | Nested text styling and per-span/per-character positioning, offsets and rotation |
| **`<textPath>`** | Text placement along paths, offsets, alignment and path-distance measurement |
| **`<image>`** | Embedded raster decoding, placement, aspect-ratio fitting, clipping and resource lifetime; external-resource policy requires separate definition |
| **`foreignObject`** | A separately defined embedded-content layout/rendering integration; HTML/CSS rendering is not provided by the vector renderer |
| **Patterns** | `<pattern>`, vector tile contents, tile/content units, transforms, viewport fitting, local inheritance and bounded repeated-tile rendering |
| **Markers** | `<marker>`, start/mid/end placement, automatic orientation, marker units, viewport fitting, context paints and marker-aware paint ordering |
| **Filters** | An explicitly supported filter graph, intermediate surfaces, effect bounds, colour-space handling and bounded GPU work |

Existing FreeType/HarfBuzz support can contribute to future SVG text implementation. Until then, lettering must be converted to paths before import.
