class_name HarborInteriorManager
extends Node2D

## Coordinates playable interiors for HarborPreview.
## Links exterior HarborEntrance nodes to dedicated interior spaces, manages
## camera framing, transition cooldowns, modal dialogue focus, and exterior return points.

signal actor_entered_interior(actor: Node2D, interior_id: StringName)
signal actor_returned_to_exterior(actor: Node2D, interior_id: StringName)

@export var enabled: bool = true
@export var transition_cooldown: float = 0.35

const GARAGE_SCRIPT := preload("res://world/harbor/interiors/HarborGarageInterior.gd")
const POLICE_SCRIPT := preload("res://world/harbor/interiors/HarborPoliceInterior.gd")
const CLINIC_SCRIPT := preload("res://world/harbor/interiors/HarborClinicInterior.gd")
const WORKSHOP_SCRIPT := preload("res://world/harbor/interiors/HarborWorkshopInterior.gd")
const FIRE_STATION_SCRIPT := preload("res://world/harbor/interiors/HarborFireStationInterior.gd")
const AMMUNATION_SCRIPT := preload("res://world/harbor/interiors/HarborAmmunationInterior.gd")
const MORGUE_SCRIPT := preload("res://world/harbor/interiors/HarborMorgueInterior.gd")

var garage_interior: Node2D
var police_interior: Node2D
var clinic_interior: Node2D
var workshop_interior: Node2D
var fire_station_interior: Node2D
var ammunation_interior: Node2D
var morgue_interior: Node2D

# Maps destination_id -> Marker2D spawn point
var _destination_spawns: Dictionary = {}
# Maps exit_destination_id -> NodePath to exterior HarborEntrance
var _exit_return_entrances: Dictionary = {}
# Tracks last entered entrance per actor to support multi-door buildings (like Fire Station)
var _actor_origin_entrances: Dictionary = {}
# Maps an interior's exit BuildingEntrance -> the interior Node2D that owns it,
# so a departure can disable that interior's NPC rendering (see
# HarborInteriorBase.set_npc_rendering_active) without a per-building special case.
var _exit_door_interior: Dictionary = {}

func _ready() -> void:
	if not enabled:
		return
	_build_all_interiors()
	call_deferred("_bind_exterior_entrances")

func _build_all_interiors() -> void:
	var spaces_root := Node2D.new()
	spaces_root.name = "InteriorSpaces"
	add_child(spaces_root)

	# 1. Garage (Westgate Motor Co.)
	garage_interior = GARAGE_SCRIPT.new()
	garage_interior.name = "GarageInterior"
	garage_interior.position = Vector2(20000, 20000)
	spaces_root.add_child(garage_interior)

	# 2. Police (Harbor Patrol)
	police_interior = POLICE_SCRIPT.new()
	police_interior.name = "PoliceInterior"
	police_interior.position = Vector2(21400, 20000)
	spaces_root.add_child(police_interior)

	# 3. Clinic (Bay Medical) — enters from north
	clinic_interior = CLINIC_SCRIPT.new()
	clinic_interior.name = "ClinicInterior"
	clinic_interior.position = Vector2(22800, 20000)
	spaces_root.add_child(clinic_interior)

	# 4. Motor Workshop (Northgate Auto)
	workshop_interior = WORKSHOP_SCRIPT.new()
	workshop_interior.name = "WorkshopInterior"
	workshop_interior.position = Vector2(24200, 20000)
	spaces_root.add_child(workshop_interior)

	# 5. Fire Station (Northgate Fire / 03) — 3 bays
	fire_station_interior = FIRE_STATION_SCRIPT.new()
	fire_station_interior.name = "FireStationInterior"
	fire_station_interior.position = Vector2(25800, 20000)
	spaces_root.add_child(fire_station_interior)

	# 6. Reusable templates (Ammu-Nation & Morgue)
	ammunation_interior = AMMUNATION_SCRIPT.new()
	ammunation_interior.name = "AmmunationInterior"
	ammunation_interior.position = Vector2(27400, 20000)
	spaces_root.add_child(ammunation_interior)

	morgue_interior = MORGUE_SCRIPT.new()
	morgue_interior.name = "MorgueInterior"
	morgue_interior.position = Vector2(28800, 20000)
	spaces_root.add_child(morgue_interior)

	_connect_npc_dialogue_signals()
	_register_interior_exits()

