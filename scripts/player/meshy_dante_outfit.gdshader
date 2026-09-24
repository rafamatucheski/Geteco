shader_type spatial;
// Traje sobre a textura assada do Dante Meshy. A máscara (R = região, G = zona
// do corpo) diz o que é jaqueta, camisa, calça etc.; a cor nova é multiplicada
// pela luminância local relativa à média da região, conservando dobras e sombras
// pintadas pelo Meshy. region_pattern baixo apaga o xadrez (terno, parka).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D region_tex : hint_default_black, filter_nearest, repeat_disable;

uniform bool recolor = false;
uniform vec4 region_tint[7];
uniform float region_pattern[7];
uniform float region_mean[7];
uniform vec4 zone_color[7];
uniform int zone_mask[7];
uniform int print_style = 0;
uniform int print_mask = 0;
uniform vec4 print_a : source_color = vec4(1.0);
uniform vec4 print_b : source_color = vec4(1.0);
uniform float print_scale = 30.0;
uniform float hit_flash = 0.0;
uniform vec3 shared_ambient_compensation = vec3(0.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 color = base;
	vec4 orm = texture(orm_tex, UV);
	float roughness = orm.g;
	float metallic = orm.b;
	if (recolor) {
		vec4 code = texture(region_tex, UV);
		int region = clamp(int(round(code.r * 255.0 / 32.0)), 0, 6);
		int zone = clamp(int(round(code.g * 255.0 / 32.0)), 0, 6);
		float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
		float ratio = lum / max(region_mean[region], 0.004);
		vec4 tint = region_tint[region];
		float detail = clamp(mix(1.0, ratio, region_pattern[region]), 0.25, 2.5);
		vec3 dressed = tint.rgb * detail;
		if (print_style > 0 && ((print_mask >> region) & 1) == 1) {
			vec2 p = UV * print_scale;
			if (print_style == 1) {
				// Estampa floral: uma flor por célula sorteada, pétalas pelo ângulo.
				vec2 cell = floor(p);
				vec2 jitter = (vec2(hash21(cell), hash21(cell + 7.1)) - 0.5) * 0.4;
				vec2 local = fract(p) - 0.5 - jitter;
				float d = length(local);
				float petals = smoothstep(0.30, 0.22, d + 0.06 * sin(atan(local.y, local.x) * 5.0));
				float present = step(0.35, hash21(cell + 3.3));
				dressed = mix(dressed, print_a.rgb * detail, petals * present);
				dressed = mix(dressed, print_b.rgb * detail, smoothstep(0.09, 0.05, d) * present);
			} else if (print_style == 2) {
				// Camuflagem: duas manchas de ruído em escalas diferentes.
				float n1 = value_noise(p) * 0.65 + value_noise(p * 2.3) * 0.35;
				float n2 = value_noise(p * 1.4 + 19.0) * 0.6 + value_noise(p * 3.1 + 5.0) * 0.4;
				dressed = mix(dressed, print_a.rgb * detail, smoothstep(0.50, 0.54, n1));
				dressed = mix(dressed, print_b.rgb * detail, smoothstep(0.56, 0.60, n2));
			}
		}
		color = mix(base, dressed, tint.a);
		vec4 zc = zone_color[zone];
		if (zc.a > 0.0 && ((zone_mask[zone] >> region) & 1) == 1) {
			float soft = clamp(mix(1.0, ratio, 0.15), 0.6, 1.4);
			color = mix(color, zc.rgb * soft, zc.a);
			// Pele e luva não herdam o metálico assado do tecido original: ele
			// escurecia e saturava a pele pintada, que saía alaranjada.
			metallic = mix(metallic, 0.0, zc.a);
			roughness = mix(roughness, 0.62, zc.a);
		}
	}
	color = mix(color, vec3(0.85, 0.08, 0.08), clamp(hit_flash, 0.0, 1.0) * 0.65);
	ALBEDO = color;
	EMISSION = color * max(shared_ambient_compensation, vec3(0.0));
	// glTF metallicRoughness: G = rugosidade, B = metálico.
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
