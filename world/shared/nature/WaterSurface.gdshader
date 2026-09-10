shader_type canvas_item;

uniform vec2 flow = vec2(7.0, 2.0);
uniform float strength = 1.0;
uniform float foam = 0.0;
uniform float fountain = 0.0;
uniform float running = 1.0;
varying vec2 water_position;

void vertex() {
    water_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    if (fountain > 0.5) water_position = VERTEX;
}

void fragment() {
    float t = TIME * running;
    vec2 p = water_position - flow * t;
    float swell = sin(p.y * 0.057 + p.x * 0.018 + sin(p.x * 0.021) * 1.7);
    float ripple = sin(p.y * 0.19 - p.x * 0.035 + swell * 1.6);
    float cross_wave = sin(p.x * 0.075 + p.y * 0.09 + t * 0.6);
    float breakup = smoothstep(-0.15, 0.85, sin(p.x * 0.039 + cross_wave * 2.0));
    float glint = pow(max(ripple, 0.0), 12.0) * breakup;
    vec3 tint = vec3(0.012, 0.026, 0.031) * swell + vec3(0.055, 0.105, 0.11) * glint;
    COLOR.rgb += tint * strength;
    if (foam > 0.0) {
        COLOR.a *= mix(1.0, 0.22 + 0.78 * smoothstep(-0.6, 0.9, ripple + cross_wave * 0.4), foam);
    }
    if (fountain > 0.5) {
        float radius = length(water_position);
        float rings = pow(max(sin(radius * 0.48 - t * 3.5), 0.0), 8.0);
        COLOR.rgb += vec3(0.12, 0.22, 0.22) * rings * smoothstep(13.0, 20.0, radius);
    }
}
