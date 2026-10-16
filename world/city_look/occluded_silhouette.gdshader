shader_type spatial;
// Silhueta do jogador atrás de prédios. Com a câmera mais baixa (40°) a
// fachada sul de um prédio passa a esconder a calçada de trás; em vez de
// sumir com o prédio, desenhamos o contorno do personagem por cima, só nos
// pixels em que outra coisa está na frente dele. Onde o personagem está
// visível, o fragmento não passa.
//
// Sem hint_depth_texture (16/10): basta UM material vivo que leia o depth para o
// Forward Mobile, com MSAA, passar a desenhar o jogo inteiro num framebuffer com
// resolução de depth que a pré-compilação em segundo plano nunca gera
// (RenderForwardMobile::_mesh_compile_pipelines_for_surface, Godot 4.7.2). Aí todo
// material novo na tela compilava síncrono no primeiro desenho (fonte "draw"):
// render_bracket de 106–586 ms sem span na fase 2 do release. A mesma regra agora sai
// do teste de profundidade invertido: o fragmento é empurrado para o ponto do raio em
// que um oclusor deixa de contar (entrada na caixa do alvo, ou a altura mínima do
// oclusor), e só passa onde a cena tem algo ainda mais perto da câmera.
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled, blend_mix;

// Neutro e só na borda: a versão amarela chapada acendia o teto inteiro de
// ônibus e carro como um bloco de luz atrás do prédio.
uniform vec4 tint : source_color = vec4(0.82, 0.86, 0.92, 0.55);
// Walking player only: dark fill reads on pale roofs, light rim on dark walls.
// Other users of this shader retain their existing neutral edge treatment.
uniform bool readable_actor = false;
// Folga em metros à frente do ponto de corte: evita que a própria superfície do
// alvo (empatada em profundidade) acenda a silhueta.
uniform float depth_margin = 0.05;
// Caixa do alvo ou conjunto piloto/veículo (espaço local da referência).
// A folga de profundidade não
// basta para veículo: bancos, chassi e rodas de um ônibus ficam metros atrás
// do teto e o carro inteiro acendia em rua aberta. Se o que está na frente
// cai dentro da caixa do alvo, é o próprio alvo se cobrindo, não um prédio.
uniform mat4 target_inverse = mat4(1.0);
uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(0.0);
// On foot, low street furniture keeps real depth instead of drawing bright
// shoes through a planter. Vehicle overlays retain their existing bounds.
uniform float minimum_occluder_height = -1000.0;

void fragment() {
	// Gameplay aid belongs only to the player's view, never reflected light.
	// CoastalPlanarReflections reserves render bits 16 and 17.
	if (CAMERA_VISIBLE_LAYERS == (1u << 16u) || CAMERA_VISIBLE_LAYERS == (1u << 17u)) discard;
	// Raio da câmera até o fragmento: da câmera (perspectiva) ou do plano próximo (ortográfica).
	bool orthographic = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 origin_world = (INV_VIEW_MATRIX * vec4(orthographic ? vec3(VERTEX.xy, 0.0) : vec3(0.0), 1.0)).xyz;
	vec3 fragment_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = (target_inverse * vec4(origin_world, 1.0)).xyz;
	vec3 f = (target_inverse * vec4(fragment_world, 1.0)).xyz;
	vec3 d = f - o;
	// Oclusor dentro da caixa do alvo não conta: com o fragmento dentro da caixa, isso é o
	// mesmo que exigir o oclusor antes da entrada do raio na caixa.
	float cut = 1.0;
	if (all(greaterThanEqual(f, box_min)) && all(lessThanEqual(f, box_max))) {
		vec3 safe = mix(vec3(1e-6), d, greaterThan(abs(d), vec3(1e-6)));
		vec3 t1 = (box_min - o) / safe;
		vec3 t2 = (box_max - o) / safe;
		vec3 near_t = min(t1, t2);
		cut = clamp(max(max(near_t.x, near_t.y), near_t.z), 0.0, 1.0);
	}
	// Oclusor abaixo da altura mínima (local) não conta: com a câmera acima dela, só contam
	// os pontos do raio antes de ele descer abaixo da altura. Câmera abaixo da altura com
	// fragmento abaixo dela: nada conta (como antes). Câmera abaixo e fragmento acima (não
	// acontece com a câmera do jogo): conta tudo, aproximação.
	float m = minimum_occluder_height;
	if (o.y >= m) {
		if (f.y < m) cut = min(cut, (o.y - m) / max(o.y - f.y, 1e-6));
	} else if (f.y < m) {
		cut = 0.0;
	}
	float ray_length = length(fragment_world - origin_world);
	float reach = cut * ray_length - depth_margin;
	if (reach <= 0.0) discard;
	vec3 probe = origin_world + (fragment_world - origin_world) * (reach / ray_length);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(probe, 1.0);
	DEPTH = clip.z / clip.w;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (readable_actor) {
		float edge = smoothstep(0.78, 0.96, rim);
		ALBEDO = mix(vec3(0.06, 0.08, 0.11), tint.rgb, edge);
		ALPHA = mix(0.92, 0.95, edge);
	} else {
		ALBEDO = tint.rgb;
		ALPHA = tint.a * (0.08 + 0.92 * pow(rim, 2.5));
	}
}
