shader_type spatial;
render_mode depth_draw_never;
uniform mat4 part_to_car;
uniform float half_length = 2.3;
uniform float half_width = 1.0;
uniform int stains = 0;
varying vec3 car_point;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
void vertex() { car_point = (part_to_car * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 p = car_point;
	float area = 0.0;
	if ((stains & 1) != 0) area = max(area, smoothstep(half_length * .30, half_length * .85, -p.z));
	if ((stains & 2) != 0) area = max(area, smoothstep(half_length * .30, half_length * .85, p.z));
	if ((stains & 4) != 0) area = max(area, smoothstep(half_width * .50, half_width * .95, -p.x));
	if ((stains & 8) != 0) area = max(area, smoothstep(half_width * .50, half_width * .95, p.x));
	vec3 grid = p * vec3(13.0, 19.0, 13.0);
	vec3 cell = floor(grid);
	float seed = hash(cell);
	float radius = mix(.09, .46, seed);
	float drop = 1.0 - smoothstep(radius * .65, radius, length(fract(grid) - vec3(.5)));
	float smear = smoothstep(.25, .8, sin(p.x * 22.0 + sin(p.z * 17.0)) * sin(p.y * 26.0 + p.z * 13.0));
	float opacity = area * max(drop, smear * .80) * smoothstep(.28,.55,p.y) * (1.0-smoothstep(1.4,1.9,p.y));
	if (opacity < .08) discard;
	ALBEDO = mix(vec3(.12,.006,.004), vec3(.34,.012,.008), seed);
	ROUGHNESS = .62;
	ALPHA = opacity * .95;
}
