extends RefCounted
## Desenha sob a cortina luzes locais com sombra (omni em cubo, omni em paraboloide duplo e spot)
## e as duas variantes do chão natural (opaca e de borda).
##
## Por que: no Forward+ do 4.7 o pipeline de sombra de cada superfície só é compilado para os
## tipos de sombra local que o renderizador já viu numa cena ("feature" de pipeline: cubemap de
## omni, paraboloide duplo, spot). Nenhum pré-aquecimento criava omni/spot com sombra; a primeira
## luz assim no jogo (as do túnel da ponte na emenda ponte–serra, a lanterna, os faróis) ligava a
## feature no meio do jogo e todo material visível compilava a variante na hora. É a hipótese 1 do
## pico isolado de 220–250 ms (auditoria Godot 4.7 de 19/10, §4 e §5). Com a feature ligada
## aqui, superfícies criadas depois já nascem com essas variantes compiladas em segundo plano.
## Mesma receita de BridgeLookPrewarm: peças temporárias na frente da câmera por alguns quadros.
## GETECO_LOCAL_SHADOW_PREWARM=0 pula este passo (A/B).
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const GROUND := preload("res://world/editing/WorldGroundFactory.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var enabled := OS.get_environment("GETECO_LOCAL_SHADOW_PREWARM") != "0"
static var _done := false
static var last_summary: Dictionary = {}
## Material da variante de borda retido: sem referência viva o RenderingServer pode descartar o
## shader e a compilação feita aqui se perde.
static var _edge_ground: ShaderMaterial

static func edge_ground_material() -> ShaderMaterial:
	if _edge_ground == null:
		_edge_ground = ShaderMaterial.new()
		_edge_ground.shader = GROUND.NATURAL_EDGE_SHADER
		_edge_ground.set_shader_parameter("edge_alpha", true)
		_edge_ground.set_shader_parameter("surface_softness", .6)
	return _edge_ground

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or not enabled or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var grounds: Array[Material] = [GROUND.material("earth"), edge_ground_material()]
	var visual := Node3D.new()
	visual.name = "LocalLightShadowPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# O painel fica de frente para a câmera (FACE_Z): a câmera ortográfica olha de cima e um
	# PlaneMesh deitado no XZ local seria visto de lado, sem área nenhuma para desenhar.
	var panel := PlaneMesh.new()
	panel.size = Vector2(2.4, 2.4)
	panel.orientation = PlaneMesh.FACE_Z
	var caster := BoxMesh.new()
	caster.size = Vector3.ONE * .45
	var lights: Array[Light3D] = []
	var omni_cube := OmniLight3D.new()
	omni_cube.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	lights.append(omni_cube)
	# Variante do túnel da ponte (WorldConnection3D).
	var omni_paraboloid := OmniLight3D.new()
	omni_paraboloid.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	lights.append(omni_paraboloid)
	# Faróis, lanternas e holofotes: spot com sombra.
	lights.append(SpotLight3D.new())
	for index in lights.size():
		var cell := Node3D.new()
		cell.position = Vector3((index - (lights.size() - 1) * .5) * 2.8, 0, 0)
		visual.add_child(cell)
		var floor_part := MeshInstance3D.new()
		floor_part.mesh = panel
		floor_part.material_override = grounds[index % grounds.size()]
		cell.add_child(floor_part)
		var body := MeshInstance3D.new()
		body.mesh = caster
		body.material_override = grounds[(index + 1) % grounds.size()]
		body.position = Vector3(0, 0, .5)
		cell.add_child(body)
		var light := lights[index]
		light.shadow_enabled = true
		light.light_energy = 2.0
		light.position = Vector3(.3, .2, 1.4)
		if light is OmniLight3D: (light as OmniLight3D).omni_range = 4.0
		else:
			(light as SpotLight3D).spot_range = 4.0
			(light as SpotLight3D).spot_angle = 50.0
		cell.add_child(light)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 9.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(visual): break
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
	_done = completed
	last_summary = {"lights": lights.size(), "grounds": grounds.size(), "completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Sombras de luz local preparadas: ", JSON.stringify(last_summary))
