shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float now_seconds;
varying float age;
varying float fall_time;
varying float daylight;
void vertex() {
 age = mod(now_seconds - INSTANCE_CUSTOM.x + 3600.0, 3600.0);
 fall_time = INSTANCE_CUSTOM.z;
 daylight = INSTANCE_CUSTOM.y;
 // Actual world-space descent towards the measured contact point. Both the
 // streak and its splash use the same timestamp, so a splash follows landing.
 vec3 center = MODEL_MATRIX[3].xyz + vec3(0.0, max(0.0, fall_time-age)*18.0, 0.0) + INV_VIEW_MATRIX[1].xyz*0.32;
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center,1.0));
}
void fragment() {
 float taper = sin(UV.y*3.14159265) * (1.0-smoothstep(0.15,0.5,abs(UV.x-0.5)));
 ALBEDO = mix(vec3(0.34,0.46,0.54),vec3(0.70,0.80,0.84),daylight);
 ALPHA = taper * (1.0-step(fall_time,age)) * 0.65;
}
