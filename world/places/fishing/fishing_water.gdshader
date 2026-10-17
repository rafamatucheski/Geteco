shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled, depth_draw_never;
varying vec2 pond;
uniform sampler2D rain_height : filter_linear, repeat_disable;
vec2 rain_uv(vec2 point) {
	// Align CPU grid samples with texture texel centers.
	return ((point - vec2(-30.0,-24.0)) / vec2(60.0,40.0) * vec2(47.0,31.0) + .5) / vec2(48.0,32.0);
}
void vertex() {
	pond = VERTEX.xz;
	VERTEX.y += textureLod(rain_height, rain_uv(pond), 0.0).r;
}
void fragment() {
	// A single transparent surface reveals the actual bed and hooked fish.
	// Broad, low-amplitude normal waves avoid noisy high-frequency specular.
	vec2 q = pond - vec2(0.0,-4.0);
	float angle = atan(q.y / 18.0, q.x / 27.0);
	float lobe = 1.0 + .045*sin(angle*3.0+.6) + .025*cos(angle*5.0);
	float edge = length(q / vec2(27.0,18.0)) / lobe;
	float depth = smoothstep(0.0,.42,1.0-edge);
	float a = pond.x*.95 + pond.y*.62 + TIME*.48;
	float b = pond.x*-.71 + pond.y*1.27 - TIME*.37;
	vec2 slope = vec2(cos(a)*.028-cos(b)*.021,cos(a)*.019+cos(b)*.031);
	vec2 rain_at = rain_uv(pond);
	vec2 texel = 1.0 / vec2(48.0,32.0);
	slope.x += (texture(rain_height, rain_at + vec2(texel.x,0)).r - texture(rain_height, rain_at - vec2(texel.x,0)).r) / (120.0/47.0);
	slope.y += (texture(rain_height, rain_at + vec2(0,texel.y)).r - texture(rain_height, rain_at - vec2(0,texel.y)).r) / (80.0/31.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x,1.0,-slope.y)),0.0)).xyz);
	float sheen = sin(a)*sin(b)*.006;
	ALBEDO = mix(vec3(.04,.12,.09),vec3(.009,.065,.057),depth) + sheen;
	ROUGHNESS = .38;
	SPECULAR = .42;
	ALPHA = mix(.36,.63,depth);
}
