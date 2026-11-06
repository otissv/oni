# Supported SVG profile (normative)

This is the normative import contract implemented by the standalone `vector` package and exposed through Oni's SVG APIs. Rendering, controlled widgets, instance overrides and release performance are documented in [VECTOR.md](VECTOR.md). Namespace-qualified SVG elements use unqualified SVG attributes; an undeclared xlink prefix is malformed XML even when href takes precedence.

## Dated specification sources

| Key | Pinned edition and sections |
|---|---|
| XML | [XML 1.0 Fifth Edition, 2008-11-26](https://www.w3.org/TR/2008/REC-xml-20081126/), §§2–4; [Namespaces in XML 1.0 Third Edition, 2009-12-08](https://www.w3.org/TR/2009/REC-xml-names-20091208/), §§2–6 |
| Structure | [SVG 1.1 Second Edition, 2011-08-16](https://www.w3.org/TR/2011/REC-SVG11-20110816/struct.html), §§5.1–5.6, 5.10; [SVG 2 CR, 2018-10-04](https://www.w3.org/TR/2018/CR-SVG2-20181004/struct.html), §5.6 for unqualified href precedence |
| Coordinates | [SVG 1.1, 2011-08-16](https://www.w3.org/TR/2011/REC-SVG11-20110816/coords.html), §§7.4–7.12; CSS reference pixel is 96 dpi |
| Geometry | [SVG 1.1 paths](https://www.w3.org/TR/2011/REC-SVG11-20110816/paths.html), §§8.3–8.4, and [basic shapes](https://www.w3.org/TR/2011/REC-SVG11-20110816/shapes.html), §§9.2–9.7 |
| Painting | [SVG 1.1 painting](https://www.w3.org/TR/2011/REC-SVG11-20110816/painting.html), §§11.2–11.7; [SVG 2 painting, 2018-10-04](https://www.w3.org/TR/2018/CR-SVG2-20181004/painting.html), paint-order and non-scaling stroke |
| Gradients | [SVG 1.1 paint servers](https://www.w3.org/TR/2011/REC-SVG11-20110816/pservers.html), §13.2; SVG 2 paint servers for focal radius |
| Composition | [SVG 1.1 masking](https://www.w3.org/TR/2011/REC-SVG11-20110816/masking.html), §§14.2–14.5; [CSS Masking Level 1 CR, 2014-08-26](https://www.w3.org/TR/2014/CR-css-masking-1-20140826/), §§6–9 for alpha/luminance mask type |
| CSS | [Selectors Level 3 Recommendation, 2011-09-29](https://www.w3.org/TR/2011/REC-css3-selectors-20110929/), §§4–6, 8–9; [CSS 2.1 Recommendation, 2011-06-07](https://www.w3.org/TR/2011/REC-CSS2-20110607/cascade.html), §6 |
| Colour | [CSS Color Level 3 Recommendation, 2011-06-07](https://www.w3.org/TR/2011/REC-css3-color-20110607/), §§3–4; short/long alpha hex is the additional hexadecimal profile supported by Oni |

## Import policy and diagnostics

Validate the entire document before deciding what to draw. Unsupported attributes, properties, elements and values fail even in unused definitions, unmatched CSS rules and display:none subtrees. Metadata alone accepts unknown nested content. Syntax remains well-formed XML inside metadata; DTDs, external entities and external stylesheet processing instructions are never admitted.

Malformed supported syntax fails the whole load. CSS declaration errors also fail the whole load, including invalid declarations superseded by later declarations. This deliberate strict-import restriction replaces browser declaration recovery: no silently dropped declarations or partially imported artwork. Comments and ordinary processing instructions are nonvisual. XML declarations require version 1.0 and optional UTF-8 encoding and yes/no standalone fields. Input is bounded UTF-8; predefined entities, numeric character references, CDATA, scoped namespaces and both quote styles are supported. Duplicate raw/expanded attributes and undeclared prefixes are malformed XML.

| Category | Meaning |
|---|---|
| Malformed_Xml | XML syntax, UTF-8, illegal XML characters, duplicate attributes, namespace binding or forbidden DTD |
| Unsupported_Feature | Unsupported visual/nonmetadata content, namespace, attribute, selector, property, external stylesheet or unavailable profile feature |
| Invalid_Value | Malformed supported geometry/property/length/value or invalid element placement |
| Duplicate_Id | More than one nonmetadata element has the same ID |
| Missing_Reference | A required local target does not exist |
| Invalid_Reference | External/empty reference or incompatible target element type |
| Reference_Cycle | A local dependency cycle through use, gradients, clipping or masking |
| Limit_Exceeded | Source, decoding, nesting, selector, command or expansion allowance exhausted |
| Allocation_Failed | Backing allocation failure prevents completing the load or instance |
| Invalid_Handle | Instance target is missing, forged or from another asset revision |
| Duplicate_Override | Instance contains more than one override for a target/property |
| Rendering_Failed | Engine GPU recording failed after successful instance validation |

Svg_Load_Result.error retains the primary category even if allocating diagnostic strings fails. Diagnostics identify source line/column, element and property when available. Limit diagnostics include the resource and consumed/allowed values. A failed load returns no asset. The caller destroys the diagnostic result separately from an asset.

## Elements and attributes

Every element accepts id, class, style and the presentation properties in the next table. XML namespace declarations are consumed by the tokenizer; xml:lang and xml:space are accepted nonvisual annotations. Unknown namespace-qualified attributes fail, including attributes incorrectly placed in the SVG namespace. Unqualified SVG attributes retain their normal semantics on prefixed SVG elements.

The following are the only element-specific attributes. All other attributes fail outside metadata.

| Element | Attributes, defaults and behavior | Source; fixtures |
|---|---|---|
| svg | x/y=0 on nested viewports; width/height default to the containing viewport; viewBox; preserveAspectRatio=xMidYMid meet; version 1.0/1.1/2.0 and baseProfile=full annotations | Structure, Coordinates; nested-viewports, namespace-default, namespace-prefixed |
| g | Local transform/composition and inherited style; no additional attributes | Structure, Composition; css-classes, opacity-paint-order |
| defs | Validated definitions, never directly painted | Structure; forward-reference, negative-hidden-geometry |
| symbol | viewBox, preserveAspectRatio, width, height; only instantiated through use | Structure, Coordinates; symbol-instances, use-sizing |
| use | x/y=0, width/height default from referenced viewport/parent; href or xlink:href; forward local fragments only | Structure; href-precedence, xlink-href, forward-reference, use-sizing |
| path | d (empty/missing means no geometry); pathLength; all absolute/relative commands, repeated argument groups, smooth-control resets, exponents and comma/space separators | Geometry; fills-document, geometry-paths, negative-nonfinite, negative-hidden-geometry |
| rect | x/y=0, width/height=0; rx/ry copy the other radius when omitted and clamp to half the corresponding side; pathLength | Geometry; geometry-paths, physical-lengths, negative-units |
| circle | cx/cy/r=0; pathLength | Geometry; namespace-default, namespace-prefixed |
| ellipse | cx/cy/rx/ry=0; pathLength | Geometry; nested-viewports |
| line | x1/y1/x2/y2=0; pathLength | Geometry; geometry-paths |
| polyline, polygon | points; empty means no geometry; polygon closes; pathLength | Geometry; geometry-paths |
| linearGradient | x1/y1=0%, x2=100%, y2=0%; gradientUnits=objectBoundingBox; gradientTransform=identity; spreadMethod=pad; href/xlink:href local templates | Gradients; gradients-document, gradient-inheritance, negative-gradient-cycle |
| radialGradient | cx/cy/r=50%, fx/fy default to center, fr=0; common gradient attributes above; profile requires a positive focal radius to be smaller than r and its start circle to be contained in the end circle | Gradients; gradients-document, gradient-inheritance |
| stop | offset=0; number/percentage clamped to [0,1], monotonically clamped against preceding stops; stop properties below | Gradients; gradient-inheritance |
| clipPath | clipPathUnits=userSpaceOnUse; child shapes/use form a union, respecting child transforms and clip-rule; nested clipping intersects | Composition; clip-union |
| mask | x/y=-10%, width/height=120%; maskUnits=objectBoundingBox; maskContentUnits=userSpaceOnUse; mask-type=luminance | Composition; mask-stroke |
| style | type=text/css if present; text or CDATA stylesheet; no external imports | CSS; css-classes, negative-unused-property, negative-selector |
| title, desc | Nonvisual text annotations; no rendered children | Structure; namespace-scope, tokenizer contract tests |
| metadata | Nonvisual, accepts arbitrary well-formed nested content | Structure; editor-metadata, namespace-scope |

Negative dimensions/radii fail. Zero dimensions suppress geometry/viewports/mask regions. All numeric values must be finite. Length units are unitless, px, in, cm, mm, pt, pc and %. Font-relative, viewport-relative and other units fail. Transform lists support matrix, translate, scale, rotate including a center, skewX and skewY. Singular transforms produce no painted geometry.

Horizontal percentages use current viewport width; vertical percentages use height. Circle radii, stroke widths and dash lengths/offsets use sqrt((width²+height²)/2). A viewBox establishes the child user-coordinate percentage bases. Object-bounding-box coordinates use a unit box mapped through exact geometric bounds, excluding strokes, clipping and antialiasing padding. User-space gradient coordinates resolve at their paint occurrence's viewport. Zero-length linear gradients and zero-radius radial gradients use the last stop, independently of spread. SVG 1.1 radial focal points outside the end circle are clamped to its boundary. Gradient percentages use the corresponding axis; radial lengths use the normalized diagonal. Offsets and opacity percentages use a base of one.

Root intrinsic dimensions preserve explicit absolute sizes and the viewBox aspect ratio. Missing intrinsic dimensions use the 300×150 replaced-element default box, constrained by an available ratio. Nested SVGs and use-instantiated symbol/svg viewports apply their viewBox once, then preserveAspectRatio fitting and viewport overflow clipping. Alignment supports all nine xMin/xMid/xMax × YMin/YMid/YMax combinations, none, meet, slice and defer.

## Presentation properties and cascade

Presentation attributes have specificity zero and precede author stylesheet rules. Inline declarations have their own higher specificity. !important outranks normal declarations across both sources; specificity and source/declaration order break remaining ties. Element/class/ID compound selectors, repeated classes, selector lists, descendant and child combinators, universal selectors and CSS identifier escapes are supported. Attribute selectors, sibling combinators, pseudo selectors, namespace selectors, CSS variables and at-rules fail.

Inheritance is property-specific. Local transforms, display, opacity, clipping, masking and vector-effect reset at each element; they are not copied into children. An element's opacity isolates its complete fill/stroke/child result. Visibility is inherited but a descendant may explicitly become visible. Local reuse uses the referencing element for inheritance while selector matching retains the definition's original document ancestry. Referenced local declarations and transforms still apply; use x/y translation occurs inside its transform.

Every listed property accepts inherit, initial and unset in addition to the values below.

| Property | Default | Inherited | Values and percentage basis | Source; fixtures |
|---|---|---|---|---|
| color | black | yes | SVG named/hex/rgb/rgba/hsl/hsla/transparent/currentColor | Colour; css-classes, use-sizing |
| fill | black | yes | none, currentColor, colour, local url(#gradient) | Painting; fills-document, gradient-inheritance |
| stroke | none | yes | Same paint forms as fill | Painting; geometry-paths, mask-stroke |
| fill-rule | nonzero | yes | nonzero, evenodd | Painting; fills-document |
| clip-rule | nonzero | yes | nonzero, evenodd | Composition; clip-union |
| opacity | 1 | no | Finite number/percentage clamped to [0,1]; isolated result | Composition; opacity-paint-order |
| fill-opacity, stroke-opacity | 1 | yes | Finite number/percentage clamped to [0,1] | Painting; fills-document, mask-stroke |
| stroke-width | 1 | yes | Nonnegative length; normalized viewport diagonal for % | Painting; geometry-paths, stroke contract tests |
| stroke-linecap | butt | yes | butt, round, square | Painting; geometry-paths, stroke contract tests |
| stroke-linejoin | miter | yes | miter, round, bevel | Painting; geometry-paths, stroke contract tests |
| stroke-miterlimit | 4 | yes | Number ≥1 | Painting; stroke contract tests |
| stroke-dasharray | none | yes | none or nonnegative lengths; diagonal % basis; odd lists repeat, zero-sum is solid | Painting; geometry-paths, stroke contract tests |
| stroke-dashoffset | 0 | yes | Signed length; normalized diagonal % basis | Painting; stroke contract tests |
| vector-effect | none | no | none, non-scaling-stroke | Painting; stroke contract tests |
| display | inline | no | inline or none | Structure; hidden-content contract tests |
| visibility | visible | yes | visible, hidden, collapse | Structure; visibility contract tests |
| transform | identity | no | Supported affine transform list | Coordinates; nested-viewports, geometry-paths |
| clip-path | none | no | none or local url(#clipPath) | Composition; clip-union |
| mask | none | no | none or local url(#mask) | Composition; mask-stroke, negative-mask-reference |
| mask-type | luminance | no | alpha, luminance on mask | Composition; mask-stroke |
| overflow | visible (root), hidden (nested svg/symbol) | no | visible, hidden, scroll, auto; latter three clip to viewport | Composition; nested-viewports, use-sizing |
| paint-order | normal | yes | normal or an ordered subset of fill/stroke/markers, without duplicates; absent phases complete normal order; markers draw nothing in this profile | Painting; opacity-paint-order |
| color-interpolation | sRGB | yes | sRGB, linearRGB | Gradients; paint and gradient contract tests |
| stop-color | black | no | Colour or currentColor | Gradients; gradient-inheritance |
| stop-opacity | 1 | no | Finite number/percentage clamped to [0,1] | Gradients; gradient contract tests |

url references accept quoted or unquoted nonempty local fragments only. External URLs and fallback paint suffixes are outside this profile. Standard xlink references are part of SVG import semantics; there is no separate compatibility parser.

## Ownership, limits and executable coverage

Each load has one bounded owning arena. It retains parsed namespaces/IDs, styles, paints, dash arrays, geometry and compiled scene data. Failure releases the entire transaction; asset destruction releases its revision reference. Prepared instances pin the exact immutable revision until explicitly destroyed; uncached layout snapshots register pin release before frame-arena reset, including cancellation. Stable-key widget snapshots may instead be retained by the engine's heap-owned cache until replacement/shutdown. Diagnostics use their recorded caller allocator and remain independently owned. Definition lookup returns distinct nonzero indices with the asset revision. Caller source storage can be released immediately after loading.

Configured XML/reference depth has hard safety ceilings of 256/128. DEFAULT_SVG_LIMITS enforces 8 MiB source, XML depth 64, reference depth 32, 100,000 elements, 100,000 expanded references, 1,000,000 source commands and separately 1,000,000 emitted commands, 4,096 CSS rules, 16,000,000 selector operations and 64 MiB decoded arena blocks. Selector charging includes failed simple tests and each ancestor traversal. Graph analysis precedes expansion and memoizes visited definitions. XML/source limits apply before parsing/reading beyond the allowance. Mesh preparation additionally uses the renderer's per-build and aggregate frame budgets.

The executable manifest is [manifest.toml](../fixtures/vector/m6/manifest.toml). Its runner verifies every entry including the final one, validates expected diagnostic categories and rejects incomplete/duplicate entries. Further semantic, limit, allocation-failure and 100-cycle ownership tests are in [`vector/svg_contract_test.odin`](../vector/svg_contract_test.odin) and [`vector_svg_test.odin`](../vector_svg_test.odin). Source and image hashes, dimensions and pinned librsvg 2.63.4 identity are in [references.json](../fixtures/vector/m6/references.json); regenerate only with [generate_svg_references.py](../scripts/generate_svg_references.py).

Run `bash scripts/test_all.sh vector oni widgets` from the framework root for parser, engine and widget coverage; add `--asan` for sanitizer coverage and `--require-vector-gpu` to fail if real-GPU checks cannot run. Passing correctness tests does not establish the release performance gate.

GPU references cover imported CSS classes, namespaces, symbols, viewports, physical lengths, strokes, clip unions/intersections, masks, opacity, paint order and inherited gradients at 1×/2× DPI. Comparisons retain the implementation plan's 2/255 interior tolerance, one-physical-pixel silhouette displacement and per-region coverage allowance of max(one pixel area, 5%). Abrupt internal colour boundaries are checked as boundaries rather than flat interiors; silhouette and integrated coverage still include every pixel. Actual/difference artifacts are written under build/test. Expected images always come from the independent renderer.

## Explicit exclusions

Text/tspan/textPath, images, foreignObject, patterns, markers, filters, switch/conditional processing, scripts, embedded animation and external resources are unsupported visual content and fail loading. Editor-specific attributes outside metadata, browser CSS declaration recovery, external stylesheets, arbitrary CSS selectors and units not listed above are excluded. Controlled widgets and per-instance editing follow the [M7 contract](VECTOR.md#svg-instances-and-controlled-widgets-m7). Lifecycle reload, stats, and release benchmarks follow the [M8 contract](VECTOR.md#m8-acceptance-status--2026-11-03).

