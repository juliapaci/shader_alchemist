#version 330 core

in vec2 v_uv;

uniform sampler2D u_private_shared;

uniform vec2 u_viewport;
uniform float u_time;

out vec4 frag_colour;

#define M_PI 3.1415926535897932384626433832795

// TODO: shadertoy interoperability

// TODO: sdf stuff
// https://iquilezles.org/articles/distfunctions/
