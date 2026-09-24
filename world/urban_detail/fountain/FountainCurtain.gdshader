shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Cortina de água que transborda da taça: filetes que descem com velocidade
// crescente (UV.y = 0 na borda da taça) e se desfazem antes de bater na bacia.
uniform float speed = 1.6;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float columns = 90.0;
	float col = floor(UV.x * columns);
	float within = fract(UV.x * columns);
	float fall = UV.y * UV.y * 2.2 + UV.y;
	float flow = fract(fall * 3.0 - TIME * speed * (0.85 + hash(col) * 0.3) + hash(col + 17.0));
	float streak = smoothstep(0.0, 0.25, within) * smoothstep(1.0, 0.7, within);
	float gap = smoothstep(0.05, 0.3, flow) * smoothstep(1.0, 0.7, flow);
	float thin = mix(1.0, 0.35, UV.y);
	float alpha = streak * mix(0.55, 1.0, gap) * thin * (1.0 - smoothstep(0.85, 1.0, UV.y));
	ALBEDO = mix(vec3(0.62, 0.8, 0.84), vec3(0.95, 0.98, 1.0), gap * 0.6);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = vec3(0.04, 0.06, 0.07);
	ALPHA = alpha * 0.7;
}
