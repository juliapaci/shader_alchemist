void main() {
    vec2 centre = v_uv - vec2(0.5);
    float time_norm = (1.0 + sin(u_time))/2;

    // frag_colour = vec4(v_uv, time_norm, 1.0);
    frag_colour = vec4(1.0, 1.0, 1.0, 1.0);

    // @pause
    // @inspect
    float radius = 0.3;
    radius += (0.05*sin(4 * u_time))*sin(10*centre.x + atan(centre.y, centre.x) * 4);
    frag_colour *= 1.0 - smoothstep(radius, radius + 0.01, length(centre));

    frag_colour.a = length(centre + vec2(0.0, 0.5));
}
