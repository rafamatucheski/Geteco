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
## Montagem e peças vivas (BlitzSet), a noite do Dante (BlitzDanteBeats) e o tiroteio (BlitzShootout)
## moram em auxiliares desde 01/11, só para este arquivo caber na leitura. O estado fica aqui: testes e a
## captura leem estes campos na cena.
const BLITZ_SET := preload("res://runtime/prologue/BlitzSet.gd")
const DANTE_BEATS := preload("res://runtime/prologue/BlitzDanteBeats.gd")
const SHOOTOUT := preload("res://runtime/prologue/BlitzShootout.gd")
var _set_kit: BLITZ_SET = BLITZ_SET.new(self)
var _dante_beats: DANTE_BEATS = DANTE_BEATS.new(self)
var _shootout: SHOOTOUT = SHOOTOUT.new(self)
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

func _build_environment() -> void: _set_kit._build_environment()

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

func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D: return _set_kit._box(parent, center, size, material)
func _strip(parent: Node3D, mesh_size: Vector3, material: Material, transforms: Array[Transform3D]) -> void: _set_kit._strip(parent, mesh_size, material, transforms)
func _build_road() -> void: _set_kit._build_road()
func _instances(mesh: PrimitiveMesh, material: Material, transforms: Array[Transform3D], shadows := false) -> void: _set_kit._instances(mesh, material, transforms, shadows)
func _build_roadside() -> void: _set_kit._build_roadside()
func _build_police() -> void: _set_kit._build_police()
func _build_truck() -> void: _set_kit._build_truck()

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

func _lantern_node(node_name: String, beam: bool) -> Node3D: return _set_kit._lantern_node(node_name, beam)
func _colleague(node_name: String, appearance: int, body: String, point: Vector3, facing: Vector3) -> Node3D: return _set_kit._colleague(node_name, appearance, body, point, facing)
func _build_cast() -> void: _set_kit._build_cast()
func _build_colleagues() -> void: _set_kit._build_colleagues()
func _hold(model, index: int, item: Node3D) -> bool: return _set_kit._hold(model, index, item)
func _body(model): return _set_kit._body(model)
func _hands(model, right: Variant, left: Variant) -> void: _set_kit._hands(model, right, left)
func _colleagues_tick() -> void: _set_kit._colleagues_tick()
func _aim_lanterns() -> void: _set_kit._aim_lanterns()
func _point(item: Node3D, target: Vector3) -> void: _set_kit._point(item, target)
func _set_light(light: Light3D, parent: Node3D, energy: float) -> void: _set_kit._set_light(light, parent, energy)
func _build_prison() -> void: _set_kit._build_prison()
func _build_room() -> void: _set_kit._build_room()
func _build_traffic() -> void: _set_kit._build_traffic()

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

func _player(bus: String, stream: AudioStream, volume: float) -> AudioStreamPlayer: return _set_kit._player(bus, stream, volume)
func _build_audio() -> void: _set_kit._build_audio()
func _sound(path: String) -> AudioStream: return _set_kit._sound(path)
func _play(path: String, volume := -4.0) -> void: _set_kit._play(path, volume)

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

func _count_draw() -> void:
	_warm_draws += 1

func _warm() -> void: _set_kit._warm()

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

func _beacons() -> void: _set_kit._beacons()
func _follow_rain() -> void: _set_kit._follow_rain()
func _engine(distance: float) -> void: _set_kit._engine(distance)
func _budget_request() -> Dictionary: return _set_kit._budget_request()
func _face(model: Node3D, direction: Vector3) -> void: _set_kit._face(model, direction)
func _forward(model: Node3D) -> Vector3: return _set_kit._forward(model)
func _head(model) -> Vector3: return _set_kit._head(model)
func _eyes(model) -> Vector3: return _set_kit._eyes(model)
func _dante_hands(swing: float) -> void: _set_kit._dante_hands(swing)
func _vicente_hands() -> void: _set_kit._vicente_hands()
func _door_point() -> Vector3: return _set_kit._door_point()
func _cab_lean() -> Vector3: return _set_kit._cab_lean()
func _move_truck(step: float) -> void: _set_kit._move_truck(step)
func _open_door() -> void: _set_kit._open_door()
func _brake_to(stop_z: float, step: float, crawl := 0.0) -> bool: return _set_kit._brake_to(stop_z, step, crawl)

# --- Ponto de vista de Dante (prólogo) -------------------------------------------------------------

func _dante_begin() -> void: _dante_beats._dante_begin()

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

