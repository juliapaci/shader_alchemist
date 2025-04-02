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

float sdEllipsoid(in vec3 p, in vec3 r) {
    float k1 = length(p/r);
    float k2 = length(p/(r*r));
    return k1*(k1-1.0)/k2;
}

vec4 map(in vec3 p) {
    vec4 d = vec4(1/0., vec3(0));

    // head (white)
    float head = sdSphere(p, 1.0) - vec2(
        sin(u_time), cos(u_time)
    );
    d = colourMin(d, vec4(head, vec3(0.5)));

    // body (red)
    float body = sdEllipsoid(vec3(p.x, p.y + 1.5, p.z), vec3(1.0, 2.0, 1.0));
    d = colourMin(d, vec4(body, vec3(1.0, 1.5, sin(u_time))));

    // idk
    // vec3 pos = p;
    // pos.x += sin(u_time)*2.;
    // pos.y += cos(u_time)*2.;
    // vec3 colour = palette(
    //     length(p)/4.,
    //     vec3(0.8, 0.5, 0.4),
    //     vec3(0.2, 0.4, 0.2),
    //     vec3(2.0, 1.0, 1.0),
    //     vec3(0.00, 0.25, 0.25)
    // );
    // float box = sdBox(pos, vec3(1.0));
    // d = colourMin(d, vec4(box, colour));
    // d.x -= length(p)/10;

    return d;
}

vec4 march(vec2 q) {
    vec3 ro = vec3(0.0);
    vec3 rd = normalize(vec3(q, 1));
    ro.z -= 5;

    vec4 d = vec4(0.0);
    for(int i = 0; i < 80; i++) {
        vec3 p = ro + rd*d.x;
        vec4 cmap = map(p);
        d.x += cmap.x;
        d.yzw = cmap.yzw;

        if(d.x >= 100. || d.x <= 0.001) break;
    }

    return d;
}

void main() {
    vec2 centre = v_uv * 2 - 1;
    centre.x *= u_viewport.x/u_viewport.y;

    vec4 c = march(centre);
    vec3 background = vec3(0.0);
    vec4 colour = colourMin(c, vec4(100., background));

    frag_colour = vec4(colour.yzw, 1.0);
}
