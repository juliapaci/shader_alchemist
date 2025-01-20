#define MAX_STEPS 80.0
#define MAX_DISTANCE 100.0
#define EPSILON 0.001

mat2 rot2D(in float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(vec2(c, -s), vec2(s, c));
}

vec3 rot3D(in vec3 p, in vec3 axis, in float angle) {
    // Rodrigues' rotation formula
    return mix(dot(axis, p) * axis, p, cos(angle)) + cross(axis, p) * sin(angle);
}

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float sdBox(vec3 p, vec3 s) {
    vec3 q = abs(p) - s;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// Cubic Polynomial Smooth-minimum
vec2 smoothMin(in float a, in float b, in float k) {
    k *= 6.0;
    float h = max( k-abs(a-b), 0.0 )/k;
    float m = h*h*h*0.5;
    float s = m*k*(1.0/3.0);

    return (a < b) ? vec2(a - s, m) : vec2(b - s, 1.0 - m);
}

// returns (distance, colour) of nearest object
vec4 map(in vec3 p) {
    vec4 d = vec4(0.0);
    d.x = MAX_DISTANCE;

    vec4 sphere = vec4(0);
    vec3 sphere_pos = vec3(5*sin(u_time), 5*cos(u_time), 0.0);
    for(int i = 0; i < 2; i++) {
        sphere = vec4(
            sdSphere(p - sphere_pos, 1.0),  // distance
            vec3(0.5, 0.2, 0.8)             // colour
        );

        d.xy = smoothMin(d.x, sphere.x, 0.05);
        sphere_pos.xy *= -1;
    }

    vec3 original = p;
    p.z += 0.1*u_time;
    p = fract(p) - 0.5;
    p.y = mod(p.y, 0.25) - (0.25)/2.;
    p.x = mod(p.x, 0.005) - (0.005)/2.;

    vec3 tmp = p;
    tmp.xy *= rot2D(u_time * 0.05);
    vec3 box_pos = vec3(0.0, 0.0, 0.0);
    vec4 box = vec4(
        sdBox(tmp - box_pos, vec3(0.01)) - 0.04,
        vec3(0.7, 0.1, 0.2)
    );
    d.xy = smoothMin(d.x, box.x, 00.5);

    d.yzw = mix(box.yzw, sphere.yzw, (sphere.x - box.x) + original.z/3 + original.y/3 + original.x/3);
    return d;
}

// returns (distance, colour)
// NOTE: direction must be normalized
vec4 march(vec3 ro, vec3 rd) {
    vec4 t = vec4(0);
    for(int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t.x;
        p.xy *= rot2D(0.1*t.x);
        p.z += 1.0 - log(t.x);

        vec4 d = map(p);
        t.x += d.x;
        t.yzw = d.yzw;
        if(t.x >= MAX_DISTANCE || d.x <= EPSILON) break;
    }

    return t;
}

void main() {
    vec2 centre = 2 * v_uv - 1;
    centre *= u_viewport.x / u_viewport.y;

    frag_colour = vec4(1.0);

    vec3 ro = vec3(0);
    ro.z -= 5;
    vec3 rd = normalize(vec3(centre, 1.0));

    vec4 colour = march(ro, rd);
    frag_colour = vec4(colour.yzw, 1.0 - 10*colour.x/MAX_DISTANCE);
}
