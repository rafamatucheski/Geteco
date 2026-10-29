shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
// Rajada do clima engrossa a areia do vento (DesertAmbientLife); 1.0 é o desenho antigo.
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz),INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz),INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p=UV*2.0-1.0;
	float feather=1.0-smoothstep(0.22,1.0,dot(p,p));
	ALBEDO=COLOR.rgb;
	ROUGHNESS=1.0;
	ALPHA=COLOR.a*feather*strength;
}
