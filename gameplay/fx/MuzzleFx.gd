extends Node3D
## Tiro saindo da arma (29/10, jogador: "parece tudo muito simples em iluminação, impacto, tudo").
## Antes: um clarão de 6 raios igual para toda arma, uma luz de 2,5 m fora do LightBudget só no jogador,
## um único emissor de fumaça reiniciado a cada tiro (na rajada só a última baforada aparecia) e cápsula
## de 5 mm sem brilho, invisível na câmera do jogo. Agora, por família de arma (pistola curta, fuzil
## longo, escopeta larga):
##   - clarão com núcleo, língua e pétalas próprias, em 3 variações que se alternam nos 3 quadros do
##     disparo (abre forte, estica, some), aditivo e acima do limiar do glow;
##   - luz curta e forte que acende o chão e a parede em volta, pelo LightBudget como "transient":
##     ocupa só vaga que sobrou (nunca apaga farol/giroflex por 60 ms a cada tiro), jogador primeiro;
##   - fumaça sombreada (escura à noite, acesa pelo próprio clarão) que sai, para e se abre;
##   - faíscas pequenas e cápsula quente que brilha no ar e esfria ao cair.
## Filho de CombatEffects; as chamadas do jogo não mudam (`muzzle_smoke`, `weapon_shot`, `shell`).
## O Gameplay (que não é editado aqui) continua criando o clarão e a luz antigos no cano: no tiro do
## jogador eles viram só a âncora (escondidos) que este nó segue.
##
## Orçamento fixo, nada criado depois de `setup`:
##   - clarão: 1 nó do jogador + NPC_FLASHES em anel;
##   - luz: 1 do jogador + NPC_LIGHTS (máximo de 3 luzes de cano ao mesmo tempo);
##   - fumaça: SMOKE_POOL emissores; sem vaga, o tiro de NPC fica sem fumaça (não corta outra);
##   - faíscas: SPARK_POOL emissores em anel (vida de ~0,15 s);
##   - cápsula: troca material/malha dos nós do anel do CombatEffects.
## Materiais: 3 do clarão (mesmo shader, só a cor muda), 1 das faíscas (mesmo shader do clarão), 1 da
## fumaça e 1 da cápsula quente. Todos passam por `prewarm` e ficam retidos aqui.
## GETECO_MUZZLE_FX=0 desliga tudo (CombatEffects volta ao comportamento antigo) para A/B.
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const NPC_FLASHES := 8
const NPC_LIGHTS := 2
const SMOKE_POOL := 16
const SPARK_POOL := 8
const QUEUE_SIZE := 24
const VARIANTS := 3
const SMOKE_AMOUNT := 4
const SPARK_AMOUNT := 6
## Rajada: uma baforada por ~0,15 s no mesmo cano, senão a fumaça da submetralhadora vira parede.
const SMOKE_MERGE_TIME := 0.15
const SMOKE_MERGE_DISTANCE := 0.7
## Vaga de fumaça é reaproveitada quando a anterior já está quase transparente (rampa de alfa).
const SMOKE_REUSE_AT := 0.85
const SHELL_HOT_TIME := 0.32
const LIGHT_COLOR := Color(1.0, 0.66, 0.30)
const HOT := Color(1.0, 0.96, 0.84, 1.0)
const WARM := Color(1.0, 0.76, 0.36, 0.9)
const EDGE := Color(0.95, 0.36, 0.06, 0.0)
## Cor (HDR) de cada quadro do clarão. Com 3,4 no primeiro quadro o glow virava uma bola branca e a
## forma sumia até de dia (capturas de 30/10); 1,7 ainda passa do limiar noturno (1,0) sem apagar a forma.
const STAGE_COLORS := [Color(1.7, 1.3, 0.8), Color(1.1, 0.75, 0.4), Color(0.6, 0.32, 0.14)]
const STAGE_SCALE := [Vector3(1.0, 1.0, 1.0), Vector3(0.86, 0.86, 1.14), Vector3(0.6, 0.6, 0.8)]
## Luz: a energia de pico foi cortada à metade depois das capturas de 30/10 (a 6,5 a escopeta acendia a
## cena inteira à noite). Medidas maiores que as reais de propósito: na câmera do jogo (ortográfica, ~33 px/m em 720p) um
## clarão de pistola de verdade ocuparia 3 px. `light` é a energia de pico, `range` o alcance em m.
const PROFILES := {
	"pistol": {"flash": true, "spike": 0.20, "spike_w": 0.05, "petals": 4, "petal": 0.12, "petal_w": 0.035,
		"petal_angle": 62.0, "core": 0.06, "diamonds": false, "life": 0.05,
		"light": 2.0, "range": 4.0, "light_life": 0.06,
		"smoke_life": 1.2, "smoke_scale": 0.8, "smoke_speed": 1.5, "smoke_alpha": 0.32, "smoke_spread": 22.0,
		"sparks": 1, "spark_speed": 9.0, "spark_spread": 16.0, "spark_life": 0.14},
	"magnum": {"flash": true, "spike": 0.28, "spike_w": 0.07, "petals": 5, "petal": 0.17, "petal_w": 0.05,
		"petal_angle": 58.0, "core": 0.085, "diamonds": false, "life": 0.065,
		"light": 2.8, "range": 5.0, "light_life": 0.075,
		"smoke_life": 1.4, "smoke_scale": 1.0, "smoke_speed": 1.8, "smoke_alpha": 0.36, "smoke_spread": 24.0,
		"sparks": 1, "spark_speed": 10.0, "spark_spread": 20.0, "spark_life": 0.16},
	# Submetralhadora: cruz curta e quase perpendicular, vida curta para a cadência não emendar.
	"smg": {"flash": true, "spike": 0.24, "spike_w": 0.045, "petals": 4, "petal": 0.11, "petal_w": 0.03,
		"petal_angle": 76.0, "core": 0.055, "diamonds": false, "life": 0.04,
		"light": 1.8, "range": 3.6, "light_life": 0.05,
		"smoke_life": 0.9, "smoke_scale": 0.65, "smoke_speed": 1.4, "smoke_alpha": 0.26, "smoke_spread": 20.0,
		"sparks": 1, "spark_speed": 8.0, "spark_spread": 14.0, "spark_life": 0.12},
	# Fuzil: língua longa com dois "diamantes" de choque e pétalas curtas de lado.
	"rifle": {"flash": true, "spike": 0.46, "spike_w": 0.06, "petals": 3, "petal": 0.13, "petal_w": 0.03,
		"petal_angle": 78.0, "core": 0.06, "diamonds": true, "life": 0.055,
		"light": 2.5, "range": 4.6, "light_life": 0.06,
		"smoke_life": 1.1, "smoke_scale": 0.8, "smoke_speed": 2.2, "smoke_alpha": 0.30, "smoke_spread": 14.0,
		"sparks": 1, "spark_speed": 13.0, "spark_spread": 10.0, "spark_life": 0.15},
	# Escopeta: cone largo de pétalas abertas para a frente, a maior luz e a maior nuvem.
	"shotgun": {"flash": true, "spike": 0.30, "spike_w": 0.16, "petals": 7, "petal": 0.30, "petal_w": 0.07,
		"petal_angle": 50.0, "core": 0.11, "diamonds": false, "life": 0.07,
		"light": 3.2, "range": 5.2, "light_life": 0.08,
		"smoke_life": 1.6, "smoke_scale": 1.25, "smoke_speed": 1.9, "smoke_alpha": 0.38, "smoke_spread": 30.0,
		"sparks": 2, "spark_speed": 10.0, "spark_spread": 28.0, "spark_life": 0.18},
	# Silenciador (catálogo ou acessório): brasa mínima, sem luz e sem faísca, como o Gameplay já fazia.
	"suppressed": {"flash": true, "spike": 0.06, "spike_w": 0.025, "petals": 0, "petal": 0.0, "petal_w": 0.0,
		"petal_angle": 0.0, "core": 0.03, "diamonds": false, "life": 0.035,
		"light": 0.0, "range": 0.0, "light_life": 0.0,
		"smoke_life": 0.7, "smoke_scale": 0.4, "smoke_speed": 0.5, "smoke_alpha": 0.18, "smoke_spread": 26.0,
		"sparks": 0, "spark_speed": 0.0, "spark_spread": 0.0, "spark_life": 0.0},
	# Lança-foguetes: o clarão e a luz continuam os do Gameplay (escala própria e sopro traseiro).
	"rocket": {"flash": false, "light": 0.0, "range": 0.0, "light_life": 0.0, "life": 0.0,
		"smoke_life": 1.6, "smoke_scale": 1.3, "smoke_speed": 2.0, "smoke_alpha": 0.36, "smoke_spread": 26.0,
		"sparks": 2, "spark_speed": 9.0, "spark_spread": 30.0, "spark_life": 0.2},
	# NPC sem arma conhecida (polícia, guarda): a pistola, um pouco menor e mais fraca.
	"npc": {"flash": true, "mesh_of": "pistol", "life": 0.05, "light": 1.6, "range": 3.8, "light_life": 0.06,
		"smoke_life": 1.1, "smoke_scale": 0.75, "smoke_speed": 1.4, "smoke_alpha": 0.30, "smoke_spread": 22.0,
		"sparks": 1, "spark_speed": 9.0, "spark_spread": 18.0, "spark_life": 0.14},
}

