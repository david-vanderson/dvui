#include "shared.hlsl"

PSInput main(float4 position : POSITION, float4 color : COLOR, float2 texcoord : TEXCOORD0)
{
    PSInput result;

    result.position = position;
    result.color = color;
    result.texcoord = texcoord;

    return result;
}
