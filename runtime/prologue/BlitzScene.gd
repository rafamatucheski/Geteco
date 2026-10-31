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
const BROTHER := preload("res://runtime/prologue/BlitzBrother.gd")
const CREW_OUTFIT := preload("res://runtime/desert/drag_meet/DragMeetWardrobe.gd")
const OPEN_TRUCK := preload("res://runtime/prologue/BlitzTruck.gd")
const CORPSE := preload("res://runtime/prologue/BlitzCorpse.gd")
const COLLEAGUE := preload("res://runtime/prologue/BlitzColleague.gd")
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")
const LOOK := preload("res://runtime/prologue/BlitzLook.gd")
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
## A prisão e o quarto de oito anos depois ficam longe da pista, no mesmo mundo; cada um só aparece no seu
## plano (escondidos, as luzes deles nem pedem vaga ao orçamento).
const PRISON := Vector3(700, 0, 0)
const ROOM := Vector3(-700, 0, 0)
## Porta de trás da viatura (lado esquerdo, frente -z do modelo) e Lima atrás do baú do caminhão parado.
const CAR_DOOR_LOCAL := Vector3(-1.35, 0, .55)
const CAR_DRIVER_LOCAL := Vector3(-1.35, 0, -.65)
const LIMA_CARGO := Vector3(1.8, 0, 3.4)
## Abrigo de Lima no tiroteio: atrás da viatura, com o carro entre ele e o atirador.
const LIMA_COVER := Vector3(6.15, 0, -16.7)
const VICENTE_FLEE := [Vector3(-.4, 0, -5.4), Vector3(-3.1, 0, 2.0), Vector3(-3.4, 0, 13.0)]
const WARM_DRAWS := 4
const CIVILIAN_MESH_KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
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
var passenger_door: Node3D
var _shooter_leg := 0
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
## Quadril de Vicente sentado no asfalto, ferido (mundo).
var _ground_seat := Vector3.ZERO
var _environment: Environment
var _prison: Node3D
var _room: Node3D
var _gate: Array[Node3D] = []
var _flood: SpotLight3D
var _set_lights: Array[Light3D] = []
var letter: MeshInstance3D
var _police_speed := 0.0
var _clock := 0.0
var _ready_ambush := -1.0
var _lima_clock := 0.0
var _lima_fire := 1.0
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
	_steps = [_build_environment, _build_road, _build_roadside, _build_police, _build_truck, _build_cast, _build_colleagues, _build_traffic, _build_prison, _build_room, _build_rain, _build_audio]
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
	environment.ambient_light_energy = .45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("0b1220")
	environment.fog_density = .03
	# A câmera do jogo fica a ~36 m do foco: a névoa começa depois disso e apaga o fim da estrada.
	environment.fog_depth_begin = 32.0
	environment.fog_depth_end = 150.0
	environment.glow_enabled = true
	environment.glow_intensity = .7
	environment.glow_bloom = .05
	_environment = environment
	var world := WorldEnvironment.new()
	world.environment = environment
	_set.add_child(world)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("8fa7c6")
	moon.light_energy = .32
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
	# Textura e detalhe de superfície por chave (BlitzLook), uma vez, sob a cortina.
	LOOK.dress(material)
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
	# De cima a câmera vê mais mato que pista: verde-escuro com valor, não preto.
	var verge := _material("blitz_verge", Color("26301f"), .92, .2)
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

## Mesma malha repetida (árvores, guarda-corpo): uma chamada de desenho por tipo, escala por instância.
func _instances(mesh: PrimitiveMesh, material: Material, transforms: Array[Transform3D], shadows := false) -> void:
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set.add_child(node)

## Beira da rodovia: de cima, sem isto a pista era uma faixa num vazio preto. Mato alto e árvores dos dois
## lados (sorteio fixo) e guarda-corpo metálico com postes.
func _build_roadside() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var crowns: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	for index in 170:
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(9.5, 36.0)
		var z := rng.randf_range(-180.0, 180.0)
		var size := rng.randf_range(2.4, 5.0)
		crowns.append(Transform3D(Basis.from_scale(Vector3(size, size * rng.randf_range(.8, 1.15), size)), Vector3(x, 1.5 + size * .45, z)))
		trunks.append(Transform3D(Basis.from_scale(Vector3(.22, 1.9, .22)), Vector3(x, .95, z)))
	for index in 260:
		var side := -1.0 if index % 2 == 0 else 1.0
		var size := rng.randf_range(.6, 1.5)
		bushes.append(Transform3D(Basis.from_scale(Vector3(size * 1.4, size * .7, size * 1.2)), Vector3(side * rng.randf_range(7.4, 40.0), size * .25, rng.randf_range(-180.0, 180.0))))
	var crown := SphereMesh.new()
	crown.radius = .5
	crown.height = 1.0
	crown.radial_segments = 10
	crown.rings = 6
	_instances(crown, _material("blitz_tree", Color("1f2b1b"), .95, .15), crowns, true)
	_instances(BoxMesh.new(), _material("blitz_trunk", Color("2b231b"), .95, .1), trunks)
	var bush := SphereMesh.new()
	bush.radius = .5
	bush.height = 1.0
	bush.radial_segments = 8
	bush.rings = 4
	_instances(bush, _material("blitz_bush", Color("29331f"), .95, .1), bushes)
	var rails: Array[Transform3D] = []
	var rail_posts: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		rails.append(Transform3D(Basis.from_scale(Vector3(.06, .3, 360.0)), Vector3(side * 6.95, .62, 0)))
		for index in 90: rail_posts.append(Transform3D(Basis.from_scale(Vector3(.1, .7, .1)), Vector3(side * 7.02, .35, -178.0 + index * 4.0)))
	var steel := _material("blitz_rail", Color("7d8287"), .45, .6)
	_instances(BoxMesh.new(), steel, rails)
	_instances(BoxMesh.new(), steel, rail_posts)

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
	# A do passageiro, espelhada: abre para fora do lado direito.
	passenger_door = Node3D.new()
	passenger_door.name = "BlitzPassengerDoor"
	passenger_door.position = Vector3(1.16, 2.0, -3.96)
	truck.add_child(passenger_door)
	_box(passenger_door, Vector3(0, -.52, .56), Vector3(.05, 1.08, 1.1), _material("blitz_truck_paint", TRUCK_PAINT, .45, .5))
	_box(passenger_door, Vector3(0, .5, .56), Vector3(.03, .72, 1.02), _material("blitz_truck_glass", Color(.32, .4, .45, .35), .05, .9))
	_box(passenger_door, Vector3(.04, -.1, .95), Vector3(.05, .05, .18), _material("blitz_truck_handle", Color("9a9c9e"), .3, .7))
	_light_truck()
	var cardboard := _material("blitz_cardboard", Color("b08a5c"), .9, .2)
	for part in truck.find_children("Freight_case", "MeshInstance3D", true, false): (part as MeshInstance3D).material_override = cardboard
	TRUCK.set_loot_visible(truck, false)
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
	# O irmão: o mesmo dante.glb, com a roupa, o cabelo e os acessórios dele (BlitzBrother), ao volante.
	vicente = BROTHER.new()
	vicente.identity_id = "vicente"
	vicente.name = "VicenteYoung"
	truck.add_child(vicente)