func _dante_tick(step: float) -> void: _dante_beats._dante_tick(step)
func _signal() -> void: _dante_beats._signal()

## Faixa de desvio: os carros vêm na faixa da direita, passam para a da esquerda antes dos cavaletes
## (Lima acenando) e voltam depois da viatura.
static func detour_x(z: float) -> float:
	var enter := clampf(inverse_lerp(30.0, 8.0, z), 0.0, 1.0)
	var leave := clampf(inverse_lerp(-26.0, -46.0, z), 0.0, 1.0)
	return lerpf(LANE_X, -LANE_X, smoothstep(0.0, 1.0, enter) * (1.0 - smoothstep(0.0, 1.0, leave)))

func _traffic_near() -> bool: return _dante_beats._traffic_near()
func _traffic(step: float) -> void: _dante_beats._traffic(step)
func _walk_bastos(step: float) -> void: _dante_beats._walk_bastos(step)
func _walk_dante(step: float) -> void: _dante_beats._walk_dante(step)
func _dante_ask(step: float) -> void: _dante_beats._dante_ask(step)
func _dante_ambush(step: float) -> void: _dante_beats._dante_ambush(step)
func _lima_tick(step: float) -> void: _dante_beats._lima_tick(step)
func _vicente_crouch() -> void: _dante_beats._vicente_crouch()

# --- Tiroteio ----------------------------------------------------------------------------------------

func _aim_camera(step: float) -> void: _shootout._aim_camera(step)

var _aim_point := Vector3.ZERO

func _aim_tick(step: float) -> void: _shootout._aim_tick(step)
func _pointer_aim(step: float) -> Vector3: return _shootout._pointer_aim(step)
func _place_crosshair() -> void: _shootout._place_crosshair()
func _muzzle_origin() -> Vector3: return _shootout._muzzle_origin()
func _current_target() -> Node3D: return _shootout._current_target()
func _shooter_visible() -> bool: return _shootout._shooter_visible()
func _fire() -> void: _shootout._fire()
func _kill(model: Node3D, direction: Vector3) -> void: _shootout._kill(model, direction)
func _drop_gun(model: Node3D) -> void: _shootout._drop_gun(model)

## Raio contra a cápsula de um corpo em pé (base nos pés). Devolve a distância até o acerto ou -1.
static func capsule_hit(origin: Vector3, direction: Vector3, base: Vector3, radius: float, height: float) -> float:
	var points := Geometry3D.get_closest_points_between_segments(origin, origin + direction * 90.0, base + Vector3.UP * .3, base + Vector3.UP * maxf(.35, height - .2))
	if points[0].distance_to(points[1]) > radius: return -1.0
	return origin.distance_to(points[0])

func _truck_hit(origin: Vector3, direction: Vector3) -> float: return _shootout._truck_hit(origin, direction)
func _shooter_tick(step: float) -> void: _shootout._shooter_tick(step)
func _enemy_shot() -> void: _shootout._enemy_shot()
func _shot_audio(volume: float) -> void: _shootout._shot_audio(volume)
func _play_at_volume(path: String, volume: float) -> void: _shootout._play_at_volume(path, volume)
func _show_fire_prompt() -> void: _shootout._show_fire_prompt()
func _capture_mouse(value: bool) -> void: _shootout._capture_mouse(value)
func _vicente_run(step: float) -> void: _dante_beats._vicente_run(step)
func _dante_wounded(step: float) -> void: _dante_beats._dante_wounded(step)
func _wrists() -> Vector3: return _dante_beats._wrists()
func _dante_cuff(step: float) -> void: _dante_beats._dante_cuff(step)
func _cut_to_black() -> void: _dante_beats._cut_to_black()
func _dante_black() -> void: _dante_beats._dante_black()
func _fade(to_black: bool, seconds: float, then := Callable()) -> void: _dante_beats._fade(to_black, seconds, then)
func _setup_escort() -> void: _dante_beats._setup_escort()
func _open_cargo() -> void: _dante_beats._open_cargo()
func _cuffed_hands() -> void: _dante_beats._cuffed_hands()
func _dante_escort(step: float) -> void: _dante_beats._dante_escort(step)
func _dante_drive(step: float) -> void: _dante_beats._dante_drive(step)
func _setup_prison() -> void: _dante_beats._setup_prison()
func _dante_prison(step: float) -> void: _dante_beats._dante_prison(step)
func _setup_room() -> void: _dante_beats._setup_room()
func _dante_after(step: float) -> void: _dante_beats._dante_after(step)

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
