#define SPEED 2

void main() {
    // same as `centre = (gl_FragCoord.xy * 2 - u_viewport.xy) / u_viewport.y`
    vec2 centre = v_uv * 2 - 1;
    centre.x *= u_viewport.x/u_viewport.y;
    float time_norm = (1.0 + sin(u_time))/2;
    frag_colour = vec4(1);

    vec2 original_centre = centre;
    float speed_off = sin(SPEED * u_time);
    centre.x += (1.0 + speed_off)/2;
    centre.x = fract(centre.x * 2) - 0.5;

    float decay = 0.04*(length(original_centre.x));
    decay = 0;

    // vignette
    frag_colour.a *= 1 - 0.5*length(original_centre);
    frag_colour.a = clamp(frag_colour.a, 0.0, 1.0);

    // ghost
    float radius = 0.3;
    radius -= decay;
    radius += (0.05*speed_off)*sin(10*centre.x + atan(centre.y, centre.x) * 4); // wobblyness based on angle
    frag_colour.xyz *= 1.0 - smoothstep(radius, radius + 0.01, length(centre));
    frag_colour.a *= length(centre + vec2(0.0, 0.5)); // lower shadow

    // eye
    float eyer = 0.05*(1 + 0.25*cos((2*SPEED)*u_time))/2;
    // eyer -= decay;
    vec2 offset = vec2(-0.2*sin(SPEED*u_time) + 0.07, 0.15);
    float eye = smoothstep(eyer, eyer+.01, length(centre - offset));
    for(int i = 0; i < 2; i++) {
        eye = smoothstep(eyer, eyer+.01, length(centre - offset));
        frag_colour *= eye;
        offset.x -= 0.15;
    }
}