## Lentes acesas: no jogo quem acende é o VehicleEquipment; aqui o caminhão é só o modelo, então as
## lentes ganham cópias emissivas próprias (retidas) e brilho de lente como o das viaturas. O material
## compartilhado do caminhão de carga do deserto não é tocado.
func _light_truck() -> void:
	# Vidros translúcidos: de dentro da cabine (flashback) Vicente vê a pista e o irmão chegando.
	var glass := truck.find_child("Freight_glass", true, false) as MeshInstance3D
	if glass != null: glass.material_override = _material("blitz_truck_cab_glass", Color(.2, .27, .31, .32), .06, .9)
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

## Colega com as mãos do Dante no corpo da patrulha (BlitzColleague).
func _colleague(node_name: String, appearance: int, body: String, point: Vector3, facing: Vector3) -> Node3D:
	var officer: Node3D = COLLEAGUE.new()
	officer.body_path = "res://assets/prologue/police/%s.glb" % body
	officer.name = node_name
	officer.appearance_index = appearance
	officer.position = point
	_set.add_child(officer)
	_face(officer, facing)
	return officer

func _build_cast() -> void:
	# O Dante do jogo (dante.glb, BlitzBrother) de farda: rosto, mãos, caminhada e pegada de pistola do
	# jogador, conduzido como marionete pela cena.
	dante = BROTHER.new()
	dante.identity_id = "dante"
	dante.name = "DanteYoung"
	dante.position = DANTE_POST
	_set.add_child(dante)
	_face(dante, Vector3.BACK)
	dante.equip("pistol")
	lantern = _lantern_node("BlitzLantern", true)
	_set.add_child(lantern)

func _build_colleagues() -> void:
	bastos = _colleague("BlitzBastos", 3, "patrol_heavy_hands", Vector3(3.75, 0, -14.9), Vector3(-1, 0, .35))
	lima = _colleague("BlitzLima", 6, "patrol_m_hands", Vector3(2.9, 0, -14.3), Vector3.BACK)
	# A pistola dele fica no coldre até a emboscada.
	if pov == "dante":
		lima.equip("pistol")
		lima.weapon.hide()
	colleagues.assign([bastos, lima])
	colleague_lantern = _lantern_node("BlitzColleagueLantern", false)
	_set.add_child(colleague_lantern)
	bastos_radio = Node3D.new()
	bastos_radio.name = "BlitzRadio"
	_box(bastos_radio, Vector3(0, 0, -.02), Vector3(.06, .035, .12), _material("blitz_radio", Color("1b1c1e"), .55, .3))
	_set.add_child(bastos_radio)
	# O Rato vai no banco do passageiro nas duas versões da noite (no flashback ele só fica ali).
	shooter = COBRA_MODEL.new()
	shooter.name = "BlitzShooter"
	# Desde o começo no banco do passageiro, pistola escondida: ninguém olhou para ele.
	shooter.seated = true
	shooter.seat_armed = true
	# Sem sorteio de aparência: a roupa padrão da gangue, para ler "Cobra" à primeira vista.
	shooter.cobra_uniform = true
	shooter.position = Vector3(.55, 1.15, -3.35)
	truck.add_child(shooter)
	# Biblioteca dos clipes de morte, sob a cortina (só o prólogo tem mortes).
	if pov == "dante": MIXAMO_DEATH.library()

## Prende um objeto na palma: filho do antebraço do rig, na ponta (onde o IK põe a mão). Assim a lanterna,
## o rádio e a algema andam com a mão de verdade, em vez de flutuar perto dela.
func _hold(model, index: int, item: Node3D) -> bool:
	if model.has_method("blitz_hold_item"): return model.blitz_hold_item(item)
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

func _set_light(light: Light3D, parent: Node3D, energy: float) -> void:
	light.shadow_enabled = false
	light.set_meta("budget_energy", energy)
	light.light_energy = energy
	parent.add_child(light)
	_set_lights.append(light)

## A prisão para onde a viatura leva Vicente: muralha de concreto com portão de aço, duas guaritas com
## holofote, blocos de celas com janelas acesas, postes na via de acesso. Só no prólogo.
func _build_prison() -> void:
	if pov != "dante": return
	_prison = Node3D.new()
	_prison.name = "BlitzPrison"
	_prison.position = PRISON
	_prison.hide()
	_set.add_child(_prison)
	var concrete := _material("blitz_concrete", Color("6d6c66"), .92, .3)
	var dark := _material("blitz_gate_steel", Color("2c3034"), .5, .6)
	var window := _material("blitz_prison_window", Color("e8c98e"), .4, .3, Color("e2b866"))
	_box(_prison, Vector3(0, -.03, -20), Vector3(260, .06, 260), _material("blitz_gravel", Color("2e2f2c"), .95, .2))
	_box(_prison, Vector3(1.8, -.01, 40), Vector3(8, .06, 110), _material("blitz_wet_asphalt", Color("202327"), .32, .5))
	for x in [-24.0, 24.0]: _box(_prison, Vector3(x, 3.5, -10), Vector3(40, 7, .7), concrete)
	for x in [-44.0, 44.0]: _box(_prison, Vector3(x, 3.5, -45), Vector3(.7, 7, 70), concrete)
	_box(_prison, Vector3(0, 3.5, -80), Vector3(88, 7, .7), concrete)
	for x in [-24.0, 24.0]: _box(_prison, Vector3(x, 7.25, -10), Vector3(40, .5, .9), dark)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * 2.0, 0, -10)
		_prison.add_child(leaf)
		_box(leaf, Vector3(0, 3.0, 0), Vector3(4.0, 6.0, .25), dark)
		_gate.append(leaf)
	_box(_prison, Vector3(-8, 2, -6), Vector3(5, 4, 4), concrete)
	_box(_prison, Vector3(-8, 2.2, -3.98), Vector3(2.2, 1, .05), window)
	for x in [-44.0, 44.0]:
		_box(_prison, Vector3(x, 5, -10), Vector3(2.2, 10, 2.2), concrete)
		_box(_prison, Vector3(x, 11.3, -10), Vector3(4, 2.6, 4), concrete)
		_box(_prison, Vector3(x, 11.4, -7.97), Vector3(3, .9, .05), window)
	for spec in [[Vector3(-14, 6, -40), Vector3(30, 12, 14)], [Vector3(18, 9, -52), Vector3(26, 18, 12)]]:
		_box(_prison, spec[0], spec[1], concrete)
		var rows := int(spec[1].y / 3.0)
		for row in rows:
			for column in int(spec[1].x / 3.0):
				if (row * 7 + column * 3) % 5 == 0: continue
				_box(_prison, spec[0] + Vector3(-spec[1].x * .5 + 1.5 + column * 3.0, -spec[1].y * .5 + 1.6 + row * 3.0, spec[1].z * .5 + .02), Vector3(.7, .9, .05), window)
	for z in [0.0, 15.0, 30.0, 45.0, 60.0]:
		_box(_prison, Vector3(6.8, 3.5, z), Vector3(.18, 7, .18), dark)
		_box(_prison, Vector3(6.0, 7.0, z), Vector3(1.6, .14, .4), window)
	_flood = SpotLight3D.new()
	_flood.name = "BlitzPrisonFlood"
	_flood.position = Vector3(44, 12.6, -8)
	_flood.light_color = Color("dfe8ff")
	_flood.spot_range = 70.0
	_flood.spot_angle = 14.0
	_flood.rotation = Vector3(-.32, -.35, 0)
	_set_light(_flood, _prison, 6.0)
	var gate_lamp := OmniLight3D.new()
	gate_lamp.position = Vector3(0, 6.6, -8.4)
	gate_lamp.light_color = Color("ffcf8c")
	gate_lamp.omni_range = 16.0
	_set_light(gate_lamp, _prison, 2.2)

