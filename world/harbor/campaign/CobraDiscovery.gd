extends Node

## Snapshot the one authored coupe; never creates another vehicle.
const SECRET_ID := "ashbend_coupe"
# Outdoor envelope; real interior camera bounds are admitted separately.
const WORLD_ENVELOPE := Rect2(-5000, -12000, 19000, 22000)
var _ledger: RefCounted
var _world: Node
var _car: CharacterBody2D
var _namespace: Dictionary = {}
var _parking_pose := Transform2D.IDENTITY
var _authored_max_speed := 0.0

func configure(world: Node, ledger: RefCounted) -> void:
	_world = world
	_ledger = ledger
	var vehicles := world.find_child("CobraVehicles", true, false)
	if vehicles == null:
		return
	_car = vehicles.get("secret_car")
	if not is_instance_valid(_car):
		return
	_parking_pose = _car.global_transform
	_authored_max_speed = float(_car.get("max_speed"))
	_ledger.call("sync_legacy")
	_namespace = _ledger.get("data")
	restore_snapshot()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_car) or _ledger == null:
		return
	var current: Dictionary = _ledger.get("data")
	if not is_same(current, _namespace):
		_ledger.call("sync_legacy")
		_namespace = _ledger.get("data")
		restore_snapshot()
	capture_snapshot()

func capture_snapshot() -> void:
	if not is_instance_valid(_car) or _ledger == null:
		return
	var state: Dictionary = _ledger.get("data")
	var owned: Dictionary = state.get("secret_owned", {})
	if not bool(_car.get("is_driven_by_player")) and not owned.has(SECRET_ID):
		return
	var point := _car.global_position
	if not _valid_pose(point):
		# Preserve the last valid pose if an invalid/debug position is encountered.
		return
	var paint: Color = _car.get("paint_color")
	owned[SECRET_ID] = {"owned": true, "position": [point.x, point.y],
		"rotation": _car.global_rotation, "paint": paint.to_html(true),
		"health": int(_car.get("health")), "was_driven": bool(_car.get("is_driven_by_player"))}
	state["secret_owned"] = owned

func restore_snapshot() -> void:
	if not is_instance_valid(_car) or _ledger == null:
		return
	var state: Dictionary = _ledger.get("data")
	var record: Variant = state.get("secret_owned", {}).get(SECRET_ID, {})
	if not record is Dictionary or record.is_empty():
		return
	var position_data: Variant = record.get("position", [])
	var point := _parking_pose.origin
	if position_data is Array and position_data.size() == 2:
		var candidate := Vector2(float(position_data[0]), float(position_data[1]))
		if _valid_pose(candidate):
			point = candidate
	var angle := float(record.get("rotation", _parking_pose.get_rotation()))
	_car.global_position = point
	_car.global_rotation = angle if is_finite(angle) else _parking_pose.get_rotation()
	_car.velocity = Vector2.ZERO
	_car.call("repair_vehicle")
	_car.set("max_speed", _authored_max_speed)
	_car.call("repaint_vehicle", Color.from_string(str(record.get("paint", "9f673f")), Color("9f673f")))
	var hp := clampi(int(record.get("health", 100)), 0, int(_car.get("max_health")))
	# Restoring damage is not a fresh collision: do not replay explosions or
	# dispatch a fire engine merely because the save contained a wreck.
	_car.set("health", hp)
	_car.set("is_broken", hp == 0)
	_car.set("is_exploded", hp == 0)
	_car.set("is_exploding", false)
	if hp == 0:
		_car.set("max_speed", 0.0)
	# SaveManager restores the player on foot at the driven vehicle's position.
	# Re-enter that same vehicle only when both saved poses actually agree.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if hp > 0 and bool(record.get("was_driven", false)) and is_instance_valid(player):
		if player.global_position.distance_to(point) < 150.0:
			_car.call("enter_vehicle", player)
	_restore_interior_context(player)

func _interior_at(point: Vector2) -> Node2D:
	if not is_inside_tree():
		return null
	for interior in get_tree().get_nodes_in_group("harbor_interior"):
		if _world.is_ancestor_of(interior) and interior.has_method("get_camera_rect"):
			var bounds: Rect2 = interior.call("get_camera_rect")
			if bounds.has_point(point):
				return interior as Node2D
	return null

func _valid_pose(point: Vector2) -> bool:
	return point.is_finite() and (WORLD_ENVELOPE.has_point(point) or _interior_at(point) != null)

func _restore_interior_context(player: Node2D) -> void:
	if not is_instance_valid(player):
		return
	var interior := _interior_at(player.global_position)
	if interior == null:
		return
	interior.call("set_npc_rendering_active", true)
	var bounds: Rect2 = interior.call("get_camera_rect")
	# The production manager owns camera policy. Its exit doors already contain
	# a default exterior destination when per-session origin maps are absent.
	for node in _world.find_children("*", "", true, false):
		if node.has_method("_frame_interior_camera"):
			node.call("_frame_interior_camera", player, bounds)
			if bool(_car.get("is_driven_by_player")):
				node.call("_frame_interior_camera", _car, bounds)
			break
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather and weather.has_method("set_interior_mode"):
		weather.call("set_interior_mode", true)
