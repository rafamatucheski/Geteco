shader_type spatial;
// Silhueta do jogador atrás de prédios. Com a câmera mais baixa (40°) a
// fachada sul de um prédio passa a esconder a calçada de trás; em vez de
// sumir com o prédio, desenhamos o contorno do personagem por cima, só nos
// pixels em que outra coisa está na frente dele (comparação com o depth
// buffer). Onde o personagem está visível, o fragmento é descartado.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, blend_mix;

uniform vec4 tint : source_color = vec4(0.98, 0.78, 0.24, 0.62);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Folga em unidades de depth não linear (câmera ortográfica: depth é linear
// no intervalo near..far, 180 m). 0.004 ~= 0.7 m, evita que braço na frente
// do tronco acenda a silhueta.
uniform float bias = 0.004;
// Caixa do próprio alvo (espaço local dele). A folga de profundidade não
// basta para veículo: bancos, chassi e rodas de um ônibus ficam metros atrás
// do teto e o carro inteiro acendia em rua aberta. Se o que está na frente
// cai dentro da caixa do alvo, é o próprio alvo se cobrindo, não um prédio.
uniform mat4 target_inverse = mat4(1.0);
uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(0.0);

void fragment() {
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	// Godot 4.3+ usa reverse-Z: maior = mais perto da câmera.
	if (scene_depth <= FRAGCOORD.z + bias) {
		discard;
	}
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec3 occluder = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	vec3 local = (target_inverse * vec4(occluder, 1.0)).xyz;
	if (all(greaterThanEqual(local, box_min)) && all(lessThanEqual(local, box_max))) {
		discard;
	}
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.55 + 0.45 * rim);
}
