shader_type canvas_item;
// Ilustração parada ganha vida sem vídeo: câmera lenta (Ken Burns), parallax do mouse,
// água que ondula, luzes que respiram e chuva. Máscaras saem da própria cor da arte:
// água = pixel escuro e azulado; luz = pixel claro e quente. Usado no menu principal e
// nas telas de carregamento (arte noturna do porto, da serra e da oficina).

uniform float zoom = 1.07;
uniform vec2 parallax = vec2(0.0);
uniform float drift = 1.0;
uniform float water = 1.0;
uniform float lights = 1.0;
uniform float rain = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// Câmera: deriva lenta em Lissajous (~3 min por volta) mais o parallax do mouse.
	vec2 pan = vec2(sin(TIME * 0.035), cos(TIME * 0.026)) * 0.011 * drift + parallax;
	float z = zoom + 0.015 * sin(TIME * 0.05) * drift;
	vec2 uv = (UV - 0.5) / z + 0.5 + pan;

	vec3 base = texture(TEXTURE, uv).rgb;
	float lum = luminance(base);
	// Água: escura e com azul acima do vermelho.
	float water_mask = smoothstep(0.03, 0.10, base.b - base.r) * (1.0 - smoothstep(0.16, 0.34, lum)) * water;
	vec2 ripple = vec2(
		sin(uv.y * 170.0 + TIME * 1.7) + sin(uv.y * 63.0 - TIME * 1.1) * 0.6,
		cos(uv.x * 120.0 + TIME * 1.3) * 0.4) * 0.0011 * water_mask;
	vec3 color = texture(TEXTURE, uv + ripple).rgb;
	// Reflexos claros sobre a água cintilam.
	float sparkle = step(0.93, hash(floor((uv + vec2(TIME * 0.004, 0.0)) * vec2(420.0, 900.0)) + floor(TIME * 6.0)));
	color += vec3(0.55, 0.62, 0.7) * sparkle * water_mask * smoothstep(0.08, 0.2, luminance(color)) * 0.35;

	// Luzes quentes respiram, cada poste num ritmo.
	float light_mask = smoothstep(0.5, 0.8, luminance(color)) * smoothstep(0.02, 0.12, color.r - color.b) * lights;
	float phase = hash(floor(uv * 36.0)) * 6.2831;
	color *= 1.0 + light_mask * (0.10 * sin(TIME * 1.8 + phase) + 0.04 * sin(TIME * 7.3 + phase * 2.0));

	// Chuva: riscos finos inclinados, duas camadas com velocidades diferentes.
	vec2 rain_uv = UV * vec2(1.0, 0.55) + vec2(UV.y * 0.18, 0.0);
	float streaks = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 90.0 : 150.0;
		float speed = layer == 0 ? 1.7 : 2.6;
		vec2 cell_uv = rain_uv * vec2(scale, scale * 0.12) + vec2(0.0, TIME * speed * scale * 0.12);
		vec2 cell = floor(cell_uv);
		vec2 local = fract(cell_uv);
		float seed = hash(cell + float(layer) * 17.0);
		float drop = step(0.82, seed) * smoothstep(0.08, 0.0, abs(local.x - seed)) * smoothstep(0.0, 0.25, local.y) * smoothstep(1.0, 0.55, local.y);
		streaks += drop * (layer == 0 ? 0.55 : 0.3);
	}
	color += vec3(0.62, 0.72, 0.85) * streaks * 0.16 * rain;

	COLOR = vec4(color, 1.0);
}
