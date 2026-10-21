extends CanvasLayer
## A blitz da rodovia, oito anos antes (roteiro de diretor de 21/10, "Prólogo — A noite da operação"
## e A2-06 "Mesa de pedra — o flashback"). A mesma noite, jogável dos dois lados da porta da cabine.
##
## API (o ato 2 chama assim; nada mais é necessário):
##
##     const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
##     var scene := BLITZ.start(session, "vicente", func(skipped: bool): _back_to_fire(skipped))
##
## - `start(session, pov, on_done)` cria a cena, pendura em `root` e devolve o nó. `pov` é "dante"
##   (prólogo: sinalizar com a lanterna, andar até a cabine, algemar, preto, "Oito anos depois.") ou
##   "vicente" (flashback: dirigir o caminhão na chuva até a blitz, a porta abre, o rosto de Dante, preto).
## - `on_done` é chamado uma vez, no fim ou no pulo (Esc duas vezes). Aceita zero ou um argumento
##   (`skipped: bool`). O sinal `finished(pov, skipped)` sai junto.
## - Enquanto roda: a árvore fica pausada e o 3D do viewport principal desligado (como o filme da
##   balsa); a cena tem mundo próprio num SubViewport e consome toda a entrada (`_input` do último
##   filho de `root` vem primeiro), então quem chama não precisa travar controle nem câmera. Ao sair,
##   pausa e 3D voltam exatamente ao que eram. Quem chama não precisa estar no Harbor: nada do mundo
##   carregado é tocado.
## - `session` só é lida (pode ser null); a cena não grava save. Marcar "visto" é de quem chama
##   (o prólogo usa `Arrival.prologue_seen`).
##
## Custo: tudo é montado sob a cortina preta, uma peça por quadro (spans `prologue.blitz.*` no
## StallWorkTrace), e desenhado alguns quadros ainda coberto, para os pipelines (chuva, vidro, brilho
## do giroflex) compilarem antes do primeiro quadro visível. Os materiais próprios ficam retidos
## estaticamente: a segunda vez (o flashback do ato 2) não compila de novo. As luzes locais (halo do
## giroflex, farol do caminhão, lanterna) passam pelo LightBudget, sem sombra. Som: só chuva, motor,
## freio, porta, metal e o clique do rádio; nenhuma trilha. Falas só em legenda
## (data/campaign/prologue-blitz-dialogue.json).
const FLEET := preload("res://runtime/FleetCatalog.gd")
const TRUCK := preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const POLICE_MODEL := preload("res://gameplay/PoliceModel.gd")
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const BANK := preload("res://audio/FireflyBank.gd")
const RAIN_SHADER := preload("res://cutscenes/opening/ferry/ferry_rain.gdshader")
const RAIN_TEXTURES := preload("res://runtime/atmosphere/WeatherParticleTextures.gd")
const LINES_PATH := "res://data/campaign/prologue-blitz-dialogue.json"
const SCRIPT_PATH := "res://runtime/prologue/BlitzScene.gd"
const POVS := ["dante", "vicente"]
## Pista de mão dupla ao longo de z; o caminhão anda para -z na faixa da direita (x>0).
const LANE_X := 1.8
## Origem do caminhão parado: a frente (z local -5,6) fica a um passo dos cavaletes.
const TRUCK_STOP_Z := -4.4
const DANTE_POST := Vector3(.1, 0, -16.0)
const POLICE_SPOT := Vector3(4.9, 0, -15.5)
const TRUCK_PAINT := Color("583d35")
## Farda da patrulha: a mesma cor e as mesmas peças de PoliceModel._body_look (escalão 0).
const UNIFORM := Color(0.11, 0.15, 0.24)
## Colegas de Dante na blitz: [nome, posição, para onde olha, appearance_index fixo (não gasta o rodízio
## de PoliceAppearance.next_model)]. Bastos encostado na viatura com o rádio; Lima no cavalete com a lanterna.
const COLLEAGUES := [["Bastos", Vector3(3.75, 0, -14.9), Vector3(-1, 0, .35), 3], ["Lima", Vector3(2.9, 0, -14.3), Vector3(0, 0, 1), 6]]
const HOLD_SECONDS := 2.6
const WARM_DRAWS := 4
signal finished(pov: String, skipped: bool)

static var _retained: Array = []
static var _rain_material: ShaderMaterial
static var _lines: Dictionary = {}

var pov := "dante"
var session
var on_done := Callable()
## Testes e captura: a cena joga sozinha (sinaliza, anda, segura a algema, dirige).
var autoplay := false
## Multiplica o relógio da cena (testes curtos); 1 no jogo.
var pace := 1.0
var stage := "build"
var stage_time := 0.0
var cuff_progress := 0.0
var skipped := false
var signaled := false

var _finishing := false
var _previous_pause := false
var _previous_3d := false
var _main_viewport: Viewport
var _owns_world := false
var _container: SubViewportContainer
var _viewport: SubViewport
var _set: Node3D
var camera: Camera3D
var curtain: ColorRect
var _subtitle: Label
var _objective: Label
var _prompt: Label
var _progress: ProgressBar
var _title: Label
var _steps: Array[Callable] = []
var _step := 0
var _warm_draws := 0
var _skip_armed := 0.0

var truck: Node3D
var truck_door: Node3D
var truck_speed := 0.0
var police: Node3D
## CivilianModel (sem tipo: as propriedades do rig não existem em Node3D).
var dante
var vicente
var lantern: Node3D
var cars: Array[Node3D] = []
## PoliceModel dos colegas (calmos: sem ator, sem IA, sem colisão).
var colleagues: Array[Node3D] = []
var colleague_lantern: Node3D
var _car_speed: Array[float] = []
var _glows: Array[Sprite3D] = []
var halo: OmniLight3D
var headlight: SpotLight3D
var lantern_light: SpotLight3D
var rain: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _engine_audio: AudioStreamPlayer
var _police_audio: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _radio_click: AudioStreamPlayer

