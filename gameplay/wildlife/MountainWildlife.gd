extends Node3D
## Tocas de urso de Mountain, nas posições da V1 (MountainSettlement.gd: ursa com
## dois filhotes em (8220,-1150) e urso solitário em (8670,-200), coordenada V1 de
## Mountain). Os ursos só existem com o jogador a menos de SPAWN_RADIUS da toca e
## somem além de DESPAWN_RADIUS, como o resto do streaming; ao voltar a uma toca
## depois de sair, os ursos mortos renascem (a V1 os "curava" por NPCMedicalCare).

const BEAR := preload("res://gameplay/wildlife/MountainBear3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const SPAWN_RADIUS := 110.0
const DESPAWN_RADIUS := 160.0
const DENS := [
	{"id": "family_den", "point": Vector2(8220, -1150), "cubs": [Vector2(-50, 35), Vector2(45, 48)]},
	{"id": "lone_den", "point": Vector2(8670, -200), "cubs": []},
]

## Os ursos eram destruídos além de DESPAWN_RADIUS e recriados ao voltar: a rota da serra sai das
## duas tocas a cada volta e cada volta pagava wildlife.bear_spawn de 22-26 ms e mais ~30 ms sem span
## (~90 malhas e ~90 StandardMaterial3D novos por urso; EXE de 17/10, perfinv9). Agora os quatro
## ursos são montados uma vez, na montagem do mundo, e ficam estacionados (escondidos, sem processo
## e fora do espaço de física) longe do jogador. GETECO_BEAR_POOL=0 volta ao criar/destruir (A/B).
static var _pool_enabled := OS.get_environment("GETECO_BEAR_POOL") != "0"
## Diagnóstico: GETECO_WILDLIFE=0 não solta urso nenhum.
static var _wildlife_enabled := OS.get_environment("GETECO_WILDLIFE") != "0"

var controller
var _spawned: Dictionary = {} # den id -> Array[MountainBear3D]
var _parked: Dictionary = {} # den id -> Array[MountainBear3D], só com o estacionamento ligado
var _clock := 0.0

func _ready() -> void:
	name = "MountainWildlife"
	# Sem fauna (A/B de 17/10: os passos de física de 30-45 ms perto da toca da família continuaram
	# iguais sem urso nenhum; eram da grama, MountainGrass3D).
	if not _wildlife_enabled:
		set_process(false)
		return
	# O primeiro urso da sessão gerava os sons (síntese em GDScript), as malhas compartilhadas e
	# as variantes de material na hora: wildlife.bear_spawn de 22,7 ms e quadro de 78 ms na
	# primeira volta da serra (EXE de 17/10). Um modelo descartável faz isso na montagem.
	var audio := preload("res://audio/wildlife/BearAudio.gd")
	audio.get_breathing_stream()
	audio.get_grunt_alert_stream()
	audio.get_charge_stream()
	var warm: Node3D = preload("res://gameplay/wildlife/MountainBearModel.gd").new()
	add_child(warm)
	warm.free()
	if _pool_enabled:
		for den in DENS: _parked[den.id] = _build_den(den, CATALOG._at(den.point, "mountain"))

func _build_den(den: Dictionary, home: Vector3) -> Array:
	var bears: Array = []
	for step in den.cubs.size() + 1:
		var bear = _make_bear(den, home, step, bears)
		add_child(bear)
		bear.park()
		bears.append(bear)
	return bears

func _make_bear(den: Dictionary, home: Vector3, step: int, bears: Array):
	var bear := BEAR.new()
	bear.controller = controller
	if step == 0:
		bear.name = "ForestBear_" + String(den.id)
		bear.home = home
	else:
		var offset: Vector2 = den.cubs[step-1]
		bear.name = "BearCub_" + String(den.id) + "_" + str(step)
		bear.is_cub = true
		bear.family_guardian = bears[0]
		bear.family_offset = Vector3(offset.x, 0, offset.y) / 16.0
		bear.home = home + bear.family_offset
	return bear

func _process(delta: float) -> void:
	_advance_queue()
	_clock += delta
	if _clock < 0.5: return
	_clock = 0.0
	var player: Node3D = controller.world.player if controller != null and controller.world != null else null
	var region = controller.regions.get("mountain") if controller != null else null
	for den in DENS:
		var home: Vector3 = CATALOG._at(den.point, "mountain")
		var near := player != null and is_instance_valid(region) and Vector2(player.global_position.x - home.x, player.global_position.z - home.z).length() < (DESPAWN_RADIUS if _spawned.has(den.id) else SPAWN_RADIUS)
		if near and not _spawned.has(den.id): _spawn(den, home, region)
		elif not near and _spawned.has(den.id): _despawn(den.id)

func _ground(region, point: Vector3) -> Vector3:
	var terrain = region.get("terrain")
	var y: float = terrain.surface_height_at(Vector2(point.x, point.z)) if terrain != null else 0.0
	return Vector3(point.x, y + 0.2, point.z)

## Uma toca (mãe e filhotes) nascia toda no mesmo quadro: cada urso monta modelo e áudio, 40-50 ms
## por toca. Agora um urso por quadro; a mãe sai primeiro e os filhotes a seguem.
var _queue: Array[Dictionary] = []

func _spawn(den: Dictionary, home: Vector3, region) -> void:
	if _parked.has(den.id):
		var traced := preload("res://runtime/StallWorkTrace.gd").begin()
		for bear in _parked[den.id]: bear.wake(_ground(region, bear.home))
		_spawned[den.id] = _parked[den.id]
		preload("res://runtime/StallWorkTrace.gd").finish("wildlife.bear_wake", traced)
		return
	_spawned[den.id] = []
	_queue.append({"den": den, "home": home, "region": region, "step": 0})

func _advance_queue() -> void:
	while not _queue.is_empty():
		var job: Dictionary = _queue[0]
		var den: Dictionary = job.den
		if not _spawned.has(den.id) or not is_instance_valid(job.region):
			_queue.pop_front()
			continue
		var bears: Array = _spawned[den.id]
		var step := int(job.step)
		var traced := preload("res://runtime/StallWorkTrace.gd").begin()
		var bear = _make_bear(den, job.home, step, bears)
		add_child(bear)
		bear.global_position = _ground(job.region, bear.home)
		bears.append(bear)
		preload("res://runtime/StallWorkTrace.gd").finish("wildlife.bear_spawn", traced)
		job.step = step + 1
		if int(job.step) > den.cubs.size(): _queue.pop_front()
		return

func _despawn(id: String) -> void:
	for bear in _spawned[id]:
		if not is_instance_valid(bear): continue
		if _parked.has(id): bear.park()
		else: bear.queue_free()
	_spawned.erase(id)
