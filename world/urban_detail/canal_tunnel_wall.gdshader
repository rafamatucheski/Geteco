shader_type spatial;
render_mode cull_back;
// Parede interna do Túnel do canal. UV.x = x do mundo (m), UV.y = altura acima do
// piso (m), montados por CanalTunnel3D.gd: azulejo em amarração, faixa de cor, friso
// laranja e a fita de LED com pulsos correndo no sentido da faixa de tráfego.
// Pulsos por TIME (GPU): sem luz dinâmica nem processamento por quadro (orçamento Mobile).
uniform vec3 tile_color : source_color = vec3(0.86, 0.85, 0.78);
uniform vec3 grout_color : source_color = vec3(0.42, 0.43, 0.41);
uniform vec3 band_color : source_color = vec3(0.04, 0.52, 0.58);
uniform vec3 stripe_color : source_color = vec3(0.96, 0.56, 0.12);
uniform vec3 led_color : source_color = vec3(0.55, 0.92, 1.0);
uniform float led_height = 3.0;
uniform float direction = 1.0;
uniform float pulse_speed = 16.0;
uniform float pulse_spacing = 14.0;

void fragment() {
	float h = UV.y;
	float row = floor(h / 0.15);
	vec2 grid = vec2(UV.x / 0.30, h / 0.15);
	vec2 cell = fract(grid + vec2(mod(row, 2.0) * 0.5, 0.0));
	// Filtrar juntas menores que um pixel: bordas duras cintilavam na perspectiva.
	vec2 footprint = max(fwidth(grid), vec2(0.0001));
	vec2 edge = min(cell, 1.0 - cell);
	vec2 joint = 1.0 - smoothstep(vec2(0.025, 0.045) - footprint * 0.5,
		vec2(0.025, 0.045) + footprint * 0.5, edge);
	joint = mix(joint, vec2(0.05, 0.09), smoothstep(vec2(0.25), vec2(1.0), footprint));
	float grout = 1.0 - (1.0 - joint.x) * (1.0 - joint.y);
	vec3 color = mix(tile_color, grout_color, grout);
	// Sujeira de pneu e água perto do piso.
	color *= mix(0.62, 1.0, smoothstep(0.0, 0.9, h));
	float band = step(0.85, h) * step(h, 1.3);
	float stripe = step(1.38, h) * step(h, 1.48);
	color = mix(color, band_color, band);
	color = mix(color, stripe_color, stripe);
	float led = step(led_height, h) * step(h, led_height + 0.12);
	float phase = fract((UV.x * direction - TIME * pulse_speed) / pulse_spacing);
	float pulse = smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.06, 0.4, phase));
	ALBEDO = mix(color, led_color, led);
	EMISSION = led_color * led * (0.7 + 3.5 * pulse) + band_color * band * 0.18;
	ROUGHNESS = mix(0.32, 0.92, grout);
	SPECULAR = 0.6;
}
