#version 330 core

// need non zero vbo but this is useless since we can just use `gl_VertexID`
layout (location = 0) in float a_index;
out vec2 v_uv;

const vec2 SCREEN[4] = vec2[4](
    vec2( 1, 1),
    vec2(-1, 1),
    vec2(-1,-1),
    vec2( 1,-1)
);

void main() {
    vec2 pos = SCREEN[gl_VertexID];
    gl_Position = vec4(pos, 0.0, 1.0);

    v_uv = 0.5*pos + vec2(0.5);
}
