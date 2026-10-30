shader_type spatial;
// Traçado da bala (gameplay/fx/TracerFx.gd): um MultiMesh desenha todas as balas e todos os rastros
// num passe só. Aditivo, sem luz, sem sombra e sem gravar profundidade: a ordem de desenho entre
// instâncias não importa e nada depende da lista alfa. Névoa desligada de propósito: em material
// aditivo a névoa SOMA a cor dela e a fita inteira aparecia como uma faixa cinza.
//
// O movimento sai do relógio `clock` e dos dados gravados no disparo; a CPU não mexe na instância
// enquanto a bala voa. Dados por instância (colunas da transformação, cor e custom):
//   origem          = boca do cano
//   coluna 2 (z)    = velocidade mostrada (direção * m/s)
//   coluna 0 (x)    = (início no relógio, distância até o fim em m, cauda máxima em m)
//   coluna 1 (y)    = (meia-largura do halo em m, calor do núcleo 0..1, semente)
//   COLOR           = cor linear da arma/munição, a = brilho
//   INSTANCE_CUSTOM = (modo 0 bala / 1 rastro, zunido 0/1, núcleo [bala] ou vida após chegar [rastro],
//                      comprimento máximo do rastro em m)
// A fita do MultiMesh traz só UV: x = -1..1 através; y = -1..0 tampa à frente da cabeça (medida na
// largura), 0..1 da cabeça à ponta da cauda.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float clock = 0.0;
// Meia-largura na tela em pixels. Abaixo do mínimo a fita alarga e o brilho cai na mesma proporção
// (energia conservada): de longe o traço continua visível sem virar uma linha grossa de laser.
uniform float min_pixels = 1.2;
// Teto perto da câmera: a bala que passa rente não cobre a tela.
uniform float max_pixels = 14.0;

