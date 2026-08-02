#version 450

layout(push_constant) uniform PushConstants {
    float angle;
    float aspect;
} push;

layout(location = 0) out vec3 color;

void main() {
    const vec3 positions[8] = vec3[8](
        vec3(-1.0, -1.0, -1.0),
        vec3( 1.0, -1.0, -1.0),
        vec3( 1.0,  1.0, -1.0),
        vec3(-1.0,  1.0, -1.0),
        vec3(-1.0, -1.0,  1.0),
        vec3( 1.0, -1.0,  1.0),
        vec3( 1.0,  1.0,  1.0),
        vec3(-1.0,  1.0,  1.0)
    );
    const int indices[36] = int[36](
        0, 2, 1, 0, 3, 2,
        4, 5, 6, 4, 6, 7,
        0, 4, 7, 0, 7, 3,
        1, 2, 6, 1, 6, 5,
        3, 7, 6, 3, 6, 2,
        0, 1, 5, 0, 5, 4
    );
    const vec3 colors[6] = vec3[6](
        vec3(0.95, 0.20, 0.15),
        vec3(0.15, 0.65, 1.00),
        vec3(0.30, 0.90, 0.35),
        vec3(0.95, 0.75, 0.15),
        vec3(0.70, 0.25, 0.95),
        vec3(0.15, 0.90, 0.85)
    );

    float cy = cos(push.angle);
    float sy = sin(push.angle);
    float cx = cos(push.angle * 0.63);
    float sx = sin(push.angle * 0.63);
    mat3 rotate_y = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy);
    mat3 rotate_x = mat3(1.0, 0.0, 0.0, 0.0, cx, sx, 0.0, -sx, cx);
    vec3 position = rotate_x * rotate_y * positions[indices[gl_VertexIndex]];
    position.z += 4.5;

    const float near_plane = 0.1;
    const float far_plane = 20.0;
    const float focal_length = 1.9;
    gl_Position = vec4(
        position.x * focal_length / push.aspect,
        -position.y * focal_length,
        position.z * far_plane / (far_plane - near_plane) -
            near_plane * far_plane / (far_plane - near_plane),
        position.z
    );
    color = colors[gl_VertexIndex / 6];
}
