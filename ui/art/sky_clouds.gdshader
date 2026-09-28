shader_type canvas_item;
render_mode unshaded;

uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform float coverage : hint_range(0.0, 1.0) = 1.0;
uniform float descent : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform float aperture = 0.36;
uniform vec3 cloud_color : source_color = vec3(0.64, 0.73, 0.80);

void fragment() {
	vec2 uv = UV;
	// Cloud drift stays independent of the descending camera. They clear before
	// the turn, instead of stretching a screen-space texture around that turn.
	vec2 p = (uv - 0.5) * vec2(1.78, 1.0);
	vec2 wind = vec2(clock * 0.008, clock * -0.003);
	float broad = texture(cloud_noise, p * 0.65 + wind).r;
	float detail = texture(cloud_noise, p * 1.8 - wind * 0.7).r;
	float vapor = broad * 0.74 + detail * 0.26;
	// The opaque perimeter is independent of noise: holes never expose map edges.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float edge = smoothstep(aperture * 0.43, aperture, length((uv - vec2(0.5)) * vec2(aspect * 0.675, 1.0)));
	float cloud = smoothstep(0.40, 0.65, vapor);
	float alpha = max(edge, cloud * 0.84);
	alpha = mix(alpha, 1.0, coverage);
	alpha *= 1.0 - descent;
	vec3 shade = cloud_color * (0.72 + vapor * 0.50);
	vec3 highlight = vec3(0.92, 0.94, 0.94);
	vec3 color = mix(shade, highlight, smoothstep(0.50, 0.78, vapor) * 0.65);
	COLOR = vec4(color, alpha);
}