var _queue: Array = []
var _line_left := 0.0
var _queue_done := Callable()
var _beats: Dictionary = {}
var _dante_heading := PI
var _swing := 0.0
var _cam_from := Transform3D.IDENTITY

static func start(owner_session, point_of_view: String, done := Callable()) -> CanvasLayer:
	var tree := (owner_session as Node).get_tree() if owner_session is Node else Engine.get_main_loop() as SceneTree
	var scene = load(SCRIPT_PATH).new()
	scene.session = owner_session
	scene.pov = point_of_view if point_of_view in POVS else "dante"
	scene.on_done = done
	tree.root.add_child.call_deferred(scene)
	return scene

## Falas e textos do JSON, lidas uma vez.
static func lines() -> Dictionary:
	if _lines.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		if parsed is Dictionary: _lines = parsed
	return _lines

static func text(entry: Variant) -> String:
	if not entry is Dictionary: return ""
	var english := TranslationServer.get_locale().begins_with("en")
	var value := str(entry.get("en", "")) if english else ""
	return value if not value.is_empty() else str(entry.get("pt", ""))

func _ready() -> void:
	name = "BlitzScene"
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	_main_viewport = tree.root
	_previous_pause = tree.paused
	_previous_3d = _main_viewport.disable_3d
	_owns_world = true
	tree.paused = true
	# A cena tem mundo próprio; o mundo carregado não precisa desenhar escondido embaixo.
	_main_viewport.disable_3d = true
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Mesmo MSAA/escala do jogo: pipeline compilado aqui serve ao jogo e vice-versa.
	_viewport.msaa_3d = _main_viewport.msaa_3d
	_viewport.screen_space_aa = _main_viewport.screen_space_aa
	_viewport.use_taa = _main_viewport.use_taa
	_viewport.scaling_3d_mode = _main_viewport.scaling_3d_mode
	_viewport.scaling_3d_scale = _main_viewport.scaling_3d_scale
	_container.add_child(_viewport)
	_set = Node3D.new()
	_set.name = "BlitzSet"
	# Tudo aqui anda em _process (a árvore está pausada): interpolação de física só atrasaria.
	_set.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_set)
	_build_ui()
	_steps = [_build_environment, _build_road, _build_police, _build_truck, _build_cast, _build_colleagues, _build_traffic, _build_rain, _build_audio]
	stage = "build"

func _build_ui() -> void:
	var height := float(_main_viewport.get_visible_rect().size.y)
	_subtitle = _label(clampi(roundi(height * .03), 16, 34))
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.offset_top = -height * .2
	_subtitle.offset_bottom = -height * .08
	_subtitle.offset_left = 80
	_subtitle.offset_right = -80
	_objective = _label(clampi(roundi(height * .024), 14, 26))
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_objective.position = Vector2(32, 28)
	_objective.size = Vector2(900, 40)
	_prompt = _label(clampi(roundi(height * .026), 15, 28))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -height * .32
	_prompt.offset_bottom = -height * .26
	_prompt.offset_left = -360
	_prompt.offset_right = 360
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_progress.offset_top = -height * .26
	_progress.offset_bottom = -height * .26 + 8
	_progress.offset_left = -140
	_progress.offset_right = 140
	_progress.hide()
	add_child(_progress)
	curtain = ColorRect.new()
	curtain.color = Color.BLACK
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(curtain)
	# O título fica acima da cortina: aparece no preto.
	_title = _label(clampi(roundi(height * .045), 24, 52))
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.modulate.a = 0.0
	move_child(_subtitle, -1)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .95))
	add_child(label)
	return label