varying vec2 v_shape;
varying vec4 v_tint;
// x = núcleo (fração da meia-largura), y = calor, z = modo, w = comprimento visível em m
varying vec4 v_look;
varying float v_seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 velocity = MODEL_MATRIX[2].xyz;
	vec3 timing = MODEL_MATRIX[0].xyz;
	vec3 look = MODEL_MATRIX[1].xyz;
	vec4 extra = INSTANCE_CUSTOM;
	float speed = length(velocity);
	float energy = COLOR.a;
	bool alive = energy > 0.0 && speed > 0.0001;
	vec3 dir = alive ? velocity / speed : vec3(0.0, 0.0, -1.0);
	float t = max(clock - timing.x, 0.0);
	float limit = max(timing.y, 0.0);
	float run = speed * t;
	float half_width = look.x;
	bool trail = extra.x > 0.5;
	float front_d;
	float back_d;
	float near = 0.0;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	if (!trail) {
		front_d = min(run, limit);
		// "Zunido": bala que vem passando rente à câmera abre o halo e estica, como um borrão de
		// movimento; só nas balas que vêm de fora (polícia, Cobras), não no tiro do próprio jogador.
		float head_distance = distance(origin + dir * front_d, camera);
		near = extra.y * (1.0 - smoothstep(0.8, 4.5, head_distance));
		back_d = clamp(run - timing.z * (1.0 + 0.8 * near), 0.0, limit);
		half_width *= 1.0 + 0.9 * near;
	} else {
		// O rastro começa atrás da parte quente e longe da boca (a fumaça do cano é outro efeito);
		// fica no lugar depois que a bala chega, abre e apaga em `extra.z` segundos.
		front_d = clamp(run - timing.z * 0.4, 0.0, limit);
		back_d = max(front_d - extra.w, min(0.4, front_d));
		float arrive = limit / max(speed, 0.0001);
		float after = clamp((t - arrive) / max(extra.z, 0.01), 0.0, 1.0);
		energy *= (1.0 - after) * smoothstep(0.0, 0.06, t);
		half_width *= 1.0 + 0.8 * min(t / 0.5, 1.0) + 1.4 * after;
	}
	float visible_length = front_d - back_d;
	alive = alive && visible_length > 0.002 && energy > 0.0;
	// Cintilação leve, diferente por bala.
	float flicker = sin(clock * 53.0 + look.z * 41.0) * sin(clock * 23.0 + look.z * 13.0);
	vec3 front_view = (VIEW_MATRIX * vec4(origin + dir * front_d, 1.0)).xyz;
	vec3 back_view = (VIEW_MATRIX * vec4(origin + dir * back_d, 1.0)).xyz;
	// Recorta no plano perto: a cauda que passa atrás da câmera não pode inverter na projeção.
	float near_plane = -0.08;
	alive = alive && (front_view.z < near_plane || back_view.z < near_plane);
	float dz = front_view.z - back_view.z;
	dz = abs(dz) < 0.00001 ? 0.00001 : dz;
	if (front_view.z > near_plane) {
		front_view = mix(back_view, front_view, clamp((near_plane - back_view.z) / dz, 0.0, 1.0));
	} else if (back_view.z > near_plane) {
		back_view = mix(front_view, back_view, clamp((near_plane - front_view.z) / -dz, 0.0, 1.0));
	}
	float along = clamp(UV.y, 0.0, 1.0);
	float cap = max(-UV.y, 0.0);
	vec3 point_view = mix(front_view, back_view, along);
	vec4 point_clip = PROJECTION_MATRIX * vec4(point_view, 1.0);
	vec4 front_clip = PROJECTION_MATRIX * vec4(front_view, 1.0);
	vec4 back_clip = PROJECTION_MATRIX * vec4(back_view, 1.0);
	vec2 half_viewport = VIEWPORT_SIZE * 0.5;
	vec2 screen_axis = (back_clip.xy / back_clip.w - front_clip.xy / front_clip.w) * half_viewport;
	float screen_length = length(screen_axis);
	screen_axis = screen_length > 0.001 ? screen_axis / screen_length : vec2(1.0, 0.0);
	vec2 screen_side = vec2(-screen_axis.y, screen_axis.x);
	float depth = max(-point_view.z, 0.05);
	// abs(): no Vulkan a projeção do Godot vem com Y invertido ([1][1] negativo) e a largura caía no mínimo.
	float metres_per_pixel = 2.0 * depth / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	// A bala afina até a ponta da cauda; o rastro afina pouco.
	float taper = trail ? mix(1.0, 0.7, along) : mix(1.0, 0.22, pow(along, 0.75));
	float wanted = half_width * taper * (0.95 + 0.05 * flicker) / metres_per_pixel;
	float shown = clamp(wanted, min_pixels, max_pixels * (1.0 + 0.4 * near));
	float gain = clamp(wanted / shown, 0.3, 1.0);
	vec2 offset = screen_side * UV.x * shown - screen_axis * cap * shown;
	point_clip.xy += offset / half_viewport * point_clip.w;
	POSITION = alive ? point_clip : vec4(2.0, 2.0, 2.0, 1.0);
	VERTEX = point_view;
	v_shape = UV;
	v_seed = look.z;
	// Perto da lente o borrão abre e escurece (a mesma luz espalhada): sem isso virava uma lâmina branca.
	v_tint = vec4(COLOR.rgb, energy * gain * (0.9 + 0.1 * flicker) * (1.0 - 0.45 * near));
	v_look = vec4(trail ? 0.0 : extra.z * (1.0 + 0.6 * near), look.y * (1.0 - 0.3 * near), trail ? 1.0 : 0.0, visible_length);
}

void fragment() {
	float across = v_shape.x;
	float cap = max(-v_shape.y, 0.0);
	float along = clamp(v_shape.y, 0.0, 1.0);
	float radius = length(vec2(across, cap));
	float edge = clamp(1.0 - radius, 0.0, 1.0);
	vec3 tint = v_tint.rgb;
	vec3 light;
	if (v_look.z < 0.5) {
		// Núcleo quente (quase branco, puxado para a cor) e halo na cor da arma; a cabeça brilha mais
		// e a cauda apaga até a ponta. O núcleo passa do limiar do glow do CityLook (2,4 de dia).
		float core_width = max(v_look.x, 0.05);
		float core = exp(-(radius * radius) / (core_width * core_width));
		float fade = pow(1.0 - along, 1.35);
		float head = 1.0 + 1.5 * exp(-along * 16.0);
		vec3 hot = mix(tint, vec3(1.0, 0.96, 0.88), v_look.y);
		light = hot * (core * 2.4 * head * fade) + tint * (pow(edge, 2.2) * 0.55 * (0.3 + 0.7 * fade));
	} else {
		// Ar mexido: fiapos de ruído que andam devagar, apagando nas duas pontas.
		float metres = along * v_look.w;
		float wisp = value_noise(vec2(metres * 1.3 - clock * 0.8, across * 1.2 + v_seed * 7.0)) * 0.65
			+ value_noise(vec2(metres * 3.1 + v_seed * 3.0, across * 2.4 - clock * 1.3)) * 0.35;
		float ends = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.55, 1.0, along));
		light = tint * (pow(edge, 1.6) * ends * (0.25 + 0.75 * wisp));
	}
	ALBEDO = light * v_tint.a;
	ALPHA = 1.0;
}
