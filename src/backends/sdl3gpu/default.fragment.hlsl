#include "shared.hlsl"

struct PixelOutput {
    float4 Color : SV_Target0;
};

Texture2D<float4> Texture0 : register(t0, space2);
SamplerState Sampler0 : register(s0, space2);

PixelOutput main(PSInput input)
{
    PixelOutput o;
    float4 sampled = Texture0.Sample(Sampler0, input.texcoord);
    o.Color = sampled * input.color;
    return o;
}
