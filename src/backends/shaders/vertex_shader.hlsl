struct VSInput
{
    float3 position : SV_POSITION;
    float2 texCoord : TEXCOORD0;
    float4 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_POSITION;
    float2 texCoord : TEXCOORD0;
    float4 fragColor : COLOR;
};

cbuffer MatrixBuffer
{
    float4x4 mvp;
};