func _connect_npc_dialogue_signals() -> void:
	for interior in [garage_interior, police_interior, clinic_interior, workshop_interior, fire_station_interior, ammunation_interior, morgue_interior]:
		if interior.has_signal("modal_opened"):
			if not interior.modal_opened.is_connected(_on_dialogue_opened):
				interior.modal_opened.connect(_on_dialogue_opened)
		if interior.has_signal("modal_closed"):
			if not interior.modal_closed.is_connected(_on_dialogue_closed):
				interior.modal_closed.connect(_on_dialogue_closed)
		for child in interior.get_children():
			if child.has_signal("dialogue_opened") and child.has_signal("dialogue_closed"):
				if not child.dialogue_opened.is_connected(_on_dialogue_opened):
					child.dialogue_opened.connect(_on_dialogue_opened)
				if not child.dialogue_closed.is_connected(_on_dialogue_closed):
					child.dialogue_closed.connect(_on_dialogue_closed)

func _register_interior_exits() -> void:
	# Garage exit
	if garage_interior.exit_door:
		_bind_exit_door(garage_interior.exit_door, &"harbor/District/Garage/Entrance", garage_interior)

	# Police exit
	if police_interior.exit_door:
		_bind_exit_door(police_interior.exit_door, &"harbor/District/Police/Entrance", police_interior)

	# Clinic exit
	if clinic_interior.exit_door:
		_bind_exit_door(clinic_interior.exit_door, &"harbor/District/Clinic/Entrance", clinic_interior)

	# Workshop exit
	if workshop_interior.exit_door:
		_bind_exit_door(workshop_interior.exit_door, &"harbor/NorthDistrict/MotorWorkshop/Entrance", workshop_interior)

	# Fire Station exits (Bays 0, 1, 2)
	for i in fire_station_interior.bay_exits.size():
		var bay_exit = fire_station_interior.bay_exits[i]
		_bind_exit_door(bay_exit, StringName("harbor/NorthDistrict/NorthFireStation/Entrance%d" % i), fire_station_interior)

func _bind_exit_door(door: BuildingEntrance, default_exterior_door_id: StringName, interior: Node2D) -> void:
	_exit_door_interior[door] = interior
	if not door.destination_requested.is_connected(_on_exit_door_requested):
		door.destination_requested.connect(_on_exit_door_requested.bind(default_exterior_door_id))

var _door_configs: Dictionary = {}

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E):
		var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
		var active_actor: Node2D = player
		for v in get_tree().get_nodes_in_group("vehicle"):
			if v.get("is_driven_by_player") == true:
				active_actor = v
				break

		# 1. Verificar saídas dos interiores
		for exit_door in get_tree().get_nodes_in_group("harbor_interior_exit"):
			if exit_door and exit_door.enabled and not exit_door.get("_busy") and exit_door.is_actor_in_range(active_actor):
				get_viewport().set_input_as_handled()
				exit_door.request_interaction(active_actor)
				return

		# 2. Verificar entradas exteriores
		var root_preview := get_parent()
		if root_preview == null:
			return

		for path in _door_configs:
			var entrance := root_preview.get_node_or_null(path) as BuildingEntrance
			if entrance and entrance.enabled and not entrance.get("_busy") and entrance.is_actor_in_range(active_actor):
				get_viewport().set_input_as_handled()
				entrance.request_interaction(active_actor)
				return