## O quarto de oito anos depois, alugado e sem vida: cama de solteiro desfeita, caixas da mudança que nunca
## foram abertas, a jaqueta na cadeira, garrafa no chão, a foto dos dois irmãos na mesa, janela de chuva.
func _build_room() -> void:
	if pov != "dante": return
	_room = Node3D.new()
	_room.name = "BlitzRoom"
	_room.position = ROOM
	_room.hide()
	_set.add_child(_room)
	var wall := _material("blitz_room_wall", Color("5b5850"), .9, .2)
	var wood := _material("blitz_room_wood", Color("4a3b2e"), .7, .3)
	var floor := _material("blitz_room_floor", Color("3d3026"), .6, .35)
	var trim := _material("blitz_room_trim", Color("2e2721"), .7, .3)
	var cloth := _material("blitz_room_curtain", Color("4f4637"), .95, .1)
	var metal := _material("blitz_room_metal", Color("8a8d90"), .4, .6)
	var black := _material("blitz_room_black", Color("15161a"), .5, .4)
	var card := _material("blitz_cardboard", Color("b08a5c"), .9, .2)
	# Piso, paredes, teto e rodapé.
	_box(_room, Vector3(0, -.03, 0), Vector3(5, .06, 5), floor)
	_box(_room, Vector3(0, 1.4, -1.6), Vector3(5, 2.8, .1), wall)
	_box(_room, Vector3(-2.5, 1.4, 0), Vector3(.1, 2.8, 5), wall)
	_box(_room, Vector3(2.5, 1.4, 0), Vector3(.1, 2.8, 5), wall)
	_box(_room, Vector3(0, 2.83, 0), Vector3(5, .06, 5), wall)
	for spec in [[Vector3(0, .06, -1.54), Vector3(5, .12, .02)], [Vector3(-2.44, .06, 0), Vector3(.02, .12, 5)], [Vector3(2.44, .06, 0), Vector3(.02, .12, 5)]]:
		_box(_room, spec[0], spec[1], trim)
	_box(_room, Vector3(0, 2.76, -.2), Vector3(.32, .06, .32), _material("blitz_room_ceiling_lamp", Color("d8d2c4"), .6, .3))
	# Janela na parede esquerda: vidro escuro de noite, caixilho em cruz, peitoril e cortinas meio abertas.
	_box(_room, Vector3(-2.44, 1.55, -.3), Vector3(.03, 1.0, 1.2), _material("blitz_room_night", Color("101a28"), .15, .9, Color("0f1a2a")))
	for spec in [[Vector3(-2.42, 2.08, -.3), Vector3(.08, .06, 1.3)], [Vector3(-2.42, 1.02, -.3), Vector3(.08, .06, 1.3)], [Vector3(-2.42, 1.55, -.93), Vector3(.08, 1.12, .06)],
			[Vector3(-2.42, 1.55, .33), Vector3(.08, 1.12, .06)], [Vector3(-2.41, 1.55, -.3), Vector3(.05, 1.0, .03)], [Vector3(-2.41, 1.55, -.3), Vector3(.05, .03, 1.2)]]:
		_box(_room, spec[0], spec[1], trim)
	_box(_room, Vector3(-2.36, 1.0, -.3), Vector3(.2, .04, 1.4), wood)
	_box(_room, Vector3(-2.38, 1.5, -1.05), Vector3(.05, 2.2, .5), cloth)
	_box(_room, Vector3(-2.38, 1.5, .42), Vector3(.05, 2.2, .36), cloth)
	_box(_room, Vector3(-2.36, 2.62, -.3), Vector3(.04, .04, 1.9), metal)
	# Cama de solteiro: estrado, cabeceira, colchão, lençol, cobertor jogado e dois travesseiros.
	_box(_room, Vector3(0, .21, -.95), Vector3(2.0, .42, .95), wood)
	_box(_room, Vector3(-.98, .55, -.95), Vector3(.06, 1.1, .95), wood)
	_box(_room, Vector3(0, .49, -.95), Vector3(1.95, .14, .9), _material("blitz_room_sheet", Color("8c877b"), .95, .1))
	var blanket := _box(_room, Vector3(.45, .58, -1.05), Vector3(1.0, .06, .78), _material("blitz_room_blanket", Color("3e4a57"), .95, .1))
	blanket.rotation = Vector3(0, .18, .04)
	_box(_room, Vector3(-.7, .62, -1.2), Vector3(.5, .12, .32), _material("blitz_room_pillow", Color("b5afa1"), .95, .1))
	_box(_room, Vector3(-.72, .64, -.85), Vector3(.48, .1, .3), _material("blitz_room_pillow", Color("b5afa1"), .95, .1))
	# Envelope aberto sobre a cama, ao lado dele.
	_box(_room, Vector3(.42, .57, -.6), Vector3(.24, .01, .14), _material("blitz_letter", Color("e9e4d6"), .9, .1)).rotation.y = .4
	# Mesa de cabeceira: abajur (base e cúpula), copo, celular, a foto dos dois.
	_box(_room, Vector3(1.4, .35, -.9), Vector3(.6, .7, .5), wood)
	_box(_room, Vector3(1.4, .5, -.66), Vector3(.5, .14, .02), trim)
	_box(_room, Vector3(1.4, .2, -.66), Vector3(.5, .14, .02), trim)
	_box(_room, Vector3(1.32, .74, -1.0), Vector3(.1, .08, .1), black)
	_box(_room, Vector3(1.32, .84, -1.0), Vector3(.03, .2, .03), metal)
	_box(_room, Vector3(1.32, 1.0, -1.0), Vector3(.26, .2, .26), _material("blitz_room_lamp", Color("f2d9a8"), .5, .3, Color("ffd59a")))
	_box(_room, Vector3(1.55, .76, -.78), Vector3(.07, .12, .07), _material("blitz_room_glass", Color(.75, .8, .82, .45), .1, .9))
	_box(_room, Vector3(1.6, .705, -.98), Vector3(.08, .01, .15), black)
	var photo := _box(_room, Vector3(1.18, .8, -.78), Vector3(.16, .2, .02), trim)
	photo.rotation = Vector3(-.2, .5, 0)
	_box(photo, Vector3(0, 0, .012), Vector3(.12, .15, .005), _material("blitz_room_photo", Color("6b6152"), .6, .3))
	# Guarda-roupa no canto, com duas portas e puxadores.
	_box(_room, Vector3(2.05, 1.0, -1.25), Vector3(.8, 2.0, .6), wood)
	_box(_room, Vector3(2.05, 1.0, -.94), Vector3(.01, 1.9, .02), trim)
	for x in [1.98, 2.12]: _box(_room, Vector3(x, 1.05, -.93), Vector3(.02, .12, .02), metal)
	# Cadeira com a jaqueta pendurada e as botas no chão.
	_box(_room, Vector3(1.75, .45, .45), Vector3(.45, .05, .45), wood)
	_box(_room, Vector3(1.75, .75, .66), Vector3(.45, .6, .04), wood)
	for leg in [Vector3(1.55, .22, .25), Vector3(1.95, .22, .25), Vector3(1.55, .22, .65), Vector3(1.95, .22, .65)]: _box(_room, leg, Vector3(.04, .45, .04), wood)
	var jacket := _box(_room, Vector3(1.75, .8, .7), Vector3(.5, .55, .12), _material("blitz_room_jacket", Color("2c2f33"), .85, .2))
	jacket.rotation.x = -.15
	for x in [.55, .72]: _box(_room, Vector3(x, .07, .35), Vector3(.12, .14, .3), black)
	# Caixas da mudança empilhadas, uma aberta; tapete gasto; garrafa ao pé da cama.
	for spec in [[Vector3(-1.9, .25, 1.2), Vector3(.6, .5, .5)], [Vector3(-1.85, .7, 1.15), Vector3(.5, .4, .45)], [Vector3(-1.3, .2, 1.6), Vector3(.55, .4, .45)]]:
		_box(_room, spec[0], spec[1], card)
	_box(_room, Vector3(.2, .006, .25), Vector3(1.6, .012, 1.0), _material("blitz_room_rug", Color("5a3d33"), .95, .1))
	_box(_room, Vector3(-.55, .14, .18), Vector3(.08, .28, .08), _material("blitz_room_bottle", Color(.22, .3, .2, .7), .1, .9))
	# Na parede: um quadro, um calendário, uma estante com livros, a porta e o interruptor.
	_box(_room, Vector3(.1, 1.75, -1.54), Vector3(.7, .5, .03), trim)
	_box(_room, Vector3(.1, 1.75, -1.525), Vector3(.62, .42, .01), _material("blitz_room_painting", Color("5d6a6a"), .7, .2))
	_box(_room, Vector3(1.25, 1.55, -1.54), Vector3(.28, .38, .01), _material("blitz_room_calendar", Color("cfc7b5"), .9, .1))
	_box(_room, Vector3(-1.6, 1.6, -1.42), Vector3(.9, .03, .24), wood)
	var books := ["5a2f2a", "2f3f52", "6b5a3a", "36463a", "4b3b52", "7a6b52"]
	for index in books.size():
		_box(_room, Vector3(-1.95 + index * .1, 1.73, -1.42), Vector3(.07, .23 - (index % 3) * .03, .18), _material("blitz_room_book_%d" % index, Color(books[index]), .8, .2))
	_box(_room, Vector3(2.44, 1.05, 1.4), Vector3(.04, 2.1, .9), trim)
	_box(_room, Vector3(2.4, 1.0, 1.05), Vector3(.05, .05, .05), metal)
	_box(_room, Vector3(2.44, 1.3, .8), Vector3(.02, .1, .07), _material("blitz_room_switch", Color("d8d2c4"), .6, .3))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(1.3, 1.05, -.9)
	lamp.light_color = Color("ffcf94")
	lamp.omni_range = 4.2
	lamp.light_specular = .3
	_set_light(lamp, _room, 1.4)
	var night := OmniLight3D.new()
	night.position = Vector3(-2.0, 1.7, -.3)
	night.light_color = Color("7f9cc4")
	night.omni_range = 3.4
	# Sem especular: o reflexo da luz da janela no vidro virava uma "lua" de televisão.
	night.light_specular = 0.0
	_set_light(night, _room, .45)
	letter = MeshInstance3D.new()
	var paper := BoxMesh.new()
	paper.size = Vector3(.2, .004, .27)
	letter.mesh = paper
	letter.material_override = _material("blitz_letter", Color("e9e4d6"), .9, .1)
	letter.hide()
	_set.add_child(letter)

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
	rain.amount = 2600
	rain.lifetime = 1.5
	rain.preprocess = 1.5
	rain.fixed_fps = 30
	rain.visibility_aabb = AABB(Vector3(-21, -14, -21), Vector3(42, 28, 42))
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
	motion.emission_box_extents = Vector3(18, 1, 18)
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
	# A pose do Dante depois de a cena movê-lo neste quadro (caminhada, mãos e objeto na palma).
	if is_instance_valid(dante): dante.pose_step(step)
	if is_instance_valid(vicente): vicente.pose_step(step)
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
	# Tudo à vista de uma câmera, ainda coberto: chuva, vidro, giroflex, lanterna, porta aberta.
	truck.position = Vector3(LANE_X, 0, TRUCK_STOP_Z)
	truck_door.rotation.y = -1.1
	for index in cars.size(): cars[index].position = Vector3(-LANE_X, 0, -30.0 - index * 7.0)
	lantern.global_position = dante.global_position + Vector3(.2, 1.2, .3)
	# Arma, clarão e atirador entram no desenho coberto (os materiais do clarão compilam aqui).
	dante.weapon.show()
	dante.muzzle_flash_3d.show()
	if is_instance_valid(shooter): shooter.muzzle_flash_3d.show()
	camera.global_position = Vector3(-2.5, 3.0, 14.0)
	camera.look_at(Vector3(1.0, 1.4, -10.0))
	_follow_rain()
	if _rain_audio.stream != null: _rain_audio.play()
	if not RenderingServer.frame_post_draw.is_connected(_count_draw): RenderingServer.frame_post_draw.connect(_count_draw)

