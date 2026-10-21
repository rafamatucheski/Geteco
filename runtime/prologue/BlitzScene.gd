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
const OFFICER := preload("res://runtime/prologue/BlitzOfficer.gd")
const OPEN_TRUCK := preload("res://runtime/prologue/BlitzTruck.gd")
const CORPSE := preload("res://runtime/prologue/BlitzCorpse.gd")
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")
const COBRA_MODEL := preload("res://gameplay/CobraModel.gd")
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
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
const HOLD_SECONDS := 2.6
## Bastos para na porta do motorista e Dante fica do lado dele, um passo atrás.
## O último ponto fica a um braço da porta fechada (local -1,62; -4,3 do caminhão parado), na frente do
## giro da chapa: o vidro a 2,35 m estava 1,25 m fora do alcance do braço dele (relatório de qualidade).
const BASTOS_PATH := [Vector3(3.0, 0, -12.7), Vector3(.2, 0, -11.7), Vector3(-.4, 0, -9.9), Vector3(.18, 0, -8.7)]
const DANTE_BESIDE := Vector3(-.75, 0, -7.6)
## Abrigo de Dante no tiroteio (fora da linha da cabine) e os dois pontos do atirador: exposto na frente
## da grade, escondido atrás do canto direito do caminhão (a cabine fica no meio).
const DANTE_COVER := Vector3(-2.0, 0, -8.6)
const SHOOTER_OUT := Vector3(3.3, 0, -10.6)
## Exposto à esquerda da grade (x < 0,5): dali vê Bastos na porta e Dante no abrigo sem atravessar o canto
## do caminhão.
const SHOOTER_EXPOSED := Vector3(.4, 0, -11.7)
const SHOOTER_HIDDEN := Vector3(3.7, 0, -10.9)
## "Demora a morrer": tiros que o atirador aguenta.
const SHOOTER_HEALTH := 8
const VICENTE_FLEE := [Vector3(-.4, 0, -5.4), Vector3(-3.1, 0, 2.0), Vector3(-3.4, 0, 13.0)]
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
var bastos: Node3D
var lima: Node3D
var bastos_radio: Node3D
## CobraModel: o atirador escondido na cabine, do lado do passageiro.
var shooter: Node3D
var shooter_health := SHOOTER_HEALTH
var shots_fired := 0
var shooter_hits := 0
var vicente_hit := false
var aim_yaw := 0.0
var aim_pitch := 0.0
var _crosshair: Label
var _fire_cooldown := 0.0
var _want_fire := false
var _shake := 0.0
var _shooter_exposed := false
var _shooter_clock := 0.0
var _shooter_fire_clock := .4
var _bastos_leg := 0
var _flee_leg := 0
var _shot_clock := 0.0
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _mouse_owned := false
var _car_speed: Array[float] = []
var _glows: Array[Sprite3D] = []
var halo: OmniLight3D
## Dois faróis do caminhão (esquerdo, direito): fachos de verdade, no orçamento.
var headlights: Array[SpotLight3D] = []
## Luz de teto da cabine: acende quando a porta abre (é o que deixa ver Vicente lá dentro).
var cab_light: OmniLight3D
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
	# Depois dos rigs (prioridade 0): a lanterna e a câmera leem a pose deste quadro; os alvos de mão
	# escritos aqui valem no quadro seguinte, o que não se vê.
	process_priority = 100
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
	_crosshair = _label(26)
	_crosshair.text = "+"
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.hide()
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
	# Molhado, mas não espelho: com rugosidade .16 cada farol virava um pilar branco no asfalto.
	var wet := _material("blitz_wet_asphalt", Color("202327"), .32, .5)
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
		glow.pixel_size = .6 / 64.0
		glow.modulate = color
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Em cima das lentes da barra (medidas na malha da viatura), não flutuando sobre ela.
		glow.position = Vector3(side * .29, roof - .06, .05)
		police.add_child(glow)
		_glows.append(glow)
		side = -side
	halo = OmniLight3D.new()
	halo.name = "BlitzBeaconHalo"
	halo.omni_range = 9.0
	halo.omni_attenuation = 1.8
	# No asfalto molhado o reflexo do giroflex virava uma faixa vermelha no chão.
	halo.light_specular = 0.0
	halo.shadow_enabled = false
	halo.position = Vector3(0, roof + .3, 0)
	halo.set_meta("budget_energy", 2.6)
	_beacon_lenses()
	halo.light_energy = 2.6
	police.add_child(halo)

func _build_truck() -> void:
	truck = OPEN_TRUCK.create_open()
	_set.add_child(truck)
	# A cabine original é uma peça só: esta porta (chapa e vidro) é a que abre.
	truck_door = Node3D.new()
	truck_door.name = "BlitzCabDoor"
	truck_door.position = Vector3(-1.16, 2.0, -3.96)
	truck.add_child(truck_door)
	# A chapa desce até o estribo: fechada, cobre o vão inteiro da cabine aberta (BlitzTruck).
	_box(truck_door, Vector3(0, -.52, .56), Vector3(.05, 1.08, 1.1), _material("blitz_truck_paint", TRUCK_PAINT, .45, .5))
	_box(truck_door, Vector3(0, .5, .56), Vector3(.03, .72, 1.02), _material("blitz_truck_glass", Color(.32, .4, .45, .35), .05, .9))
	_box(truck_door, Vector3(-.04, -.1, .95), Vector3(.05, .05, .18), _material("blitz_truck_handle", Color("9a9c9e"), .3, .7))
	_light_truck()
	var wheel := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .16
	ring.outer_radius = .2
	ring.rings = 24
	ring.ring_segments = 8
	wheel.mesh = ring
	wheel.material_override = _material("blitz_wheel", Color("1b1c1e"), .5, .4)
	wheel.position = Vector3(-.55, 2.02, -3.75)
	# Aro inclinado para o motorista, como volante de caminhão.
	wheel.rotation = Vector3(-1.05, 0, 0)
	truck.add_child(wheel)
	cab_light = OmniLight3D.new()
	cab_light.name = "BlitzCabLight"
	cab_light.position = Vector3(0, 2.85, -3.25)
	cab_light.light_color = Color("ffd7a6")
	cab_light.omni_range = 2.6
	cab_light.omni_attenuation = 1.2
	cab_light.shadow_enabled = false
	cab_light.set_meta("budget_energy", 0.0)
	cab_light.light_energy = 0.0
	truck.add_child(cab_light)
	vicente = _person("vicente")
	var spec: Dictionary = truck.get_meta("vehicle_interior_spec", {})
	vicente.position = Vector3(float(spec.get("sx", -.55)), float(spec.get("floor", 1.15)), float(spec.get("sz", -3.35)))
	vicente.sit_amount = 1.0
	vicente.rotation.y = PI
	truck.add_child(vicente)

