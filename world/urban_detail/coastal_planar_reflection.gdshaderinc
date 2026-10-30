// One shared scene capture, sampled in world space. No scrolling noise or
// screen-space dependence: reflection remains anchored while the camera moves.
uniform sampler2D reflection_texture : filter_linear_mipmap, repeat_disable;
uniform mat4 reflection_projection;
uniform bool reflection_enabled = false;
uniform bool reflection_flip_y = true;
uniform float reflection_strength : hint_range(0.0,1.0) = 1.0;
uniform vec2 reflection_texel_size = vec2(0.0015625,0.00277778);

float coastal_film_hash(vec2 p) {
	vec3 q = fract(vec3(p.x,p.y,p.x)*0.1031);
	q += dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}

float coastal_film_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	// C2-continuous interpolation avoids grid lines and hard puddle contours.
	f = f*f*f*(f*(f*6.0-15.0)+10.0);
	return mix(mix(coastal_film_hash(cell),coastal_film_hash(cell+vec2(1.0,0.0)),f.x),
		mix(coastal_film_hash(cell+vec2(0.0,1.0)),coastal_film_hash(cell+vec2(1.0,1.0)),f.x),f.y);
}

float coastal_wet_film(vec2 ground_position) {
	// A film forms in broad shallow basins, not over the entire wet road.
	// Rotate the main field away from street/chunk axes; the smaller field
	// varies the shoreline over metres, never at noisy aggregate scale.
	vec2 rotated = vec2(dot(ground_position,vec2(0.8,0.6)),dot(ground_position,vec2(-0.6,0.8)));
	float broad = coastal_film_noise(rotated*0.14+vec2(17.3,8.1));
	float local = coastal_film_noise(ground_position*0.37+vec2(-3.7,23.9));
	// About a quarter of the field receives any planar reflection. Exactly
	// zero outside, with a continuous soft ramp instead of an outlined decal.
	return smoothstep(0.64,0.82,broad*0.82+local*0.18);
}

vec3 coastal_asphalt_aggregate(vec3 sampled) {
	// Reuse the shared four-metre texture and its mipmaps: centimetre-scale
	// aggregate becomes legible without per-pixel procedural grain or shimmer.
	float luminance = dot(sampled,vec3(0.2126,0.7152,0.0722));
	float grain_contrast = clamp(1.0+(luminance/0.0225-1.0)*1.30,0.78,1.24);
	return mix(vec3(luminance),sampled,0.45)*1.55*grain_contrast;
}

// Desgaste seco do asfalto urbano (HarborRoadWear, uniform urban_wear; 0 = asfalto anterior).
// O agregado é um ladrilho de 4 m igual no porto inteiro: de cima a rua lia como tapete novo.
// Três campos de ruído em metros de mundo, sem derivada nem textura nova: oxidado claro e
// cinza-quente em manchas de ~45 m, recapeado mais escuro em ~12 m e sujeira de metro em metro.
// Remendo, buraco e rachadura de verdade são decalques (atlas), não este ruído.
vec3 coastal_urban_wear(vec3 base, vec2 g, out float rough_scale) {
	vec2 r = vec2(dot(g,vec2(0.8,-0.6)),dot(g,vec2(0.6,0.8)));
	float broad = coastal_film_noise(r*0.022+vec2(31.7,-12.9));
	float mid = coastal_film_noise(g*0.083+vec2(-7.3,19.1));
	float fine = coastal_film_noise(r*0.55+vec2(4.9,8.3));
	float lum = dot(base,vec3(0.2126,0.7152,0.0722));
	float oxid = smoothstep(0.40,0.84,broad*0.65+mid*0.35);
	vec3 aged = mix(base,vec3(lum)*vec3(1.05,1.0,0.93),0.65)*1.42;
	vec3 color = mix(base,aged,oxid*0.85);
	float fresh = smoothstep(0.60,0.74,mid*0.7+(1.0-broad)*0.3);
	color *= 1.0-fresh*0.22;
	color *= 0.91+fine*0.18;
	// Asfalto novo é mais liso; o oxidado, mais áspero.
	rough_scale = 1.0-fresh*0.06+oxid*0.02;
	return color;
}

vec4 coastal_reflection_tap(vec2 uv) {
	vec4 captured = texture(reflection_texture,uv);
	// Filter covered radiance, not arbitrary RGB outside the geometry alpha.
	return vec4(captured.rgb*captured.a,captured.a);
}

vec4 coastal_planar_sample(vec3 world_position, vec2 distortion, float blur_radius) {
	if (!reflection_enabled || reflection_strength <= 0.0) return vec4(0.0);
	vec4 clip = reflection_projection * vec4(world_position,1.0);
	if (clip.w <= 0.0001) return vec4(0.0);
	vec2 uv = clip.xy / clip.w * 0.5 + vec2(0.5);
	if (reflection_flip_y) uv.y = 1.0 - uv.y;
	vec2 edge_distance = min(uv,vec2(1.0)-uv);
	float coverage = smoothstep(0.0,0.025,min(edge_distance.x,edge_distance.y));
	if (coverage <= 0.0) return vec4(0.0);
	vec2 texel = max(reflection_texel_size,vec2(0.00001));
	vec2 step_uv = texel * clamp(blur_radius,0.65,1.10);
	uv = clamp(uv+distortion*texel,step_uv+texel,vec2(1.0)-step_uv-texel);
	// Contiguous 3x3 Gaussian: separated cross taps made repeated outlines
	// around thin lamp poles and cornices. Weights sum to one, including alpha.
	vec4 reflected = coastal_reflection_tap(uv) * 0.25;
	reflected += coastal_reflection_tap(uv+vec2(step_uv.x,0.0)) * 0.125;
	reflected += coastal_reflection_tap(uv-vec2(step_uv.x,0.0)) * 0.125;
	reflected += coastal_reflection_tap(uv+vec2(0.0,step_uv.y)) * 0.125;
	reflected += coastal_reflection_tap(uv-vec2(0.0,step_uv.y)) * 0.125;
	reflected += coastal_reflection_tap(uv+step_uv) * 0.0625;
	reflected += coastal_reflection_tap(uv-step_uv) * 0.0625;
	reflected += coastal_reflection_tap(uv+vec2(step_uv.x,-step_uv.y)) * 0.0625;
	reflected += coastal_reflection_tap(uv+vec2(-step_uv.x,step_uv.y)) * 0.0625;
	// The transparent HDR capture contains geometry, not a second sky/fog.
	// Empty pixels retain ordinary pavement instead of reflecting a black card.
	vec3 radiance = reflected.rgb/max(reflected.a,0.0001);
	return vec4(radiance,coverage*reflection_strength*reflected.a);
}