## Ombro redondo só nos dois irmãos (corpo do kit): a manga começa abaixo do ombro e termina em domo,
## sem a tampa reta que saltava como ombreira quadrada. O kit dos outros NPCs não muda.
func _round_shoulders(body) -> void:
	if not is_instance_valid(body) or body.get("_meshy") != null or body.upper_arms.is_empty(): return
	var kit = CIVILIAN_MESH_KIT
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
	if is_instance_valid(shooter): shooter.muzzle_flash_3d.hide()
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
	# Na câmera alta a chuva cai sobre o foco; nos closes, na frente da lente.
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _high_focus.is_finite(): rain.global_position = _high_focus + Vector3.UP * 9.0
	else: rain.global_position = camera.global_position + Vector3.UP * 7.0 - camera.global_basis.z * 5.0

func _engine(distance: float) -> void:
	if not is_instance_valid(_engine_audio) or _engine_audio.stream == null: return
	if not _engine_audio.playing: _engine_audio.play()
	_engine_audio.volume_db = lerpf(-6.0, -40.0, clampf(distance / 160.0, 0.0, 1.0))
	_engine_audio.pitch_scale = .8 + clampf(truck_speed / 20.0, 0.0, 1.0) * .45

func _budget_request() -> Dictionary:
	var lights: Array[Light3D] = []
	var wanted: Array[Dictionary] = []
	for light in [halo, lantern_light, cab_light] + headlights + _set_lights:
		if not is_instance_valid(light): continue
		lights.append(light)
		# Pela visibilidade do dono: a luz escondida pelo próprio orçamento continua pedindo.
		if light.get_parent().is_visible_in_tree(): wanted.append({"light": light, "headlight": false})
	# "player": a cena é a única coisa na tela; o mundo pausado embaixo não disputa.
	return {"lights": lights, "wanted": wanted, "player": true, "camera": camera.global_position if is_instance_valid(camera) else Vector3.ZERO}

