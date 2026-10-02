extends RefCounted
## Desenha o visual real do fogo na janela principal durante a carga. Construir
## o PackedScene fora da árvore não exercita os passes GPU da primeira explosão.
## Só transfere a apresentação: Fire nunca entra na árvore, registra incidente
## ou executa dano. Os recursos continuam vivos no template compartilhado.
const FIRE = preload("res://gameplay/emergency/Fire.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _drawn := false

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not _covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not _current_camera(host, camera): return
	var tree := host.get_tree()
	var fire = FIRE.new()
	fire._ensure_visuals()
	fire._apply_intensity()
	var visual := Node3D.new()
	visual.name = "GroundFirePrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in fire.get_children():
		fire.remove_child(child)
		visual.add_child(child)
		if child is GPUParticles3D:
			# Produz partículas já no primeiro desenho, mesmo com FPS alto e fixed_fps=30.
			child.preprocess = 0.1
		elif child is OmniLight3D:
			child.light_energy = 1.4
	fire.free()
	var point := camera.global_position - camera.global_basis.z * 9.0
	visual.transform = host.global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, point)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	# Espera limitada: minimizar a janela não pode deixar o carregamento preso.
	# Só considera preparado quando houve desenho; headless não vale como GPU.
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not _covered_loading(host, curtain) or not _current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		visual.global_position = camera.global_position - camera.global_basis.z * 9.0
		if draws[0] >= DRAW_FRAMES:
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	# Não deixa um queue_free atravessar a retirada da cortina no chamador.
	if is_instance_valid(visual): visual.free()

static func _current_camera(host: Variant, camera: Variant) -> bool:
	return is_instance_valid(host) and host.is_inside_tree() and is_instance_valid(camera) \
		and camera.is_inside_tree() and not camera.is_queued_for_deletion() \
		and host.get_viewport().get_camera_3d() == camera

static func _covered_loading(host: Variant, curtain: Variant) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion(): return false
	if not is_instance_valid(curtain) or not curtain.is_inside_tree() or curtain.is_queued_for_deletion() or not curtain.visible: return false
	var controller: Variant = host.get("production")
	if not is_instance_valid(controller) or controller.is_queued_for_deletion() or controller.get("ready_for_play") == true: return false
	if not bool(curtain.get("stage_only")):
		var cover := curtain.get("_root") as Control
		return is_instance_valid(cover) and cover.is_visible_in_tree() and cover.modulate.a >= 1.0
	# No menu a StartupCurtain só registra etapas; a cobertura real são as nuvens.
	var preview: Variant = host.get_meta("menu_preview", null)
	if not is_instance_valid(preview) or preview.get("loading") != true or preview.get("is_ready") == true: return false
	var clouds := preview.get("clouds") as CanvasLayer
	var material := preview.get("material") as ShaderMaterial
	return is_instance_valid(clouds) and clouds.visible and is_instance_valid(material) \
		and float(material.get_shader_parameter("coverage")) >= 1.0 \
		and float(material.get_shader_parameter("descent")) <= 0.0
