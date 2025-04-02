// https://iquilezles.org/articles/palettes
vec3 palette(in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d) {
    return a + b*cos(6.283185*(c*t+d) );
}

void main() {
    vec2 centre = 2*v_uv - 1;
    centre.x *= u_viewport.x/u_viewport.y;
    vec2 original_centre = centre;

    for(int i = 0; i < 3; i++) {
        @inspect
        centre = fract(1.9*centre) - 0.5;

        frag_colour = vec4(0.0);

        float ring = 1.0 - exp(-length(original_centre));
        ring += (1 + sin(u_time))/2 * length(centre);
        ring += (1 + cos(u_time))/2 * length(original_centre);
        frag_colour.xyz = palette(
            ring,
            vec3(length(original_centre), length(centre), sin(ring + u_time)),
            vec3(1.0, 0.5, 0.3),
            vec3(0.7, 0.3, 0.7),
            vec3(0.3, 0.1, 0.4)
        );

        ring *= sin(4*i*ring + u_time)/(4*i);
        ring += cos(atan(centre.y, centre.x)*5*i)/(10*i);
        ring = abs(ring);
        ring = 0.01/ring;

        frag_colour += ring;
    }
}
