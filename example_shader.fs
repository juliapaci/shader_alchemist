void main() {
    frag_colour = vec4(v_uv, (sin(u_time) + 1)/2, v_uv.x);
}
