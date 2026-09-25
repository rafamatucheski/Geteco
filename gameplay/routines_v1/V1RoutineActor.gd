extends CharacterBody3D
## Corpo fisico desacoplado para rotinas ambientais do V1. Deliberadamente nao
## expoe health, receive_damage, take_damage ou die: combate nao faz parte deste
## modulo e Maciota/mecanico nunca sao catalogados aqui.

signal activity_changed(routine_id: String, activity: String)

var definition: Dictionary = {}
var route: Array[Vector3] = []
var route_index := 0
var home := Vector3.ZERO
var destination := Vector3.ZERO
var model: Node3D
var carried_crate: Node3D
var carrying := false
var crate_stock: Array[int] = [3, 0]
var deliveries := 0
var source_index := 0
var activity := "idle"
var activity_left := 0.0
var travel_left := 0.0
var routine_cycle := 0
var dialogue_index := 0
var point_clear := Callable()
var rng := RandomNumberGenerator.new()

func configure(spec: Dictionary, clear_callback := Callable()) -> void:
	definition = spec.duplicate(true)
	point_clear = clear_callback
	name = str(definition.get("id","V1RoutineActor"))
	set_meta("v1_routine_id",definition.get("id",""))
	set_meta("persistent_id",definition.get("id",""))
	set_meta("gameplay_role","ambient_worker")
	for point in definition.get("route",[]):
		if point is Vector3: route.append(point)
	position = definition.get("position",Vector3.ZERO)
	home = position
	destination = route[0] if not route.is_empty() else home
	rng.seed = hash(definition.get("id","v1_routine"))

func _ready() -> void:
	add_to_group("v1_routine_actor")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .86
	add_child(collision)
	_build_model()
	if definition.get("kind","") == "dock_worker": _build_carried_crate()
	var stationary: bool = bool(definition.get("stationary",false))
	set_physics_process(not stationary)
	set_process(false)
	if not stationary and route.is_empty():
		activity_left = 1.5 + rng.randf_range(0.0,2.0)
	elif not route.is_empty():
		activity = "pickup"
		activity_left = .9
		_sync_model(false)
	if definition.get("kind", "") == "dock_worker" and get_parent().get("gameplay") != null:
		preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self, model, get_parent().gameplay)

func _build_model() -> void:
	if definition.get("kind","") == "dock_worker":
		model = preload("res://gameplay/routines_v1/DockWorkerModel.gd").new()
		model.worker_index = int(definition.get("worker_index",0))
	else:
		model = preload("res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd").new()
		model.role = str(definition.get("role","ranger"))
		model.coat_color = definition.get("coat_color",Color("3f6872"))
		model.appearance_variant = int(definition.get("appearance_variant",0))
		model.appearance_female = str(definition.get("display_name","")).to_upper() in ["NORA","LIA","INES","INÊS","HELENA","RUTE","IRIS","ÍRIS","DORA","ANA","MILA","LUISA","LUÍSA","CECILIA","CECÍLIA"]
	add_child(model)
	model.rotation.y = PI

func _build_carried_crate() -> void:
	carried_crate = Node3D.new()
	carried_crate.name = "CarriedCrate"
	carried_crate.position = Vector3(0,1.0,-.34)
	add_child(carried_crate)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("ab7c49")
	wood.roughness = .85
	var slat := StandardMaterial3D.new()
	slat.albedo_color = Color("d0a66b")
	slat.roughness = .9
	_box(carried_crate,Vector3.ZERO,Vector3(.46,.34,.36),wood)
	for x in [-.17,.17]: _box(carried_crate,Vector3(x,0,-.01),Vector3(.05,.35,.38),slat)
	carried_crate.hide()

func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.material_override = material
	parent.add_child(mesh)

func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	if not route.is_empty(): _tick_cargo_route(delta)
	else: _tick_mountain_routine(delta)
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	var horizontal := Vector3(velocity.x,0,velocity.z)
	if horizontal.length_squared() > .01:
		model.rotation.y = lerp_angle(model.rotation.y,atan2(-horizontal.x,-horizontal.z),1.0-exp(-12.0*delta))
	if activity == "work" and model.get("work_time") != null:
		model.work_pose_active = true
		model.work_target = Vector3(0,0,-.8)
		model.work_time += delta
	elif model.get("work_pose_active") != null:
		model.work_pose_active = false
	_sync_model(horizontal.length_squared() > .01)

func _tick_cargo_route(delta: float) -> void:
	if activity in ["pickup","put_down","rest"]:
		velocity.x = 0
		velocity.z = 0
		activity_left -= delta
		if activity_left > 0: return
		if activity == "pickup":
			if crate_stock[source_index] > 0:
				crate_stock[source_index] -= 1
				carrying = true
				route_index = (route_index + 1) % route.size()
				_set_activity("carry")
			else:
				_set_activity("rest", .8)
		elif activity == "put_down":
			crate_stock[1 - source_index] += 1
			carrying = false
			deliveries += 1
			_set_activity("rest",.8)
		else:
			if crate_stock[source_index] == 0 and crate_stock[1 - source_index] > 0:
				source_index = 1 - source_index
			if route_index == source_index * 2 and crate_stock[source_index] > 0:
				_set_activity("pickup", 1.8)
			else:
				route_index = (route_index + 1) % route.size()
				_set_activity("return")
		return
	var offset := route[route_index] - global_position
	offset.y = 0
	if offset.length() < .38:
		if route_index == source_index * 2 and not carrying:
			_set_activity("pickup",1.8)
		elif route_index == (1 - source_index) * 2 and carrying:
			_set_activity("put_down",1.6)
		else:
			route_index = (route_index + 1) % route.size()
		return
	var direction := offset.normalized()
	velocity.x = direction.x * (2.0 + float(int(definition.get("worker_index",0)) % 3) * .12)
	velocity.z = direction.z * (2.0 + float(int(definition.get("worker_index",0)) % 3) * .12)