## Lentes acesas: no jogo quem acende é o VehicleEquipment; aqui o caminhão é só o modelo, então as
## lentes ganham cópias emissivas próprias (retidas) e brilho de lente como o das viaturas. O material
## compartilhado do caminhão de carga do deserto não é tocado.
func _light_truck() -> void:
	var lenses := {"headlight_left": [Color("fff1d2"), 4.5], "headlight_right": [Color("fff1d2"), 4.5], "tail": [Color("ff2a1c"), 2.4], "amber": [Color("ffa23a"), 1.6]}
	for finish in lenses:
		var part := truck.find_child("Freight_" + finish, true, false) as MeshInstance3D
		if part == null: continue
		var lit: StandardMaterial3D = null
		for held in _retained:
			if held is StandardMaterial3D and held.resource_name == "blitz_lit_" + finish: lit = held
		if lit == null:
			lit = (TRUCK.material(finish)).duplicate() as StandardMaterial3D
			lit.resource_name = "blitz_lit_" + finish
			lit.emission_enabled = true
			lit.emission = lenses[finish][0]
			lit.emission_energy_multiplier = lenses[finish][1]
			_retained.append(lit)
		part.material_override = lit
	# Brilho nas lentes (faróis brancos na frente, lanternas vermelhas atrás): na chuva é o que se vê de longe.
	for side in [-1.0, 1.0]:
		for spec in [[Vector3(side * 1.05, 1.34, -5.6), Color(1, .93, .8), .6], [Vector3(side * 1.02, 1.06, 5.8), Color(1, .16, .1), .45]]:
			var glow := Sprite3D.new()
			glow.texture = EQUIPMENT._lens_glow_texture()
			glow.pixel_size = float(spec[2]) / 64.0
			glow.modulate = spec[1]
			glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.position = spec[0]
			truck.add_child(glow)
		var beam := SpotLight3D.new()
		beam.name = "BlitzTruckHeadlight"
		beam.position = Vector3(side * 1.05, 1.34, -5.65)
		beam.light_color = Color("ffe9c8")
		beam.spot_range = 35.0
		beam.spot_angle = 32.0
		beam.spot_attenuation = .85
		beam.spot_angle_attenuation = 1.5
		beam.light_specular = .2
		beam.shadow_enabled = false
		# Baixo e um pouco para fora, como farol de verdade: uma mancha no asfalto a ~12 m, sem estourar
		# rostos e cavaletes de perto (energia 9 com borda dura estourava; relatório de qualidade).
		beam.rotation_degrees = Vector3(-6.0, -side * 2.0, 0)
		beam.set_meta("budget_energy", 5.0)
		beam.light_energy = 5.0
		truck.add_child(beam)
		headlights.append(beam)

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

func _lantern_node(node_name: String, beam: bool) -> Node3D:
	var item := Node3D.new()
	item.name = node_name
	# O tubo segue o antebraço (-Z do objeto = direção dos dedos): a mão fecha no corpo, a lente passa
	# dos nós dos dedos.
	_box(item, Vector3(0, 0, -.03), Vector3(.045, .045, .19), _material("blitz_lantern_body", Color("6a6e72"), .45, .5))
	_box(item, Vector3(0, 0, -.13), Vector3(.05, .05, .01), _material("blitz_lantern_lens", Color("fff3d8"), .2, .5, Color("fff0cc")))
	if beam:
		lantern_light = SpotLight3D.new()
		lantern_light.name = "BlitzLanternBeam"
		lantern_light.position = Vector3(0, 0, -.15)
		lantern_light.light_color = Color("fff1d6")
		lantern_light.spot_range = 22.0
		lantern_light.spot_angle = 16.0
		lantern_light.shadow_enabled = false
		lantern_light.set_meta("budget_energy", 4.0)
		lantern_light.light_energy = 4.0
		item.add_child(lantern_light)
	return item

func _officer(script: GDScript, node_name: String, appearance: int, point: Vector3, facing: Vector3) -> Node3D:
	var officer: Node3D = script.new()
	officer.name = node_name
	# Índice fixo: não gasta o rodízio de PoliceAppearance.next_model do jogo.
	officer.appearance_index = appearance
	officer.position = point
	_set.add_child(officer)
	_face(officer, facing)
	return officer

func _build_cast() -> void:
	# Dante é o PoliceModel da patrulha com o rosto dele (BlitzOfficer): mesma farda e a pegada de pistola
	# do jogo, com as duas mãos no lugar.
	dante = _officer(OFFICER, "DanteYoung", 0, DANTE_POST, Vector3.BACK)
	dante.equip("pistol")
	lantern = _lantern_node("BlitzLantern", true)
	_set.add_child(lantern)

func _build_colleagues() -> void:
	bastos = _officer(POLICE_MODEL, "BlitzBastos", 3, Vector3(3.75, 0, -14.9), Vector3(-1, 0, .35))
	lima = _officer(POLICE_MODEL, "BlitzLima", 6, Vector3(2.9, 0, -14.3), Vector3.BACK)
	colleagues.assign([bastos, lima])
	colleague_lantern = _lantern_node("BlitzColleagueLantern", false)
	_set.add_child(colleague_lantern)
	bastos_radio = Node3D.new()
	bastos_radio.name = "BlitzRadio"
	_box(bastos_radio, Vector3(0, 0, -.02), Vector3(.06, .035, .12), _material("blitz_radio", Color("1b1c1e"), .55, .3))
	_set.add_child(bastos_radio)
	if pov == "dante":
		shooter = COBRA_MODEL.new()
		shooter.name = "BlitzShooter"
		shooter.look_seed = 4417
		shooter.position = SHOOTER_OUT
		_set.add_child(shooter)
		# Biblioteca dos clipes de morte, sob a cortina (só o prólogo tem mortes).
		MIXAMO_DEATH.library()

## Prende um objeto na palma: filho do antebraço do rig, na ponta (onde o IK põe a mão). Assim a lanterna,
## o rádio e a algema andam com a mão de verdade, em vez de flutuar perto dela.
func _hold(model, index: int, item: Node3D) -> bool:
	var body = model.get("body") if model is POLICE_MODEL else model
	if not is_instance_valid(body) or not is_instance_valid(item) or body.forearms.size() <= index: return false
	var fore: Node3D = body.forearms[index]
	if item.get_parent() != fore: item.reparent(fore, false)
	item.position = Vector3(0, -float(body._arm_measure(index).y) + .03, .015)
	item.rotation = Vector3(-PI * .5, 0, 0)
	return true