func _face(model: Node3D, direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < .001: return
	if model.has_method("blitz_face"):
		model.blitz_face(direction)
		return
	# PoliceModel olha para -z (o corpo vai girado em PI dentro dele); o rig civil solto olha para +z.
	if model is POLICE_MODEL: model.rotation.y = atan2(-direction.x, -direction.z)
	else: model.rotation.y = atan2(direction.x, direction.z)

func _forward(model: Node3D) -> Vector3:
	if model.has_method("blitz_forward"): return model.blitz_forward()
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

## Vicente ao volante: quadril no banco, pés nos pedais e as duas mãos no aro, pela pose de motorista do
## jogo (a mesma dos carros). Refeita a cada quadro porque o caminhão anda.
func _vicente_hands() -> void:
	if not is_instance_valid(vicente) or vicente.get_parent() != truck: return
	var wheel := truck.to_global(Vector3(-.55, 2.02, -3.75))
	var rim := truck.global_basis.x.normalized()
	var grip := truck.global_basis.orthonormalized()
	vicente.seat(truck.to_global(Vector3(-.55, 1.7, -3.28)),
		{"Left": truck.to_global(Vector3(-.72, 1.22, -3.92)), "Right": truck.to_global(Vector3(-.38, 1.22, -3.92))},
		{"Left": Transform3D(grip, wheel - rim * .17), "Right": Transform3D(grip, wheel + rim * .17)})

func _door_point() -> Vector3:
	return truck.to_global(Vector3(-1.85, 0, -3.4))

func _cab_head() -> Vector3:
	return _head(vicente)

## Olhos de Vicente debruçado no vão da porta: do banco, a linha até o rosto de Dante (mais baixo,
## no asfalto) cortaria a lataria da cabine.
## Olhos de Vicente no banco, um pouco à frente: vê o para-brisa e a janela, sem a coluna da porta no meio.
func _cab_lean() -> Vector3:
	return truck.to_global(Vector3(-.88, truck.to_local(_eyes(vicente)).y, -3.78))

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

## Câmera do jogo (CameraRig): ortográfica, inclinada a 45°, a ~36 m do foco. Os modelos de perto não
## seguravam a cena; de cima ela tem a cara do resto do jogo. `heading` PI = olhando pela pista para +z.
const HIGH_OFFSET := Vector3(0, 25.3, 25.3)
const HIGH_DRIVE_OFFSET := Vector3(0, 30.4, 19.0)
const HIGH_SIZE := 17.0
var _high_focus := Vector3.INF

func _high_camera(focus: Vector3, size: float, step: float, offset := HIGH_OFFSET, heading := PI) -> void:
	var snap := camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not _high_focus.is_finite()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	focus.y = 0.0
	_high_focus = focus if snap else _high_focus.lerp(focus, 1.0 - exp(-4.2 * step))
	camera.size = size if snap else lerpf(camera.size, size, 1.0 - exp(-3.0 * step))
	var jitter := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * _shake * .15
	camera.global_position = _high_focus + offset.rotated(Vector3.UP, heading) + jitter
	camera.look_at(_high_focus + jitter, Vector3.UP)

## Close em perspectiva (rostos): sai da câmera alta.
func _close_camera() -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_high_focus = Vector3.INF

func _stage_size() -> float:
	if stage == "dante_ask": return 10.0
	if stage == "dante_walk": return 14.0
	return HIGH_SIZE

## Segue Dante de cima, um pouco à frente de onde ele olha (ou a meio caminho de `focus_point`).
func _nape_camera(step: float, ahead := 6.0, focus_point := Vector3.INF) -> void:
	var focus: Vector3 = dante.global_position + _forward(dante) * ahead * .4
	if focus_point.is_finite(): focus = dante.global_position.lerp(focus_point, .5)
	_high_camera(focus, _stage_size(), step)

func _dante_tick(step: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - step)
	_shake = maxf(0.0, _shake - step * 2.5)
	_vicente_hands()
	if stage in ["dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_cuffed"]: _lima_tick(step)
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
		"dante_cuffed":
			_high_camera(_wrists(), 5.0, step)
			if stage_time > 1.4 and _beat("to_car"): _fade(true, .6, _setup_escort)
		"dante_escort": _dante_escort(step)
		"dante_drive": _dante_drive(step)
		"dante_prison": _dante_prison(step)
		"dante_black": _dante_black()
		"dante_after": _dante_after(step)
	if stage in ["dante_open", "dante_walk", "dante_ask", "dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_cuffed", "dante_escort"]: _engine(camera.global_position.distance_to(truck.global_position) if stage == "dante_open" else 4.0)

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
	_dante_heading = heading
	_face(dante, velocity)

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
	# Sem close na cabine: a conversa pela porta aberta fica na câmera alta, como o resto da blitz.
	if not _beats.has("step_down"): _nape_camera(step, 3.0, glass)
	if stage_time > 4.8 and _beat("vicente_line"): say("dante", "door", func(): _clock = stage_time)
	if _beats.has("vicente_line") and not speaking() and stage_time - _clock > .8 and _beat("step_down"):
		# Bastos olha de um para o outro; Vicente desce com as mãos à vista.
		vicente.reparent(_set)
		vicente.stand_up()
		vicente.global_position = _door_point() + Vector3(.3, 0, .15)
		_face(vicente, Vector3.LEFT)
		# Ninguém ali tinha feito nada: ele desce, explica a carga, oferece abrir o baú.
		say("dante", "order_out", func(): _ready_ambush = stage_time)
	if _beats.has("step_down"):
		_nape_camera(step, 3.0, _eyes(vicente).lerp(_eyes(bastos), .35))
		# Mãos ao alto, abertas acima da cabeça (com a junta do pescoço como cabeça, iam às orelhas).
		var neck := _head(vicente)
		var side := _forward(vicente).cross(Vector3.UP).normalized()
		var front := _forward(vicente) * .06
		vicente.hand_targets = [neck + Vector3.UP * .4 + side * .27 + front, neck + Vector3.UP * .4 - side * .27 + front]
	if _ready_ambush >= 0.0 and stage_time - _ready_ambush > .6: _set_stage("dante_ambush")

## Tiros do lado do passageiro: Bastos cai, Dante saca e vai para o abrigo.
func _dante_ambush(step: float) -> void:
	if _beat("shooter_out"):
		# A porta do passageiro abre: o Rato desce do banco, pistola na mão. Dante vê primeiro e grita.
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(passenger_door, "rotation:y", 1.5, .45 / pace)
		_play("res://audio/vehicle_fx/door_open_1.wav", -3.0)
		# Os dois policiais congelam: Bastos na porta, Lima no cavalete. Quem reage é Dante.
		_hands(bastos, null, null)
		_hands(lima, null, null)
		_face(bastos, SHOOTER_OUT - bastos.global_position)
		_face(lima, SHOOTER_OUT - lima.global_position)
		say("dante", "ambush")
		_play("res://audio/weapons_fire/gun_draw_0.wav", -4.0)
		dante.weapon.show()
		lantern.hide()
	# Ele desce do banco quando a porta já abriu; o primeiro tiro é em Bastos, na porta do motorista.
	if stage_time > .35 and _beat("shooter_jump"):
		shooter.reparent(_set)
		shooter.seated = false
		shooter.body.sit_amount = 0.0
		shooter.weapon.visible = true
		shooter.global_position = truck.to_global(Vector3(1.95, 0, -3.3))
		shooter.rotation = Vector3.ZERO
	# Contorna a frente do caminhão (por fora da carroceria) até ter linha.
	var legs := [SHOOTER_OUT, SHOOTER_EXPOSED]
	if _beats.has("shooter_jump") and _shooter_leg < legs.size():
		shooter.global_position = shooter.global_position.move_toward(legs[_shooter_leg], 3.6 * step)
		if shooter.global_position.distance_to(legs[_shooter_leg]) < .05: _shooter_leg += 1
	var first_target: Vector3 = bastos.global_position if not _beats.has("first_shot") else dante.global_position
	if _beats.has("shooter_jump"): _face(shooter, first_target - shooter.global_position)
	if _beats.has("shooter_jump") and shooter.global_position.distance_to(SHOOTER_EXPOSED) < .3 and _beat("first_shot"):
		_enemy_shot()
		_kill(bastos, (bastos.global_position - shooter.global_position).normalized())
		_shake = .5
		say("dante", "man_down")
		_shot_clock = stage_time
	if _beats.has("shooter_jump"): shooter.update_pose(step, true, false, 0.0, 0.0)
	var cover: Vector3 = dante.global_position.move_toward(DANTE_COVER, 2.6 * step)
	dante.global_position = cover
	_vicente_crouch()
	_aim_point = SHOOTER_EXPOSED + Vector3.UP * 1.2
	var toward: Vector3 = _aim_point - dante.global_position
	aim_yaw = atan2(-toward.x, -toward.z)
	dante.update_pose(step, true, false, 0.0, 0.0)
	_aim_camera(step)
	if _beats.has("first_shot") and stage_time - _shot_clock > .7:
		_shooter_exposed = true
		_shooter_clock = 1.6
		_objective_text("fight")
		_show_fire_prompt()
		_set_stage("dante_fight")

## Lima reage: um instante de susto, corre para trás da viatura, saca e atira por cima do capô enquanto o
## atirador está vivo (o acerto é do jogador). Depois guarda a arma, vai até Bastos e pede apoio no rádio.
func _lima_tick(step: float) -> void:
	if not _beats.has("first_shot"): return
	_lima_clock += step
	if _lima_clock < .9: return
	var fighting := is_instance_valid(shooter) and shooter_health > 0
	if fighting:
		if _beat("lima_draw"):
			lima.weapon.show()
			_play_at_volume("res://audio/weapons_fire/gun_draw_1.wav", -8.0)
		var offset := LIMA_COVER - lima.global_position
		offset.y = 0.0
		if offset.length() > .1:
			lima.global_position += offset.normalized() * minf(offset.length(), 3.6 * step)
			_face(lima, offset)
			lima.update_pose(step, false, false, 0.0, 0.0)
			return
		if not speaking() and _beat("lima_in_cover"): say("dante", "lima_cover")
		_face(lima, shooter.global_position - lima.global_position)
		lima.update_pose(step, true, false, 0.0, 0.0)
		_lima_fire -= step
		if _lima_fire <= 0.0 and _shooter_exposed:
			_lima_fire = randf_range(.8, 1.3)
			lima.attack()
			_play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % randi_range(0, 3), -9.0)
		return
	# Atirador no chão: arma no coldre, ao lado de Bastos, rádio na boca.
	if lima.weapon.visible:
		lima.weapon.hide()
		_play_at_volume("res://audio/weapons_fire/gun_holster_2.wav", -10.0)
	var beside: Vector3 = bastos.global_position + Vector3(-.9, 0, -.5)
	var walk := beside - lima.global_position
	walk.y = 0.0
	if walk.length() > .1:
		lima.global_position += walk.normalized() * minf(walk.length(), 2.4 * step)
		_face(lima, walk)
		_hands(lima, null, null)
		return
	_face(lima, bastos.global_position - lima.global_position)
	var mouth: Vector3 = _head(lima) + Vector3.UP * .14 + _forward(lima) * .13 - _forward(lima).cross(Vector3.UP).normalized() * .05
	_hands(lima, null, mouth)
	if not speaking() and _beat("lima_radio_call"): say("dante", "lima_radio")

