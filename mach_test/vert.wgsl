struct Uniforms {
  matrix: mat4x4<f32>,
  use_tex: i32,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;

struct VertexOutput {
  @builtin(position) position : vec4<f32>,
  @location(0) color : vec4<f32>,
  @location(1) uv: vec2<f32>,
};

@stage(vertex) fn main(
  @location(0) position : vec2<f32>,
  @location(1) color : vec4<f32>,
  @location(2) uv: vec2<f32>,
) -> VertexOutput {
  var output : VertexOutput;

  var pos = vec4<f32>(position, 0.0, 1.0);
  output.position = uniforms.matrix * pos;

  output.color = color;
  output.uv = uv;

  return output;
}
