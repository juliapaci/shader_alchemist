#define MAX_STEPS 100.0
#define MAX_DISTANCE 100.0

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

@pause
float sdBox(vec3 p, vec3 s) {
    vec3 q = abs(p) - s;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// returns distance of nearest object
float map(in vec3 p) {
    float d = MAX_DISTANCE;

    vec3 sphere_pos = vec3(vec2(tan(u_time)), 0.0);
    float sphere = sdSphere(p - sphere_pos, 1.0);
    d = min(d, sphere);

    vec3 box_pos = vec3(vec2(-tan(u_time)), 0.0);
    float box = sdBox(p - box_pos, vec3(1)) - 0.2;
    d = min(d, box);

    float ground = p.y + 0.75;
    d = min(d, ground);

    return d;
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

    float colour = march(ro, rd);
    frag_colour = vec4(vec3(colour/MAX_STEPS), 1.0);
}