func _tick_mountain_routine(delta: float) -> void:
	activity_left -= delta
	if activity == "walk":
		travel_left -= delta
		var offset := destination - global_position
		offset.y = 0
		if offset.length() < .35 or travel_left <= 0:
			velocity.x = 0
			velocity.z = 0
			_set_activity("idle",rng.randf_range(5.0,10.0))
		else:
			var direction := offset.normalized()
			velocity.x = direction.x * rng.randf_range(1.25,1.55)
			velocity.z = direction.z * rng.randf_range(1.25,1.55)
		return
	velocity.x = 0
	velocity.z = 0
	if activity_left > 0: return
	routine_cycle += 1
	if routine_cycle % 2 == 0 and _choose_wander_target():
		travel_left = 8.0
		_set_activity("walk",travel_left)
	elif definition.get("role","") == "logger" and routine_cycle % 3 == 0:
		_set_activity("work",rng.randf_range(6.0,10.0))
	else:
		_set_activity("drink" if routine_cycle % 3 == 1 else "warm",rng.randf_range(5.0,9.0))

func _choose_wander_target() -> bool:
	var radius: float = float(definition.get("wander_radius",3.0))
	for _attempt in 8:
		var distance := rng.randf_range(radius*.46,radius)
		var angle := rng.randf_range(0,TAU)
		var candidate := home + Vector3(cos(angle),0,sin(angle)) * distance
		if not point_clear.is_valid() or point_clear.call(candidate+Vector3.UP*.04):
			destination = candidate
			return true
	return false

func begin_interaction() -> void:
	velocity.x = 0
	velocity.z = 0
	activity = "talk"
	activity_left = 4.5
	if not is_physics_processing(): set_process(true)
	_sync_model(false)
	activity_changed.emit(str(definition.get("id","")),activity)

func next_dialogue_line() -> String:
	var lines: Array = definition.get("lines", [])
	if lines.is_empty(): return ""
	var message := str(lines[dialogue_index % lines.size()])
	dialogue_index = (dialogue_index + 1) % lines.size()
	return message

func crate_total() -> int:
	return crate_stock[0] + crate_stock[1] + int(carrying)

func snapshot_routine() -> Dictionary:
	return {
		"position": global_position if is_inside_tree() else position,
		"velocity": velocity,
		"route_index": route_index,
		"destination": destination,
		"carrying": carrying,
		"crate_stock": crate_stock.duplicate(),
		"deliveries": deliveries,
		"source_index": source_index,
		"activity": activity,
		"activity_left": activity_left,
		"travel_left": travel_left,
		"routine_cycle": routine_cycle,
		"dialogue_index": dialogue_index,
		"rng_state": rng.state,
	}

func restore_routine(state: Dictionary, restore_position := true) -> void:
	if restore_position and state.get("position") is Vector3:
		global_position = state.position
		reset_physics_interpolation()
	if state.get("velocity") is Vector3: velocity = state.velocity
	route_index = clampi(int(state.get("route_index", route_index)), 0, maxi(0, route.size() - 1))
	if state.get("destination") is Vector3: destination = state.destination
	carrying = bool(state.get("carrying", carrying))
	var stock: Variant = state.get("crate_stock")
	if stock is Array and stock.size() == 2:
		crate_stock.assign([maxi(0, int(stock[0])), maxi(0, int(stock[1]))])
	deliveries = maxi(0, int(state.get("deliveries", deliveries)))
	source_index = clampi(int(state.get("source_index", source_index)), 0, 1)
	activity = str(state.get("activity", activity))
	activity_left = maxf(0.0, float(state.get("activity_left", activity_left)))
	travel_left = maxf(0.0, float(state.get("travel_left", travel_left)))
	routine_cycle = maxi(0, int(state.get("routine_cycle", routine_cycle)))
	dialogue_index = maxi(0, int(state.get("dialogue_index", dialogue_index)))
	if state.has("rng_state"): rng.state = int(state.rng_state)
	if not is_physics_processing() and activity == "talk": set_process(true)
	_sync_model(activity in ["carry", "return", "walk"])

func _process(delta: float) -> void:
	activity_left -= delta
	if activity_left > 0: return
	activity = "idle"
	_sync_model(false)
	set_process(false)

func _set_activity(next: String, duration := 0.0) -> void:
	activity = next
	activity_left = duration
	activity_changed.emit(str(definition.get("id","")),activity)
	_sync_model(activity in ["carry","return","walk"])

func _sync_model(walking: bool) -> void:
	if not is_instance_valid(model): return
	if model.get("walking") != null: model.walking = walking
	if model.get("motion_speed") != null: model.motion_speed = Vector2(velocity.x,velocity.z).length()
	if model.get("activity") != null: model.activity = activity
	if is_instance_valid(carried_crate): carried_crate.visible = carrying