func _body(model):
	return model.get("body") if model is POLICE_MODEL else model

## Alvos fixos das mãos (null = braço livre). Desliga o provedor de arma do PoliceModel, que reescreveria.
func _hands(model, right: Variant, left: Variant) -> void:
	var body = _body(model)
	if not is_instance_valid(body): return
	body.hand_provider = Callable()
	body.hand_targets = [right, left]

func _colleagues_tick() -> void:
	if not is_instance_valid(lima) or not is_instance_valid(bastos): return
	_hold(lima, 0, colleague_lantern)
	_hold(bastos, 1, bastos_radio)
	_hold(dante, 0, lantern)
	if stage in ["dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_black"]: return
	# Lima manda os carros para a outra faixa: a lanterna varre da faixa fechada para a aberta.
	var forward := _forward(lima)
	var right := forward.cross(Vector3.UP).normalized()
	var waving := _traffic_near()
	var sweep := (.5 + .5 * sin(stage_time * 3.4)) if waving else .15
	# Cotovelo dobrado: com o alvo no limite do alcance o braço ficava travado e reto como um bastão.
	_hands(lima, lima.global_position + Vector3.UP * (1.12 + .10 * sweep) + forward * .28 + right * lerpf(.20, -.25, sweep), null)
	# Bastos no rádio até ir com Dante: a mão esquerda leva o rádio à boca (a junta da cabeça é o pescoço).
	if stage in ["dante_open", "vicente_drive", "vicente_stop", "vicente_wait", "vicente_face"]:
		var mouth: Vector3 = _head(bastos) + Vector3.UP * .14 + _forward(bastos) * .13 - _forward(bastos).cross(Vector3.UP).normalized() * .05
		_hands(bastos, null, mouth)

## Depois da pose do quadro (process_priority): o facho aponta para onde o policial olha, não para onde o
## antebraço aponta (seguia o braço: chão aos pés em repouso, céu ao sinalizar).
func _aim_lanterns() -> void:
	if is_instance_valid(lantern) and lantern.is_visible_in_tree():
		var aim: Vector3 = dante.global_position + _forward(dante) * 4.0
		if stage == "dante_ask" or stage == "vicente_face": aim = truck.to_global(Vector3(-.55, 2.3, -3.4))
		elif _swing > .05 and truck.position.z < 800.0: aim = truck.to_global(Vector3(-.5, 2.5, -5.0))
		_point(lantern, aim)
		var raised := _swing > .05 or stage in ["dante_ask", "vicente_wait", "vicente_face"]
		lantern_light.set_meta("budget_energy", 4.0 if raised else 1.5)
		if not LIGHT_BUDGET.enabled: lantern_light.light_energy = lantern_light.get_meta("budget_energy")
	if is_instance_valid(colleague_lantern) and colleague_lantern.is_visible_in_tree():
		# Lima ilumina a faixa aberta por onde os carros devem passar.
		_point(colleague_lantern, Vector3(-LANE_X, 0, lima.global_position.z + 12.0))

func _point(item: Node3D, target: Vector3) -> void:
	var direction := target - item.global_position
	if direction.length() < .1: return
	item.global_basis = Basis.looking_at(direction.normalized(), Vector3.UP).scaled(item.global_basis.get_scale())

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
	_aim_lanterns()
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
	_round_shoulders(_body(dante))
	_round_shoulders(vicente)
	# Tudo à vista de uma câmera, ainda coberto: chuva, vidro, giroflex, lanterna, porta aberta.
	truck.position = Vector3(LANE_X, 0, TRUCK_STOP_Z)
	truck_door.rotation.y = -1.1
	for index in cars.size(): cars[index].position = Vector3(-LANE_X, 0, -30.0 - index * 7.0)
	lantern.global_position = dante.global_position + Vector3(.2, 1.2, .3)
	# Arma, clarão e atirador entram no desenho coberto (os materiais do clarão compilam aqui).
	dante.weapon.show()
	dante.muzzle_flash_3d.show()
	if is_instance_valid(shooter):
		shooter.position = Vector3(-1.0, 0, 2.0)
		shooter.muzzle_flash_3d.show()
	camera.global_position = Vector3(-2.5, 3.0, 14.0)
	camera.look_at(Vector3(1.0, 1.4, -10.0))
	_follow_rain()
	if _rain_audio.stream != null: _rain_audio.play()
	if not RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.connect(_count_draw)

## Ombro redondo só nos dois irmãos (corpo do kit): a manga começa abaixo do ombro e termina em domo,
## sem a tampa reta que saltava como ombreira quadrada. O kit dos outros NPCs não muda.
func _round_shoulders(body) -> void:
	if not is_instance_valid(body) or body.get("_meshy") != null or body.upper_arms.is_empty(): return
	var kit = load("res://assets/civilians/CivilianMeshKit.gd")
	var profile: Dictionary = kit.build_profile(bool(body.wardrobe.female), int(body.wardrobe.build))
	profile.merge(body.wardrobe.get("body_profile", {}), true)
	var k: float = profile.limb
	var builder = kit._builder()
	var sleeve: int = kit.SLOT_TOP
	builder.loft([[-.02, .046 * k, .048 * k, sleeve], [-.07, .056 * k, .058 * k, sleeve], [-.2, .049 * k, .052 * k, sleeve], [-.3, .045 * k, .048 * k, sleeve]], sleeve, Transform3D.IDENTITY, 12)
	builder.ellipsoid(Vector3(0, -.03, 0), Vector3(.052, .042, .054) * k, sleeve, Basis.IDENTITY, 10, 6)
	builder.ellipsoid(Vector3(0, -kit.UPPER_ARM, 0), Vector3(.042, .045, .044) * k, sleeve, Basis.IDENTITY, 8, 5)
	var mesh: ArrayMesh = builder.commit()
	for arm in body.upper_arms: arm.mesh = mesh

func _count_draw() -> void:
	_warm_draws += 1

func _warm() -> void:
	if DisplayServer.get_name() != "headless" and _warm_draws < WARM_DRAWS: return
	if RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.disconnect(_count_draw)
	truck_door.rotation.y = 0.0
	for car in cars: car.position = Vector3(LANE_X, 0, 900)
	dante.weapon.hide()
	dante.muzzle_flash_3d.hide()
	if is_instance_valid(shooter):
		shooter.muzzle_flash_3d.hide()
		shooter.hide()
		shooter.position = SHOOTER_OUT
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

