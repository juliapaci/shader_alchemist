float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float map(in vec3 p) {
    return sdSphere(p, 1 + sin(u_time));
}

void main() {
    vec2 centre = v_uv * 2 - 1;
    centre.x *= u_viewport.x/u_viewport.y;

    vec3 ro = vec3(0);
    ro.z -= 5;
    vec3 rd = normalize(vec3(centre, 1));

    float d = 0;
    for(int i = 0; i < 80; i++) {
        vec3 p = ro + rd * d;
        d += map(p);
        if(d >= 100 || d <= 0.001) break;
    }

    frag_colour = vec4(1.0 - vec3(d/100.), 1.0);
}
