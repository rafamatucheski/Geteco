shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Corpo dos civis. A malha é compartilhada por todos os pedestres com o mesmo
// corte de roupa; a cor de cada um vem de `instance uniform`, então pessoas
// diferentes continuam no mesmo material e na mesma malha (sem malha por
// indivíduo, sem material por cor).
// Vértice: COLOR.r = slot da peça (0..15), COLOR.g = oclusão assada.
instance uniform vec4 skin_color : source_color = vec4(0.78, 0.57, 0.45, 1.0);
instance uniform vec4 hair_color : source_color = vec4(0.19, 0.15, 0.13, 1.0);
instance uniform vec4 top_color : source_color = vec4(0.26, 0.42, 0.44, 1.0);
instance uniform vec4 inner_color : source_color = vec4(0.88, 0.87, 0.83, 1.0);
instance uniform vec4 bottom_color : source_color = vec4(0.20, 0.27, 0.36, 1.0);
instance uniform vec4 shoe_color : source_color = vec4(0.15, 0.14, 0.14, 1.0);
instance uniform vec4 accent_color : source_color = vec4(0.55, 0.22, 0.18, 1.0);

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	int slot = int(COLOR.r * 16.0);
	vec3 albedo = top_color.rgb;
	float rough = 0.86;
	float metal = 0.0;
	float weave = 0.0;
	if (slot == 0) { albedo = skin_color.rgb; rough = 0.58; }
	else if (slot == 1) { albedo = hair_color.rgb; rough = 0.62; }
	else if (slot == 2) { albedo = top_color.rgb; weave = 1.0; }
	else if (slot == 3) { albedo = inner_color.rgb; weave = 1.0; }
	else if (slot == 4) { albedo = bottom_color.rgb; rough = 0.9; weave = 1.6; }
	else if (slot == 5) { albedo = shoe_color.rgb; rough = 0.48; }
	else if (slot == 6) { albedo = accent_color.rgb; rough = 0.7; weave = 0.6; }
	else if (slot == 7) { albedo = vec3(0.86, 0.85, 0.82); rough = 0.75; }
	else if (slot == 8) { albedo = vec3(0.045, 0.04, 0.04); rough = 0.25; }
	else if (slot == 9) { albedo = skin_color.rgb * vec3(0.80, 0.56, 0.54); rough = 0.45; }
	else if (slot == 10) { albedo = hair_color.rgb * 0.72; rough = 0.8; }
	else if (slot == 11) { albedo = vec3(0.04, 0.045, 0.05); rough = 0.12; metal = 0.4; }
	else if (slot == 12) { albedo = vec3(0.62, 0.60, 0.55); rough = 0.35; metal = 0.7; }
	// Trama leve: quebra o plástico liso do tecido sem textura nem UV. Em
	// jeans (slot 4) as diagonais são mais marcadas, como sarja.
	if (weave > 0.0) {
		float diagonal = sin((local_position.x + local_position.y + local_position.z) * 420.0);
		float fibre = fract(sin(dot(floor(local_position * 160.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		albedo *= 1.0 + weave * (diagonal * 0.018 + (fibre - 0.5) * 0.035);
	}
	ALBEDO = albedo * COLOR.g;
	ROUGHNESS = rough;
	METALLIC = metal;
	// Pele e cabelo recebem um pouco de luz de contorno: sem isso a cabeça
	// some contra o asfalto na câmera de 45 graus.
	if (slot <= 1) {
		RIM = 0.25;
		RIM_TINT = 0.4;
	}
}
