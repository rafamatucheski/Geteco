extends Node
## Walk into the ship hold or cave; the sewer uses explicit interaction.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_sewer", "santa_mare_hold", "mountain_mystery_cave"]
const ZOOM_SECONDS := .55
var session: Node
var definitions: Dictionary = {}
var busy := false
var blocked_id := ""
var current_place := ""
var exit_armed := false
var hatch: Node3D
var hatch_id := ""

func handles_place(id: String) -> bool:
	return id in IDS

func _ready() -> void:
	for id in IDS: definitions[id] = PLACES.get_definition(id)

func _blocked() -> bool:
	return busy or session.modal or session.is_transition_blocked() or session.world.player.input_locked or session.world.gameplay.health <= 0 or session.world.driving.occupied or session.world.driving.is_body_transition_active()

func _door(id: String) -> Vector3:
	var definition: Dictionary = definitions[id]
	if id == "mountain_mystery_cave": return definition.exterior_position + Vector3(0,0,.9)
	return definition.entry_position

func update(delta: float) -> void:
	if not session.ready_for_play or session.get_tree().paused: return
	var place: String = session.state.place_id
	if place != current_place:
		current_place = place
		exit_armed = false
	if handles_place(place):
		if not is_instance_valid(session.room) or _blocked(): return
		var offset: Vector3 = session.room.exit_position-session.world.player.global_position
		offset.y = 0
		if offset.length() > 1.3: exit_armed = true
		if exit_armed and offset.length() < .8 and session.world.player.velocity.dot(offset.normalized()) > .3:
			_leave(place)
		return
	if not place.is_empty(): return
	var point: Vector3 = session.world.player.global_position
	var id := ""
	var distance := INF
	for candidate in IDS:
		if candidate == "harbor_sewer": continue
		if definitions[candidate].region != session.state.region_id: continue
		var d := point.distance_squared_to(_door(candidate))
		if d < distance: distance = d; id = candidate
	if id.is_empty(): return
	if not blocked_id.is_empty() and (blocked_id != id or distance > 6.25): blocked_id = ""
	_update_hatch(id, distance < 9.0 and not _blocked(), delta)
	if _blocked() or blocked_id == id: return
	var offset := point-_door(id)
	if id == "mountain_mystery_cave":
		if absf(offset.x) > .72 or offset.z < -.25 or offset.z > .6 or session.world.player.velocity.z > -.5: return
	elif distance > .55*.55 or session.world.player.velocity.length_squared() < .3:
		return
	blocked_id = id
	_enter(id)

func _update_hatch(id: String, opened: bool, delta: float) -> void:
	if hatch_id != id:
		if is_instance_valid(hatch): hatch.set_open_amount(0.0)
		hatch = null
		hatch_id = id
	if not is_instance_valid(hatch) and opened:
		if id == "santa_mare_hold": hatch = get_tree().get_first_node_in_group("santa_mare_hold_hatch") as Node3D
	if is_instance_valid(hatch) and not busy:
		hatch.set_open_amount(move_toward(float(hatch.get("open_amount")),1.0 if opened else 0.0,delta/.35))

func _enter(id: String) -> void:
	busy = true
	var player: CharacterBody3D = session.world.player
	var camera = session.world.camera
	var generation: int = session.transition_generation
	player.input_locked = true
	camera.focus_on_store(_door(id)+Vector3.UP*.5,8.0,ZOOM_SECONDS)
	await get_tree().create_timer(ZOOM_SECONDS).timeout
	var admitted: bool = session.transition_generation == generation and not session.modal and not session.is_transition_blocked() and session.world.gameplay.health > 0
	if admitted:
		player.input_locked = false
		await session.enter_place(id,true,id)
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)
	if is_instance_valid(camera): camera.clear_store_focus()
	if not session.modal and not session.is_transition_blocked(): player.input_locked = false
	busy = false

func _leave(id: String) -> void:
	busy = true
	var left: bool = await session.leave_place()
	if left:
		blocked_id = id
		var player = session.world.player
		player.input_locked = true
		var camera = session.world.camera
		camera.zoom_out_from_store(_door(id),8.0,ZOOM_SECONDS)
		camera._process(0.0)
		await get_tree().create_timer(ZOOM_SECONDS).timeout
		camera.clear_store_focus()
		if not session.modal and not session.is_transition_blocked(): player.input_locked = false
	busy = false
