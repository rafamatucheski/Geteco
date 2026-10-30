extends RefCounted
## Carrega e desenha sob a cortina todas as texturas do PaintedFacadeKit (paredes,
## telhados, portas e máscaras de luz noturna dos 9 estilos). Sem isto cada estilo
## (todos os de assets/facades, inclusive telhado sem neve) lia os JPG do pacote e subia para a GPU no primeiro sobrado que aparecia na
## rua: no A/B de 15/10 o kit teve mais quadros >100 ms (8 e 5 contra 5 e 3).
## Mesma receita de BridgeLookPrewarm: caixas temporárias na frente da câmera por
## alguns quadros; os materiais ficam retidos no cache estático do kit.
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const PARTS := ["front", "back", "side", "roof", "door_front", "door_front_inside", "door_back", "door_back_inside"]
## Peças do prédio alto (térreo, andar, topo de cada lado e as máscaras de luz):
## só entram com o piloto ligado (padrão; GETECO_PAINTED_TALL=0 desliga), senão
## seriam ~18 texturas carregadas a troco de nada.
const TALL_PARTS := ["front_ground", "front_floor", "front_top", "back_ground", "back_floor", "back_top",
	"side_ground", "side_floor", "side_top"]
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _done := false
static var last_summary: Dictionary = {}

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or not PaintedFacadeKit.enabled() or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var materials: Array = []
	for style in PaintedFacadeKit.all_styles():
		PaintedFacadeKit.style_data(style)
		for part in PARTS + ["roof_clear"] + (TALL_PARTS if preload("res://world/urban_detail/PaintedTallBuildings.gd").enabled() else []):
			if ResourceLoader.exists(PaintedFacadeKit.ROOT + style + "/" + part + ".jpg"):
				materials.append(PaintedFacadeKit.material(style, part))
	materials.append(PaintedFacadeKit._corridor_material())
	# Beira de estrada do deserto: compõe os quatro lugares (malha por material) e desenha o atlas
	# das placas e as cópias de pintura das carcaças aqui, não na primeira visita a cada lugar.
	materials.append_array(preload("res://runtime/desert/roadside/RoadsideBuild.gd").prewarm())
	# Atlas de desgaste da rua do Harbor (adesivo, cartaz, ferrugem): poste de luz, de energia e placa.
	materials.append_array(preload("res://world/city_look/HarborStreetWear.gd").prewarm())
	# Recorte do trem na frente do prédio ocupado (HarborBuildingMovingSightline):
	# o ShaderMaterial nasce ao entrar no prédio, sem cortina, e o shader só era
	# compilado quando o trem aparecia na tela com o jogador lá dentro.
	var clip := ShaderMaterial.new()
	clip.shader = preload("res://world/places/harbor_buildings/HarborBuildingMovingSightline.gdshader")
	materials.append(clip)
	var visual := Node3D.new()
	visual.name = "PaintedFacadePrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * .4
	var columns := 9
	for index in materials.size():
		var part := MeshInstance3D.new()
		part.mesh = box
		part.material_override = materials[index]
		part.position = Vector3((index % columns - (columns - 1) * .5) * .5, (floori(float(index) / columns) - 4) * .5, 0)
		visual.add_child(part)
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
	print("Fachadas pintadas preparadas: ", JSON.stringify(last_summary))