var _red_lenses: Array[StandardMaterial3D] = []
var _blue_lenses: Array[StandardMaterial3D] = []

## Lentes vermelha e azul da barra: cópias próprias (o material da viatura é compartilhado) para alternar
## com o brilho. Sem VehicleEquipment ficavam as duas acesas o tempo todo.
func _beacon_lenses() -> void:
	for node in police.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null or not original.emission_enabled: continue
			var tint := original.emission
			var red := tint.r > .6 and tint.g < .35 and tint.b < .35
			var blue := tint.b > .6 and tint.r < .35
			if not red and not blue: continue
			var lens := original.duplicate() as StandardMaterial3D
			_retained.append(lens)
			part.set_surface_override_material(surface, lens)
			(_red_lenses if red else _blue_lenses).append(lens)

func _beacons() -> void:
	# Vermelho e azul alternando em pares rápidos, como o giroflex das viaturas.
	var phase := fposmod(stage_time * 2.2, 1.0)
	var red := phase < .5
	var flash := fposmod(stage_time * 8.8, 1.0) < .55
	if _glows.size() == 2:
		_glows[0].visible = red and flash
		_glows[1].visible = not red and flash
	for lens in _red_lenses: lens.emission_energy_multiplier = 2.8 if red and flash else 0.0
	for lens in _blue_lenses: lens.emission_energy_multiplier = 2.8 if not red and flash else 0.0
	if is_instance_valid(halo):
		halo.light_color = Color(1, .15, .12) if red else Color(.2, .38, 1)
		halo.set_meta("budget_energy", 1.5 if flash else .35)
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
	for light in [halo, lantern_light, cab_light] + headlights:
		if not is_instance_valid(light): continue
		lights.append(light)
		# Pela visibilidade do dono: a luz escondida pelo próprio orçamento continua pedindo.
		if light.get_parent().is_visible_in_tree(): wanted.append({"light": light, "headlight": false})
	# "player": a cena é a única coisa na tela; o mundo pausado embaixo não disputa.
	return {"lights": lights, "wanted": wanted, "player": true, "camera": camera.global_position if is_instance_valid(camera) else Vector3.ZERO}

func _face(model: Node3D, direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < .001: return
	# PoliceModel olha para -z (o corpo vai girado em PI dentro dele); o rig civil solto olha para +z.
	if model is POLICE_MODEL: model.rotation.y = atan2(-direction.x, -direction.z)
	else: model.rotation.y = atan2(direction.x, direction.z)

func _forward(model: Node3D) -> Vector3:
	if model is POLICE_MODEL: return -model.global_basis.z.normalized()
	return model.global_basis.z.normalized()

## Base do pescoço do rig (é onde fica a junta "cabeça"; a pose sentada/em pé muda a altura).
## Rosto e boca ficam ~12-14 cm acima: use _eyes para câmera e mãos na cabeça.
func _head(model) -> Vector3:
	var body = _body(model)
	var head = body.get("head_node") if is_instance_valid(body) else null
	if head is Node3D and is_instance_valid(head): return head.global_position
	return model.global_position + Vector3.UP * 1.62

func _eyes(model) -> Vector3:
	return _head(model) + Vector3.UP * .12

## Mão direita de Dante com a lanterna: baixa e livre, ou erguida balançando (`swing` 0..1) para o
## caminhão parar.
func _dante_hands(swing: float) -> void:
	if swing <= .01:
		_hands(dante, null, null)
		return
	var forward := _forward(dante)
	var right := forward.cross(Vector3.UP).normalized()
	var wave := sin(stage_time * 7.0) * .34 * swing
	_hands(dante, dante.global_position + Vector3.UP * (1.2 + .32 * swing) + forward * (.38 + .12 * swing) + right * (.22 + wave), null)

## Vicente ao volante: as duas mãos no aro enquanto está sentado na cabine.
func _vicente_hands() -> void:
	if not is_instance_valid(vicente) or vicente.get_parent() != truck: return
	# No aro (z -3,75): em -3,92 as mãos paravam 10-14 cm antes do volante.
	var center := truck.to_global(Vector3(-.55, 2.02, -3.75))
	var across := truck.global_basis.x.normalized()
	vicente.hand_targets = [center - across * .17, center + across * .17]

func _door_point() -> Vector3:
	return truck.to_global(Vector3(-1.85, 0, -3.4))

func _cab_head() -> Vector3:
	return _head(vicente)

## Olhos de Vicente debruçado no vão da porta: do banco, a linha até o rosto de Dante (mais baixo,
## no asfalto) cortaria a lataria da cabine.
func _cab_lean() -> Vector3:
	return truck.to_global(Vector3(-.95, truck.to_local(_eyes(vicente)).y, -3.3))

func _move_truck(step: float) -> void:
	truck.position.z -= truck_speed * step

## Abre a porta do motorista: chapa girando, som e a luz de teto acendendo.
func _open_door() -> void:
	# Escancarada (86°): meio aberta, a chapa ficava entre o asfalto e o rosto de quem está ao volante.
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(truck_door, "rotation:y", -1.5, 1.0 / pace)
	_play("res://audio/vehicle_fx/door_open_0.wav", -5.0)
	cab_light.set_meta("budget_energy", 1.4)
	if not LIGHT_BUDGET.enabled: cab_light.light_energy = 1.4

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
	_face(dante, Vector3.BACK)
	_dante_heading = dante.rotation.y
	_police_audio.play()
	_police_audio.volume_db = -26.0
	say("dante", "radio_open", func(): say("dante", "colleagues"))

func _nape_camera(step: float, ahead := 6.0, focus_point := Vector3.INF) -> void:
	# Câmera na nuca de Dante: perto, um pouco acima, olhando para onde ele anda (ou para `look_at`).
	var forward := _forward(dante)
	var target: Vector3 = dante.global_position + Vector3.UP * 1.72 - forward * 1.25 + forward.cross(Vector3.UP).normalized() * .32
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-6.0 * step)) if stage_time > .05 else target
	var focus: Vector3 = dante.global_position + Vector3.UP * 1.45 + forward * ahead if not focus_point.is_finite() else focus_point
	_look_smooth(focus, step)

var _focus := Vector3.INF
## A câmera vira para o alvo sem salto (acompanha quem fala e anda).
func _look_smooth(point: Vector3, step: float, rate := 5.0) -> void:
	_focus = point if not _focus.is_finite() else _focus.lerp(point, 1.0 - exp(-rate * step))
	camera.look_at(_focus, Vector3.UP)

