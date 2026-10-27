extends RefCounted
## Pipelines que a sonda (GETECO_PIPELINE_PROBE) ainda via compilar com a partida jogável nas rodadas de
## 22–25/10 (oeste, porto, sobrados; evidence/pipeline-probe dos exports perf-r3/r5/r6/r9/r13), desenhadas
## sob a cortina com a receita do ForgePrewarm:
## - silhueta de oclusão (CityLook, `material_overlay`) nos formatos de vértice de carro e no corpo do
##   jogador: 84–101 ms no oeste quando o casco do carro do jogador ganhava o overlay (`PlayerCoupe/Shell`)
##   e o 1º quadro depois da cortina compilava a do Dante;
## - mobília dos prédios do porto (HarborBuildingDressing: MultiMesh de cilindro e caixa por família de
##   material, luz com emissão, envelope sem material): 1º quadro depois da cortina no oeste, pátio da
##   delegacia norte (`harbor_building_patrol_court_north`), 2 pipelines em quadros de 32–37 ms.
## - adereços da rua sumindo com `transparency` (DestroyedFade3D nos destroços do FragileProps3D): cada material
##   × formato do adereço vai ao passe alfa e compila no desenho (`draw`). A sonda de assinatura pegou a placa da
##   3ª onda (wave3_sinal.glb) e uma esfera de material padrão, ambas com `tr1`, em quadros `draw` de 834–975 ms
##   no frio (perf-r6, perf-r9, perf-r13). Aqui cada tipo do CityPropKit é desenhado com a malha e os
##   materiais reais e transparência 0,5 (GETECO_PROP_ALPHA_PREWARM=0 tira só esta parte).
## GETECO_LATE_SURFACE_PREWARM=0 desliga.
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const FORMAT := preload("res://runtime/FormatPrewarm.gd")
const DRESSING_MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
const SILHOUETTE_SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")
const DRESSING_KINDS := ["wood", "cloth", "stone", "metal", "ceramic", "glass", "tank_glass", "paper", "light"]
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _done := false
static var _retained: Array[Resource] = []
static var last_summary: Dictionary = {}

static func enabled() -> bool:
	return OS.get_environment("GETECO_LATE_SURFACE_PREWARM") != "0"

