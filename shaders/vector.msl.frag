#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

struct Paint
{
    float4 mode;
    float4 uv_scale;
    float4 uv_offset;
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 v_uv [[user(locn0)]];
    float4 v_colour [[user(locn1), flat]];
    float2 v_pos [[user(locn2)]];
    float4 v_paint [[user(locn3), flat]];
    float4 v_grad0 [[user(locn4), flat]];
    float4 v_combined_linear [[user(locn5), flat]];
    float4 v_combined_shift_focal [[user(locn6), flat]];
};

static inline __attribute__((always_inline))
float srgb_to_linear(thread const float& c)
{
    if (c <= 0.040449999272823333740234375)
    {
        return c / 12.9200000762939453125;
    }
    return powr((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
}

static inline __attribute__((always_inline))
float mask_luminance(thread const float4& mask_value)
{
    float a = mask_value.w;
    float3 _479;
    if (a > 0.0)
    {
        _479 = mask_value.xyz / float3(a);
    }
    else
    {
        _479 = float3(0.0);
    }
    float3 rgb = _479;
    float param = rgb.x;
    float r = srgb_to_linear(param);
    float param_1 = rgb.y;
    float g = srgb_to_linear(param_1);
    float param_2 = rgb.z;
    float b = srgb_to_linear(param_2);
    return (((0.2125999927520751953125 * r) + (0.715200006961822509765625 * g)) + (0.072200000286102294921875 * b)) * a;
}

static inline __attribute__((always_inline))
float2 apply_combined(thread const float2& p, thread float4& v_combined_linear, thread float4& v_combined_shift_focal)
{
    return (float2x2(float2(v_combined_linear.x, v_combined_linear.y), float2(v_combined_linear.z, v_combined_linear.w)) * p) + v_combined_shift_focal.xy;
}

static inline __attribute__((always_inline))
float4 sample_ramp(thread const float& t, thread float4& v_paint, texture2d<float> ramp_texture, sampler ramp_textureSmplr, thread float4& v_colour)
{
    float row = v_paint.z;
    float height = float(max(int2(ramp_texture.get_width(), ramp_texture.get_height()).y, 1));
    float v = (row + 0.5) / height;
    float4 colour = ramp_texture.sample(ramp_textureSmplr, float2(fast::clamp(t, 0.0, 1.0), v));
    return float4(colour.xyz * colour.w, colour.w) * v_colour.w;
}

static inline __attribute__((always_inline))
float spread_parameter(thread const float& t, thread const float& spread)
{
    if (spread < 0.5)
    {
        return fast::clamp(t, 0.0, 1.0);
    }
    if (spread < 1.5)
    {
        float cycle = floor(t);
        float frac = t - cycle;
        if (mod(cycle, 2.0) >= 1.0)
        {
            return 1.0 - frac;
        }
        return frac;
    }
    return t - floor(t);
}

static inline __attribute__((always_inline))
float4 paint_linear(thread float4& v_combined_linear, thread float4& v_combined_shift_focal, thread float4& v_paint, texture2d<float> ramp_texture, sampler ramp_textureSmplr, thread float4& v_colour, thread float2& v_pos, thread float4& v_grad0)
{
    float2 param = v_pos;
    float2 p = apply_combined(param, v_combined_linear, v_combined_shift_focal);
    float2 p1 = v_grad0.xy;
    float2 p2 = v_grad0.zw;
    float scale = fast::max(fast::max(abs(p.x), abs(p.y)), fast::max(fast::max(abs(p1.x), abs(p1.y)), fast::max(abs(p2.x), abs(p2.y))));
    if (scale == 0.0)
    {
        float param_1 = 1.0;
        return sample_ramp(param_1, v_paint, ramp_texture, ramp_textureSmplr, v_colour);
    }
    p /= float2(scale);
    p1 /= float2(scale);
    p2 /= float2(scale);
    float2 d = p2 - p1;
    float len_sq = dot(d, d);
    if (len_sq == 0.0)
    {
        float param_2 = 1.0;
        return sample_ramp(param_2, v_paint, ramp_texture, ramp_textureSmplr, v_colour);
    }
    float t = 0.0;
    if (len_sq > 0.0)
    {
        t = dot(p - p1, d) / len_sq;
    }
    float param_3 = t;
    float param_4 = v_paint.y;
    t = spread_parameter(param_3, param_4);
    float param_5 = t;
    return sample_ramp(param_5, v_paint, ramp_texture, ramp_textureSmplr, v_colour);
}

static inline __attribute__((always_inline))
float4 paint_radial(thread float4& v_combined_linear, thread float4& v_combined_shift_focal, thread float4& v_paint, texture2d<float> ramp_texture, sampler ramp_textureSmplr, thread float4& v_colour, thread float2& v_pos, thread float4& v_grad0)
{
    float2 param = v_pos;
    float2 p = apply_combined(param, v_combined_linear, v_combined_shift_focal);
    float2 center = v_grad0.xy;
    float radius = fast::max(v_grad0.z, 0.0);
    float fr = fast::max(v_grad0.w, 0.0);
    float2 focal = v_combined_shift_focal.zw;
    float scale = fast::max(fast::max(fast::max(abs(p.x), abs(p.y)), fast::max(abs(center.x), abs(center.y))), fast::max(fast::max(abs(focal.x), abs(focal.y)), fast::max(radius, fr)));
    bool _296 = scale == 0.0;
    bool _305;
    if (!_296)
    {
        _305 = (radius == 0.0) && (fr == 0.0);
    }
    else
    {
        _305 = _296;
    }
    if (_305)
    {
        float param_1 = 1.0;
        return sample_ramp(param_1, v_paint, ramp_texture, ramp_textureSmplr, v_colour);
    }
    p /= float2(scale);
    center /= float2(scale);
    focal /= float2(scale);
    radius /= scale;
    fr /= scale;
    float2 d = p - focal;
    float2 c = center - focal;
    float dr = radius - fr;
    float a = dot(c, c) - (dr * dr);
    float b = (-2.0) * (dot(d, c) + (fr * dr));
    float cc = dot(d, d) - (fr * fr);
    float t = 0.0;
    if (a == 0.0)
    {
        if ((b > 0.0) && (radius >= fr))
        {
            t = 1.0;
        }
        else
        {
            if (b != 0.0)
            {
                t = (-cc) / b;
            }
            else
            {
                if (cc > 0.0)
                {
                    t = 1.0;
                }
            }
        }
    }
    else
    {
        float disc = fast::max((b * b) - ((4.0 * a) * cc), 0.0);
        float sqrt_disc = sqrt(disc);
        float _414;
        if (b < 0.0)
        {
            _414 = -sqrt_disc;
        }
        else
        {
            _414 = sqrt_disc;
        }
        float q = (-0.5) * (b + _414);
        float _426;
        if (q == 0.0)
        {
            _426 = (-b) / (2.0 * a);
        }
        else
        {
            _426 = fast::max(q / a, cc / q);
        }
        t = _426;
    }
    float param_2 = t;
    float param_3 = v_paint.y;
    t = spread_parameter(param_2, param_3);
    float param_4 = t;
    return sample_ramp(param_4, v_paint, ramp_texture, ramp_textureSmplr, v_colour);
}

fragment main0_out main0(main0_in in [[stage_in]], constant Paint& _522 [[buffer(0)]], texture2d<float> content_texture [[texture(0)]], texture2d<float> mask_texture [[texture(1)]], texture2d<float> ramp_texture [[texture(2)]], sampler content_textureSmplr [[sampler(0)]], sampler mask_textureSmplr [[sampler(1)]], sampler ramp_textureSmplr [[sampler(2)]])
{
    main0_out out = {};
    if (_522.mode.x >= 0.5)
    {
        float4 content = content_texture.sample(content_textureSmplr, ((in.v_uv * _522.uv_scale.xy) + _522.uv_offset.xy));
        float4 mask_value = mask_texture.sample(mask_textureSmplr, ((in.v_uv * _522.uv_scale.zw) + _522.uv_offset.zw));
        float coverage = 1.0;
        if (_522.mode.y > 1.5)
        {
            float4 param = mask_value;
            coverage = mask_luminance(param);
        }
        else
        {
            if (_522.mode.y > 0.5)
            {
                coverage = mask_value.w;
            }
        }
        out.result = content * (coverage * in.v_colour.w);
        return out;
    }
    if (in.v_paint.x < 0.5)
    {
        out.result = float4(in.v_colour.xyz * in.v_colour.w, in.v_colour.w);
        return out;
    }
    if (in.v_paint.x < 1.5)
    {
        out.result = paint_linear(in.v_combined_linear, in.v_combined_shift_focal, in.v_paint, ramp_texture, ramp_textureSmplr, in.v_colour, in.v_pos, in.v_grad0);
        return out;
    }
    out.result = paint_radial(in.v_combined_linear, in.v_combined_shift_focal, in.v_paint, ramp_texture, ramp_textureSmplr, in.v_colour, in.v_pos, in.v_grad0);
    return out;
}

