#version 450

layout(push_constant) uniform PushConstants {
    float angle;
} push;

layout(location = 0) out vec3 color;

void main() {
    const vec2 positions[3] = vec2[3](
        vec2( 0.0, -0.65),
        vec2( 0.65, 0.55),
        vec2(-0.65, 0.55)
    );
    const vec3 colors[3] = vec3[3](
        vec3(1.0, 0.2, 0.15),
        vec3(0.15, 1.0, 0.3),
        vec3(0.2, 0.4, 1.0)
    );

    float c = cos(push.angle);
    float s = sin(push.angle);
    mat2 rotation = mat2(c, s, -s, c);
    gl_Position = vec4(rotation * positions[gl_VertexIndex], 0.0, 1.0);
    color = colors[gl_VertexIndex];
}