## Dono de luz para o LightBudget: um para o jogador (`player` = prioridade), um para os NPCs.
class LightOwner extends Node:
	const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
	var fx: Node
	var for_player := false
	var lights: Array[Light3D] = []
	func _enter_tree() -> void:
		if BUDGET.enabled: BUDGET.register(self)
	func _exit_tree() -> void:
		if BUDGET.enabled: BUDGET.unregister(self)
	func _budget_request() -> Dictionary:
		return fx._light_request(for_player, lights)

var _effects: Node3D
var _flash_materials: Array[StandardMaterial3D] = []
var _spark_material: StandardMaterial3D
var _smoke_material: StandardMaterial3D
var _hot_brass: StandardMaterial3D
var _meshes: Dictionary = {}
var _rifle_shell_mesh: CylinderMesh
var _flash_nodes: Array[MeshInstance3D] = []
var _flash_age := PackedFloat32Array()
var _flash_life := PackedFloat32Array()
var _flash_stage := PackedInt32Array()
var _flash_variant := PackedInt32Array()
var _flash_roll := PackedFloat32Array()
var _flash_scale := PackedFloat32Array()
var _flash_mesh_kind := PackedStringArray()
var _flash_base: Array[Transform3D] = []
var _next_flash := 0
var _light_nodes: Array[OmniLight3D] = []
var _light_age := PackedFloat32Array()
var _light_life := PackedFloat32Array()
var _light_peak := PackedFloat32Array()
var _light_offset := PackedVector3Array()
var _player_owner: LightOwner
var _npc_owner: LightOwner
var _lights_new := false
var _lights_changed := false
var _smoke: Array[CPUParticles3D] = []
var _smoke_born := PackedFloat64Array()
var _smoke_life := PackedFloat32Array()
var _smoke_at := PackedVector3Array()
var _smoke_player := PackedByteArray()
var _sparks: Array[CPUParticles3D] = []
var _next_spark := 0
var _hot_until := PackedFloat64Array()
var _hot_active := 0
var _anchor: Node3D
var _q_origin := PackedVector3Array()
var _q_dir := PackedVector3Array()
var _q_kind := PackedStringArray()
var _q_player := PackedByteArray()
var _q_scale := PackedFloat32Array()
var _q_count := 0
var _q_frame := -1
var _flush_pending := false
var _shell_hint := ""
var _shell_hint_frame := -1
## Contadores para testes e diagnóstico (inteiros, sem alocar por tiro).
var shots := 0
var dropped_events := 0
var lights_started := 0
var lights_skipped := 0
var smoke_started := 0
var smoke_merged := 0
var smoke_dropped := 0

