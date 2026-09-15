extends Node

# Object Pool para Veículos de Emergência (Polícia, Ambulância, Bombeiros)
# Mantém N objetos dormindo fora da tela sem colisão ativa.

const POOL_SIZE_POLICE = 7 # Three sedans, two SUVs and two motorcycle patrols.
const POOL_SIZE_AMBULANCE = 2
const POOL_SIZE_FIRE = 2
const POOL_SIZE_CORONER = 2

var _pool: Dictionary = {"police": [], "ambulance": [], "fire": [], "coroner": []}
var _officer_reserve: Dictionary = {}
var _police_suv_slots: Array = [0, 2, 3, 5, 6]

func prepare_officers() -> void:
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	# One initial full deployment per tier, bounded by the existing fleet size.
	# Detached unused units have no active groups, physics, audio or viewport.
	var scene := load("res://PoliceOfficer.tscn") as PackedScene
	for level in [1, 3, 4, 5, 6]:
		if not _officer_reserve.has(level): _officer_reserve[level] = []
		var reserve: Array = _officer_reserve[level]
		while reserve.size() < POOL_SIZE_POLICE * 2:
			await batch.checkpoint(get_tree())
			var officer := scene.instantiate() as Node2D
			officer.set_meta("response_tier_level", level)
			officer.set_meta("crew_preparing", true)
			officer.process_mode = Node.PROCESS_MODE_DISABLED
			officer.hide()
			add_child(officer)
			remove_child(officer)
			officer.remove_meta("crew_preparing")
			reserve.append(officer)

func take_officer(level: int) -> Node2D:
	var key := clampi(level, 1, 6)
	if key == 2: key = 1
	var reserve: Array = _officer_reserve.get(key, [])
	if reserve.is_empty():
		return load("res://PoliceOfficer.tscn").instantiate()
	var officer: Node2D = reserve.pop_back()
	# No used or dead officer returns here: combat/loot state is never recycled.
	# The caller assigns target, tier and disembark state before adding it.
	officer.request_ready()
	officer.process_mode = Node.PROCESS_MODE_INHERIT
	officer.show()
	return officer

func _exit_tree() -> void:
	for reserve in _officer_reserve.values():
		for officer in reserve:
			if is_instance_valid(officer): officer.free()
	_officer_reserve.clear()

func prepare_presentations() -> void:
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	# Called behind the loading screen. Pooling just the 2D shell leaves the
	# expensive model/doors/wheels to be assembled on the first dispatch.
	for fleet in _pool.values():
		for vehicle in fleet:
			if not is_instance_valid(vehicle) or not vehicle.is_node_ready(): continue
			if vehicle.visual_3d != null: continue
			await batch.checkpoint(get_tree())
			if is_instance_valid(vehicle): vehicle.ensure_presentation()
	await prepare_officers()

func _ready():
	# Shuffle bodies once, then preserve each slot across pooling/replacement.
	# Low-level patrols can also get an SUV, without rebuilding cars on dispatch.
	_police_suv_slots.shuffle()
	_police_suv_slots.resize(2)
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
	if key == "police":
		if _pool[key].size() in [1, 4]: obj.police_variant = "motorcycle"
		obj.police_archetype = "police_suv" if _pool[key].size() in _police_suv_slots else "police_cruiser"
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
	if type == "police": _retire_empty_police_offscreen()
	# Reuse the visible ambulance at its real hospital bay before waking a
	# hidden pooled unit. Dispatch preserves this departure position.
	for parked in _pool[type]:
		if is_instance_valid(parked) and bool(parked.get_meta("hospital_available", false)) and not parked.is_broken:
			var at: Vector2 = parked.global_position
			var facing: float = parked.global_rotation
			parked.activate()
			parked.set_meta("hospital_departure_position", at)
			parked.set_meta("hospital_departure_rotation", facing)
			return parked
		
	for i in range(_pool[type].size()):
		var obj = _pool[type][i]
		var wanted := get_node_or_null("/root/WantedManager")
		if type == "police" and i in [1, 4] and wanted and wanted.current_stars >= 3: continue
		if not is_instance_valid(obj):
			var em_scene = load("res://EmergencyVehicle.tscn")
			if em_scene:
				obj = em_scene.instantiate()
				obj.type = 0 if type == "police" else (1 if type == "ambulance" else (2 if type == "fire" else 3))
				if type == "police":
					if i in [1, 4]: obj.police_variant = "motorcycle"
					obj.police_archetype = "police_suv" if i in _police_suv_slots else "police_cruiser"
				obj.process_mode = Node.PROCESS_MODE_DISABLED
				obj.hide()
				obj.collision_layer = 0
				obj.collision_mask = 0
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

func _retire_empty_police_offscreen() -> void:
	var wanted := get_node_or_null("/root/WantedManager")
	if wanted == null: return
	var suspect: Node2D = wanted.get_suspect_actor()
	if not is_instance_valid(suspect): return
	var camera := suspect.get_viewport().get_camera_2d()
	var view_rect := Rect2()
	if camera:
		var size := suspect.get_viewport_rect().size / camera.zoom
		view_rect = Rect2(camera.get_screen_center_position() - size * .5, size).grow(150.0)
	for unit in _pool.police:
		if not is_instance_valid(unit) or not unit.visible: continue
		if not unit.get_meta("police_player_pursuit", false) or unit.get("is_driven_by_player") == true: continue
		if unit.has_police_response_crew(): continue
		# Empty cars remain physical, stealable wrecks at the encounter. Only
		# retire an unseen, distant shell; never invent a driver or move it home.
		if unit.global_position.distance_to(suspect.global_position) < 1800.0: continue
		if camera and view_rect.has_point(unit.global_position): continue
		unit._deactivate()

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
