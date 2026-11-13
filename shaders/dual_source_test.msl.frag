#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 out0 [[color(0), index(0)]];
    float4 out1 [[color(0), index(1)]];
};

fragment main0_out main0()
{
    main0_out out = {};
    float3 tint = float3(0.800000011920928955078125, 0.20000000298023223876953125, 0.100000001490116119384765625);
    float3 cov = float3(0.5, 0.25, 0.75);
    out.out0 = float4(tint * cov, 1.0);
    out.out1 = float4(cov, 1.0);
    return out;
}

