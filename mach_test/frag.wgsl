struct Uniforms {
  matrix: mat4x4<f32>,
  use_tex: i32,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler : sampler;
@group(0) @binding(2) var myTexture : texture_2d<f32>;

@stage(fragment) fn main(
  @location(0) color : vec4<f32>,
  @location(1) uv : vec2<f32>,
) -> @location(0) vec4<f32> {
    if (uniforms.use_tex == 1) {
      return textureSample(myTexture, mySampler, uv) * color;
    }
    else {
      return color;
    }
}
