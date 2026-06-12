# Learn how to build a high level render with SDL£


## Overview
For a general renderer for **2D games + desktop UI + editor/tools**, learn in this order: 
1. **SDL3 basics**  
2. **SDL_Renderer as a beginner-friendly high-level drawing API**  
3. **SDL_GPU as your real backend**  
4. **renderer systems** like batching, text, clipping, atlases, render targets, and UI/vector drawing.



## 1. Odin + SDL3 basics first, no custom GPU yet

  Use Odin’s official vendor package docs so you know what you are importing; Odin lists `vendor:sdl3`, `vendor:sdl3/image`, and `vendor:sdl3/ttf`. 

  Focus on:
  - Opening a window and basic SDL render + vsync
  - event loop
  - keyboard/mouse input
  - timing, resize
  - cleanup. 

  Resources: 
  - Odin vendor package list
  - Odin examples repo
  - Odin forum SDL3 “Hellope” example, which shows SDL3 initialization, event handling, drawing, debug text, FPS limiting, and VSync. 

  ([Odin vendor packages](https://pkg.odin-lang.org/vendor/))

## 2. Learn SDL3 from official examples before tutorials full of code

The SDL wiki says the best simple SDL3 tutorials are currently `examples.libsdl.org`; focus only on these sections first: 
- **Renderer**, 
- **Input**
- **Audio**

Then the small full demos like Snake. Do not study every example; for you, the goal is to understand what SDL does for the app layer before building your own renderer. 

([SDL Wiki](https://wiki.libsdl.org/SDL3/Tutorials))

## 3. Use SDL_Renderer briefly as the “model” of a high-level renderer

This is not your final backend, but it teaches the API shape you want: `draw_rect`, `draw_texture`, `draw_geometry`, viewports, clipping, and presentation. Use the SDL3 renderer examples and the [Odin SDL3 basic setup](https://github.com/simon-robertson/odin-sdl3-basic-setup) repo.  

Focus on how a simple renderer is created, how events are handled, and how textures/shapes are drawn, not on memorizing C syntax.

## 4. Then move to SDL_GPU in Odin

Use Nadako’s **Odin SDL3 GPU Tutorial** playlist as your main Odin-first GPU resource; 
Focus on:
- Part 1 “Basic Setup, A Red Triangle”
- Part 4 “Indexed Drawing, A Quad”
- Part 5 “Texture Sampling”, 

Later Part 10 only when you care about Dear ImGui/editor UI. 

Skip the 3D-heavy episodes at first because you want a 2D/UI/tool renderer, not a 3D engine. 

([Odin SDL3 GPU Tutorial](https://www.youtube.com/playlist?list=PLI3kBEQ3yd-CbQfRchF70BPLF9G1HEzhy))

## 5. Use C/C++ SDL_GPU resources only for concepts, not as your main path

The best non-Odin beginner resource is **GPUForBeginners**, because it starts from blank window and first triangle using SDL3’s GPU API. 

Use it to understand words like command buffer, swapchain, pipeline, texture, sampler, and render pass. 

Also keep SDL’s official GPU docs open because SDL_GPU targets broad hardware support and is designed so apps usually do not need lots of feature-branching. 

([GPUForBeginners](https://gpuforbeginners.com/))

##  6. Build your renderer in layers

- Layer 1: platform/app with SDL3.

- Layer 2: low-level backend with SDL_GPU. 

- Layer 3: high-level drawing API: `draw_rect`, `draw_texture`, `draw_sprite`, `draw_text`, `draw_line`, `draw_panel`, `draw_clip_rect`, `draw_render_target`.

- Layer 4: editor/UI features: clipping, scrolling panels, text input, cursor, selection, docking later.

- Layer 5: production systems: asset loading, texture atlases, font atlas, batching, hot reload, debug overlay, frame stats, error logging, and RenderDoc captures.

##  7. For text and UI, delay the hard path

Start with `vendor:sdl3/ttf` or a bitmap font so you can build `draw_text` early. 

Later learn FreeType + HarfBuzz if you need professional text shaping. 

For UI, you can render Clay or your own immediate-mode UI using your renderer, but your renderer should only need primitives: rectangles, rounded rectangles later, text, images, clipping, and layers.

## 8. Final project sequence

Make these mini-projects in order: 
- SDL3 window and input viewer; SDL_Renderer rectangle/texture demo
- SDL_GPU red triangle; SDL_GPU quad; textured quad; `draw_sprite`
- Sprite batcher; texture atlas; clipping/scissor demo
- Render-to-texture demo
- Font rendering demo
- Simple UI panel system; 
- A tiny editor with viewport, toolbar, asset list, and property panel.
- SVG / paths
