#include "shared.hlsl"

struct PixelOutput {
    float4 Color : SV_Target0;
};

Texture2D<float4> Texture0 : register(t0, space2);
SamplerState Sampler0 : register(s0, space2);


struct ClipRect
{
    float x;
    float y;
    float w;
    float h;
};

StructuredBuffer<ClipRect> clipRect: register(t1, space2);

PixelOutput main(PSInput input)
{
    PixelOutput o;
    if(input.texcoord.x < 0 || input.texcoord.x > 1 || input.texcoord.y < 0 || input.texcoord.y > 1)
    {
        o.Color = input.color;
        return o;
    }
    ClipRect r = clipRect[input.instance];
    // discard pixel if its outside of the clip r.
    //if ((input.position.x < 30.0)) //|| (input.position.x > r.x + r.w))// ||
        //(input.position.y < r.y) || (input.position.y > r.y + r.h)) 
    if ((input.position.x < r.x) || (input.position.x > r.x + r.w)  ||
        (input.position.y < r.y) || (input.position.y > r.y + r.h - 2)) 
    {
        // o.Color = float4(1.0, 0.0, 0.0, 1.0);
        // return o;
        discard;
    }

    float4 sampled = Texture0.Sample(Sampler0, input.texcoord);
    o.Color = sampled * input.color;
    return o;
}
