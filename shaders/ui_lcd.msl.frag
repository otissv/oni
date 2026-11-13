#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct LcdUBO
{
    float bgr;
};

struct main0_out
{
    float4 out0 [[color(0), index(0)]];
    float4 out1 [[color(0), index(1)]];
};

struct main0_in
{
    float4 v_color [[user(locn0)]];
    float2 v_uv [[user(locn2)]];
    float4 v_params [[user(locn6)]];
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
float3 text_coverage_rgb(thread const float3& coverage, thread const float3& tint_rgb)
{
    float lum = dot(tint_rgb, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float exponent = mix(1.4500000476837158203125, 0.699999988079071044921875, fast::clamp(lum, 0.0, 1.0));
    return powr(fast::max(coverage, float3(0.0)), float3(exponent));
}

fragment main0_out main0(main0_in in [[stage_in]], constant LcdUBO& _116 [[buffer(0)]], texture2d<float> tex0 [[texture(0)]], texture2d<float> tex1 [[texture(1)]], texture2d<float> tex2 [[texture(2)]], texture2d<float> tex3 [[texture(3)]], sampler tex0Smplr [[sampler(0)]], sampler tex1Smplr [[sampler(1)]], sampler tex2Smplr [[sampler(2)]], sampler tex3Smplr [[sampler(3)]])
{
    main0_out out = {};
    float3 tint = in.v_color.xyz;
    float2 param = in.v_uv;
    float param_1 = in.v_params.z;
    float3 sample_rgb = sample_texture(param, param_1, tex1, tex1Smplr, tex2, tex2Smplr, tex3, tex3Smplr, tex0, tex0Smplr).xyz;
    if (_116.bgr > 0.5)
    {
        sample_rgb = sample_rgb.zyx;
    }
    float3 param_2 = sample_rgb;
    float3 param_3 = tint;
    float3 cov = text_coverage_rgb(param_2, param_3);
    out.out0 = float4(tint * cov, 1.0);
    out.out1 = float4(cov, 1.0);
    return out;
}