static func enabled() -> bool:
	return OS.get_environment("GETECO_MUZZLE_FX") != "0"

static func kind_of(id: String) -> String:
	match id:
		"magnum": return "magnum"
		"smg", "smg_compact", "smg_tactical": return "smg"
		"ak47", "m4a1", "hunting_rifle": return "rifle"
		"shotgun", "sawed_off", "shotgun_auto": return "shotgun"
		"pistol_suppressed": return "suppressed"
		"rpg": return "rocket"
	return "pistol"

## Variação dentro da família (a compacta é menor, o fuzil de caça mais longo, a de cano serrado abre mais).
static func id_scale(id: String) -> float:
	match id:
		"smg_compact": return 0.85
		"smg_tactical": return 0.95
		"shotgun_auto": return 0.9
		"sawed_off": return 1.12
		"hunting_rifle": return 1.15
	return 1.0

## Monta tudo uma vez (CombatEffects._ready, sob a cortina de carregamento).
func setup(effects: Node3D) -> void:
	_effects = effects
	name = "MuzzleFx"
	# Os nós são posicionados em _process com a pose já interpolada do cano; interpolar de novo daria rastro.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Antes dos carros (prioridade 0): o refresh do LightBudget deste quadro já inclui a luz do tiro, e o
	# deles vira no-op em vez de um segundo refresh forçado.
	process_priority = -20
	for color in STAGE_COLORS:
		_flash_materials.append(_additive(color))
	_spark_material = _additive(Color(2.6, 1.8, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 291026
	for kind in PROFILES:
		var profile: Dictionary = PROFILES[kind]
		if not bool(profile.flash) or profile.has("mesh_of"): continue
		var variants: Array[ArrayMesh] = []
		for variant in VARIANTS: variants.append(_flash_mesh(profile, rng))
		_meshes[kind] = variants
	for slot in 1 + NPC_FLASHES:
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.top_level = true
		node.visible = false
		add_child(node)
		_flash_nodes.append(node)
		_flash_base.append(Transform3D.IDENTITY)
	# Um resize por vetor: num laço `for array in [...]` o vetor empacotado pode ser uma cópia.
	_flash_age.resize(1 + NPC_FLASHES)
	_flash_life.resize(1 + NPC_FLASHES)
	_flash_roll.resize(1 + NPC_FLASHES)
	_flash_scale.resize(1 + NPC_FLASHES)
	_flash_age.fill(-1.0)
	_flash_stage.resize(1 + NPC_FLASHES)
	_flash_variant.resize(1 + NPC_FLASHES)
	_flash_mesh_kind.resize(1 + NPC_FLASHES)
	_player_owner = LightOwner.new()
	_player_owner.name = "PlayerMuzzleLight"
	_player_owner.fx = self
	_player_owner.for_player = true
	_npc_owner = LightOwner.new()
	_npc_owner.name = "NpcMuzzleLights"
	_npc_owner.fx = self
	for slot in 1 + NPC_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = LIGHT_COLOR
		light.shadow_enabled = false
		# Clarão de décimos de segundo: não alimenta a névoa volumétrica nem precisa de brilho especular forte.
		light.light_volumetric_fog_energy = 0.0
		light.light_specular = 0.45
		light.omni_attenuation = 1.3
		light.top_level = true
		light.visible = false
		light.set_meta("budget_energy", 0.0)
		add_child(light)
		_light_nodes.append(light)
		(_player_owner if slot == 0 else _npc_owner).lights.append(light)
	add_child(_player_owner)
	add_child(_npc_owner)
	_light_age.resize(1 + NPC_LIGHTS)
	_light_life.resize(1 + NPC_LIGHTS)
	_light_peak.resize(1 + NPC_LIGHTS)
	_light_age.fill(-1.0)
	_light_offset.resize(1 + NPC_LIGHTS)
	_build_smoke()
	_build_sparks()
	_build_shells()
	_hot_until.resize(int(effects.get("MAX_SHELLS")) if effects.get("MAX_SHELLS") != null else 16)
	_hot_until.fill(-1.0)
	_q_origin.resize(QUEUE_SIZE)
	_q_dir.resize(QUEUE_SIZE)
	_q_kind.resize(QUEUE_SIZE)
	_q_player.resize(QUEUE_SIZE)
	_q_scale.resize(QUEUE_SIZE)

func _ready() -> void:
	set_process(false)

## Aditivo, sem luz, cor por vértice e sem névoa (a névoa somada ao aditivo vira halo cinza ao longe).
static func _additive(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.albedo_color = color
	return material

## Clarão em malha com cor por vértice (eixo -Z = cano): núcleo de três discos cruzados (lê como bola de
## luz de qualquer ângulo da câmera), língua da frente em duas lâminas cruzadas e pétalas cruzadas em
## volta do cano. As variações sorteiam ângulo, comprimento e largura das peças.
static func _flash_mesh(profile: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var forward := Vector3(0.0, 0.0, -1.0)
	var core := float(profile.core) * rng.randf_range(0.75, 0.9)
	var center := forward * core * 0.5
	# Os três discos se somam no centro (aditivo): o miolo entra a 45% para não estourar em bola branca.
	var core_hot := Color(HOT.r, HOT.g, HOT.b, 0.45)
	var rim := Color(HOT.r, HOT.g * 0.8, HOT.b * 0.45, 0.0)
	for axes in [[Vector3.RIGHT, Vector3.UP], [Vector3.RIGHT, forward], [Vector3.UP, forward]]:
		for index in 10:
			var a0 := TAU * float(index) / 10.0
			var a1 := TAU * float(index + 1) / 10.0
			var p0: Vector3 = center + ((axes[0] as Vector3) * cos(a0) + (axes[1] as Vector3) * sin(a0)) * core
			var p1: Vector3 = center + ((axes[0] as Vector3) * cos(a1) + (axes[1] as Vector3) * sin(a1)) * core
			_tri(surface, center, core_hot, p0, rim, p1, rim)
	var length := float(profile.spike) * rng.randf_range(0.85, 1.15)
	var width := float(profile.spike_w) * rng.randf_range(0.85, 1.15)
	var stations := PackedFloat32Array([0.0, 0.22, 0.42, 0.62, 0.82, 1.0]) if bool(profile.diamonds) else PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	var widths := PackedFloat32Array([0.35, 1.0, 0.45, 0.8, 0.3, 0.0]) if bool(profile.diamonds) else PackedFloat32Array([0.4, 1.0, 0.5, 0.0])
	for side in [Vector3.RIGHT, Vector3.UP]:
		_blade(surface, Vector3.ZERO, forward, side, length, width, stations, widths)
	var count := int(profile.petals)
	var spin := rng.randf() * TAU
	for index in count:
		var theta := spin + TAU * float(index) / float(count) + rng.randf_range(-0.35, 0.35)
		var radial := Vector3(cos(theta), sin(theta), 0.0)
		var tangent := Vector3(-sin(theta), cos(theta), 0.0)
		var phi := deg_to_rad(float(profile.petal_angle) + rng.randf_range(-10.0, 10.0))
		var direction := (forward * cos(phi) + radial * sin(phi)).normalized()
		var crossing := direction.cross(tangent).normalized()
		var petal := float(profile.petal) * rng.randf_range(0.7, 1.25)
		var petal_w := float(profile.petal_w) * rng.randf_range(0.8, 1.2)
		var root := radial * 0.01 + forward * 0.004
		for side in [tangent, crossing]:
			_blade(surface, root, direction, side, petal, petal_w, PackedFloat32Array([0.0, 0.4, 1.0]), PackedFloat32Array([0.3, 1.0, 0.0]))
	return surface.commit()

static func _blade(surface: SurfaceTool, root: Vector3, direction: Vector3, side: Vector3, length: float, width: float, stations: PackedFloat32Array, widths: PackedFloat32Array) -> void:
	for k in stations.size() - 1:
		var a := root + direction * length * stations[k]
		var b := root + direction * length * stations[k + 1]
		var wa := side * width * widths[k]
		var wb := side * width * widths[k + 1]
		var ca := _heat(stations[k])
		var cb := _heat(stations[k + 1])
		_tri(surface, a - wa, ca, b - wb, cb, b + wb, cb)
		_tri(surface, a - wa, ca, b + wb, cb, a + wa, ca)

## Branco-amarelo na boca, laranja no meio, ponta apagando.
static func _heat(f: float) -> Color:
	if f < 0.4: return HOT.lerp(WARM, f / 0.4)
	return WARM.lerp(EDGE, (f - 0.4) / 0.6)

static func _tri(surface: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	surface.set_color(ca)
	surface.add_vertex(a)
	surface.set_color(cb)
	surface.add_vertex(b)
	surface.set_color(cc)
	surface.add_vertex(c)

## Fumaça sombreada (a antiga era sem luz e clareava à noite como neblina cinza): aparece rápido, para
## no ar perto do cano (amortecimento), sobe devagar e se abre até sumir.
func _build_smoke() -> void:
	_smoke_material = StandardMaterial3D.new()
	_smoke_material.vertex_color_use_as_albedo = true
	_smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_smoke_material.roughness = 1.0
	_smoke_material.metallic_specular = 0.1
	var soft: Texture2D = null
	var source_mesh: Variant = _effects.get("_smoke_mesh")
	if source_mesh is QuadMesh and (source_mesh as QuadMesh).material is StandardMaterial3D:
		soft = ((source_mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
	if soft == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		soft = texture
	_smoke_material.albedo_texture = soft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = _smoke_material
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.08, 0.35, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0.72), Color(1, 1, 1, 0)])
	var curve := Curve.new()
	curve.max_value = 3.2
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.15, 0.9))
	curve.add_point(Vector2(1.0, 3.0))
	for slot in SMOKE_POOL:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.85
		emitter.amount = SMOKE_AMOUNT
		emitter.lifetime = 1.2
		emitter.local_coords = false
		emitter.mesh = quad
		emitter.direction = Vector3.UP
		emitter.spread = 22.0
		emitter.damping_min = 2.2
		emitter.damping_max = 3.4
		emitter.gravity = Vector3(0.0, 0.32, 0.0)
		emitter.angle_min = 0.0
		emitter.angle_max = 360.0
		emitter.angular_velocity_min = -40.0
		emitter.angular_velocity_max = 40.0
		emitter.scale_amount_curve = curve
		emitter.color = Color(0.74, 0.73, 0.70, 0.3)
		emitter.color_ramp = ramp
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.top_level = true
		add_child(emitter)
		_smoke.append(emitter)
	_smoke_born.resize(SMOKE_POOL)
	_smoke_born.fill(-1000.0)
	_smoke_life.resize(SMOKE_POOL)
	_smoke_life.fill(1.0)
	_smoke_at.resize(SMOKE_POOL)
	_smoke_player.resize(SMOKE_POOL)

## Faíscas: riscos de ~6-10 cm alinhados à velocidade, aditivos (mesmo shader do clarão).
func _build_sparks() -> void:
	var streak := BoxMesh.new()
	streak.size = Vector3(0.014, 0.10, 0.014)
	streak.material = _spark_material
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.96, 0.75, 1.0), Color(1.0, 0.6, 0.18, 0.9), Color(0.8, 0.25, 0.05, 0.0)])
	for slot in SPARK_POOL:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.amount = SPARK_AMOUNT
		emitter.lifetime = 0.14
		emitter.local_coords = false
		emitter.mesh = streak
		emitter.direction = Vector3.UP
		emitter.spread = 16.0
		emitter.gravity = Vector3(0.0, -9.0, 0.0)
		emitter.scale_amount_min = 0.6
		emitter.scale_amount_max = 1.0
		emitter.particle_flag_align_y = true
		emitter.color = Color.WHITE
		emitter.color_ramp = ramp
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.top_level = true
		add_child(emitter)
		_sparks.append(emitter)