func _bind_exterior_entrances() -> void:
	var root_preview = get_parent()
	if root_preview == null:
		return

	# Map of exterior door paths to spawn points & interior refs
	_door_configs = {
		"District/Garage/Entrance": {
			"interior": garage_interior,
			"spawn": garage_interior.spawn_point,
			"id": &"harbor/District/Garage/Entrance"
		},
		"District/Police/Entrance": {
			"interior": police_interior,
			"spawn": police_interior.spawn_point,
			"id": &"harbor/District/Police/Entrance"
		},
		"District/Clinic/Entrance": {
			"interior": clinic_interior,
			"spawn": clinic_interior.spawn_point,
			"id": &"harbor/District/Clinic/Entrance"
		},
		"NorthDistrict/MotorWorkshop/Entrance": {
			"interior": workshop_interior,
			"spawn": workshop_interior.spawn_point,
			"id": &"harbor/NorthDistrict/MotorWorkshop/Entrance"
		},
		"NorthDistrict/NorthFireStation/Entrance0": {
			"interior": fire_station_interior,
			"spawn": fire_station_interior.get_spawn_for_bay(0),
			"id": &"harbor/NorthDistrict/NorthFireStation/Entrance0"
		},
		"NorthDistrict/NorthFireStation/Entrance1": {
			"interior": fire_station_interior,
			"spawn": fire_station_interior.get_spawn_for_bay(1),
			"id": &"harbor/NorthDistrict/NorthFireStation/Entrance1"
		},
		"NorthDistrict/NorthFireStation/Entrance2": {
			"interior": fire_station_interior,
			"spawn": fire_station_interior.get_spawn_for_bay(2),
			"id": &"harbor/NorthDistrict/NorthFireStation/Entrance2"
		}
	}

	for path in _door_configs:
		var entrance = root_preview.get_node_or_null(path) as BuildingEntrance
		if entrance:
			var cfg = _door_configs[path]
			entrance.destination_id = cfg.id
			entrance.set("interior_available", true)
			if not entrance.destination_requested.is_connected(_on_exterior_destination_requested):
				entrance.destination_requested.connect(_on_exterior_destination_requested.bind(cfg.interior, cfg.spawn))

func _on_exterior_destination_requested(entrance: BuildingEntrance, actor: Node2D, _dest_id: StringName, _scene: PackedScene, _spawn_name: StringName, interior: Node2D, spawn_marker: Marker2D) -> void:
	if not is_instance_valid(actor) or interior == null or spawn_marker == null:
		return

	# Record origin entrance for return routing
	_actor_origin_entrances[actor] = entrance

	# Arm cooldown on exterior door
	_arm_cooldown(entrance)

	# If actor is inside a car or is car
	var effective_actor := actor
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		player.set_meta("police_exterior_position", entrance.global_position)
		player.set_meta("harbor_interior", true)
	if actor.is_in_group("vehicle") and actor.get("is_driven_by_player") == true:
		effective_actor = actor
		if player and is_instance_valid(player):
			player.global_position = spawn_marker.global_position
			player.velocity = Vector2.ZERO
			_actor_origin_entrances[player] = entrance
			_frame_interior_camera(player, interior.get_camera_rect())

	effective_actor.global_position = spawn_marker.global_position
	if "velocity" in effective_actor:
		effective_actor.velocity = Vector2.ZERO

	if effective_actor == player:
		for col in player.find_children("", "CollisionShape2D", true, false):
			col.disabled = false

	# Adjust camera limits
	_frame_interior_camera(effective_actor, interior.get_camera_rect())

	# Arm cooldown on interior exit door
	if interior.exit_door:
		_arm_cooldown(interior.exit_door)

	interior.set_npc_rendering_active(true)
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather and weather.has_method("set_interior_mode"):
		weather.set_interior_mode(true)
	actor_entered_interior.emit(effective_actor, interior.interior_id)

