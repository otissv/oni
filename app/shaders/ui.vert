#version 460

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
layout(location = 3) in vec2 rect_size;
layout(location = 4) in vec2 params;

layout(set = 1, binding = 0) uniform UBO {
    mat4 proj;
};

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out vec2 v_rect_size;
layout(location = 3) out vec2 v_params;

void main() {
    gl_Position = proj * vec4(pos, 0.0, 1.0);
    v_color = color;
    v_uv = uv;
    v_rect_size = rect_size;
    v_params = params;
}