# --- Montagem (uma peça por quadro, sob a cortina) -----------------------------------------------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Fundo e névoa na mesma cor: o fim da estrada some na noite, sem borda.
	environment.background_color = Color("0b1220")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("6f86a3")
	environment.ambient_light_energy = .32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("0b1220")
	environment.fog_density = .03
	environment.fog_depth_begin = 18.0
	environment.fog_depth_end = 120.0
	environment.glow_enabled = true
	environment.glow_intensity = .7
	environment.glow_bloom = .05
	var world := WorldEnvironment.new()
	world.environment = environment
	_set.add_child(world)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("8fa7c6")
	moon.light_energy = .22
	moon.rotation_degrees = Vector3(-52, 28, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 45.0
	_set.add_child(moon)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = .05
	camera.far = 260.0
	_set.add_child(camera)
	camera.current = true

func _material(key: String, color: Color, roughness: float, specular := .5, emission := Color.BLACK) -> StandardMaterial3D:
	for held in _retained:
		if held is StandardMaterial3D and held.resource_name == key: return held
	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = specular
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	if color.a < 1.0: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_retained.append(material)
	return material

func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = center
	parent.add_child(node)
	return node

func _strip(parent: Node3D, mesh_size: Vector3, material: Material, transforms: Array[Transform3D]) -> void:
	# Faixas, tachões e balizas repetidos: uma chamada de desenho por tipo.
	var mesh := BoxMesh.new()
	mesh.size = mesh_size
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func _build_road() -> void:
	var wet := _material("blitz_wet_asphalt", Color("16181b"), .16, .75)
	_box(_set, Vector3(0, -.03, -60), Vector3(11.8, .06, 1100), wet)
	var verge := _material("blitz_verge", Color("1a2016"), .9, .2)
	for side in [-1, 1]:
		_box(_set, Vector3(side * 160.0, -.09, -60), Vector3(308, .06, 1100), verge)
	var white := _material("blitz_paint_white", Color("c9ccc8"), .35, .5)
	var yellow := _material("blitz_paint_yellow", Color("c7a33a"), .35, .5)
	var dashes: Array[Transform3D] = []
	for index in 140: dashes.append(Transform3D(Basis.IDENTITY, Vector3(0, .004, 480.0 - index * 8.0)))
	_strip(_set, Vector3(.14, .01, 4.0), yellow, dashes)
	var edges: Array[Transform3D] = []
	for side in [-1, 1]: edges.append(Transform3D(Basis.IDENTITY, Vector3(side * 3.6, .004, -60)))
	_strip(_set, Vector3(.16, .01, 1100), white, edges)
	# Balizas refletivas na beira: dão leitura de velocidade no escuro.
	var posts: Array[Transform3D] = []
	for index in 56:
		for side in [-1, 1]: posts.append(Transform3D(Basis.IDENTITY, Vector3(side * 6.4, .45, 480.0 - index * 20.0)))
	_strip(_set, Vector3(.1, .9, .1), _material("blitz_post", Color("d8dad6"), .4, .5), posts)
	var reflectors: Array[Transform3D] = []
	for transform in posts: reflectors.append(transform.translated(Vector3(0, .32, 0)))
	_strip(_set, Vector3(.11, .12, .11), _material("blitz_reflector", Color("e0a43a"), .3, .5, Color("b97a22")), reflectors)
	# Cavaletes estreitando a faixa: listras vermelhas e brancas, sem cone de perto.
	var red := _material("blitz_barrier_red", Color("a3221d"), .5, .4)
	for spot in [Vector3(2.4, 0, -13.2), Vector3(4.4, 0, -11.6), Vector3(1.3, 0, -14.6)]:
		var barrier := Node3D.new()
		barrier.position = spot
		barrier.rotation.y = .35
		_set.add_child(barrier)
		for stripe in 4:
			_box(barrier, Vector3(-.6 + stripe * .4, .92, 0), Vector3(.4, .22, .05), red if stripe % 2 == 0 else white)
		for leg in [-1, 1]:
			_box(barrier, Vector3(leg * .7, .45, 0), Vector3(.06, .9, .45), white)

func _build_police() -> void:
	police = FLEET.create("police_cruiser")
	if police == null: police = Node3D.new()
	police.process_mode = Node.PROCESS_MODE_DISABLED
	police.position = POLICE_SPOT
	police.rotation.y = .22
	_set.add_child(police)
	var spec := FLEET.spec("police_cruiser")
	var roof := float(spec.get("bounds_size", [0, 1.55, 0])[1]) + .05
	var side := -1.0
	for color in [Color(1, .12, .1), Color(.15, .35, 1)]:
		var glow := Sprite3D.new()
		glow.name = "BlitzBeaconGlow"
		glow.texture = EQUIPMENT._lens_glow_texture()
		glow.pixel_size = .9 / 64.0
		glow.modulate = color
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(side * .35, roof, 0)
		police.add_child(glow)
		_glows.append(glow)
		side = -side
	halo = OmniLight3D.new()
	halo.name = "BlitzBeaconHalo"
	halo.omni_range = 12.0
	halo.omni_attenuation = 1.2
	halo.shadow_enabled = false
	halo.position = Vector3(0, roof + .3, 0)
	halo.set_meta("budget_energy", 2.6)
	halo.light_energy = 2.6
	police.add_child(halo)

func _build_truck() -> void:
	truck = TRUCK.create()
	_set.add_child(truck)
	# A cabine original é uma peça só: esta porta (chapa e vidro) é a que abre.
	truck_door = Node3D.new()
	truck_door.name = "BlitzCabDoor"
	truck_door.position = Vector3(-1.16, 2.0, -3.96)
	truck.add_child(truck_door)
	_box(truck_door, Vector3(0, -.36, .56), Vector3(.05, .8, 1.1), _material("blitz_truck_paint", TRUCK_PAINT, .45, .5))
	_box(truck_door, Vector3(0, .5, .56), Vector3(.03, .72, 1.02), _material("blitz_truck_glass", Color(.32, .4, .45, .35), .05, .9))
	_box(truck_door, Vector3(-.04, -.1, .95), Vector3(.05, .05, .18), _material("blitz_truck_handle", Color("9a9c9e"), .3, .7))
	headlight = SpotLight3D.new()
	headlight.name = "BlitzTruckHeadlight"
	headlight.position = Vector3(0, 1.35, -5.7)
	headlight.light_color = Color("ffe6c0")
	headlight.spot_range = 42.0
	headlight.spot_angle = 34.0
	headlight.spot_attenuation = .9
	headlight.shadow_enabled = false
	headlight.rotation_degrees = Vector3(-4, 0, 0)
	headlight.set_meta("budget_energy", 5.0)
	headlight.light_energy = 5.0
	truck.add_child(headlight)
	vicente = _person("vicente")
	var spec: Dictionary = truck.get_meta("vehicle_interior_spec", {})
	vicente.position = Vector3(float(spec.get("sx", -.55)), float(spec.get("floor", 1.15)), float(spec.get("sz", -3.35)))
	vicente.sit_amount = 1.0
	vicente.rotation.y = PI
	truck.add_child(vicente)

## Os dois oito anos mais novos: sem barba de agora, Dante de capa e farda.
func _person(identity: String):
	var model = CIVILIAN.new()
	model.appearance_locked = true
	if identity == "dante":
		# Fardado como os colegas: rosto e corpo do Dante jovem no rig civil (o corpo Meshy da patrulha
		# traz outro rosto), com a farda que PoliceModel veste no mesmo rig (camisa 6, quepe 4).
		model.name = "DanteYoung"
		model.appearance_variant = 9601
		model.coat_color = UNIFORM
		model.pants_color = UNIFORM.darkened(.25)
		model.wardrobe_overrides = {"female":false, "height":1.02, "build":1, "skin":Color("d4a688"), "hair_color":Color("2a221d"), "beard":0, "glasses":false, "bag":0, "backpack":false,
			"top":6, "bottom":0, "shoe":2, "hat":4, "accent":Color("141a26"), "inner":Color("d9d6cc"), "shoe_color":Color("141416")}
	else:
		model.name = "VicenteYoung"
		model.appearance_variant = 9511
		model.coat_color = Color("4d5a52")
		model.pants_color = Color("292d30")
		model.wardrobe_overrides = {"female":false, "height":1.04, "build":1, "skin":Color("c38d6e"), "hair_color":Color("25201d"), "hat":0, "beard":0, "glasses":false, "bag":0, "backpack":false, "top":1, "bottom":0, "shoe":0}
	return model

func _build_cast() -> void:
	dante = _person("dante")
	dante.position = DANTE_POST
	_set.add_child(dante)
	lantern = Node3D.new()
	lantern.name = "BlitzLantern"
	_set.add_child(lantern)
	_box(lantern, Vector3(0, 0, -.06), Vector3(.05, .05, .2), _material("blitz_lantern_body", Color("26282b"), .5, .4))
	_box(lantern, Vector3(0, 0, -.165), Vector3(.055, .055, .01), _material("blitz_lantern_lens", Color("fff3d8"), .2, .5, Color("fff0cc")))
	lantern_light = SpotLight3D.new()
	lantern_light.name = "BlitzLanternBeam"
	lantern_light.position = Vector3(0, 0, -.18)
	lantern_light.light_color = Color("fff1d6")
	lantern_light.spot_range = 22.0
	lantern_light.spot_angle = 16.0
	lantern_light.shadow_enabled = false
	lantern_light.set_meta("budget_energy", 4.0)
	lantern_light.light_energy = 4.0
	lantern.add_child(lantern_light)

func _build_colleagues() -> void:
	for entry in COLLEAGUES:
		var officer: Node3D = POLICE_MODEL.new()
		officer.name = "Blitz" + str(entry[0])
		officer.appearance_index = int(entry[3])
		officer.position = entry[1]
		# PoliceModel olha para -z (o corpo articulado vai girado dentro dele).
		officer.rotation.y = atan2(-entry[2].x, -entry[2].z)
		_set.add_child(officer)
		colleagues.append(officer)
	colleague_lantern = Node3D.new()
	colleague_lantern.name = "BlitzColleagueLantern"
	_set.add_child(colleague_lantern)
	# Só a lanterna acesa (emissiva): a luz de verdade fica com a de Dante, dentro do orçamento.
	_box(colleague_lantern, Vector3(0, 0, -.06), Vector3(.05, .05, .2), _material("blitz_lantern_body", Color("26282b"), .5, .4))
	_box(colleague_lantern, Vector3(0, 0, -.165), Vector3(.055, .055, .01), _material("blitz_lantern_lens", Color("fff3d8"), .2, .5, Color("fff0cc")))

## Mãos dos colegas: Bastos com o rádio no ombro, Lima com a lanterna baixa para a pista.
func _colleagues_tick() -> void:
	for index in colleagues.size():
		var officer := colleagues[index]
		var body = officer.get("body")
		if not is_instance_valid(body): continue
		var forward := -officer.global_basis.z.normalized()
		var right := forward.cross(Vector3.UP).normalized()
		var base := officer.global_position
		if index == 0:
			body.hand_targets = [base + Vector3.UP * 1.5 + forward * .1 - right * .14, null]
		else:
			var hand := base + Vector3.UP * (1.05 + .04 * sin(stage_time * 1.3)) + forward * .32 + right * .18
			body.hand_targets = [hand, null]
			colleague_lantern.global_position = hand
			colleague_lantern.look_at(hand + forward * 3.0 + Vector3.DOWN * 1.2, Vector3.UP)
		# hand_targets fixos: o provedor de arma do PoliceModel não pode sobrescrever.
		body.hand_provider = Callable()

func _build_traffic() -> void:
	# Os dois carros que passam antes do "terceiro" (só no prólogo).
	if pov != "dante": return
	for id in ["station_wagon", "sedan_classic"]:
		var car: Node3D = FLEET.create(id)
		if car == null: continue
		car.process_mode = Node.PROCESS_MODE_DISABLED
		car.position = Vector3(LANE_X, 0, 900)
		_set.add_child(car)
		cars.append(car)
		_car_speed.append(0.0)

func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "BlitzRain"
	rain.amount = 1500
	rain.lifetime = 1.5
	rain.preprocess = 1.5
	rain.fixed_fps = 30
	rain.visibility_aabb = AABB(Vector3(-16, -14, -16), Vector3(32, 28, 32))
	var quad := QuadMesh.new()
	quad.size = Vector2(.02, .26)
	if _rain_material == null:
		# Mesma gota da balsa; retida para o flashback não recompilar.
		_rain_material = ShaderMaterial.new()
		_rain_material.shader = RAIN_SHADER
		_rain_material.set_shader_parameter("rain_texture", RAIN_TEXTURES.texture("rain"))
		_rain_material.set_shader_parameter("rain_color", Color(.56, .66, .78, .32))
	quad.material = _rain_material
	rain.draw_pass_1 = quad
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(13, 1, 13)
	motion.direction = Vector3(.08, -1, .03)
	motion.spread = 1.0
	motion.initial_velocity_min = 11.0
	motion.initial_velocity_max = 14.0
	motion.gravity = Vector3(0, -3, 0)
	rain.process_material = motion
	_set.add_child(rain)

func _player(bus: String, stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	return player

func _build_audio() -> void:
	_rain_audio = _player("Ambient", BANK.loop("weather", "rain_bed.wav"), -9.0)
	_engine_audio = _player("SFX", BANK.loop("acoustic", "engine_truck_1.wav"), -80.0)
	_police_audio = _player("SFX", BANK.loop("acoustic", "engine_police_0.wav"), -80.0)
	_sfx = _player("SFX", null, -4.0)
	_radio_click = _player("SFX", _sound("res://audio/menu/click_0.wav"), -14.0)

func _sound(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null

func _play(path: String, volume := -4.0) -> void:
	var stream := _sound(path)
	if stream == null or not is_instance_valid(_sfx): return
	# Um efeito por vez basta aqui: porta, freio e metal nunca se sobrepõem.
	_sfx.stream = stream
	_sfx.volume_db = volume
	_sfx.play()

# --- Relógio ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _finishing: return
	_skip_armed = maxf(0.0, _skip_armed - delta)
	if _skip_armed <= 0.0 and _prompt.text == text(lines().get("prompts", {}).get("skip")): _prompt.text = ""
	if stage == "build":
		_build_step()
		return
	if stage == "warm":
		_warm()
		return
	var step := delta * pace
	stage_time += step
	_captions(step)
	_beacons()
	_colleagues_tick()
	if pov == "dante": _dante_tick(step)
	else: _vicente_tick(step)
	_follow_rain()
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.refresh()

func _build_step() -> void:
	if _step >= _steps.size():
		_stage_warm()
		return
	var trace := STALL_WORK.begin()
	_steps[_step].call()
	STALL_WORK.finish_slow("prologue.blitz.build.%d" % _step, trace, 2000)
	_step += 1

func _stage_warm() -> void:
	stage = "warm"
	_warm_draws = 0
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.register(self)
	# Tudo à vista de uma câmera, ainda coberto: chuva, vidro, giroflex, lanterna, porta aberta.
	truck.position = Vector3(LANE_X, 0, TRUCK_STOP_Z)
	truck_door.rotation.y = -1.1
	for index in cars.size(): cars[index].position = Vector3(-LANE_X, 0, -30.0 - index * 7.0)
	lantern.global_position = dante.global_position + Vector3(.2, 1.2, .3)
	camera.global_position = Vector3(-2.5, 3.0, 14.0)
	camera.look_at(Vector3(1.0, 1.4, -10.0))
	_follow_rain()
	if _rain_audio.stream != null: _rain_audio.play()
	if not RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.connect(_count_draw)

func _count_draw() -> void:
	_warm_draws += 1

func _warm() -> void:
	if DisplayServer.get_name() != "headless" and _warm_draws < WARM_DRAWS: return
	if RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.disconnect(_count_draw)
	truck_door.rotation.y = 0.0
	for car in cars: car.position = Vector3(LANE_X, 0, 900)
	if pov == "dante": _dante_begin()
	else: _vicente_begin()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(curtain, "color:a", 0.0, .9 / pace)

func _set_stage(value: String) -> void:
	stage = value
	stage_time = 0.0

func _beat(id: String) -> bool:
	# Verdadeiro uma única vez por id: marca os acontecimentos já disparados.
	if _beats.has(id): return false
	_beats[id] = true
	return true

# --- Legendas --------------------------------------------------------------------------------------

func say(group: String, key: String, done := Callable()) -> void:
	var source: Array = lines().get(group, {}).get(key, [])
	_queue = source.duplicate()
	_queue_done = done
	_line_left = 0.0
	_next_line()

func speaking() -> bool:
	return not _queue.is_empty() or _line_left > 0.0

func _next_line() -> void:
	if _queue.is_empty():
		_subtitle.text = ""
		var done := _queue_done
		_queue_done = Callable()
		if done.is_valid(): done.call()
		return
	var line: Dictionary = _queue.pop_front()
	var spoken := text(line)
	var radio := bool(line.get("radio", false))
	var english := TranslationServer.get_locale().begins_with("en")
	var speaker := str(line.get("speaker", ""))
	if radio: speaker += " (radio)" if english else " (rádio)"
	_subtitle.text = speaker + "\n" + spoken
	_line_left = clampf(1.0 + spoken.length() * .07, 1.7, 4.2)
	if radio and is_instance_valid(_radio_click) and _radio_click.stream != null: _radio_click.play()

func _captions(step: float) -> void:
	if _line_left <= 0.0: return
	_line_left -= step
	if _line_left <= 0.0:
		_line_left = 0.0
		_next_line()

func _objective_text(key: String) -> void:
	_objective.text = text(lines().get("objectives", {}).get(key))

# --- Peças vivas -----------------------------------------------------------------------------------

func _beacons() -> void:
	# Vermelho e azul alternando em pares rápidos, como o giroflex das viaturas.
	var phase := fposmod(stage_time * 2.2, 1.0)
	var red := phase < .5
	var flash := fposmod(stage_time * 8.8, 1.0) < .55
	if _glows.size() == 2:
		_glows[0].visible = red and flash
		_glows[1].visible = not red and flash
	if is_instance_valid(halo):
		halo.light_color = Color(1, .15, .12) if red else Color(.2, .38, 1)
		halo.set_meta("budget_energy", 2.6 if flash else .7)
		if not LIGHT_BUDGET.enabled: halo.light_energy = halo.get_meta("budget_energy")

func _follow_rain() -> void:
	if not is_instance_valid(rain) or not is_instance_valid(camera): return
	rain.global_position = camera.global_position + Vector3.UP * 7.0 - camera.global_basis.z * 5.0

func _engine(distance: float) -> void:
	if not is_instance_valid(_engine_audio) or _engine_audio.stream == null: return
	if not _engine_audio.playing: _engine_audio.play()
	_engine_audio.volume_db = lerpf(-6.0, -40.0, clampf(distance / 160.0, 0.0, 1.0))
	_engine_audio.pitch_scale = .8 + clampf(truck_speed / 20.0, 0.0, 1.0) * .45

func _budget_request() -> Dictionary:
	var lights: Array[Light3D] = []
	var wanted: Array[Dictionary] = []
	for light in [halo, headlight, lantern_light]:
		if not is_instance_valid(light): continue
		lights.append(light)
		# Pela visibilidade do dono: a luz escondida pelo próprio orçamento continua pedindo.
		if light.get_parent().is_visible_in_tree(): wanted.append({"light": light, "headlight": false})
	# "player": a cena é a única coisa na tela; o mundo pausado embaixo não disputa.
	return {"lights": lights, "wanted": wanted, "player": true, "camera": camera.global_position if is_instance_valid(camera) else Vector3.ZERO}

func _face(model: Node3D, direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < .001: return
	# O rig civil olha para +z local (a frente de um Node3D comum é -z).
	model.rotation.y = atan2(direction.x, direction.z)

func _forward(model: Node3D) -> Vector3:
	return model.global_basis.z.normalized()

## Cabeça de verdade do rig (a pose sentada/em pé muda a altura); sem rig, estimativa.
func _head(model) -> Vector3:
	var head = model.get("head_node")
	if head is Node3D and is_instance_valid(head): return head.global_position
	return model.global_position + Vector3.UP * (1.32 if model.sit_amount > .5 else 1.62)

## Lanterna na mão direita de quem segura; `swing` 0..1 balança para o caminhão parar.
func _hold_lantern(holder, swing: float) -> void:
	var forward := _forward(holder)
	var right := forward.cross(Vector3.UP).normalized()
	var wave := sin(stage_time * 7.0) * .38 * swing
	var hand: Vector3 = holder.global_position + Vector3.UP * (1.18 + .28 * swing) + forward * (.36 + .12 * swing) + right * (.2 + wave)
	holder.hand_targets = [holder.hand_targets[0], hand]
	lantern.global_position = hand
	lantern.look_at(hand + forward * 4.0 + Vector3.DOWN * (1.4 - swing * 1.1) + right * wave * 2.0, Vector3.UP)

func _door_point() -> Vector3:
	return truck.to_global(Vector3(-1.85, 0, -3.4))

func _cab_head() -> Vector3:
	return _head(vicente)

## Olhos de Vicente debruçado no vão da porta: do banco, a linha até o rosto de Dante (mais baixo,
## no asfalto) cortaria a lataria da cabine.
func _cab_lean() -> Vector3:
	return truck.to_global(Vector3(-1.3, truck.to_local(_cab_head()).y + .02, -3.3))

func _move_truck(step: float) -> void:
	truck.position.z -= truck_speed * step

## Desacelera para parar exatamente em `stop_z`; devolve true ao parar.
func _brake_to(stop_z: float, step: float, crawl := 0.0) -> bool:
	var distance := truck.position.z - stop_z
	if distance <= .05:
		truck.position.z = stop_z
		truck_speed = 0.0
		return true
	# Até `crawl` ele ainda anda (parado longe, volta a rodar); perto, a curva de frenagem manda.
	if crawl > 0.0 and truck_speed < crawl: truck_speed = minf(crawl, truck_speed + 2.0 * step)
	truck_speed = minf(truck_speed, sqrt(2.0 * 2.4 * distance))
	truck_speed = minf(truck_speed, distance / maxf(step, .001))
	_move_truck(step)
	return false

# --- Ponto de vista de Dante (prólogo) -------------------------------------------------------------

func _dante_begin() -> void:
	_set_stage("dante_open")
	truck.position = Vector3(LANE_X, 0, 900)
	truck_speed = 0.0
	_dante_heading = 0.0
	dante.rotation.y = _dante_heading
	_police_audio.play()
	_police_audio.volume_db = -26.0
	say("dante", "radio_open", func(): say("dante", "colleagues"))

func _nape_camera(step: float, ahead := 6.0) -> void:
	# Câmera na nuca de Dante: perto, um pouco acima, olhando para onde ele anda.
	var forward := _forward(dante)
	var target: Vector3 = dante.global_position + Vector3.UP * 1.72 - forward * 1.25 + forward.cross(Vector3.UP).normalized() * .32
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-6.0 * step)) if stage_time > .05 else target
	camera.look_at(dante.global_position + Vector3.UP * 1.45 + forward * ahead, Vector3.UP)

func _dante_tick(step: float) -> void:
	match stage:
		"dante_open":
			_traffic(step)
			_hold_lantern(dante, _swing)
			_nape_camera(step)
			# O terceiro veículo é o caminhão: entra depois dos dois carros.
			if stage_time > 10.0 and _beat("truck_enters"):
				truck.position = Vector3(LANE_X, 0, 230.0)
				truck_speed = 14.0
			if truck.position.z < 800.0 and not signaled:
				var distance := truck.position.z - TRUCK_STOP_Z
				# Sem sinal, ele se arrasta e espera perto dos cavaletes.
				if distance < 160.0: _show_prompt("signal")
				if distance > 70.0: _move_truck(step)
				else: _brake_to(TRUCK_STOP_Z + 42.0, step, 3.0)
				if autoplay and distance < 140.0: _signal()
			elif signaled:
				_swing = minf(1.0, _swing + step * 3.0) if stage_time < 2.0 else maxf(0.0, _swing - step * 1.5)
				if _brake_to(TRUCK_STOP_Z, step, 4.0):
					_play("res://audio/vehicle_fx/air_brake.wav", -6.0)
					_hide_prompt()
					_set_stage("dante_walk")
					if not speaking(): say("dante", "stopped")
					_objective_text("walk")
			_engine(camera.global_position.distance_to(truck.global_position))
		"dante_walk":
			_traffic(step)
			_swing = maxf(0.0, _swing - step * 1.5)
			_walk_dante(step)
			_hold_lantern(dante, _swing)
			_nape_camera(step, 4.0)
			_engine(camera.global_position.distance_to(truck.global_position))
			var door := _door_point()
			if Vector2(dante.global_position.x - door.x, dante.global_position.z - door.z).length() < .45:
				_objective.text = ""
				_set_stage("dante_door")
		"dante_door": _dante_door(step)
		"dante_cuff": _dante_cuff(step)
		"dante_black": _dante_black()

func _signal() -> void:
	if signaled or stage != "dante_open": return
	signaled = true
	stage_time = 0.0
	_hide_prompt()

func _traffic(step: float) -> void:
	for index in cars.size():
		var car := cars[index]
		var start_at := 1.5 + index * 4.5
		if stage == "dante_open" and stage_time > start_at and _beat("car_%d" % index):
			car.position = Vector3(LANE_X, 0, 150.0)
			_car_speed[index] = 15.0
		if _car_speed[index] <= 0.0: continue
		# Passam devagar pela blitz, olhando, e seguem.
		var near := absf(car.position.z - DANTE_POST.z) < 30.0
		_car_speed[index] = move_toward(_car_speed[index], 6.0 if near else 15.0, step * 5.0)
		car.position.z -= _car_speed[index] * step
		if car.position.z < -320.0:
			_car_speed[index] = 0.0
			car.hide()

func _walk_dante(step: float) -> void:
	var input := Vector2.ZERO
	var door := _door_point()
	if autoplay:
		var offset: Vector3 = door - dante.global_position
		input = Vector2(offset.x, offset.z).normalized() if offset.length() > .05 else Vector2.ZERO
	else:
		var game_input := get_node_or_null("/root/GameInput")
		var move: Vector2 = game_input.movement() if game_input != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Para frente é para o caminhão (+z) do ponto de vista da nuca.
		input = Vector2(-move.x, -move.y)
	if input.length() < .1: return
	input = input.limit_length(1.0)
	var velocity := Vector3(input.x, 0, input.y) * 1.55
	var next: Vector3 = dante.position + velocity * step
	next.x = clampf(next.x, -5.5, 5.5)
	next.z = clampf(next.z, -24.0, 6.0)
	# A carroceria e a cabine são sólidas para quem anda.
	var local := truck.to_local(next)
	if absf(local.x) < 1.6 and local.z > -6.0 and local.z < 6.0:
		next = truck.to_global(Vector3(signf(local.x) * 1.6 if local.x != 0.0 else -1.6, 0, local.z))
	dante.position = next
	var heading := atan2(velocity.x, velocity.z)
	_dante_heading = lerp_angle(_dante_heading, heading, 1.0 - exp(-8.0 * step))
	dante.rotation.y = _dante_heading

func _dante_door(step: float) -> void:
	_engine(4.0)
	if _beat("door_opens"):
		_face(dante, Vector3.RIGHT)
		_dante_heading = dante.rotation.y
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(truck_door, "rotation:y", -1.15, .9 / pace)
		_play("res://audio/vehicle_fx/door_open_0.wav", -5.0)
	_hold_lantern(dante, 0.0)
	if stage_time < 1.0:
		_nape_camera(step, 3.0)
		return
	# Close no rosto de Vicente, molhado, olhando para baixo pela porta aberta.
	var head := _cab_head()
	if _beat("face_close"):
		vicente.activity = "talk"
		camera.fov = 46.0
		# A porta abre pela frente (dobradiça no para-brisa): o vão e a câmera ficam atrás dela.
		# No vão aberto, por dentro do vidro lateral da cabine (é uma peça só com a lataria e escura
		# por fora): de baixo, a lataria ficaria no meio; de fora, o vidro.
		camera.global_position = truck.to_global(Vector3(-1.0, truck.to_local(head).y - .02, -3.95))
		camera.look_at(head, Vector3.UP)
	if stage_time > 1.6 and _beat("vicente_line"):
		say("dante", "door")
	# Silêncio depois do nome: só chuva e o motor parado.
	if stage_time > 6.4 and _beat("order_line"):
		vicente.activity = ""
		camera.fov = 55.0
		_nape_camera(1.0, 2.0)
		say("dante", "order")
	if stage_time > 9.2 and _beat("step_out"):
		# Vicente desce da cabine; Dante recua um passo.
		vicente.reparent(_set)
		vicente.sit_amount = 0.0
		var door := _door_point()
		vicente.global_position = door + Vector3(.35, 0, 0)
		_face(vicente, Vector3.LEFT)
		dante.global_position = door + Vector3(-.6, 0, 0)
		_face(dante, Vector3.RIGHT)
		_dante_heading = dante.rotation.y
		_cam_from = Transform3D.IDENTITY
		_set_stage("dante_cuff")
		_objective_text("cuff")
		_show_prompt("cuff")
		_progress.value = 0.0
		_progress.show()

func _wrists() -> Vector3:
	return vicente.global_position + _forward(vicente) * .3 + Vector3.UP * .98

func _dante_cuff(step: float) -> void:
	_engine(4.0)
	var holding := autoplay or Input.is_action_pressed("interact")
	# Segurar demora; soltar devolve devagar. Não existe outro comando.
	cuff_progress = clampf(cuff_progress + (step / HOLD_SECONDS if holding else -step * .4), 0.0, 1.0)
	_progress.value = cuff_progress
	var wrists := _wrists()
	var across := _forward(vicente).cross(Vector3.UP).normalized()
	vicente.hand_targets = [wrists + across * .06, wrists - across * .06]
	if cuff_progress > .02:
		var rest: Vector3 = dante.global_position + Vector3.UP * 1.0 + _forward(dante) * .25
		var reach: Vector3 = rest.lerp(wrists, smoothstep(0.0, .6, cuff_progress))
		dante.hand_targets = [reach + across * .1, reach - across * .1]
		lantern.hide()
	else:
		_hold_lantern(dante, 0.0)
		lantern.show()
	# A câmera sai da nuca e fecha nas mãos conforme o botão é segurado.
	var forward := _forward(dante)
	var nape: Vector3 = dante.global_position + Vector3.UP * 1.7 - forward * 1.1 + forward.cross(Vector3.UP).normalized() * .35
	var close := wrists + Vector3(0, .3, 0) + across * .62 - forward * .25
	var k := smoothstep(0.0, 1.0, cuff_progress)
	camera.global_position = nape.lerp(close, k)
	camera.fov = lerpf(55.0, 38.0, k)
	camera.look_at(vicente.global_position + Vector3.UP * 1.45 if k < .01 else (vicente.global_position + Vector3.UP * 1.45).lerp(wrists, k), Vector3.UP)
	if cuff_progress >= 1.0:
		_play("res://audio/weapons_fire/gun_holster_0.wav", -2.0)
		_cut_to_black()
		_set_stage("dante_black")

func _cut_to_black() -> void:
	# Corte seco: sem fade, a chuva e o motor somem junto com a imagem.
	curtain.color.a = 1.0
	_hide_prompt()
	_progress.hide()
	_objective.text = ""
	_subtitle.text = ""
	_queue.clear()
	_line_left = 0.0
	for player in [_rain_audio, _engine_audio, _police_audio, _radio_click]:
		if is_instance_valid(player): player.stop()

func _dante_black() -> void:
	if stage_time > 1.4 and _beat("title"):
		_title.text = text(lines().get("title"))
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_title, "modulate:a", 1.0, .8 / pace)
		tween.tween_interval(2.2 / pace)
		tween.tween_property(_title, "modulate:a", 0.0, .8 / pace)
	if stage_time > 5.4: _finish(false)

# --- Ponto de vista de Vicente (flashback do ato 2) ------------------------------------------------

func _vicente_begin() -> void:
	_set_stage("vicente_drive")
	truck.position = Vector3(LANE_X, 0, 460.0)
	truck_speed = 16.0
	dante.position = DANTE_POST
	_face(dante, Vector3.BACK)
	_objective_text("drive")
	say("vicente", "radio_open")

func _chase_camera(step: float) -> void:
	var target := truck.to_global(Vector3(-.6, 4.4, 11.5))
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-4.0 * step)) if stage_time > .05 else target
	camera.look_at(truck.to_global(Vector3(0, 2.2, -9.0)), Vector3.UP)