func _vicente_crouch() -> void:
	# Agachado atrás da porta aberta, mãos na cabeça.
	vicente.global_position = vicente.global_position.move_toward(_door_point() + Vector3(.35, 0, .55), .05)
	vicente.sit_amount = move_toward(vicente.sit_amount, .55, .05)
	var neck := _head(vicente)
	var side := _forward(vicente).cross(Vector3.UP).normalized()
	var back := _forward(vicente) * .02
	vicente.hand_targets = [neck + Vector3.UP * .27 + side * .07 - back, neck + Vector3.UP * .27 - side * .07 - back]

# --- Tiroteio ----------------------------------------------------------------------------------------

## Por cima do ombro direito; o corpo de Dante gira com a mira e o PoliceModel põe as duas mãos na arma.
## De cima, um pouco adiantada para onde ele mira; o corpo de Dante gira com a mira e a pegada da pistola é
## a do jogo.
func _aim_camera(step: float) -> void:
	var lead: Vector3 = _aim_point - dante.global_position
	lead.y = 0.0
	_high_camera(dante.global_position + lead.limit_length(6.0) * .35, HIGH_SIZE, step)
	dante.combat_facing = aim_yaw

var _aim_point := Vector3.ZERO

func _aim_tick(step: float) -> void:
	var target := _current_target()
	if autoplay and target != null:
		_aim_point = target.global_position + Vector3.UP * 1.2
		var exposed: bool = target != shooter or _shooter_visible()
		_want_fire = exposed and _fire_cooldown <= 0.0 and stage_time > (.4 if target == shooter else 1.8)
	else: _aim_point = _pointer_aim(step)
	var toward: Vector3 = _aim_point - dante.global_position
	if Vector2(toward.x, toward.z).length() > .3: aim_yaw = atan2(-toward.x, -toward.z)
	dante.update_pose(step, true, false, 0.0, 0.0)
	_aim_camera(step)
	_place_crosshair()
	if _want_fire or (not autoplay and Input.is_action_pressed("fire") and _fire_cooldown <= 0.0):
		_want_fire = false
		_fire()

## Ponto mirado: o mouse projetado no plano do peito (como o jogo mira de cima); no controle, a direção do
## analógico do GameInput do jogo.
func _pointer_aim(step: float) -> Vector3:
	var game_input := get_node_or_null("/root/GameInput")
	if game_input != null and game_input.using_gamepad:
		var point: Vector3 = game_input.aim_target_3d(dante, camera, step, false)
		return Vector3(point.x, 1.2, point.z)
	var mouse := _main_viewport.get_mouse_position() * Vector2(_viewport.size) / _main_viewport.get_visible_rect().size
	var hit: Variant = Plane(Vector3.UP, 1.2).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	return hit if hit != null else _aim_point

func _place_crosshair() -> void:
	if not _crosshair.visible or camera.is_position_behind(_aim_point): return
	var screen := camera.unproject_position(_aim_point) * _main_viewport.get_visible_rect().size / Vector2(_viewport.size)
	_crosshair.position = screen - _crosshair.size * .5

## Peito de Dante: de onde sai o tiro.
func _muzzle_origin() -> Vector3:
	return dante.global_position + Vector3.UP * 1.35

func _current_target() -> Node3D:
	if stage == "dante_fight" and shooter_health > 0: return shooter
	if stage == "dante_flee" and not vicente_hit: return vicente
	return null

func _shooter_visible() -> bool:
	if not is_instance_valid(shooter) or shooter_health <= 0: return false
	var chest := shooter.global_position + Vector3.UP * 1.2
	return _truck_hit(_muzzle_origin(), (chest - _muzzle_origin()).normalized()) > _muzzle_origin().distance_to(chest)

