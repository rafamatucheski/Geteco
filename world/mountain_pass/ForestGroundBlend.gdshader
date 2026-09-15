shader_type canvas_item;
uniform sampler2D surface : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D litter : source_color, repeat_enable, filter_linear_mipmap;
uniform float litter_amount = 0.15;
uniform float shade = 1.0;
uniform vec4 base_tint : source_color = vec4(.41,.325,.224,1.0);
varying vec2 ground_position;
void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
}
void fragment() {
	vec3 soil = texture(surface,ground_position/210.0).rgb;
	vec3 fine = texture(surface,ground_position/69.0).rgb;
	vec3 broad = texture(surface,ground_position/977.0+vec2(.37,.61)).rgb;
	vec4 leaves = texture(litter,ground_position/237.0).rgba;
	vec3 ground = mix(soil,fine,.18)*(0.83+broad.r*.50);
	ground = mix(base_tint.rgb,ground,.65);
	float edge = 1.0-COLOR.a;
	float cover = smoothstep(.02,.96,COLOR.a+(fine.r-.35)*edge*.8);
	ground = mix(ground,leaves.rgb,leaves.a*clamp(litter_amount+edge*.85,0.0,1.0));
	COLOR = vec4(ground*shade,cover);
}