## Cápsula 20% maior (raio de 5 → 6 mm, igual ao afastamento de repouso do CombatEffects) e uma de fuzil
## mais comprida no mesmo latão; a quente brilha em laranja só enquanto voa.
func _build_shells() -> void:
	var pistol_case: Variant = _effects.get("_shell_mesh")
	var brass: Material = null
	if pistol_case is CylinderMesh:
		(pistol_case as CylinderMesh).top_radius = 0.006
		(pistol_case as CylinderMesh).bottom_radius = 0.006
		(pistol_case as CylinderMesh).height = 0.03
		brass = (pistol_case as CylinderMesh).material
	_rifle_shell_mesh = CylinderMesh.new()
	_rifle_shell_mesh.top_radius = 0.006
	_rifle_shell_mesh.bottom_radius = 0.006
	_rifle_shell_mesh.height = 0.046
	_rifle_shell_mesh.radial_segments = 6
	_rifle_shell_mesh.rings = 1
	_rifle_shell_mesh.material = brass
	_hot_brass = StandardMaterial3D.new()
	_hot_brass.albedo_color = Color(0.86, 0.58, 0.2)
	_hot_brass.metallic = 0.85
	_hot_brass.roughness = 0.28
	_hot_brass.emission_enabled = true
	_hot_brass.emission = Color(1.0, 0.62, 0.22)
	_hot_brass.emission_energy_multiplier = 2.4

