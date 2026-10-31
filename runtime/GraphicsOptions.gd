extends RefCounted
## Shared graphics policy. Presets never change population, physics or authored lighting colours.
const DETAIL_GROUP := &"graphics_optional_detail"
const KEYS := ["aa_mode", "msaa", "upscale_mode", "render_scale", "shadow_quality", "shadow_distance", "anisotropy", "reflection_quality", "detail_quality", "ssao", "volumetric_fog", "glow", "glow_strength"]
const PRESETS := [
	{"aa_mode":1,"msaa":0,"upscale_mode":1,"render_scale":.75,"shadow_quality":0,"shadow_distance":0,"anisotropy":2,"reflection_quality":0,"detail_quality":0,"ssao":false,"volumetric_fog":false,"glow":true,"glow_strength":.6},
	{"aa_mode":0,"msaa":1,"upscale_mode":1,"render_scale":1.0,"shadow_quality":1,"shadow_distance":1,"anisotropy":3,"reflection_quality":1,"detail_quality":1,"ssao":false,"volumetric_fog":false,"glow":true,"glow_strength":.75},
	{"aa_mode":0,"msaa":2,"upscale_mode":1,"render_scale":1.0,"shadow_quality":2,"shadow_distance":2,"anisotropy":4,"reflection_quality":2,"detail_quality":2,"ssao":true,"volumetric_fog":false,"glow":true,"glow_strength":.75},
]

static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

static func modern_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() in ["forward_plus","mobile"]

static func apply_viewport(view: Viewport, settings: Node) -> void:
	# TAA/FSR2 e SSR ligam um grupo de shaders avançados de todo o processo no Forward+.
	# Medido na RTX 4060: ~5 GiB a mais de memória privada, retidos mesmo depois de desligar.
	# Preferências antigas e chamadas diretas não podem ligar esse grupo de novo.
	var mode: int = clampi(settings.aa_mode,0,2)
	if not modern_renderer(): mode = 0
	var target_msaa := mini(settings.msaa, 2) as Viewport.MSAA if mode == 0 else Viewport.MSAA_DISABLED
	var target_screen_aa := Viewport.SCREEN_SPACE_AA_DISABLED
	var target_scale_mode := Viewport.SCALING_3D_MODE_BILINEAR
	if mode == 1: target_screen_aa = Viewport.SCREEN_SPACE_AA_FXAA
	elif mode == 2: target_screen_aa = Viewport.SCREEN_SPACE_AA_SMAA
	if modern_renderer() and settings.upscale_mode != 0 and settings.render_scale < .999:
		target_scale_mode = Viewport.SCALING_3D_MODE_FSR
	# Não reconstrói os alvos de AA em preferências sem relação (áudio, brilho etc.).
	if view.use_taa: view.use_taa = false
	# Leave FSR2 before restoring MSAA; their render targets cannot coexist.
	if view.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and target_scale_mode != view.scaling_3d_mode:
		view.scaling_3d_mode = target_scale_mode
	if view.msaa_3d != target_msaa: view.msaa_3d = target_msaa
	if view.scaling_3d_mode != target_scale_mode: view.scaling_3d_mode = target_scale_mode
	if view.screen_space_aa != target_screen_aa: view.screen_space_aa = target_screen_aa
	if not is_equal_approx(view.scaling_3d_scale,settings.render_scale): view.scaling_3d_scale = settings.render_scale
	view.anisotropic_filtering_level = clampi(settings.anisotropy,0,4) as Viewport.AnisotropicFiltering
	view.mesh_lod_threshold = [2.0,1.0,.75][clampi(settings.detail_quality,0,2)]

static func tag_detail(node: GeometryInstance3D) -> void:
	if node.visibility_range_end <= 0.0: return
	if not node.has_meta("graphics_base_range"):
		node.set_meta("graphics_base_range",node.visibility_range_end)
		node.set_meta("graphics_base_margin",node.visibility_range_end_margin)
	node.add_to_group(DETAIL_GROUP)
	if node.is_inside_tree():
		var settings := node.get_node_or_null("/root/V2Settings")
		if settings != null: apply_detail(node,settings.detail_quality)

static func apply_detail(node: Node, quality: int) -> void:
	if not is_instance_valid(node) or not node is GeometryInstance3D or not node.has_meta("graphics_base_range"): return
	node.visibility_range_end = float(node.get_meta("graphics_base_range")) * [.8,1.0,1.4][clampi(quality,0,2)]
	node.visibility_range_end_margin = float(node.get_meta("graphics_base_margin"))
