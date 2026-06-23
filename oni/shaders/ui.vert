#version 460

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec2 local_uv;
layout(location = 3) in vec4 color;
layout(location = 4) in vec4 border_color;
layout(location = 5) in vec2 rect_size;
layout(location = 6) in vec4 radii;
layout(location = 7) in vec2 params;
layout(location = 8) in vec4 border;

layout(set = 1, binding = 0) uniform UBO {
    mat4 proj;
};

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec4 v_border_color;
layout(location = 2) out vec2 v_uv;
layout(location = 3) out vec2 v_local_uv;
layout(location = 4) out vec2 v_rect_size;
layout(location = 5) out vec4 v_radii;
layout(location = 6) out vec2 v_params;
layout(location = 7) out vec4 v_border;

void main() {
    gl_Position = proj * vec4(pos, 0.0, 1.0);
    v_color = color;
    v_border_color = border_color;
    v_uv = uv;
    v_local_uv = local_uv;
    v_rect_size = rect_size;
    v_radii = radii;
    v_params = params;
    v_border = border;
}
