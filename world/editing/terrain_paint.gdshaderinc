uniform bool editor_terrain_paint_enabled = false;
uniform sampler2D editor_terrain_paint_a : filter_linear, repeat_disable;
uniform sampler2D editor_terrain_paint_b : filter_linear, repeat_disable;
uniform sampler2D editor_terrain_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D editor_terrain_earth : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 editor_terrain_paint_origin = vec2(0.0);
uniform vec2 editor_terrain_paint_extent = vec2(64.0);
uniform vec2 editor_terrain_paint_size = vec2(33.0);

// Seven continuous material weights, rather than interpolated material IDs.
// Both neighboring mountain chunks sample identical world-space border points.
vec4 editor_terrain_finish(vec3 base, vec2 point) {
	if (!editor_terrain_paint_enabled) { return vec4(base, 0.0); }
	vec2 uv = ((point - editor_terrain_paint_origin) / editor_terrain_paint_extent * (editor_terrain_paint_size - 1.0) + 0.5) / editor_terrain_paint_size;
	vec4 a = texture(editor_terrain_paint_a, uv);
	vec3 b = texture(editor_terrain_paint_b, uv).rgb;
	float coverage = clamp(dot(a, vec4(1.0)) + dot(b, vec3(1.0)), 0.0, 1.0);
	if (coverage < 0.001) { return vec4(base, 0.0); }
	vec3 grass = texture(editor_terrain_grass, point * 0.16).rgb;
	vec3 earth = mix(texture(editor_terrain_earth, point * 0.045).rgb, texture(editor_terrain_earth, point * 0.65).rgb, 0.32);
	float grain = texture(editor_terrain_earth, point * 1.25).r;
	float luminance = dot(earth, vec3(0.299,0.587,0.114));
	vec3 sand = vec3(0.68,0.58,0.39) * (0.76 + luminance * 0.9);
	vec3 gravel = vec3(0.40,0.43,0.40) * (0.72 + grain * 0.8);
	vec3 rock = vec3(0.38,0.42,0.42) * (0.72 + grain * 0.6);
	vec3 snow = vec3(0.79,0.83,0.82) * (0.93 + grain * 0.12);
	vec3 asphalt = vec3(0.14,0.16,0.16) * (0.82 + grain * 0.3);
	vec3 painted = grass*a.r + earth*a.g + sand*a.b + gravel*a.a + rock*b.r + snow*b.g + asphalt*b.b;
	return vec4(base * (1.0-coverage) + painted, coverage);
}