func _dante_tick(step: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - step)
	_shake = maxf(0.0, _shake - step * 2.5)
	_vicente_hands()
	match stage:
		"dante_open":
			_traffic(step)
			_dante_hands(_swing)
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
					say("dante", "stopped", func(): say("dante", "approach"))
					_objective_text("walk")
			_engine(camera.global_position.distance_to(truck.global_position))
		"dante_walk":
			_traffic(step)
			_swing = maxf(0.0, _swing - step * 1.5)
			_walk_dante(step)
			_dante_hands(_swing)
			_walk_bastos(step)
			_nape_camera(step, 4.0)
			_engine(camera.global_position.distance_to(truck.global_position))
			var beside := Vector2(dante.global_position.x - DANTE_BESIDE.x, dante.global_position.z - DANTE_BESIDE.z).length() < .6
			if beside and _bastos_leg >= BASTOS_PATH.size():
				_objective.text = ""
				_set_stage("dante_ask")
		"dante_ask": _dante_ask(step)
		"dante_ambush": _dante_ambush(step)
		"dante_fight":
			_aim_tick(step)
			_shooter_tick(step)
			_vicente_crouch()
			if shooter_health <= 0 and stage_time > 1.4:
				say("dante", "flee")
				_objective_text("flee")
				_set_stage("dante_flee")
		"dante_flee":
			_aim_tick(step)
			_vicente_run(step)
		"dante_wounded": _dante_wounded(step)
		"dante_cuff": _dante_cuff(step)
		"dante_black": _dante_black()
	if stage != "dante_black": _engine(camera.global_position.distance_to(truck.global_position) if stage == "dante_open" else 4.0)

func _signal() -> void:
	if signaled or stage != "dante_open": return
	signaled = true
	stage_time = 0.0
	_hide_prompt()

## Faixa de desvio: os carros vêm na faixa da direita, passam para a da esquerda antes dos cavaletes
## (Lima acenando) e voltam depois da viatura.
static func detour_x(z: float) -> float:
	var enter := clampf(inverse_lerp(30.0, 8.0, z), 0.0, 1.0)
	var leave := clampf(inverse_lerp(-26.0, -46.0, z), 0.0, 1.0)
	return lerpf(LANE_X, -LANE_X, smoothstep(0.0, 1.0, enter) * (1.0 - smoothstep(0.0, 1.0, leave)))

func _traffic_near() -> bool:
	for index in cars.size():
		if _car_speed[index] > 0.0 and cars[index].position.z < 70.0 and cars[index].position.z > -20.0: return true
	return false

func _traffic(step: float) -> void:
	for index in cars.size():
		var car := cars[index]
		var start_at := 1.5 + index * 4.5
		if stage == "dante_open" and stage_time > start_at and _beat("car_%d" % index):
			car.position = Vector3(LANE_X, 0, 150.0)
			_car_speed[index] = 15.0
		if _car_speed[index] <= 0.0: continue
		# Reduzem na blitz, desviam dos cavaletes pela faixa da esquerda e seguem.
		var near := car.position.z < 45.0 and car.position.z > -30.0
		_car_speed[index] = move_toward(_car_speed[index], 5.5 if near else 15.0, step * 5.0)
		var z := car.position.z - _car_speed[index] * step
		var x := detour_x(z)
		var ahead := Vector3(detour_x(z - 1.0) - x, 0, -1.0)
		car.position = Vector3(x, 0, z)
		car.rotation.y = atan2(-ahead.x, -ahead.z)
		if z < -320.0:
			_car_speed[index] = 0.0
			car.hide()

func _walk_bastos(step: float) -> void:
	if _bastos_leg >= BASTOS_PATH.size():
		_face(bastos, _door_point() - bastos.global_position)
		return
	var goal: Vector3 = BASTOS_PATH[_bastos_leg]
	var offset := goal - bastos.global_position
	offset.y = 0.0
	if offset.length() < .08:
		_bastos_leg += 1
		return
	bastos.global_position += offset.normalized() * minf(offset.length(), 1.45 * step)
	_face(bastos, offset)
	_hands(bastos, null, null)

func _walk_dante(step: float) -> void:
	var input := Vector2.ZERO
	if autoplay:
		var offset: Vector3 = DANTE_BESIDE - dante.global_position
		# Contorna a frente do caminhão pela esquerda, como Bastos.
		if dante.global_position.z < -10.3 and dante.global_position.x > -.6: offset = Vector3(-.9, 0, -10.6) - dante.global_position
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
	var heading := atan2(-velocity.x, -velocity.z)
	_dante_heading = lerp_angle(_dante_heading, heading, 1.0 - exp(-8.0 * step))
	dante.rotation.y = _dante_heading

## Bastos bate no vidro e pede para descer; a câmera, da nuca de Dante, vira acompanhando ele.
func _dante_ask(step: float) -> void:
	_face(dante, _door_point() + Vector3(0, 0, -.6) - dante.global_position)
	# De frente para a chapa da porta.
	_face(bastos, truck.global_basis.x)
	var glass := truck.to_global(Vector3(-1.2, 2.35, -3.25))
	if _beat("ask_line"): say("dante", "ask")
	# Os nós dos dedos na porta, na altura do ombro dele, três batidas (o vidro fica alto demais).
	var knock := stage_time < 1.4
	var tap := .05 * maxf(0.0, sin(stage_time * 14.0))
	_hands(bastos, truck.to_global(Vector3(-1.25 - tap, 1.62, -3.8)) if knock else null, null)
	if stage_time < 3.2:
		_nape_camera(step, 3.0, _head(bastos).lerp(glass, smoothstep(.2, 1.4, stage_time) * .6))
		return
	if _beat("door_opens"): _open_door()
	if stage_time < 4.2:
		_nape_camera(step, 3.0, glass)
		return
	# Close no rosto de Vicente: ele vê Dante atrás do policial.
	var head := _eyes(vicente)
	if _beat("face_close"):
		vicente.activity = "talk"
		camera.fov = 40.0
		# Pelo vão da porta aberta, à frente dele e fora da cabine, quase na altura do rosto (mais baixa, o
		# painel cortava o quadro e se via a nuca).
		camera.global_position = truck.to_global(Vector3(-1.55, truck.to_local(head).y - .05, -3.62))
		camera.look_at(head, Vector3.UP)
	if stage_time > 4.8 and _beat("vicente_line"): say("dante", "door")
	if stage_time > 7.6 and _beat("step_down"):
		# Bastos olha de um para o outro; Vicente desce com as mãos à vista.
		vicente.activity = ""
		camera.fov = 55.0
		_focus = Vector3.INF
		vicente.reparent(_set)
		vicente.sit_amount = 0.0
		vicente.global_position = _door_point() + Vector3(.3, 0, .15)
		_face(vicente, Vector3.LEFT)
		say("dante", "order_out")
	if stage_time > 7.6:
		_nape_camera(step, 3.0, _eyes(vicente).lerp(_eyes(bastos), .35))
		# Mãos ao alto, abertas acima da cabeça (com a junta do pescoço como cabeça, iam às orelhas).
		var neck := _head(vicente)
		var side := _forward(vicente).cross(Vector3.UP).normalized()
		var front := _forward(vicente) * .06
		vicente.hand_targets = [neck + Vector3.UP * .4 + side * .27 + front, neck + Vector3.UP * .4 - side * .27 + front]
	if stage_time > 10.4: _set_stage("dante_ambush")

