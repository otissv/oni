#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 out_color [[color(0)]];
};

struct main0_in
{
    float4 v_color [[user(locn0)]];
    float4 v_border_color [[user(locn1)]];
    float2 v_uv [[user(locn2)]];
    float2 v_local_uv [[user(locn3)]];
    float2 v_rect_size [[user(locn4)]];
    float4 v_radii [[user(locn5)]];
    float4 v_params [[user(locn6)]];
    float4 v_border [[user(locn7)]];
};

static inline __attribute__((always_inline))
float4 sample_texture(thread const float2& coord, thread const float& slot_value, texture2d<float> tex1, sampler tex1Smplr, texture2d<float> tex2, sampler tex2Smplr, texture2d<float> tex3, sampler tex3Smplr, texture2d<float> tex0, sampler tex0Smplr)
{
    int slot = clamp(int(slot_value + 0.5), 0, 3);
    if (slot == 1)
    {
        return tex1.sample(tex1Smplr, coord);
    }
    if (slot == 2)
    {
        return tex2.sample(tex2Smplr, coord);
    }
    if (slot == 3)
    {
        return tex3.sample(tex3Smplr, coord);
    }
    return tex0.sample(tex0Smplr, coord);
}

static inline __attribute__((always_inline))
float text_coverage_alpha(thread const float& coverage, thread const float3& tint_rgb, thread const float& tint_a)
{
    float lum = dot(tint_rgb, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float exponent = mix(1.4500000476837158203125, 0.699999988079071044921875, fast::clamp(lum, 0.0, 1.0));
    return powr(fast::max(coverage, 0.0), exponent) * tint_a;
}

static inline __attribute__((always_inline))
float sd_rounded_box_corners(thread const float2& p, thread const float2& half_size, thread const float4& corner_radii)
{
    float r;
    if (p.x < 0.0)
    {
        float _58;
        if (p.y < 0.0)
        {
            _58 = corner_radii.x;
        }
        else
        {
            _58 = corner_radii.w;
        }
        r = _58;
    }
    else
    {
        float _72;
        if (p.y < 0.0)
        {
            _72 = corner_radii.y;
        }
        else
        {
            _72 = corner_radii.z;
        }
        r = _72;
    }
    r = fast::min(r, fast::min(half_size.x, half_size.y));
    float2 q = (abs(p) - half_size) + float2(r);
    return (fast::min(fast::max(q.x, q.y), 0.0) + length(fast::max(q, float2(0.0)))) - r;
}

static inline __attribute__((always_inline))
float4 rounded_fill(thread const float4& tint, thread const float& dist)
{
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    return float4(tint.xyz, tint.w * alpha);
}

static inline __attribute__((always_inline))
float4 rounded_shape(thread const float4& tint, thread const float2& local_uv, thread const float2& size, thread const float4& outer_r, thread const float4& border_widths, thread float4& v_border_color)
{
    float2 p = local_uv * size;
    float2 half_size = size * 0.5;
    float2 outer_local = p - half_size;
    float bt = border_widths.x;
    float bb = border_widths.y;
    float bl = border_widths.z;
    float br = border_widths.w;
    bool has_border = (((bt + bb) + bl) + br) > 0.001000000047497451305389404296875;
    float2 param = outer_local;
    float2 param_1 = half_size;
    float4 param_2 = outer_r;
    float outer_d = sd_rounded_box_corners(param, param_1, param_2);
    float outer_a = 1.0 - smoothstep(-0.5, 0.5, outer_d);
    if (outer_a <= 0.0)
    {
        discard_fragment();
    }
    if (!has_border)
    {
        float4 param_3 = tint;
        float param_4 = outer_d;
        return rounded_fill(param_3, param_4);
    }
    float2 inner_half = fast::max(half_size - (float2(bl + br, bt + bb) * 0.5), float2(0.0));
    float2 inner_local = outer_local - (float2(bl - br, bt - bb) * 0.5);
    float2 param_5 = inner_local;
    float2 param_6 = inner_half;
    float4 param_7 = outer_r;
    float inner_d = sd_rounded_box_corners(param_5, param_6, param_7);
    float inner_a = 1.0 - smoothstep(-0.5, 0.5, inner_d);
    float4 fill = float4(tint.xyz, tint.w * inner_a);
    if (fill.w > 0.0)
    {
        return fill;
    }
    float border_a = outer_a * (1.0 - inner_a);
    return float4(v_border_color.xyz, v_border_color.w * border_a);
}

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> tex0 [[texture(0)]], texture2d<float> tex1 [[texture(1)]], texture2d<float> tex2 [[texture(2)]], texture2d<float> tex3 [[texture(3)]], sampler tex0Smplr [[sampler(0)]], sampler tex1Smplr [[sampler(1)]], sampler tex2Smplr [[sampler(2)]], sampler tex3Smplr [[sampler(3)]])
{
    main0_out out = {};
    float4 tint = in.v_color;
    float mode = in.v_params.y;
    float2 param = in.v_uv;
    float param_1 = in.v_params.z;
    float4 texel = sample_texture(param, param_1, tex1, tex1Smplr, tex2, tex2Smplr, tex3, tex3Smplr, tex0, tex0Smplr);
    if (mode >= 3.5)
    {
        float coverage = texel.w;
        float param_2 = coverage;
        float3 param_3 = tint.xyz;
        float param_4 = tint.w;
        out.out_color = float4(tint.xyz, text_coverage_alpha(param_2, param_3, param_4));
        return out;
    }
    if (mode >= 2.5)
    {
        float2 local_px = in.v_local_uv * in.v_rect_size;
        if (in.v_params.x > 0.5)
        {
            float min_x = in.v_border.z;
            float min_y = in.v_border.x;
            float max_x = in.v_rect_size.x - in.v_border.w;
            float max_y = in.v_rect_size.y - in.v_border.y;
            bool _414 = local_px.x < min_x;
            bool _422;
            if (!_414)
            {
                _422 = local_px.y < min_y;
            }
            else
            {
                _422 = _414;
            }
            bool _430;
            if (!_422)
            {
                _430 = local_px.x > max_x;
            }
            else
            {
                _430 = _422;
            }
            bool _438;
            if (!_430)
            {
                _438 = local_px.y > max_y;
            }
            else
            {
                _438 = _430;
            }
            if (_438)
            {
                discard_fragment();
            }
        }
        float4 tex_color = texel * tint;
        float4 param_5 = tex_color;
        float2 param_6 = in.v_local_uv;
        float2 param_7 = in.v_rect_size;
        float4 param_8 = in.v_radii;
        float4 param_9 = float4(0.0);
        float4 _457 = rounded_shape(param_5, param_6, param_7, param_8, param_9, in.v_border_color);
        out.out_color = _457;
        return out;
    }
    if (mode >= 1.5)
    {
        float edge = fast::min(in.v_uv.y, 1.0 - in.v_uv.y);
        float alpha = smoothstep(0.0, 0.0500000007450580596923828125, edge);
        out.out_color = float4(tint.xyz, tint.w * alpha);
        return out;
    }
    if (mode >= 0.5)
    {
        out.out_color = texel * tint;
        return out;
    }
    float4 param_10 = tint;
    float2 param_11 = in.v_uv;
    float2 param_12 = in.v_rect_size;
    float4 param_13 = in.v_radii;
    float4 param_14 = in.v_border;
    float4 _504 = rounded_shape(param_10, param_11, param_12, param_13, param_14, in.v_border_color);
    out.out_color = _504;
    return out;
}

