#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct UBO
{
    float4x4 proj;
};

struct main0_out
{
    float4 v_color [[user(locn0)]];
    float4 v_border_color [[user(locn1)]];
    float2 v_uv [[user(locn2)]];
    float2 v_local_uv [[user(locn3)]];
    float2 v_rect_size [[user(locn4)]];
    float4 v_radii [[user(locn5)]];
    float4 v_params [[user(locn6)]];
    float4 v_border [[user(locn7)]];
    float4 gl_Position [[position]];
};

struct main0_in
{
    float2 pos [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float2 local_uv [[attribute(2)]];
    float4 color [[attribute(3)]];
    float4 border_color [[attribute(4)]];
    float2 rect_size [[attribute(5)]];
    float4 radii [[attribute(6)]];
    float4 params [[attribute(7)]];
    float4 border [[attribute(8)]];
};

vertex main0_out main0(main0_in in [[stage_in]], constant UBO& _19 [[buffer(0)]])
{
    main0_out out = {};
    out.gl_Position = _19.proj * float4(in.pos, 0.0, 1.0);
    out.v_color = in.color;
    out.v_border_color = in.border_color;
    out.v_uv = in.uv;
    out.v_local_uv = in.local_uv;
    out.v_rect_size = in.rect_size;
    out.v_radii = in.radii;
    out.v_params = in.params;
    out.v_border = in.border;
    return out;
}