## `CombatEffects.muzzle_smoke`: todo tiro (jogador, polícia, Cobras, guardas) passa aqui. O tiro do
## jogador é reconhecido pelo clarão do Gameplay aceso exatamente nesse ponto; o resto é NPC. O efeito
## sai no fim do passo (call_deferred), depois de `weapon_hint`, que vem logo atrás no mesmo disparo.
func muzzle(origin: Vector3, direction: Vector3) -> void:
	if _q_count >= QUEUE_SIZE:
		dropped_events += 1
		return
	var player := false
	var kind := ""
	var scale_value := 1.0
	var gameplay: Node = _effects.get_parent() if is_instance_valid(_effects) else null
	if gameplay != null:
		var anchor: Variant = gameplay.get("_muzzle_flash")
		if is_instance_valid(anchor) and anchor is Node3D and (anchor as Node3D).visible and (anchor as Node3D).global_position.distance_squared_to(origin) < 0.0001:
			player = true
			var id := str(gameplay.call("equipped")) if gameplay.has_method("equipped") else ""
			var light: Variant = gameplay.get("_muzzle_light")
			# O Gameplay apaga a própria luz quando há silenciador (catálogo ou acessório).
			var suppressed: bool = is_instance_valid(light) and light is Light3D and not (light as Light3D).visible
			kind = "suppressed" if suppressed else kind_of(id)
			scale_value = id_scale(id)
			if kind != "rocket":
				(anchor as Node3D).visible = false
				if is_instance_valid(light) and light is Light3D: (light as Light3D).visible = false
				_anchor = anchor
	_q_origin[_q_count] = origin
	_q_dir[_q_count] = direction
	_q_kind[_q_count] = kind
	_q_player[_q_count] = 1 if player else 0
	_q_scale[_q_count] = scale_value
	_q_count += 1
	_q_frame = Engine.get_process_frames()
	if not _flush_pending:
		_flush_pending = true
		_flush.call_deferred()

