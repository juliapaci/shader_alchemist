vec3 A = vec3(0.5, 0.50, 0.50);
vec3 B = vec3(0.5, 0.50, 0.50);
vec3 C = vec3(1.0, 0.70, 0.40);
vec3 D = vec3(0.0, 0.15, 0.20);

// https://iquilezles.org/articles/palettes/
vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b*cos(6.283185*(c*t + d));
}

vec4 drawing(vec2 p) {
    vec2 pos = p;
    pos.y += 0.35;
    vec2 d = abs(pos) - 0.5;
    float rect = length(max(d,0.0)) + min(max(d.x,d.y),0.0);
    rect = smoothstep(0.1, 0.1+0.01, rect);

    vec3 graph = palette(p.x + 0.5, A, B, C, D);
    // graph = palette(length(fract(d) - 0.5)*10 + u_time, A, B, C, D);

    return vec4(
        rect,
        graph
    );
}

void main() {
    vec2 c = v_uv * 2 - 1;
    c.x *= u_viewport.x/u_viewport.y;

    frag_colour = vec4(1.0);

    vec4 obj = drawing(c);
    vec3 colour = obj.yzw;

    frag_colour.xyz = colour*(1.0 - obj.x);
}
