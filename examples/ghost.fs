void main() {
    // same as `centre = (gl_FragCoord.xy * 2 - u_viewport.xy) / u_viewport.y`
    vec2 centre = v_uv * 2 - vec2(1);
    centre.x *= u_viewport.x/u_viewport.y;
    float time_norm = (1.0 + sin(u_time))/2;

    vec2 original_centre = centre;
    centre *= 1/(10*time_norm+0.01) + 1.0;
    centre = fract(centre);
    centre -= 0.5;

    frag_colour = vec4(1);

    // @pause
    // @inspect
    float radius = 0.3;
    radius += (0.05*sin(4 * u_time))*sin(10*centre.x + atan(centre.y, centre.x) * 4);
    frag_colour.xyz *= 1.0 - smoothstep(radius, radius + 0.01, length(centre));
    frag_colour.a *= length(centre + vec2(0.0, 0.5));

    float eyer = 0.05;
    vec2 offset = vec2(-0.2*sin(4*u_time) + 0.07, 0.15);
    for(int i = 0; i < 2; i++) {
        float eye = smoothstep(eyer, eyer+.01, length(centre - offset));
        frag_colour *= eye;
        offset.x -= 0.15;
    }
}