func _vicente_tick(step: float) -> void:
	_hold_lantern(dante, _swing)
	match stage:
		"vicente_drive":
			var distance := truck.position.z - TRUCK_STOP_Z
			if distance < 300.0 and not speaking() and _beat("warning"): say("vicente", "radio_warning")
			if distance < 150.0 and _beats.has("warning") and not speaking() and _beat("lights"): say("vicente", "lights")
			# Dante na pista, a lanterna balançando: parar é reflexo, não escolha.
			if distance < 130.0: _swing = minf(1.0, _swing + step * 2.0)
			if distance < 95.0:
				_objective.text = ""
				_set_stage("vicente_stop")
			else: _drive(step)
			_chase_camera(step)
			_engine(12.0)
		"vicente_stop":
			truck.position.x = move_toward(truck.position.x, LANE_X, step * 1.2)
			truck.rotation.y = move_toward(truck.rotation.y, 0.0, step * .2)
			_chase_camera(step)
			_engine(12.0)
			if _brake_to(TRUCK_STOP_Z, step, 3.0):
				_play("res://audio/vehicle_fx/air_brake.wav", -6.0)
				_swing = 0.0
				say("vicente", "stop")
				_set_stage("vicente_wait")
		"vicente_wait":
			_engine(3.0)
			_cab_camera(step)
			var door := _door_point()
			var offset: Vector3 = door - dante.global_position
			offset.y = 0.0
			if offset.length() > .05:
				dante.global_position += offset.normalized() * minf(offset.length(), 1.35 * step)
				_face(dante, offset)
			elif _beat("door_opens"):
				_face(dante, Vector3.RIGHT)
				create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(truck_door, "rotation:y", -1.15, .9 / pace)
				_play("res://audio/vehicle_fx/door_open_0.wav", -5.0)
				_set_stage("vicente_face")
		"vicente_face":
			_engine(3.0)
			# O rosto de Dante pela porta aberta, de cima, do banco do motorista.
			var face := _head(dante)
			camera.fov = move_toward(camera.fov, 42.0, step * 14.0)
			# Vicente desce o rosto até o vão: de cima, a aba do quepe tapava o rosto de Dante.
			camera.global_position = _cab_lean() + Vector3.DOWN * .5
			camera.look_at(face, Vector3.UP)
			if stage_time > 4.2:
				_cut_to_black()
				_set_stage("vicente_black")
		"vicente_black":
			if stage_time > .8: _finish(false)

