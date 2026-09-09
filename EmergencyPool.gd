extends Node

# Object Pool para Veículos de Emergência (Polícia, Ambulância, Bombeiros)
# Mantém N objetos dormindo fora da tela sem colisão ativa.

const POOL_SIZE_POLICE = 4
const POOL_SIZE_AMBULANCE = 2
const POOL_SIZE_FIRE = 2
const POOL_SIZE_CORONER = 2

var _pool: Dictionary = {"police": [], "ambulance": [], "fire": [], "coroner": []}

func _ready():
	var em_scene = load("res://EmergencyVehicle.tscn")
	if not em_scene:
		return
	
	# Pré-aloca os objetos
	for i in range(POOL_SIZE_POLICE):
		_create_pooled(em_scene, "police", 0)
	for i in range(POOL_SIZE_AMBULANCE):
		_create_pooled(em_scene, "ambulance", 1)
	for i in range(POOL_SIZE_FIRE):
		_create_pooled(em_scene, "fire", 2)
	for i in range(POOL_SIZE_CORONER):
		_create_pooled(em_scene, "coroner", 3)

func _create_pooled(scene: PackedScene, key: String, type: int):
	var obj = scene.instantiate()
	obj.type = type
	obj.process_mode = Node.PROCESS_MODE_DISABLED
	obj.position = Vector2(9999, 9999) # Fora do mapa
	obj.collision_layer = 0
	obj.collision_mask = 0
	obj.hide()
	get_tree().get_root().call_deferred("add_child", obj)
	_pool[key].append(obj)

func get_vehicle(type: String) -> Node:
	if not _pool.has(type):
		return null
		
	for i in range(_pool[type].size()):
		var obj = _pool[type][i]
		if not is_instance_valid(obj):
			var em_scene = load("res://EmergencyVehicle.tscn")
			if em_scene:
				obj = em_scene.instantiate()
				obj.type = 0 if type == "police" else (1 if type == "ambulance" else (2 if type == "fire" else 3))
				obj.position = Vector2(9999, 9999)
				get_tree().get_root().call_deferred("add_child", obj)
				_pool[type][i] = obj
				
		if is_instance_valid(obj) and obj.is_node_ready() and not obj.visible:
			obj.show()
			obj.process_mode = Node.PROCESS_MODE_INHERIT
			# Pooling must run the vehicle's complete reset.  Merely showing a
			# previously dispatched ambulance/fire truck left its target, siren or
			# collision state stale and made the service fleet look disabled.
			if obj.has_method("activate"):
				obj.activate()
			else:
				obj.collision_layer = 2
				obj.collision_mask = 5
			return obj
			
	return null

func return_vehicle(obj: Node, _type: String = ""):
	if is_instance_valid(obj):
		if obj.has_method("_clear_tactical_doors"): obj._clear_tactical_doors()
		obj.hide()
		obj.process_mode = Node.PROCESS_MODE_DISABLED
		obj.position = Vector2(9999, 9999)
		obj.collision_layer = 0
		obj.collision_mask = 0
		if "velocity" in obj: obj.velocity = Vector2.ZERO
		if "target" in obj: obj.target = null
		for audio_key in ["siren_audio", "engine_audio"]:
			var audio = obj.get(audio_key)
			if is_instance_valid(audio): audio.stop()
