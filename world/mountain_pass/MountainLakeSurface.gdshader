shader_type canvas_item;
varying vec2 world;
void vertex() { world = VERTEX; }
void fragment() {
    vec2 p = world - vec2(2.0, 0.7) * TIME;
    vec2 delta = world - vec2(7160.0, 25.0);
    vec2 basin = vec2(dot(delta, vec2(0.68, -0.73)), dot(delta, vec2(0.73, 0.68)));
    float depth = smoothstep(0.05, 0.85, 1.0 - length(basin / vec2(345.0, 155.0)));
    float wave = sin(p.y * 0.13 + sin(p.x * 0.036) * 1.6);
    float detail = sin(p.y * 0.31 + p.x * 0.046 + TIME * 0.25);
    float glint = pow(max(wave * detail, 0.0), 14.0) * smoothstep(-0.3, 0.8, sin(p.x * 0.07 + sin(p.y * 0.051)));
    COLOR.rgb = mix(vec3(0.17, 0.32, 0.32), vec3(0.055, 0.16, 0.19), depth);
    COLOR.rgb += wave * 0.008 + glint * vec3(0.035, 0.05, 0.045);
}