## Tiros do lado do passageiro: Bastos cai, Dante saca e vai para o abrigo.
func _dante_ambush(step: float) -> void:
	if _beat("shooter_out"):
		# Sai pelo lado do passageiro, arma na mão: Dante vê primeiro e grita.
		shooter.show()
		shooter.global_position = SHOOTER_OUT
		say("dante", "ambush")
		_play("res://audio/weapons_fire/gun_draw_0.wav", -4.0)
		dante.weapon.show()
		lantern.hide()
	# Contorna a grade até ter linha; o primeiro tiro é em Bastos, na porta.
	shooter.global_position = shooter.global_position.move_toward(SHOOTER_EXPOSED, 3.4 * step)
	var first_target: Vector3 = bastos.global_position if not _beats.has("first_shot") else dante.global_position
	_face(shooter, first_target - shooter.global_position)
	if shooter.global_position.distance_to(SHOOTER_EXPOSED) < .3 and _beat("first_shot"):
		_enemy_shot()
		_kill(bastos, (bastos.global_position - shooter.global_position).normalized())
		_shake = .5
		say("dante", "man_down")
		_shot_clock = stage_time
	shooter.update_pose(step, true, false, 0.0, 0.0)
	var cover: Vector3 = dante.global_position.move_toward(DANTE_COVER, 2.6 * step)
	dante.global_position = cover
	_vicente_crouch()
	var toward: Vector3 = SHOOTER_EXPOSED + Vector3.UP * 1.3 - (dante.global_position + Vector3.UP * 1.6)
	aim_yaw = atan2(-toward.x, -toward.z) + .12
	aim_pitch = asin(clampf(toward.normalized().y, -1.0, 1.0))
	dante.update_pose(step, true, false, 0.0, 0.0)
	_aim_camera(step)
	if _beats.has("first_shot") and stage_time - _shot_clock > .7:
		_shooter_exposed = true
		_shooter_clock = 1.6
		_objective_text("fight")
		_show_fire_prompt()
		_set_stage("dante_fight")
		_capture_mouse(true)

func _vicente_crouch() -> void:
	# Agachado atrás da porta aberta, mãos na cabeça.
	vicente.global_position = vicente.global_position.move_toward(_door_point() + Vector3(.35, 0, .55), .05)
	vicente.sit_amount = move_toward(vicente.sit_amount, .55, .05)
	var neck := _head(vicente)
	var side := _forward(vicente).cross(Vector3.UP).normalized()
	var back := _forward(vicente) * .02
	vicente.hand_targets = [neck + Vector3.UP * .27 + side * .07 - back, neck + Vector3.UP * .27 - side * .07 - back]

# --- Tiroteio ----------------------------------------------------------------------------------------

func _aim_dir() -> Vector3:
	return (Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, aim_pitch)) * Vector3.FORWARD