## `CombatEffects.weapon_shot`: dá a arma ao último tiro de NPC sem família (Cobras) e à próxima cápsula.
func weapon_hint(id: String) -> void:
	_shell_hint = id
	_shell_hint_frame = Engine.get_process_frames()
	if _q_count > 0 and _q_frame == _shell_hint_frame and _q_kind[_q_count - 1] == "" and _q_player[_q_count - 1] == 0:
		_q_kind[_q_count - 1] = kind_of(id)
		_q_scale[_q_count - 1] = id_scale(id)

func _flush() -> void:
	_flush_pending = false
	if _q_count == 0 or not is_inside_tree():
		_q_count = 0
		return
	var began := STALL_WORK.begin()
	for index in _q_count:
		var kind := _q_kind[index] if _q_kind[index] != "" else "npc"
		_spawn(_q_origin[index], _q_dir[index], kind, _q_player[index] == 1, _q_scale[index])
	_q_count = 0
	set_process(true)
	STALL_WORK.finish_slow("combat.muzzle_fx.flush", began, 1000, self)

func _spawn(origin: Vector3, direction: Vector3, kind: String, player: bool, scale_value: float) -> void:
	# Efeito transparente em NaN derruba a ordenação da lista alfa do release (runtime/NonFiniteGuard.gd).
	if not origin.is_finite() or not direction.is_finite(): return
	var aim := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var profile: Dictionary = PROFILES.get(kind, PROFILES.npc)
	shots += 1
	if bool(profile.flash): _start_flash(origin, aim, kind, profile, player, scale_value)
	if float(profile.light) > 0.0: _start_light(origin, aim, profile, player)
	_start_smoke(origin, aim, profile, player)
	for burst in int(profile.sparks): _start_sparks(origin, aim, profile)

func _start_flash(origin: Vector3, aim: Vector3, kind: String, profile: Dictionary, player: bool, scale_value: float) -> void:
	var slot := 0
	if not player:
		slot = 1 + _next_flash
		_next_flash = (_next_flash + 1) % NPC_FLASHES
	var up := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	_flash_base[slot] = Transform3D(Basis.looking_at(aim, up), origin)
	_flash_age[slot] = 0.0
	_flash_life[slot] = float(profile.life)
	_flash_stage[slot] = 0
	_flash_variant[slot] = randi() % VARIANTS
	_flash_roll[slot] = randf() * TAU
	_flash_scale[slot] = scale_value
	_flash_mesh_kind[slot] = str(profile.get("mesh_of", kind))
	var node := _flash_nodes[slot]
	node.mesh = _meshes[_flash_mesh_kind[slot]][_flash_variant[slot]]
	node.material_override = _flash_materials[0]
	node.global_transform = _flash_transform(slot)
	node.visible = true

func _flash_transform(slot: int) -> Transform3D:
	var base := _flash_base[slot]
	var stage_scale: Vector3 = STAGE_SCALE[_flash_stage[slot]] * _flash_scale[slot]
	return Transform3D(base.basis * Basis(Vector3.BACK, _flash_roll[slot]) * Basis.from_scale(stage_scale), base.origin)

## Luz do jogador sempre na vaga 0; NPC usa vaga livre, ou toma a mais apagada se ela já passou da metade.
func _start_light(origin: Vector3, aim: Vector3, profile: Dictionary, player: bool) -> void:
	var slot := 0
	if not player:
		slot = -1
		var oldest := 0.5
		for candidate in range(1, 1 + NPC_LIGHTS):
			if _light_age[candidate] < 0.0:
				slot = candidate
				break
			var progress := _light_age[candidate] / maxf(_light_life[candidate], 0.001)
			if progress > oldest:
				oldest = progress
				slot = candidate
		if slot < 0:
			lights_skipped += 1
			return
	var node := _light_nodes[slot]
	# Um palmo à frente e acima da boca: acende o chão e a parede, não o braço de quem atira.
	_light_offset[slot] = aim * 0.14 + Vector3.UP * 0.06
	node.global_position = origin + _light_offset[slot]
	node.omni_range = float(profile.range)
	_light_peak[slot] = float(profile.light) * randf_range(0.9, 1.1)
	_light_life[slot] = float(profile.light_life)
	_light_age[slot] = 0.0
	node.set_meta("budget_energy", _light_peak[slot])
	node.light_energy = _light_peak[slot]
	lights_started += 1
	if LIGHT_BUDGET.enabled: _lights_new = true
	else: node.visible = true

