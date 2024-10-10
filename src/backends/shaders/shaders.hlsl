struct PSInput
{
    float4 position : SV_POSITION;
    float4 color : COLOR;
    float2 texcoord : TEXCOORD0;
};

PSInput VSMain(float4 position : POSITION, float4 color : COLOR, float2 texcoord : TEXCOORD0)
{
    PSInput result;

    result.position = position;
    result.color = color;
    result.texcoord = texcoord;

    return result;
}

Texture2D myTexture : register(t0);
SamplerState samplerState : register(s0);

float4 PSMain(PSInput input) : SV_TARGET
{
    return myTexture.Sample(samplerState, input.texcoord);
    // return texColor * input.color;
}