## Por cima do ombro direito; o corpo de Dante gira com a mira e o PoliceModel põe as duas mãos na arma.
func _aim_camera(step: float) -> void:
	var direction := _aim_dir()
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	var right := flat.cross(Vector3.UP).normalized()
	var target: Vector3 = dante.global_position + Vector3.UP * 1.68 + right * .55 - flat * 1.55
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-12.0 * step))
	camera.fov = move_toward(camera.fov, 50.0, step * 20.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * .03
	camera.look_at(camera.global_position + direction + jitter, Vector3.UP)
	dante.rotation.y = aim_yaw

func _aim_tick(step: float) -> void:
	var target := _current_target()
	if autoplay and target != null:
		var toward: Vector3 = target.global_position + Vector3.UP * 1.15 - camera.global_position
		aim_yaw = lerp_angle(aim_yaw, atan2(-toward.x, -toward.z), 1.0 - exp(-10.0 * step))
		aim_pitch = lerpf(aim_pitch, asin(clampf(toward.normalized().y, -1.0, 1.0)), 1.0 - exp(-10.0 * step))
		var exposed: bool = target != shooter or _shooter_visible()
		_want_fire = exposed and _fire_cooldown <= 0.0 and stage_time > (.4 if target == shooter else 1.8)
	else:
		aim_yaw -= Input.get_axis("camera_left", "camera_right") * 2.2 * step if InputMap.has_action("camera_left") else 0.0
	aim_pitch = clampf(aim_pitch, -.6, .5)
	dante.update_pose(step, true, false, 0.0, 0.0)
	_aim_camera(step)
	if _want_fire or (not autoplay and Input.is_action_pressed("fire") and _fire_cooldown <= 0.0):
		_want_fire = false
		_fire()

func _current_target() -> Node3D:
	if stage == "dante_fight" and shooter_health > 0: return shooter
	if stage == "dante_flee" and not vicente_hit: return vicente
	return null

func _shooter_visible() -> bool:
	return is_instance_valid(shooter) and shooter_health > 0 and _truck_hit(camera.global_position, (shooter.global_position + Vector3.UP * 1.2 - camera.global_position).normalized()) > camera.global_position.distance_to(shooter.global_position + Vector3.UP * 1.2)

func _fire() -> void:
	if _fire_cooldown > 0.0: return
	_fire_cooldown = .26
	shots_fired += 1
	dante.attack()
	_shot_audio(-1.0)
	var origin := camera.global_position
	var direction := -camera.global_basis.z.normalized()
	var wall := _truck_hit(origin, direction)
	var target := _current_target()
	if target == null: return
	var distance := capsule_hit(origin, direction, target.global_position, .4 if target == shooter else .36, 1.75 if target == shooter else (1.75 - .7 * vicente.sit_amount))
	if distance < 0.0 or distance > wall:
		if wall < INF: _play_at_volume("res://audio/weapons_fire/ricochet_%d.wav" % (shots_fired % 4), -10.0)
		return
	_play_at_volume("res://audio/body_impacts/body_hit_%d.wav" % (shots_fired % 3), -6.0)
	if target == shooter:
		shooter_hits += 1
		shooter_health -= 1
		if shooter_health > 0:
			FALL.apply_hit(shooter, shooter, direction, 26.0)
			# Ferido, ele se esconde antes da próxima rajada.
			if shooter_hits % 3 == 0: _shooter_exposed = false
		else:
			_kill(shooter, direction)
			stage_time = 0.0
			say("dante", "shooter_down")
	elif target == vicente:
		vicente_hit = true
		_capture_mouse(false)
		_crosshair.hide()
		_hide_prompt()
		_objective.text = ""
		vicente.take_hit(direction, .9)
		_set_stage("dante_wounded")

## Morte como a do jogo: solta as mãos, a arma cai da mão até o asfalto e o corpo toca o clipe de morte do
## Mixamo (o lado sai do empurrão do tiro). Sem a biblioteca, a queda procedural.
func _kill(model: Node3D, direction: Vector3) -> void:
	FALL._release_hands(model)
	_drop_gun(model)
	var marker := CORPSE.new()
	model.add_child(marker)
	if not MIXAMO_DEATH.play(marker, model, direction): FALL.apply_fall(model, model, direction)
	_play_at_volume("res://audio/body_impacts/body_land_%d.wav" % randi_range(0, 2), -8.0)

## A arma sai da mão: cai girando, quica uma vez e fica deitada no asfalto.
func _drop_gun(model: Node3D) -> void:
	var gun = model.get("weapon")
	if not gun is Node3D or not is_instance_valid(gun) or not gun.visible: return
	var flash = model.get("muzzle_flash_3d")
	if flash is Node3D: flash.hide()
	gun.reparent(_set, true)
	var start: Transform3D = gun.global_transform
	var scale_kept := start.basis.get_scale()
	var land := Vector3(start.origin.x, .03, start.origin.z) + _forward(model) * .3 + Vector3(randf_range(-.15, .15), 0, randf_range(-.15, .15))
	var rest := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * .5)
	var from_rotation := start.basis.orthonormalized().get_rotation_quaternion()
	var to_rotation := rest.get_rotation_quaternion()
	var fall := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fall.tween_method(func(t: float):
		if not is_instance_valid(gun): return
		# Queda com gravidade até o chão (70% do tempo) e um quique baixo.
		var drop := clampf(t / .7, 0.0, 1.0)
		var bounce := sin(clampf((t - .7) / .3, 0.0, 1.0) * PI) * .07 if t > .7 else 0.0
		var height := lerpf(start.origin.y, land.y, drop * drop) + bounce
		var flat := start.origin.lerp(land, minf(1.0, t * 1.2))
		var turn := from_rotation.slerp(to_rotation, smoothstep(0.0, .85, t))
		gun.global_transform = Transform3D(Basis(turn).scaled(scale_kept), Vector3(flat.x, height, flat.z))
	, 0.0, 1.0, .55 / pace)
	fall.tween_callback(func(): _play_at_volume("res://audio/weapons_fire/gun_holster_2.wav", -10.0))

## Raio contra a cápsula de um corpo em pé (base nos pés). Devolve a distância até o acerto ou -1.
static func capsule_hit(origin: Vector3, direction: Vector3, base: Vector3, radius: float, height: float) -> float:
	var points := Geometry3D.get_closest_points_between_segments(origin, origin + direction * 90.0, base + Vector3.UP * .3, base + Vector3.UP * maxf(.35, height - .2))
	if points[0].distance_to(points[1]) > radius: return -1.0
	return origin.distance_to(points[0])

## O caminhão para bala: distância até a caixa dele ao longo do raio (INF se passa livre).
func _truck_hit(origin: Vector3, direction: Vector3) -> float:
	var inverse := truck.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var hit: Variant = AABB(Vector3(-1.3, 0, -5.75), Vector3(2.6, 3.9, 11.5)).intersects_ray(local_origin, inverse.basis * direction)
	return INF if hit == null else local_origin.distance_to(hit)

func _shooter_tick(step: float) -> void:
	if not is_instance_valid(shooter) or shooter_health <= 0: return
	_shooter_clock -= step
	if _shooter_clock <= 0.0:
		_shooter_exposed = not _shooter_exposed
		_shooter_clock = 2.2 if _shooter_exposed else 1.3
	var goal := SHOOTER_EXPOSED if _shooter_exposed else SHOOTER_HIDDEN
	shooter.global_position = shooter.global_position.move_toward(goal, 2.6 * step)
	_face(shooter, dante.global_position - shooter.global_position)
	shooter.update_pose(step, true, false, 0.0, 0.0)
	if shooter.global_position.distance_to(SHOOTER_EXPOSED) < .35:
		_shooter_fire_clock -= step
		if _shooter_fire_clock <= 0.0:
			_shooter_fire_clock = randf_range(.5, .8)
			_enemy_shot()

func _enemy_shot() -> void:
	shooter.attack()
	_play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % randi_range(0, 3), -3.0)
	_play_at_volume("res://audio/weapons_fire/bullet_whiz_%d.wav" % randi_range(0, 3), -8.0)
	_shake = maxf(_shake, .25)

func _shot_audio(volume: float) -> void:
	_play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % (shots_fired % 4), volume)

## Tiros e impactos se sobrepõem: cada um num tocador próprio que some ao terminar.
func _play_at_volume(path: String, volume: float) -> void:
	var stream := _sound(path)
	if stream == null: return
	var player := _player("SFX", stream, volume)
	player.finished.connect(player.queue_free)
	player.play()

func _show_fire_prompt() -> void:
	var game_input := get_node_or_null("/root/GameInput")
	var hint: String = game_input.prompt("fire") if game_input != null else "—"
	if hint == "—": hint = "Mouse"
	_prompt.text = "[%s] %s" % [hint, text(lines().get("prompts", {}).get("fire"))]
	_crosshair.show()

func _capture_mouse(value: bool) -> void:
	if DisplayServer.get_name() == "headless": return
	if value and not _mouse_owned:
		_previous_mouse = Input.mouse_mode
		_mouse_owned = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not value and _mouse_owned:
		_mouse_owned = false
		Input.mouse_mode = _previous_mouse

