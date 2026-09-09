extends Node

## One victory reward, independent from the discoverable Ashbend coupe.
const REWARD_ID := "cobra_boss_ironback"
const MODEL_PATH := "res://prototypes/living_cast/HarborBossMuscle.gd"
const BAY := Vector2(-220, 130)
const WORLD_ENVELOPE := Rect2(-5000, -12000, 19000, 22000)
var reward_car: CharacterBody2D
var _world: Node2D
var _garage: Node2D
var _ledger: RefCounted
var _namespace: Dictionary = {}
var _normal_speed := 560.0
var _retry_clock := 0.0
var recovery_panel: PanelContainer
var recovery_button: Button
var repair_button: Button
var _feedback: Label
var _owns_input := false

func configure(world: Node2D, ledger: RefCounted) -> void:
	_world = world
	_ledger = ledger
	_garage = world.get_node("Interiors").garage_interior
	_ledger.call("sync_legacy")
	_namespace = _ledger.get("data")
	if not _garage.has_node("IronbackRewardBay"):
		var marker := Marker2D.new()
		marker.name = "IronbackRewardBay"
		marker.position = BAY
		_garage.add_child(marker)
	if recovery_panel == null:
		_create_recovery_ui()
	sync_reward()

func _physics_process(delta: float) -> void:
	if _ledger == null or not is_instance_valid(_world):
		return
	var current: Dictionary = _ledger.get("data")
	if not is_same(current, _namespace):
		_ledger.call("sync_legacy")
		_namespace = _ledger.get("data")
		sync_reward(true)
	_retry_clock += delta
	if _retry_clock >= 0.5:
		_retry_clock = 0.0
		sync_reward()
	capture_snapshot()
	recovery_panel.visible = _can_recover_here()
	if not recovery_panel.visible:
		_unlock_input()
	recovery_button.text = _text("Recolher à baia (não repara)", "Tow to bay (does not repair)")
	repair_button.text = _text("Reparar Ironback na baia", "Repair Ironback in bay")

func _authorized() -> bool:
	var state: Dictionary = _ledger.get("data")
	return bool(state.get("defeated", false)) and bool(state.get("completed", {}).get("cobra_finale", false))

func sync_reward(restoring := false) -> void:
	if _ledger == null:
		return
	_ledger.call("sync_legacy")
	if not _authorized():
		if is_instance_valid(reward_car):
			if bool(reward_car.get("is_driven_by_player")):
				reward_car.call("exit_vehicle")
			reward_car.queue_free()
			reward_car = null
		return
	if not is_instance_valid(reward_car):
		var existing := _world.get_node_or_null("CobraBossIronback") as CharacterBody2D
		if existing and str(existing.get_meta("campaign_reward_id", "")) == REWARD_ID:
			reward_car = existing
		else:
			var pose := _saved_pose()
			if not _pose_clear(pose):
				return # Do not crush somebody occupying the bay or saved location.
			var model := load(MODEL_PATH) as Script
			if model == null:
				return
			reward_car = model.new()
			reward_car.name = "CobraBossIronback"
			reward_car.transform = _world.global_transform.affine_inverse() * pose
			reward_car.set_meta("campaign_reward_id", REWARD_ID)
			_world.add_child(reward_car)
			_normal_speed = float(reward_car.get("max_speed"))
			restoring = true
	if restoring:
		_restore_record()
	capture_snapshot()

func _record() -> Dictionary:
	var state: Dictionary = _ledger.get("data")
	var record: Variant = state.get("boss_owned", {}).get(REWARD_ID, {})
	return record if record is Dictionary else {}

func _saved_pose() -> Transform2D:
	var record := _record()
	var position := _garage.to_global(BAY)
	var raw: Variant = record.get("position", [])
	if raw is Array and raw.size() == 2:
		var candidate := Vector2(float(raw[0]), float(raw[1]))
		if _valid_position(candidate):
			position = candidate
	var rotation := float(record.get("rotation", 0.0))
	return Transform2D(rotation if is_finite(rotation) else 0.0, position)

