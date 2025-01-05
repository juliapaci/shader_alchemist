void main() {
    vec2 centre = v_uv - vec2(0.5);
    // centre *= u_viewport.x/u_viewport.y;

    // frag_colour = vec4(v_uv, (sin(u_time) + 1)/2, v_uv.x);
    frag_colour = vec4(1.0, 1.0, 1.0, 1.0);

    // @inspect
    float radius = 0.3;
    radius += (0.05*sin(4 * u_time))*sin(10*centre.x + atan(centre.y, centre.x) * 4);
    frag_colour *= 1.0 - smoothstep(radius, radius + 0.01, length(centre));

    frag_colour.a *= length(centre - vec2(0.0, 0.5));
}