## Vicente corre pela pista escura; se chega ao fim, para e olha para trás (ainda dá para alcançar).
func _vicente_run(step: float) -> void:
	vicente.sit_amount = move_toward(vicente.sit_amount, 0.0, step * 3.0)
	vicente.hand_targets = [null, null]
	if _flee_leg >= VICENTE_FLEE.size():
		_face(vicente, dante.global_position - vicente.global_position)
		return
	var goal: Vector3 = VICENTE_FLEE[_flee_leg]
	var offset: Vector3 = goal - vicente.global_position
	offset.y = 0.0
	if offset.length() < .1:
		_flee_leg += 1
		return
	vicente.global_position += offset.normalized() * minf(offset.length(), 3.4 * step)
	_face(vicente, offset)

## Vicente cai sentado segurando a coxa; Prado no rádio; Dante vai até ele, guarda a arma e se agacha.
func _dante_wounded(step: float) -> void:
	# As pernas falham primeiro (agacha) e depois ele senta no asfalto.
	vicente.sit_amount = move_toward(vicente.sit_amount, 1.0, step * 1.3)
	vicente.seat_height = lerpf(.45, .16, smoothstep(.5, 1.0, vicente.sit_amount))
	var forward := _forward(vicente)
	var side := forward.cross(Vector3.UP).normalized()
	var thigh: Vector3 = vicente.global_position + forward * .3 + Vector3.UP * .3 - side * .1
	vicente.hand_targets = [thigh + side * .05, thigh - side * .07 + forward * .06]
	if _beat("procedure"): say("dante", "order")
	# A 0,85 m: de 1 m, agachado, as mãos dele paravam 30 cm antes dos pulsos.
	var stand: Vector3 = vicente.global_position + forward * .85
	var offset: Vector3 = stand - dante.global_position
	offset.y = 0.0
	if offset.length() > .05:
		dante.global_position += offset.normalized() * minf(offset.length(), 1.3 * step)
	_face(dante, vicente.global_position - dante.global_position)
	dante.update_pose(step, offset.length() > .4, false, 0.0, 0.0)
	# De lado, os dois no quadro: atrás da nuca, Dante tapava Vicente sentado no chão.
	var middle: Vector3 = (dante.global_position + vicente.global_position) * .5
	var across: Vector3 = (vicente.global_position - dante.global_position).cross(Vector3.UP).normalized()
	var side_view: Vector3 = middle + across * 2.6 + Vector3.UP * 1.25
	camera.global_position = camera.global_position.lerp(side_view, 1.0 - exp(-3.0 * step)) if stage_time > .05 else side_view
	_look_smooth(middle + Vector3.UP * .8, step)
	if offset.length() <= .05 and stage_time > 3.2 and not speaking():
		_play("res://audio/weapons_fire/gun_holster_1.wav", -6.0)
		dante.weapon.hide()
		_set_stage("dante_cuff")
		_objective_text("cuff")
		_show_prompt("cuff")
		_progress.value = 0.0
		_progress.show()

## Pulsos de Vicente juntos à frente, sobre o colo.
func _wrists() -> Vector3:
	return vicente.global_position + _forward(vicente) * .4 + Vector3.UP * .42

func _dante_cuff(step: float) -> void:
	var holding := autoplay or Input.is_action_pressed("interact")
	# Segurar demora; soltar devolve devagar. Não existe outro comando.
	cuff_progress = clampf(cuff_progress + (step / HOLD_SECONDS if holding else -step * .4), 0.0, 1.0)
	_progress.value = cuff_progress
	var wrists := _wrists()
	var across := _forward(vicente).cross(Vector3.UP).normalized()
	vicente.hand_targets = [wrists - across * .05, wrists + across * .05]
	# Dante agacha na frente dele; as mãos vão aos pulsos (direita por cima, esquerda segurando).
	var body = _body(dante)
	if is_instance_valid(body):
		body.sit_amount = move_toward(body.sit_amount, .8, step * 2.0)
		body.seat_height = .25
	var reach := smoothstep(0.0, .5, cuff_progress)
	if reach > .01:
		var rest: Vector3 = dante.global_position + Vector3.UP * .55 + _forward(dante) * .25
		var grip: Vector3 = rest.lerp(wrists, reach)
		_hands(dante, grip + Vector3.UP * .05 - across * .04, grip - Vector3.UP * .02 + across * .05)
	else:
		_hands(dante, null, null)
	# A câmera sai da nuca e fecha nas mãos conforme o botão é segurado.
	var forward := _forward(dante)
	var nape: Vector3 = dante.global_position + Vector3.UP * 1.45 - forward * 1.0 + forward.cross(Vector3.UP).normalized() * .35
	var close := wrists + Vector3.UP * .35 + across * .55 - _forward(vicente) * .35
	var k := smoothstep(0.0, 1.0, cuff_progress)
	camera.global_position = nape.lerp(close, k)
	camera.fov = lerpf(55.0, 40.0, k)
	camera.look_at(_head(vicente).lerp(wrists, k), Vector3.UP)
	if cuff_progress >= 1.0:
		_play("res://audio/weapons_fire/gun_holster_0.wav", -2.0)
		_cut_to_black()
		_set_stage("dante_black")

func _cut_to_black() -> void:
	# Corte seco: sem fade, a chuva e o motor somem junto com a imagem.
	curtain.color.a = 1.0
	if is_instance_valid(_crosshair): _crosshair.hide()
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
	# Alta e à esquerda: atrás do baú (3,8 m) a pista e o facho dos faróis ficavam escondidos.
	var target := truck.to_global(Vector3(-2.4, 5.6, 12.5))
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-4.0 * step)) if stage_time > .05 else target
	camera.look_at(truck.to_global(Vector3(-.4, .8, -24.0)), Vector3.UP)

func _vicente_tick(step: float) -> void:
	_dante_hands(_swing)
	_vicente_hands()
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
				_open_door()
				_set_stage("vicente_face")
		"vicente_face":
			_engine(3.0)
			# O rosto de Dante pela porta aberta, de cima, do banco do motorista.
			var face := _eyes(dante)
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
	camera.look_at(_eyes(dante) - Vector3.UP * .1, Vector3.UP)

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
	if stage in ["dante_fight", "dante_flee"] and not autoplay:
		if event is InputEventMouseMotion:
			aim_yaw -= event.relative.x * .0028
			aim_pitch -= event.relative.y * .0028
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("fire"):
			_want_fire = _fire_cooldown <= 0.0

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
	_capture_mouse(false)
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.unregister(self)
	if RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.disconnect(_count_draw)
	if not _owns_world: return
	_owns_world = false
	if is_instance_valid(_main_viewport): _main_viewport.disable_3d = _previous_3d
	if is_inside_tree(): get_tree().paused = _previous_pause

func _exit_tree() -> void:
	_release_world()
