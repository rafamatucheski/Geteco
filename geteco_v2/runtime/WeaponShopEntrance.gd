extends Node

## Walk-up access for the two V2 Ammu-Nation branches. The existing room is
## loaded after the exterior camera has framed the real facade.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_ammunation", "mountain_gunshop"]
const CAMERA_SECONDS := 0.55

var session: Node
var _facade: Node3D
var _facade_id := ""
var _door_amount := 0.0
var _entering := false
var _leaving := false
var _definition_id := ""
var _definition: Dictionary = {}

func update(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play or session.get_tree().paused:
		return
	if session.state.place_id in IDS:
		_update_exit()
		return
	if not session.state.place_id.is_empty() or session.world.driving.occupied:
		return
	var id := "harbor_ammunation" if session.state.region_id == "harbor" else "mountain_gunshop" if session.state.region_id == "mountain" else ""
	if id.is_empty(): return
	if id != _definition_id:
		_definition_id = id
		_definition = PLACES.get_definition(id)
	var definition: Dictionary = _definition
	var player: CharacterBody3D = session.world.player
	var door: Vector3 = definition.exterior_position + Vector3(0, 0, 5.8 if id == "harbor_ammunation" else 2.7)
	var near := player.global_position.distance_to(door) < 9.0
	if near or (_facade_id == id and is_instance_valid(_facade)):
		_update_facade(id, near, delta)
	if not near or _entering or session.modal or session.is_transition_blocked() or player.input_locked or session.world.gameplay.health <= 0:
		return
	var local: Vector3 = player.global_position - door
	# The actor must intentionally walk into the centre of the physical doorway.
	# Proximity opens the door, but standing beside it never enters the shop.
	if absf(local.x) > (1.05 if id == "harbor_ammunation" else 0.62): return
	if local.z < 0.15 or local.z > 1.15 or player.velocity.z > -0.7: return
	_enter(id, definition)

func _update_facade(id: String, near: bool, delta: float) -> void:
	if not is_instance_valid(_facade) or _facade_id != id:
		_facade = null
		_facade_id = ""
		for candidate in get_tree().get_nodes_in_group("v2_weapon_shop_facade"):
			if str(candidate.get_meta("place_id", "")) == id:
				_facade = candidate
				_facade_id = id
				_door_amount = float(candidate.get("open_amount"))
				break
	if not is_instance_valid(_facade): return
	var next := move_toward(_door_amount, 1.0 if near or _entering else 0.0, delta / 0.28)
	if not is_equal_approx(next, _door_amount):
		_door_amount = next
		_facade.set_open_amount(_door_amount)

func _enter(id: String, definition: Dictionary) -> void:
	_entering = true
	var player: CharacterBody3D = session.world.player
	player.input_locked = true
	var camera = session.world.camera
	var focus: Vector3 = definition.exterior_position + Vector3(0, 1.2, 2.0 if id == "harbor_ammunation" else 0.0)
	var size := 11.0 if id == "harbor_ammunation" else 8.0
	camera.focus_on_store(focus, size, CAMERA_SECONDS)
	await get_tree().create_timer(CAMERA_SECONDS).timeout
	if not is_instance_valid(session) or not is_instance_valid(player): return
	player.input_locked = false
	if session.state.place_id.is_empty() and session.state.region_id == definition.region and session.world.gameplay.health > 0:
		await session.enter_place(id, true, id)
	if is_instance_valid(camera): camera.clear_store_focus()
	_entering = false

func _update_exit() -> void:
	if _leaving or _entering or session.modal or session.is_transition_blocked() or session.world.driving.occupied:
		return
	var player: CharacterBody3D = session.world.player
	if player.input_locked or not is_instance_valid(session.room): return
	var exit_point: Vector3 = session.room.exit_position
	var local := player.global_position - exit_point
	if absf(local.x) > 0.75 or local.z < -0.55 or local.z > 0.45 or player.velocity.z < 0.7:
		return
	_leave()

func _leave() -> void:
	_leaving = true
	await session.leave_place()
	_leaving = false