func _valid_position(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	if WORLD_ENVELOPE.has_point(point):
		return true
	for room in get_tree().get_nodes_in_group("harbor_interior"):
		if _world.is_ancestor_of(room) and room.has_method("get_camera_rect") and room.get_camera_rect().has_point(point):
			return true
	return false

func _pose_clear(pose: Transform2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(82, 35)
	query.shape = shape
	query.transform = pose
	query.collision_mask = 7
	if is_instance_valid(reward_car):
		query.exclude = [reward_car.get_rid()]
	var player := _world.get_node("Player") as CharacterBody2D
	# SaveManager restores the hidden driver's position before this adapter.
	if int(_record().get("health", 100)) > 0 and bool(_record().get("was_driven", false)) and player.global_position.distance_to(pose.origin) < 2.0:
		query.exclude.append(player.get_rid())
	return _garage.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _restore_record() -> void:
	var record := _record()
	if record.is_empty():
		return
	if not _pose_clear(_saved_pose()):
		return
	reward_car.global_transform = _saved_pose()
	reward_car.velocity = Vector2.ZERO
	reward_car.call("repair_vehicle")
	reward_car.set("max_speed", _normal_speed)
	reward_car.call("repaint_vehicle", Color.from_string(str(record.get("paint", "542d38")), Color("542d38")))
	var hp := clampi(int(record.get("health", reward_car.get("max_health"))), 0, int(reward_car.get("max_health")))
	reward_car.set("health", hp)
	reward_car.set("is_broken", hp == 0)
	reward_car.set("is_exploded", hp == 0)
	reward_car.set("is_exploding", false)
	var player := _world.get_node("Player") as CharacterBody2D
	if hp > 0 and bool(record.get("was_driven", false)) and player.global_position.distance_to(reward_car.global_position) < 150.0:
		reward_car.call("enter_vehicle", player)
		for room in get_tree().get_nodes_in_group("harbor_interior"):
			if _world.is_ancestor_of(room) and room.has_method("get_camera_rect") and room.get_camera_rect().has_point(reward_car.global_position):
				_world.get_node("Interiors").call("_frame_interior_camera", reward_car, room.get_camera_rect())
				break

func capture_snapshot() -> void:
	if not is_instance_valid(reward_car) or not _authorized() or not _valid_position(reward_car.global_position):
		return
	var state: Dictionary = _ledger.get("data")
	var color: Color = reward_car.get("paint_color")
	var point := reward_car.global_position
	state.boss_owned[REWARD_ID] = {"owned": true, "position": [point.x, point.y],
		"rotation": reward_car.global_rotation, "paint": color.to_html(true),
		"health": int(reward_car.get("health")), "was_driven": bool(reward_car.get("is_driven_by_player"))}

func recover_to_garage() -> bool:
	# Explicit tow only; does not repair damage or cancel a driven vehicle.
	if not _can_recover_here() or not is_instance_valid(reward_car) or bool(reward_car.get("is_driven_by_player")):
		return false
	var pose := Transform2D(0.0, _garage.to_global(BAY))
	if not _pose_clear(pose):
		return false
	reward_car.global_transform = pose
	reward_car.velocity = Vector2.ZERO
	capture_snapshot()
	return true

func _can_recover_here() -> bool:
	if _ledger == null or not _authorized() or get_tree().paused:
		return false
	var player := _world.get_node("Player") as Node2D
	if not player.visible or (not _owns_input and (player.get("is_in_dialogue") or player.get("is_control_disabled"))):
		return false
	if player.global_position.distance_to(_garage.to_global(BAY)) > 180.0:
		return false
	var wanted := get_node_or_null("/root/WantedManager")
	if wanted != null and int(wanted.get("current_stars")) > 0:
		return false
	return str(_ledger.get("data").get("active_id", "")).is_empty()

func repair_in_bay() -> bool:
	if not _can_recover_here() or not is_instance_valid(reward_car) or bool(reward_car.get("is_driven_by_player")):
		return false
	if reward_car.global_position.distance_to(_garage.to_global(BAY)) > 45.0:
		return false
	reward_car.call("repair_vehicle")
	reward_car.set("max_speed", _normal_speed)
	capture_snapshot()
	return true

func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func _lock_input() -> void:
	if _owns_input or not _can_recover_here():
		return
	_owns_input = true
	_world.get_node("Player").set("is_in_dialogue", true)
	_world.get_node("Player").set("is_control_disabled", true)

func _unlock_input() -> void:
	if _owns_input and is_instance_valid(_world):
		var player := _world.get_node_or_null("Player")
		if player != null:
			player.set("is_in_dialogue", false)
			player.set("is_control_disabled", false)
	_owns_input = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and recovery_panel != null:
		if recovery_panel.visible and recovery_panel.get_global_rect().has_point(event.position):
			_lock_input()
		else:
			_unlock_input()

func _exit_tree() -> void:
	_unlock_input()

func _create_recovery_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	recovery_panel = PanelContainer.new()
	recovery_panel.position = Vector2(24, 220)
	layer.add_child(recovery_panel)
	recovery_panel.mouse_entered.connect(_lock_input)
	var column := VBoxContainer.new()
	recovery_panel.add_child(column)
	var title := Label.new()
	title.text = "IRONBACK V8"
	column.add_child(title)
	recovery_button = Button.new()
	recovery_button.custom_minimum_size = Vector2(285, 42)
	column.add_child(recovery_button)
	recovery_button.mouse_entered.connect(_lock_input)
	recovery_button.button_down.connect(_lock_input)
	repair_button = Button.new()
	repair_button.custom_minimum_size = Vector2(285, 42)
	column.add_child(repair_button)
	repair_button.mouse_entered.connect(_lock_input)
	repair_button.button_down.connect(_lock_input)
	repair_button.pressed.connect(func():
		_feedback.text = _text("Ironback reparado.", "Ironback repaired.") if repair_in_bay() else _text("Recolha o Ironback à baia primeiro.", "Tow the Ironback to the bay first."))
	_feedback = Label.new()
	column.add_child(_feedback)
	recovery_button.pressed.connect(func():
		_feedback.text = _text("Recolhido. Danos preservados.", "Towed. Damage preserved.") if recover_to_garage() else _text("Baia ocupada ou veículo indisponível.", "Bay occupied or vehicle unavailable."))
	recovery_panel.hide()

func get_reward_status() -> Dictionary:
	return {"unlocked": _authorized(), "available": is_instance_valid(reward_car),
		"id": REWARD_ID, "bay": _garage.to_global(BAY),
		"health": int(reward_car.get("health")) if is_instance_valid(reward_car) else -1}