func _start_smoke(origin: Vector3, aim: Vector3, profile: Dictionary, player: bool) -> void:
	var now := _now()
	var merge := SMOKE_MERGE_DISTANCE * SMOKE_MERGE_DISTANCE
	var slot := -1
	var oldest := INF
	var oldest_npc := -1
	var oldest_npc_born := INF
	for index in SMOKE_POOL:
		var born := _smoke_born[index]
		var age := now - born
		if age < SMOKE_MERGE_TIME and _smoke_at[index].distance_squared_to(origin) < merge:
			smoke_merged += 1
			return
		if age >= _smoke_life[index] * SMOKE_REUSE_AT and born < oldest:
			oldest = born
			slot = index
		if _smoke_player[index] == 0 and born < oldest_npc_born:
			oldest_npc_born = born
			oldest_npc = index
	# Sem vaga: o jogador corta a baforada de NPC mais velha; o NPC fica sem fumaça.
	if slot < 0 and player: slot = oldest_npc
	if slot < 0:
		smoke_dropped += 1
		return
	var emitter := _smoke[slot]
	var size := float(profile.smoke_scale)
	var speed := float(profile.smoke_speed)
	emitter.lifetime = float(profile.smoke_life)
	emitter.scale_amount_min = size * 0.75
	emitter.scale_amount_max = size * 1.15
	emitter.initial_velocity_min = speed * 0.45
	emitter.initial_velocity_max = speed
	emitter.spread = float(profile.smoke_spread)
	emitter.color = Color(0.74, 0.73, 0.70, float(profile.smoke_alpha))
	_place(emitter, origin + aim * 0.06, aim + Vector3.UP * 0.15)
	emitter.visible = true
	emitter.restart()
	_smoke_born[slot] = now
	_smoke_life[slot] = float(profile.smoke_life)
	_smoke_at[slot] = origin
	_smoke_player[slot] = 1 if player else 0
	smoke_started += 1

func _start_sparks(origin: Vector3, aim: Vector3, profile: Dictionary) -> void:
	var emitter := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % SPARK_POOL
	var speed := float(profile.spark_speed)
	emitter.lifetime = float(profile.spark_life)
	emitter.initial_velocity_min = speed * 0.55
	emitter.initial_velocity_max = speed
	emitter.spread = float(profile.spark_spread)
	_place(emitter, origin + aim * 0.03, aim)
	emitter.visible = true
	emitter.restart()

## Eixo +Y do emissor na direção de emissão (mesma convenção do CombatEffects._fire).
static func _place(emitter: CPUParticles3D, point: Vector3, direction: Vector3) -> void:
	var up := direction.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	emitter.global_transform = Transform3D(Basis(side, up, side.cross(up)), point)

## `CombatEffects.shell`: cápsula de fuzil mais comprida e latão quente que esfria em SHELL_HOT_TIME.
## Cartucho de escopeta e cápsula que cai na recarga (revólver) não brilham.
func shell_ejected(index: int, node: MeshInstance3D, shotgun: bool, dropped: bool) -> void:
	if index < 0 or index >= _hot_until.size() or not is_instance_valid(node): return
	var id := _shell_hint if _shell_hint_frame == Engine.get_process_frames() else _player_weapon()
	_shell_hint_frame = -1
	if not shotgun and not dropped and kind_of(id) == "rifle": node.mesh = _rifle_shell_mesh
	var was_hot := _hot_until[index] >= 0.0
	if shotgun or dropped:
		if was_hot:
			_hot_until[index] = -1.0
			_hot_active -= 1
		node.material_override = null
		return
	node.material_override = _hot_brass
	if not was_hot: _hot_active += 1
	_hot_until[index] = _now() + SHELL_HOT_TIME
	set_process(true)

func _player_weapon() -> String:
	var gameplay: Node = _effects.get_parent() if is_instance_valid(_effects) else null
	return str(gameplay.call("equipped")) if gameplay != null and gameplay.has_method("equipped") else ""

static func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0

func _reference() -> Vector3:
	var gameplay: Node = _effects.get_parent() if is_instance_valid(_effects) else null
	if gameplay != null:
		var player: Variant = gameplay.get("player")
		if is_instance_valid(player) and player is Node3D: return (player as Node3D).global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if is_instance_valid(camera) else Vector3.ZERO

## Pedido ao LightBudget: luz acesa é "transient" (só ocupa vaga que sobrou, ver LightBudget._nearer).
func _light_request(for_player: bool, lights: Array[Light3D]) -> Dictionary:
	var wanted: Array[Dictionary] = []
	var first := 0 if for_player else 1
	var last := 1 if for_player else _light_nodes.size()
	for slot in range(first, last):
		if _light_age[slot] >= 0.0: wanted.append({"light": _light_nodes[slot], "headlight": false, "transient": true})
	return {"lights": lights, "wanted": wanted, "player": for_player, "camera": _reference()}