## Formatos de lataria (posição + normal/tangente, com ou sem cor, UV e UV2), da porta e das peças de
## SurfaceTool: a silhueta vai para toda malha do carro, inclusive casco de peças soltas e acabamento.
static func _vehicle_formats() -> Array:
	var formats: Array = []
	for color in [0, FORMAT.C]:
		for uv in [0, FORMAT.UV]:
			for uv2 in [0, FORMAT.UV2]:
				formats.append(FORMAT.V | FORMAT.N | color | uv | uv2)
	for extra in FORMAT.DOOR_FORMATS + [FORMAT.V | FORMAT.N, FORMAT.V]:
		if extra not in formats: formats.append(extra)
	return formats

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or not enabled() or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var stage := Node3D.new()
	stage.name = "LateSurfacePrewarm"
	host.add_child(stage)
	var silhouette := ShaderMaterial.new()
	silhouette.shader = SILHOUETTE_SHADER
	_retained.append(silhouette)
	# Base neutra: o pipeline que falta é o do overlay; o da base já existe ou é o padrão.
	var base := StandardMaterial3D.new()
	_retained.append(base)
	var pieces := 0
	for attrs in _vehicle_formats():
		var mesh := FORMAT.mesh_for(int(attrs))
		if mesh == null: continue
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = base
		part.material_overlay = silhouette
		part.position = Vector3((pieces % 6 - 2.5) * FORMAT.SPACING, -floorf(pieces / 6.0) * FORMAT.SPACING, 0)
		stage.add_child(part)
		pieces += 1
	# Corpo do jogador (malha com esqueleto, que o triângulo não reproduz): overlay emprestado e devolvido.
	var borrowed: Array[GeometryInstance3D] = []
	var player := host.get("player") as Node3D
	if is_instance_valid(player):
		for node in player.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if geometry.material_overlay != null or not geometry.is_visible_in_tree(): continue
			if geometry is Label3D or geometry is GPUParticles3D or geometry is CPUParticles3D: continue
			geometry.material_overlay = silhouette
			borrowed.append(geometry)
	# Mobília dos prédios: uma instância de cilindro e de caixa por família, como HarborBuildingDressing._flush.
	var shapes: Array[PrimitiveMesh] = []
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .5
	cylinder.bottom_radius = .5
	cylinder.height = 1.0
	cylinder.radial_segments = 12
	shapes.append(cylinder)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	shapes.append(box)
	var column := 0
	for kind in DRESSING_KINDS:
		for shape in shapes:
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = shape
			instances.instance_count = 1
			instances.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * .2), Vector3.ZERO))
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = instances
			visual.material_override = DRESSING_MATERIALS.material(kind, Color("8a8f96"))
			visual.position = Vector3((column % 6 - 2.5) * FORMAT.SPACING, .6 + floorf(column / 6.0) * FORMAT.SPACING, 0)
			stage.add_child(visual)
			column += 1
	var props := 0
	if OS.get_environment("GETECO_PROP_ALPHA_PREWARM") != "0": props = _alpha_props(stage)
	# Envelope da mobília: caixa sem material (o jogo a cria escondida; aqui desenhada).
	var envelope := MeshInstance3D.new()
	var envelope_mesh := BoxMesh.new()
	envelope_mesh.size = Vector3.ONE * .2
	envelope.mesh = envelope_mesh
	envelope.position = Vector3(0, -1.0, 0)
	stage.add_child(envelope)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	await preload("res://runtime/HiddenCompile.gd").prepare(stage, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		if is_instance_valid(stage): stage.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 6.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(stage): break
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	for geometry in borrowed:
		if is_instance_valid(geometry) and geometry.material_overlay == silhouette: geometry.material_overlay = null
	if is_instance_valid(stage): stage.free()
	_done = completed
	last_summary = {"completed": completed, "draws": draws[0], "silhouette_formats": pieces, "player_parts": borrowed.size(), "dressing": column, "alpha_props": props, "usec": Time.get_ticks_usec() - began}
	print("Superfícies tardias preparadas: ", JSON.stringify(last_summary))

## Cada tipo do kit de adereços com a malha e os materiais do jogo, no passe alfa (transparência 0,5), e
## esfera/caixa de material padrão (peças de destroço sem material). Devolve quantas peças entraram.
static func _alpha_props(stage: Node3D) -> int:
	var kit := preload("res://world/city_look/CityPropKit.gd")
	# Só os tipos que saem do .glb com os interruptores atuais: a malha procedural de um tipo sem receita
	# sairia vazia. São as mesmas peças (e partes) que viram destroço.
	var kinds: Array = []
	if kit.blender_props_enabled: kinds.append_array(kit.BLENDER_WHOLE.keys())
	for kind in kit.WAVE3_KINDS:
		if kit.wave3_modeled(kind): kinds.append(kind)
	var placed := 0
	for kind in kinds:
		var mesh: Mesh = kit.mesh(str(kind))
		if mesh == null: continue
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.transparency = .5
		# Escala pequena: dezenas de tipos numa grade diante da câmera.
		part.scale = Vector3.ONE * .15
		part.position = Vector3((placed % 10 - 4.5) * .3, -1.4 - floorf(placed / 10.0) * .3, 0)
		stage.add_child(part)
		placed += 1
	for primitive: PrimitiveMesh in [SphereMesh.new(), BoxMesh.new()]:
		var piece := MeshInstance3D.new()
		piece.mesh = primitive
		piece.transparency = .5
		piece.scale = Vector3.ONE * .15
		piece.position = Vector3((placed % 10 - 4.5) * .3, -1.4 - floorf(placed / 10.0) * .3, 0)
		stage.add_child(piece)
		placed += 1
	return placed
