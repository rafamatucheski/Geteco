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

var controller
var _spawned: Dictionary = {} # den id -> Array[MountainBear3D]
var _clock := 0.0

func _ready() -> void:
	name = "MountainWildlife"

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
		if step == 0:
			var mother := BEAR.new()
			mother.name = "ForestBear_" + String(den.id)
			mother.controller = controller
			mother.home = job.home
			add_child(mother)
			mother.global_position = _ground(job.region, job.home)
			bears.append(mother)
		else:
			var offset: Vector2 = den.cubs[step-1]
			var cub := BEAR.new()
			cub.name = "BearCub_" + String(den.id) + "_" + str(bears.size())
			cub.controller = controller
			cub.is_cub = true
			cub.family_guardian = bears[0]
			cub.family_offset = Vector3(offset.x, 0, offset.y) / 16.0
			cub.home = job.home + cub.family_offset
			add_child(cub)
			cub.global_position = _ground(job.region, cub.home)
			bears.append(cub)
		job.step = step + 1
		if int(job.step) > den.cubs.size(): _queue.pop_front()
		return

func _despawn(id: String) -> void:
	for bear in _spawned[id]:
		if is_instance_valid(bear): bear.queue_free()
	_spawned.erase(id)
