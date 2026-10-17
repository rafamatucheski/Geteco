shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.17, 0.28, 0.24, 1.0);
uniform int surface_kind = 0; // painted boards, timber, folded metal, stone
varying vec3 local_point;
varying vec3 local_normal;

float grain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);
}

void vertex() {
	local_point = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(local_normal);
	vec2 p = n.y > 0.6 ? local_point.xz : (n.x > 0.6 ? local_point.zy : local_point.xy);
	float lightness = 1.0;
	float rough = 0.86;
	if (surface_kind < 2) {
		float board = floor(p.x / 0.145);
		float seam = abs(fract(p.x / 0.145) - 0.5);
		float edge = smoothstep(0.465, 0.49, seam);
		float fibers = sin(p.x * 570.0 + sin(p.y * 8.0 + board) * 2.1);
		float long_grain = sin(p.x * 145.0 + sin(p.y * 3.1) * 1.7);
		lightness = 0.92 + grain_hash(vec2(board, 4.0)) * 0.12;
		lightness += fibers * 0.025 + long_grain * 0.035;
		lightness *= 1.0 - edge * 0.48;
		if (surface_kind == 0) {
			float scuff = smoothstep(0.8, 0.99, sin(p.y * 25.0 + board * 3.7));
			lightness += edge * scuff * 0.13;
		}
	} else if (surface_kind == 2) {
		float rib = pow(max(0.0, cos(p.x * 6.283185 / 0.16)), 12.0);
		lightness = 0.88 + rib * 0.25;
		rough = 0.61 + (1.0 - rib) * 0.16;
	} else {
		float fleck = grain_hash(floor(p * 220.0));
		lightness = 0.89 + fleck * 0.16 + sin(p.x * 15.0 + p.y * 7.0) * 0.025;
		rough = 0.76;
	}
	ALBEDO = base_color.rgb * lightness;
	ROUGHNESS = rough;
}