func _fire() -> void:
	if _fire_cooldown > 0.0: return
	_fire_cooldown = .26
	shots_fired += 1
	dante.attack()
	_shot_audio(-1.0)
	# Do peito de Dante para o ponto mirado, na altura do peito (de cima a mira é no chão do mapa).
	var origin := _muzzle_origin()
	var direction := (Vector3(_aim_point.x, 1.25, _aim_point.z) - origin).normalized()
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
		vicente._flinch(direction, 35.0)
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
	vicente.global_position += offset.normalized() * minf(offset.length(), 4.6 * step)
	_face(vicente, offset)

## Vicente cai sentado segurando a coxa; Prado no rádio; Dante vai até ele, guarda a arma e se agacha.
func _dante_wounded(step: float) -> void:
	var forward := _forward(vicente)
	var side := forward.cross(Vector3.UP).normalized()
	if _beat("sit_down"):
		# As pernas falham e ele senta no asfalto, pernas à frente, as mãos na coxa baleada.
		vicente.sit_amount = 0.0
		vicente.hand_targets = [null, null]
		_ground_seat = vicente.global_position + forward * .05 + Vector3.UP * .16
		var thigh: Vector3 = _ground_seat + forward * .3 + Vector3.UP * .02 - side * .1
		var grip := Basis.looking_at(forward, Vector3.UP)
		# `side` é a direita dele: o pé e a mão esquerdos vão para -side (trocados, as pernas se cruzavam).
		vicente.sit_on_ground(_ground_seat, {"Left": _ground_seat + forward * .62 - side * .16 - Vector3.UP * .1, "Right": _ground_seat + forward * .5 + side * .16 - Vector3.UP * .1},
			{"Left": Transform3D(grip, thigh - side * .07), "Right": Transform3D(grip, thigh + side * .05)}, .8)
	if _beat("procedure"): say("dante", "wounded", func(): say("dante", "order"))
	# A 0,85 m: de 1 m, agachado, as mãos dele paravam 30 cm antes dos pulsos.
	var stand: Vector3 = _ground_seat + forward * .85 - Vector3.UP * .16
	var offset: Vector3 = stand - dante.global_position
	offset.y = 0.0
	if offset.length() > .05:
		dante.global_position += offset.normalized() * minf(offset.length(), 1.3 * step)
	_face(dante, vicente.global_position - dante.global_position)
	dante.update_pose(step, offset.length() > .4, false, 0.0, 0.0)
	# De cima, os dois no quadro, aproximando.
	_high_camera((dante.global_position + vicente.global_position) * .5, 9.0, step)
	if offset.length() <= .05 and stage_time > 4.5 and not speaking():
		_play("res://audio/weapons_fire/gun_holster_1.wav", -6.0)
		dante.weapon.hide()
		_set_stage("dante_cuff")
		_objective_text("cuff")
		_show_prompt("cuff")
		_progress.value = 0.0
		_progress.show()

## Pulsos de Vicente juntos à frente do peito, oferecidos (sentado no asfalto).
func _wrists() -> Vector3:
	return _ground_seat + _forward(vicente) * .36 + Vector3.UP * .34

func _dante_cuff(step: float) -> void:
	var holding := autoplay or Input.is_action_pressed("interact")
	# Segurar demora; soltar devolve devagar. Não existe outro comando.
	cuff_progress = clampf(cuff_progress + (step / HOLD_SECONDS if holding else -step * .4), 0.0, 1.0)
	_progress.value = cuff_progress
	var wrists := _wrists()
	var across := _forward(vicente).cross(Vector3.UP).normalized()
	var offer := Basis.looking_at(_forward(vicente), Vector3.UP)
	vicente.update_seat_hands({"Left": Transform3D(offer, wrists - across * .05), "Right": Transform3D(offer, wrists + across * .05)})
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
	# De cima, fechando nas mãos conforme o botão é segurado.
	_high_camera(wrists, lerpf(9.0, 5.0, smoothstep(0.0, 1.0, cuff_progress)), step)
	if cuff_progress >= 1.0:
		_play("res://audio/weapons_fire/gun_holster_0.wav", -2.0)
		_hide_prompt()
		_progress.hide()
		_objective.text = ""
		_set_stage("dante_cuffed")

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
	if stage_time > 5.4 and _beat("after"): _setup_room()

func _fade(to_black: bool, seconds: float, then := Callable()) -> void:
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(curtain, "color:a", 1.0 if to_black else 0.0, seconds / pace)
	if then.is_valid(): tween.tween_callback(then)

## Corte para a viatura: Vicente de pé, algemado, Dante segurando o braço dele; Lima atrás do baú.
func _setup_escort() -> void:
	vicente.stand_up()
	var door := police.to_global(CAR_DOOR_LOCAL)
	var out := (door - police.global_position)
	out.y = 0.0
	out = out.normalized()
	vicente.global_position = door + out * .35
	_face(vicente, -out)
	dante.global_position = door + out * 1.05 + out.cross(Vector3.UP) * .35
	_face(dante, vicente.global_position - dante.global_position)
	dante.sit_amount = 0.0
	lima.global_position = LIMA_CARGO
	_face(lima, Vector3.FORWARD)
	_hands(lima, null, null)
	_high_focus = Vector3.INF
	_clock = 0.0
	_set_stage("dante_escort")
	_fade(false, .6)
	say("dante", "escort", _open_cargo)

## O baú aberto: geladeira e fogão encaixotados, nada além disso.
func _open_cargo() -> void:
	TRUCK.set_loot_visible(truck, true)
	TRUCK.set_cargo_open(truck, true)
	_play("res://audio/vehicle_fx/door_open_2.wav", -4.0)
	_clock = stage_time

func _cuffed_hands() -> void:
	var forward := _forward(vicente)
	var side := forward.cross(Vector3.UP).normalized()
	var waist: Vector3 = vicente.global_position + forward * .22 + Vector3.UP * .95
	vicente.hand_targets = [waist + side * .04, waist - side * .04]
	# Dante conduz pelo braço: a mão esquerda dele no braço direito de Vicente.
	_hands(dante, null, _head(vicente) - Vector3.UP * .3 - side * .2)

func _dante_escort(step: float) -> void:
	# Na viatura enquanto ele pede; no baú aberto (as caixas de eletrodoméstico à vista); de volta a ele.
	var at_cargo := _clock > 0.0 or (_clock < 0.0 and stage_time + _clock < .4)
	if at_cargo:
		# De trás do caminhão, por cima do ombro de Lima, para dentro do baú: de cima o teto escondia as caixas.
		if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
			_close_camera()
			camera.fov = 50.0
		camera.global_position = truck.to_global(Vector3(.9, 2.3, 10.8))
		camera.look_at(truck.to_global(Vector3(0, 1.6, 3.0)), Vector3.UP)
	else: _high_camera(police.global_position.lerp(vicente.global_position, .5), 10.0, step)
	_cuffed_hands()
	if _beats.has("cargo_line") == false and _clock > 0.0 and stage_time - _clock > 1.4 and not speaking() and _beat("cargo_line"):
		say("dante", "cargo", func(): _clock = -stage_time)
	# Depois do "Viu?!": Dante põe Vicente na viatura sem responder e vai para o volante.
	if _clock < 0.0 and stage_time + _clock > 1.2 and _beat("into_car"):
		vicente.hide()
		_play("res://audio/vehicle_fx/door_close_0.wav", -4.0)
	if _beats.has("into_car"):
		_hands(dante, null, null)
		var driver := police.to_global(CAR_DRIVER_LOCAL)
		var offset: Vector3 = driver - dante.global_position
		offset.y = 0.0
		if offset.length() > .05:
			dante.global_position += offset.normalized() * minf(offset.length(), 1.4 * step)
			_face(dante, offset)
		elif _beat("driver_in"):
			dante.hide()
			_play("res://audio/vehicle_fx/door_close_1.wav", -4.0)
			_police_audio.volume_db = -14.0
			_set_stage("dante_drive")