func _on_exit_door_requested(exit_door_node: BuildingEntrance, actor: Node2D, _dest_id: StringName, _scene: PackedScene, _spawn_name: StringName, default_exterior_door_id: StringName) -> void:
	if not is_instance_valid(actor):
		return

	var origin_entrance = _actor_origin_entrances.get(actor) as BuildingEntrance
	if origin_entrance == null or not is_instance_valid(origin_entrance):
		# If actor is player, check if vehicle was registered
		for v in get_tree().get_nodes_in_group("vehicle"):
			if _actor_origin_entrances.has(v):
				origin_entrance = _actor_origin_entrances.get(v) as BuildingEntrance
				break
		if origin_entrance == null or not is_instance_valid(origin_entrance):
			var root_preview = get_parent()
			if root_preview:
				for node in root_preview.get_tree().get_nodes_in_group("harbor_entrance"):
					if node.get("destination_id") == default_exterior_door_id:
						origin_entrance = node
						break

	var return_pos := Vector2.ZERO
	if origin_entrance != null and is_instance_valid(origin_entrance):
		var return_marker = origin_entrance.get_node_or_null("OutsideReturn") as Marker2D
		if return_marker:
			return_pos = return_marker.global_position
		else:
			return_pos = origin_entrance.to_global(Vector2(0, 42))
		_arm_cooldown(origin_entrance)
	else:
		return_pos = Vector2(715, 1800) # Safe city fallback

	var effective_actor := actor
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if actor.is_in_group("vehicle") and actor.get("is_driven_by_player") == true:
		effective_actor = actor
		if player and is_instance_valid(player):
			player.global_position = return_pos
			player.velocity = Vector2.ZERO
			_reset_exterior_camera(player)

	effective_actor.global_position = return_pos
	if player:
		player.remove_meta("police_exterior_position")
		player.remove_meta("harbor_interior")
	if "velocity" in effective_actor:
		effective_actor.velocity = Vector2.ZERO

	if effective_actor == player:
		player.show()
		player.set_physics_process(true)
		for col in player.find_children("", "CollisionShape2D", true, false):
			col.disabled = false

	_reset_exterior_camera(effective_actor)

	if exit_door_node:
		_arm_cooldown(exit_door_node)
		var interior: Node2D = _exit_door_interior.get(exit_door_node)
		if interior:
			interior.set_npc_rendering_active(false)

	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather and weather.has_method("set_interior_mode"):
		weather.set_interior_mode(false)

	actor_returned_to_exterior.emit(effective_actor, default_exterior_door_id)

func _frame_interior_camera(actor: Node2D, rect: Rect2) -> void:
	var cam := actor.get_node_or_null("Camera") as Camera2D
	if cam:
		if rect.size.x < 500:
			cam.set_meta("compact_interior", rect)
			cam.global_position = rect.get_center()
			var screen := cam.get_viewport_rect().size
			cam.zoom = Vector2.ONE * minf(screen.x / rect.size.x, screen.y / rect.size.y) * 0.88
			cam.limit_left = -10000000
			cam.limit_top = -10000000
			cam.limit_right = 10000000
			cam.limit_bottom = 10000000
			cam.reset_smoothing()
			return
		else:
			cam.remove_meta("compact_interior")
		cam.limit_left = int(rect.position.x - 20)
		cam.limit_top = int(rect.position.y - 20)
		cam.limit_right = int(rect.position.x + rect.size.x + 20)
		cam.limit_bottom = int(rect.position.y + rect.size.y + 20)
		if cam.has_method("reset_smoothing"):
			cam.reset_smoothing()

func _reset_exterior_camera(actor: Node2D) -> void:
	var cam := actor.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.remove_meta("compact_interior")
		cam.position = Vector2.ZERO
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000
		if cam.has_method("reset_smoothing"):
			cam.reset_smoothing()

func _arm_cooldown(entrance: BuildingEntrance) -> void:
	if entrance == null:
		return
	entrance.enabled = false
	await get_tree().create_timer(transition_cooldown).timeout
	if is_instance_valid(entrance):
		entrance.enabled = true

func _on_dialogue_opened() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_dialogue_active"):
		player.set_dialogue_active(true)

func _on_dialogue_closed() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_dialogue_active"):
		player.set_dialogue_active(false)
