shader_type spatial;
// Braço e palheta do limpador de para-brisa: duas tiras planas giradas em torno do pivô no
// plano do vidro. A fase integrada é compartilhada com `VehicleWindshieldRain.gdshader`.
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform float wiper_amp : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_period = 1.6;
uniform float wiper_phase = 0.0;
uniform float wiper_sweep = 1.75;
uniform float wiper_park = 0.06;
// Plano do para-brisa: z = plane.x + plane.y * (y - plane.z); plane.w = recuo para fora (m).
uniform vec4 plane = vec4(0.0, 0.6, 0.0, 0.02);
uniform vec3 plane_normal = vec3(0.0, 0.8, -0.6);

void vertex() {
	// VERTEX.x = distância ao longo do braço, VERTEX.y = lateral, COLOR.xy = pivô.
	float ph = fract(wiper_phase);
	float u = ph < 0.5 ? ph * 2.0 : 2.0 - ph * 2.0;
	float th = wiper_park + wiper_amp * u * wiper_sweep;
	vec2 dir = vec2(cos(th), sin(th));
	vec2 side = vec2(-dir.y, dir.x);
	vec2 xy = COLOR.xy + dir * VERTEX.x + side * VERTEX.y;
	float z = plane.x + plane.y * (xy.y - plane.z);
	VERTEX = vec3(xy, z) + plane_normal * plane.w;
	NORMAL = plane_normal;
}

void fragment() {
	ALBEDO = vec3(0.025);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
