#define MAX_STEPS 100.0
#define MAX_DISTANCE 100.0

// returns distance of nearest object
float map(in vec3 p) {
    return length(p) - TIME_NORM;
}

// returns distance travelled
// NOTE: direction must be normalized
float march(vec3 ro, vec3 rd) {
    float t = 0;
    for(int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t;
        float d = map(p);
        t += d;

        if(t >= MAX_DISTANCE || d <= 0.001) break;
    }

    return t;
}

void main() {
    vec2 centre = 2 * v_uv - 1;
    centre *= u_viewport.x / u_viewport.y;

    vec3 ro = vec3(0);
    ro.z -= 5;
    vec3 rd = normalize(vec3(centre, 1.0));

    frag_colour = vec4(vec3(march(ro, rd)/MAX_STEPS), 1.0);
}