## A viatura sai com ele no banco de trás, giroflex ligado, e some na pista.
func _dante_drive(step: float) -> void:
	_police_speed = minf(13.0, _police_speed + 3.2 * step)
	police.rotation.y = move_toward(police.rotation.y, 0.0, step * .25)
	police.position.x = move_toward(police.position.x, LANE_X, step * .9)
	police.position.z -= _police_speed * step
	_high_camera(police.global_position + Vector3(0, 0, 4.0), 19.0, step)
	if stage_time > 4.0 and _beat("leave"): _fade(true, 1.0, _setup_prison)

## A prisão à noite: muralha, guaritas, holofote; a viatura chega e o portão abre.
func _setup_prison() -> void:
	_prison.show()
	police.global_position = PRISON + Vector3(1.8, 0, 46.0)
	police.rotation = Vector3.ZERO
	_police_speed = 9.0
	_close_camera()
	camera.fov = 52.0
	camera.global_position = PRISON + Vector3(17.0, 6.5, 31.0)
	camera.look_at(PRISON + Vector3(0, 3.5, -7.0), Vector3.UP)
	# Mais longe da câmera que a blitz: a névoa recua para a muralha aparecer.
	_environment.fog_depth_begin = 45.0
	_environment.fog_depth_end = 260.0
	_set_stage("dante_prison")
	_fade(false, 1.0)

func _dante_prison(step: float) -> void:
	var stop_z := PRISON.z + 1.0
	var distance := police.global_position.z - stop_z
	_police_speed = minf(_police_speed, sqrt(maxf(0.0, 2.0 * 2.6 * distance)))
	police.global_position.z -= minf(_police_speed * step, maxf(0.0, distance))
	if stage_time > 2.4 and _beat("gate"): _play("res://audio/vehicle_fx/air_brake.wav", -12.0)
	if _beats.has("gate"):
		for index in _gate.size():
			var leaf := _gate[index]
			leaf.position.x = move_toward(leaf.position.x, (-6.2 if index == 0 else 6.2), step * 1.3)
	if is_instance_valid(_flood): _flood.rotation.y = -.35 + sin(stage_time * .5) * .25
	if stage_time > 7.0 and _beat("prison_out"): _fade(true, 1.2, func(): _cut_to_black(); _set_stage("dante_black"))

## Oito anos depois: Dante, sem farda, sentado na beira da cama com a carta, a cabeça baixa. Sem fala.
func _setup_room() -> void:
	_prison.hide()
	_room.show()
	police.hide()
	rain.emitting = false
	rain.hide()
	_environment.fog_depth_begin = 32.0
	_environment.fog_depth_end = 150.0
	dante.show()
	dante.civilian()
	dante.combat_facing = NAN
	dante.global_position = ROOM
	# O corpo inteiro vira para +z, não só o visual: a pose sentada do jogo lê as mãos no espaço do Actor, e
	# com só o visual girado as palmas ficavam de trás para a frente (braços torcidos).
	dante.rotation.y = PI
	dante.visual.rotation.y = 0.0
	# Curvado para a frente, cotovelos perto dos joelhos, a carta entre as mãos e a cabeça baixa sobre ela.
	dante.head_bow = .5
	# Mãos nas bordas da folha como no volante (Y ao longo do que segura, Z para o corpo), a folha inclinada
	# com o topo longe dele.
	var hold: Basis = dante.global_basis * Basis(Vector3.RIGHT, -.6)
	# De frente para +z, a esquerda dele é +x (trocado, uma perna atravessava a outra).
	dante.seat(ROOM + Vector3(0, .64, -.42), {"Left": ROOM + Vector3(.18, .08, .14), "Right": ROOM + Vector3(-.18, .08, .14)},
		{"Left": Transform3D(hold, ROOM + Vector3(.12, .8, .1)), "Right": Transform3D(hold, ROOM + Vector3(-.12, .8, .1))}, -.32)
	letter.show()
	# Três-quartos pela esquerda dele, na altura do rosto curvado: a luz do abajur no rosto e na carta, a
	# janela de chuva e a cama ao fundo.
	_close_camera()
	camera.fov = 40.0
	camera.global_position = ROOM + Vector3(1.2, .98, 1.1)
	camera.look_at(ROOM + Vector3(0, .9, -.18), Vector3.UP)
	if is_instance_valid(_rain_audio):
		_rain_audio.volume_db = -18.0
		_rain_audio.play()
	_title.modulate.a = 0.0
	_set_stage("dante_after")
	_fade(false, 1.2)

func _dante_after(step: float) -> void:
	# A carta entre as mãos, com a face voltada para o rosto dele; a câmera se aproxima devagar.
	var left: Vector3 = dante.combat_palm_position("Left")
	var right: Vector3 = dante.combat_palm_position("Right")
	var middle: Vector3 = (left + right) * .5
	var facing: Vector3 = (_eyes(dante) - middle).normalized()
	var across := (left - right).normalized()
	across = (across - facing * across.dot(facing)).normalized()
	letter.global_transform = Transform3D(Basis(across, facing, across.cross(facing)), middle)
	camera.global_position = camera.global_position.move_toward(ROOM + Vector3(.95, .95, .82), step * .05)
	camera.look_at(ROOM + Vector3(0, .9, -.18), Vector3.UP)
	if stage_time > 7.0 and _beat("end"): _fade(true, 1.4, func(): _finish(false))

# --- Ponto de vista de Vicente (flashback do ato 2) ------------------------------------------------

func _vicente_begin() -> void:
	_set_stage("vicente_drive")
	truck.position = Vector3(LANE_X, 0, 460.0)
	truck_speed = 16.0
	dante.position = DANTE_POST
	_face(dante, Vector3.BACK)
	_objective_text("drive")
	say("vicente", "radio_open")

## Dirigindo, a câmera de direção do jogo: mais alta e atrás, com a pista à frente do caminhão.
func _chase_camera(step: float) -> void:
	_high_camera(truck.to_global(Vector3(0, 0, -9.0)), 21.0, step, HIGH_DRIVE_OFFSET, truck.global_rotation.y)

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
			# Um passo atrás da porta: a chapa gira 1,1 m a partir da dobradiça e passava por dentro dele.
			var door := truck.to_global(Vector3(-2.4, 0, -3.15))
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
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		_close_camera()
		camera.fov = 50.0
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
	# A cena é dona de toda a entrada: nada chega à sessão pausada embaixo. O GameInput ainda vê o evento
	# (troca teclado/controle), como a sessão faz antes de consumir.
	var game_input := get_node_or_null("/root/GameInput")
	if game_input != null: game_input.observe_event(event)
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		request_skip()
		return
	if pov == "dante" and stage == "dante_open" and event.is_action_pressed("interact") and not _prompt.text.is_empty(): _signal()
	if stage in ["dante_fight", "dante_flee"] and not autoplay:
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
