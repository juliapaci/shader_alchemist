#version 330 core

in vec2 v_uv;

uniform vec2 u_viewport;
uniform float u_time;

out vec4 frag_colour;

// shadertoy interoperability
// TODO: do this way better
#define iTime u_time
#define iResolution u_viewport
#define mainImage main
#define fragColor frag_colour
#define fragCoord gl_FragCoord


// TODO: sdf stuff
// https://iquilezles.org/articles/distfunctions/