func _drive(step: float) -> void:
	var steer := 0.0
	var pedal := .35
	if not autoplay:
		var game_input := get_node_or_null("/root/GameInput")
		var axes: Vector2 = game_input.vehicle_input() if game_input != null else Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_down", "move_up"))
		steer = axes.x
		pedal = axes.y
	if pedal > 0.0: truck_speed += pedal * 1.8 * step
	elif pedal < 0.0: truck_speed += pedal * 5.5 * step
	else: truck_speed -= .35 * step
	# "Cê não para": dá para frear, não para ficar parado longe da blitz.
	truck_speed = clampf(truck_speed, 4.0, 22.0)
	var grip := clampf(truck_speed / 8.0, 0.0, 1.0)
	truck.position.x = clampf(truck.position.x + steer * 2.4 * grip * step, .95, 4.6)
	truck.rotation.y = lerpf(truck.rotation.y, -steer * .05 * grip, 1.0 - exp(-3.0 * step))
	_move_truck(step)

func _cab_camera(step: float) -> void:
	camera.fov = move_toward(camera.fov, 50.0, step * 10.0)
	# Dos olhos de Vicente, um palmo à frente da cabeça (dentro dela a câmera vê o próprio rosto).
	camera.global_position = _cab_lean()
	camera.look_at(_head(dante) - Vector3.UP * .1, Vector3.UP)