func _process(delta: float) -> void:
	var began := STALL_WORK.begin()
	var busy := false
	var has_anchor := is_instance_valid(_anchor) and _anchor.is_inside_tree()
	var anchor_xform := _anchor.get_global_transform_interpolated() if has_anchor else Transform3D.IDENTITY
	for slot in _flash_nodes.size():
		var age := _flash_age[slot]
		if age < 0.0: continue
		age += delta
		var node := _flash_nodes[slot]
		if age >= _flash_life[slot]:
			_flash_age[slot] = -1.0
			node.visible = false
			continue
		busy = true
		_flash_age[slot] = age
		var stage := mini(int(age / _flash_life[slot] * 3.0), 2)
		var changed := stage != _flash_stage[slot]
		if changed:
			_flash_stage[slot] = stage
			_flash_roll[slot] += randf_range(0.6, 2.2)
			node.mesh = _meshes[_flash_mesh_kind[slot]][(_flash_variant[slot] + stage) % VARIANTS]
			node.material_override = _flash_materials[stage]
		if slot == 0 and has_anchor:
			_flash_base[0] = Transform3D(anchor_xform.basis.orthonormalized(), anchor_xform.origin)
			changed = true
		if changed: node.global_transform = _flash_transform(slot)
	var lights_on := false
	for slot in _light_nodes.size():
		var age := _light_age[slot]
		if age < 0.0: continue
		age += delta
		var node := _light_nodes[slot]
		if age >= _light_life[slot]:
			_light_age[slot] = -1.0
			node.visible = false
			node.set_meta("budget_energy", 0.0)
			_lights_changed = true
			continue
		lights_on = true
		_light_age[slot] = age
		var fade := 1.0 - age / _light_life[slot]
		var energy := _light_peak[slot] * fade * fade * randf_range(0.82, 1.0)
		# O LightBudget repõe light_energy = budget_energy × peso da distância no refresh logo abaixo.
		node.set_meta("budget_energy", energy)
		node.light_energy = energy
		if slot == 0 and has_anchor: node.global_position = anchor_xform.origin + _light_offset[0]
	if _hot_active > 0:
		var now := _now()
		var shells: Variant = _effects.get("_shells") if is_instance_valid(_effects) else null
		for index in _hot_until.size():
			if _hot_until[index] < 0.0 or now < _hot_until[index]: continue
			_hot_until[index] = -1.0
			_hot_active -= 1
			if shells is Array and index < (shells as Array).size():
				var shell: MeshInstance3D = (shells as Array)[index]
				if is_instance_valid(shell) and shell.material_override == _hot_brass: shell.material_override = null
		busy = busy or _hot_active > 0
	if LIGHT_BUDGET.enabled and (lights_on or _lights_new or _lights_changed):
		# Forçado só no quadro de luz nova: se alguém já rodou o refresh neste quadro, ela ficaria apagada.
		LIGHT_BUDGET.refresh(_lights_new)
	_lights_new = false
	_lights_changed = false
	if not busy and not lights_on: set_process(false)
	STALL_WORK.finish_slow("combat.muzzle_fx.process", began, 1000, self)

## Sob a cortina (CombatEffectsPrewarm): cada família dispara uma vez de verdade diante da câmera
## (clarão, luz, fumaça, faíscas), depois os nós do clarão ficam parados nos três materiais e a cápsula
## quente de fuzil é desenhada num nó do anel do CombatEffects. `CombatEffects.clear()` apaga tudo.
func prewarm(origin: Vector3, right: Vector3, up: Vector3) -> void:
	var kinds := ["pistol", "magnum", "smg", "rifle", "shotgun", "suppressed", "rocket", "npc"]
	for index in kinds.size():
		@warning_ignore("integer_division")
		var point := origin + right * (float(index % 4) - 1.5) * 1.3 - up * (1.7 + float(index / 4) * 0.9)
		_spawn(point, right, kinds[index], index == 0, 1.0)
	var meshes: Array[ArrayMesh] = []
	for variants in _meshes.values(): meshes.append_array(variants)
	for slot in _flash_nodes.size():
		var node := _flash_nodes[slot]
		_flash_age[slot] = -1.0
		node.mesh = meshes[(slot * 2) % meshes.size()]
		node.material_override = _flash_materials[slot % _flash_materials.size()]
		node.global_transform = Transform3D(Basis.looking_at(right, up).scaled(Vector3.ONE * 2.0), origin + right * (float(slot) - 4.0) * 0.6 - up * 3.6)
		node.visible = true
	var shells: Variant = _effects.get("_shells")
	if shells is Array and (shells as Array).size() > 2 and _hot_until.size() > 2:
		var shell: MeshInstance3D = (shells as Array)[2]
		shell.mesh = _rifle_shell_mesh
		shell.material_override = _hot_brass
		shell.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3.0), origin - up * 2.7 + right * 3.0)
		shell.visible = true
		if _hot_until[2] < 0.0: _hot_active += 1
		_hot_until[2] = _now() + 10.0
	set_process(true)

## Troca de região/descarga do jogo (CombatEffects.clear): para e limpa partículas, apaga luzes e
## clarões, devolve o latão frio às cápsulas.
func clear() -> void:
	_q_count = 0
	for slot in _flash_nodes.size():
		_flash_age[slot] = -1.0
		_flash_nodes[slot].visible = false
	for slot in _light_nodes.size():
		_light_age[slot] = -1.0
		_light_nodes[slot].visible = false
		_light_nodes[slot].set_meta("budget_energy", 0.0)
	_lights_new = false
	_lights_changed = false
	# Sem `restart()`: no Godot 4.7 ele emite na hora (set_emitting → _update_internal com time 0) e
	# soltaria uma baforada em cada vaga onde ela estava. Escondido, o que resta some; o próximo tiro mostra.
	for emitter in _smoke + _sparks:
		emitter.emitting = false
		emitter.visible = false
	_smoke_born.fill(-1000.0)
	_restore_shells()
	_anchor = null
	set_process(false)

## Descarga: sem `restart()` (os nós podem já estar saindo da árvore).
func shutdown() -> void:
	_q_count = 0
	for node in _flash_nodes:
		if is_instance_valid(node): node.visible = false
	for light in _light_nodes:
		if is_instance_valid(light): light.visible = false
	_light_age.fill(-1.0)
	_flash_age.fill(-1.0)
	for emitter in _smoke + _sparks:
		if is_instance_valid(emitter): emitter.emitting = false
	_restore_shells()
	_anchor = null

func _restore_shells() -> void:
	var shells: Variant = _effects.get("_shells") if is_instance_valid(_effects) else null
	for index in _hot_until.size():
		if _hot_until[index] < 0.0: continue
		_hot_until[index] = -1.0
		if shells is Array and index < (shells as Array).size():
			var shell: MeshInstance3D = (shells as Array)[index]
			if is_instance_valid(shell): shell.material_override = null
	_hot_active = 0
