#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct View
{
    float4 bounds;
};

struct main0_out
{
    float2 v_uv [[user(locn0)]];
    float4 v_colour [[user(locn1)]];
    float2 v_pos [[user(locn2)]];
    float4 v_paint [[user(locn3)]];
    float4 v_grad0 [[user(locn4)]];
    float4 v_combined_linear [[user(locn5)]];
    float4 v_combined_shift_focal [[user(locn6)]];
    float4 gl_Position [[position]];
};

struct main0_in
{
    float2 position [[attribute(0)]];
    float4 colour [[attribute(2)]];
    float2 origin [[attribute(3)]];
    float4 morph_linear [[attribute(4)]];
    float2 morph_shift [[attribute(5)]];
    float4 paint [[attribute(6)]];
    float4 grad0 [[attribute(7)]];
    float4 combined_linear [[attribute(8)]];
    float4 combined_shift_focal [[attribute(9)]];
};

vertex main0_out main0(main0_in in [[stage_in]], constant View& _47 [[buffer(0)]])
{
    main0_out out = {};
    float2 local = (float2x2(float2(in.morph_linear.x, in.morph_linear.y), float2(in.morph_linear.z, in.morph_linear.w)) * in.position) + in.morph_shift;
    float2 p = ((local + in.origin) - _47.bounds.xy) / _47.bounds.zw;
    out.gl_Position = float4((p.x * 2.0) - 1.0, 1.0 - (p.y * 2.0), 0.0, 1.0);
    float2 _84;
    if (in.paint.x >= 2.5)
    {
        _84 = (in.position - in.grad0.xy) / in.grad0.zw;
    }
    else
    {
        _84 = float2(0.0);
    }
    out.v_uv = _84;
    out.v_colour = in.colour;
    out.v_pos = in.position;
    out.v_paint = in.paint;
    out.v_grad0 = in.grad0;
    out.v_combined_linear = in.combined_linear;
    out.v_combined_shift_focal = in.combined_shift_focal;
    return out;
}

