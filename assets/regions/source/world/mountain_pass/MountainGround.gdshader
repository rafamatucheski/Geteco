shader_type canvas_item;
uniform sampler2D surface : source_color, repeat_enable, filter_linear_mipmap;
uniform bool tint_existing = false;
varying vec2 ground_position;
void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
}
void fragment() {
	vec3 soil = texture(surface, ground_position / 256.0).rgb;
	vec3 fine = texture(surface, ground_position / 57.0).rgb;
	soil = mix(soil, fine, 0.28);
	COLOR = vec4(tint_existing ? COLOR.rgb*(0.84+soil.r*0.5) : soil,COLOR.a);
}
