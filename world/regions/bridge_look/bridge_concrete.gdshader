shader_type spatial;

// Concreto da ponte Harbor–Mountain. A cor de cada peça vem do vértice (tabuleiro, fáscia,
// pilar e mureta dividem uma malha só), e o acabamento é procedural em coordenada de MUNDO:
// sem textura para gerar na CPU quando a conexão monta, e nada estica nas faces longas.
// Projeção pelo eixo dominante da normal: a geometria é de faces quase ortogonais, então
// uma amostra por pixel basta (triplanar completo custaria o triplo sem diferença visível).
//
// UV.x = altura da água sob a peça (banda molhada); UV.y = marcas: 1 = juntas de dilatação,
// 2 = juntas de dilatação + placas da calçada.

// Coordenadas relativas ao meio da ponte: no renderizador Mobile, posição de mundo ~500 m no
// fragmento perdia precisão (mesmo problema registrado no mar, HarborOcean.PERIOD).
uniform vec3 origin = vec3(500.0, 0.0, -285.0);
uniform vec4 expansion_joints_x = vec4(-43.75, -12.5, 22.5, 59.375);
uniform float lift_pitch = 1.2;
uniform float panel_pitch = 2.4;
uniform float slab_pitch = 2.0;
uniform vec3 algae_tint : source_color = vec3(0.42, 0.50, 0.40);
// Chuva (0 seco, 1 encharcado), o mesmo valor que molha a cidade (Weather.get_coastal_wetness).
uniform float rain_wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying vec3 world_normal;
varying vec3 tint;
varying vec2 info;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	local_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - origin;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = srgb_to_linear(COLOR.rgb);
	info = UV;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Linha fina a cada `pitch` metros. Longe da câmera a linha fica menor que um pixel: o peso
// cai na mesma proporção em vez de serrilhar (sem mipmap, não há outro filtro aqui).
float grid_line(float coord, float pitch, float width) {
	float d = abs(fract(coord / pitch + 0.5) - 0.5) * pitch;
	float w = max(width, fwidth(coord));
	return (1.0 - smoothstep(w * 0.5, w, d)) * (width / w);
}

float joint_at(float x, float joint_x, float width) {
	float d = abs(x - joint_x);
	float w = max(width, fwidth(x));
	return (1.0 - smoothstep(w * 0.5, w, d)) * (width / w);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	bool top_face = an.y > 0.7;
	vec2 p = top_face ? local_pos.xz : (an.x > an.z ? vec2(local_pos.z, local_pos.y) : vec2(local_pos.x, local_pos.y));
	// Manchas grandes, mosqueado e grão: três escalas para não ler como plástico de perto
	// nem como cor chapada a 30 m.
	float big = noise(p * 0.17 + 13.0);
	float mid = noise(p * 0.9 + 3.0);
	float fine = noise(p * 3.6 + 7.0);
	float v = 1.0 + (big - 0.5) * 0.26 + (mid - 0.5) * 0.14 + (fine - 0.5) * 0.08;
	float wet = 0.0;
	if (!top_face) {
		// Escorrido de chuva: listras estreitas na horizontal da face, longas na vertical.
		float column = noise(vec2(p.x * 2.4, p.y * 0.10 + 41.0));
		float fade = noise(vec2(p.x * 0.6 + 9.0, p.y * 0.55));
		v -= smoothstep(0.55, 0.85, column) * (0.35 + 0.65 * fade) * 0.26;
		// Juntas de concretagem: camadas horizontais e painéis de fôrma.
		v -= grid_line(p.y, lift_pitch, 0.03) * 0.14;
		v -= grid_line(p.x, panel_pitch, 0.025) * 0.07;
		// Linha d'água: faixa escura e esverdeada onde a maré molha, sujeira acima dela.
		float water = info.x;
		wet = 1.0 - smoothstep(water + 0.2, water + 1.1, local_pos.y);
		v -= (1.0 - smoothstep(water + 1.1, water + 3.2, local_pos.y)) * 0.10;
	} else if (info.y > 1.5) {
		// Placas da calçada da ponte.
		v -= grid_line(local_pos.x, slab_pitch, 0.03) * 0.16;
	}
	if (n.y < -0.7) v *= 0.72; // fundo do tabuleiro e das vigas: nunca recebe céu aberto.
	if (info.y > 0.5) {
		float x = local_pos.x;
		float gap = joint_at(x, expansion_joints_x.x, 0.06) + joint_at(x, expansion_joints_x.y, 0.06)
			+ joint_at(x, expansion_joints_x.z, 0.06) + joint_at(x, expansion_joints_x.w, 0.06);
		v -= clamp(gap, 0.0, 1.0) * 0.55;
	}
	vec3 color = tint * clamp(v, 0.35, 1.2);
	// Concreto molhado escurece e fica liso; o tabuleiro empoça mais que as faces verticais.
	float rain = rain_wetness * (top_face ? 1.0 : 0.7) * (n.y < -0.7 ? 0.0 : 1.0);
	color *= 1.0 - rain * 0.32;
	ALBEDO = mix(color, color * algae_tint, wet * 0.85);
	ROUGHNESS = mix(mix(0.93 - (fine - 0.5) * 0.08, 0.55, wet), 0.32, rain);
	SPECULAR = 0.35;
}
