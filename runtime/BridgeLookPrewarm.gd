extends RefCounted
## Desenha sob a cortina os materiais do acabamento da ponte cidade–serra (shader de concreto procedural e aço
## com cor no vértice). Sem isto o shader compilava no primeiro desenho da ponte: picos de 0,35–0,95 s no HUD
## das capturas de 14/10, contra 25–60 ms sem o acabamento. Mesma receita de VehicleMaterialVariantPrewarm:
## caixas temporárias na frente da câmera por alguns quadros, com sombra, e o material fica retido.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const UNIFIED_BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const NORTH_SCENERY := preload("res://world/north_gateway/NorthGatewayScenery.gd")
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _done := false
static var last_summary: Dictionary = {}

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or (not UNIFIED_BRIDGE.enabled() and not CONNECTION.look_enabled) or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var materials: Array
	if UNIFIED_BRIDGE.enabled():
		# A geração procedural também fica sob a cortina; o streaming só instancia
		# recursos prontos, inclusive os materiais do túnel e das luminárias.
		CONNECTION.prewarm_unified_geometry()
		NORTH_SCENERY.prewarm_geometry()
		materials = UNIFIED_BRIDGE.materials()
		for material in CONNECTION.unified_geometry_materials():
			if not materials.has(material): materials.append(material)
		for material in NORTH_SCENERY.geometry_materials():
			if not materials.has(material): materials.append(material)
	else:
		CONNECTION._look_concrete()
		CONNECTION._look_steel()
		materials = CONNECTION._look_materials.values()
	var visual := Node3D.new()
	visual.name = "BridgeLookPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * .5
	for index in materials.size():
		var part := MeshInstance3D.new()
		part.mesh = box
		part.material_override = materials[index]
		part.position = Vector3((index - (materials.size() - 1) * .5) * .7, 0, 0)
		visual.add_child(part)
		# O canteiro usa instâncias: sua variante de shader também deve desenhar
		# durante o carregamento, antes de a obra aparecer no mundo.
		var instanced := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = box
		instances.instance_count = 1
		instances.set_instance_transform(0, Transform3D.IDENTITY)
		instanced.multimesh = instances
		instanced.material_override = materials[index]
		instanced.position = part.position + Vector3(0, .65, 0)
		visual.add_child(instanced)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(visual, host.get_tree())
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
	last_summary = {"materials": materials.size(), "completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Materiais da ponte preparados: ", JSON.stringify(last_summary))
