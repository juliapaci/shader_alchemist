vec3 palette(in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d) {
    return a + b*cos(6.283185*(c*t+d));
}

vec4 colourMin(vec4 a, vec4 b) {
    return (a.x < b.x) ? a : b;
}

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}


vec4 map(in vec3 p, float depth, int iteration) {
    vec4 d = vec4(1/0., vec3(0));
    float r = 0.1;
    vec3 q = p;
    p = fract(p) - 0.5;

    float sphere = sdSphere(p, r);
    d = colourMin(d, vec4(
        sphere,
        palette(
            length(q),
            vec3(0.5, 0.5, 0.5),
            vec3(0.5, 0.5, 0.5),
            vec3(2.0, 1.0, 0.0),
            vec3(0.50, 0.20, 0.25)
        )
    ));

    float box = sdBox(p, vec3(r));
    d = colourMin(d, vec4(
        box,
        palette(
            depth,
            vec3(0.5, 0.5, 0.5),
            vec3(0.5, 0.5, 0.5),
            vec3(2.0, 1.0, 0.0),
            vec3(0.50, 0.20, 0.25)
        )
    ));

    return d;
}

void main() {
    vec2 centre = v_uv * 2 - 1;
    centre.x *= u_viewport.x/u_viewport.y;

    vec3 ro = vec3(
        sin(u_time),
        cos(u_time),
        u_time
    );
    vec3 rd = normalize(vec3(centre, 1));

    vec4 d = vec4(0);
    for(int i = 0; i < 80; i++) {
        vec3 p = ro + rd * d.x;
        vec4 cmap = map(p, d.x, i);
        d.x += cmap.x;
        d.yzw = cmap.yzw;
        if(d.x >= 100. || d.x <= 0.001) break;
    }

    vec4 colour = vec4(
        100.0,
        palette(
            v_uv.x + v_uv.y + u_time,
            vec3(0.8, 0.5, 0.4),
            vec3(0.2, 0.4, 0.2),
            vec3(2.0, 1.0, 1.0),
            vec3(0.00, 0.25, 0.25)
        )
    );
    colour = colourMin(d, colour);

    frag_colour = vec4(colour.yzw, 1.0);
}
