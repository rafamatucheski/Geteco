shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
varying float age;
varying float daylight;
varying float water_contact;
uniform float now_seconds;
void vertex() {
 age = mod(now_seconds - INSTANCE_CUSTOM.x + 3600.0, 3600.0) - INSTANCE_CUSTOM.z;
 daylight = INSTANCE_CUSTOM.y;
 water_contact = clamp(INSTANCE_CUSTOM.a, 0.0, 1.0);
 float lifetime = mix(0.45, 0.85, water_contact);
 VERTEX.xz *= mix(0.12, mix(1.0, 1.65, water_contact), clamp(age / lifetime, 0.0, 1.0));
}
void fragment() {
 float radius = length(UV * 2.0 - 1.0);
 float ring = smoothstep(mix(0.62, 0.75, water_contact), mix(0.78, 0.83, water_contact), radius) * (1.0 - smoothstep(mix(0.82, 0.88, water_contact), 1.0, radius));
 vec3 dry_color = mix(vec3(0.26,0.34,0.39), vec3(0.64,0.73,0.77), daylight);
 vec3 water_color = mix(vec3(0.21,0.32,0.31), vec3(0.38,0.50,0.45), daylight);
 ALBEDO = mix(dry_color, water_color, water_contact);
 ALPHA = ring * step(0.0, age) * (1.0 - smoothstep(mix(0.05, 0.12, water_contact), mix(0.45, 0.85, water_contact), age)) * mix(0.75, 0.40, water_contact);
}