# --- Comandos --------------------------------------------------------------------------------------

func _show_prompt(key: String) -> void:
	var game_input := get_node_or_null("/root/GameInput")
	var label := text(lines().get("prompts", {}).get(key))
	var hint: String = game_input.prompt("interact") if game_input != null else "E"
	_prompt.text = "[%s] %s" % [hint, label]

func _hide_prompt() -> void:
	_prompt.text = ""

func _input(event: InputEvent) -> void:
	if _finishing: return
	# A cena é dona de toda a entrada: nada chega à sessão pausada embaixo.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		request_skip()
		return
	if pov == "dante" and stage == "dante_open" and event.is_action_pressed("interact") and not _prompt.text.is_empty(): _signal()

## Esc uma vez arma o pulo por 3 s; a segunda pula.
func request_skip() -> void:
	if stage in ["build", "warm"]: return
	if _skip_armed > 0.0:
		skip()
		return
	_skip_armed = 3.0
	_prompt.text = text(lines().get("prompts", {}).get("skip"))

func skip() -> void:
	if _finishing: return
	skipped = true
	_finish(true)

func _finish(was_skipped: bool) -> void:
	if _finishing: return
	_finishing = true
	_cut_to_black()
	_release_world()
	finished.emit(pov, was_skipped)
	var done := on_done
	on_done = Callable()
	if done.is_valid():
		if done.get_argument_count() >= 1: done.call(was_skipped)
		else: done.call()
	queue_free()

func _release_world() -> void:
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.unregister(self)
	if RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.disconnect(_count_draw)
	if not _owns_world: return
	_owns_world = false
	if is_instance_valid(_main_viewport): _main_viewport.disable_3d = _previous_3d
	if is_inside_tree(): get_tree().paused = _previous_pause

func _exit_tree() -> void:
	_release_world()
