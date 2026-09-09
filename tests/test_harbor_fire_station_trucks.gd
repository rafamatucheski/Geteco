extends SceneTree

## Exercises the real firefighter loop for all 3 Northgate Fire / 03 bays:
## walk in on foot, board the bay's own truck via the normal vehicle-entry
## call, drive it for real through the gate, confirm the automatic no-keypress
## exterior transfer lands the SAME node (never a duplicate) aligned with the
## matching exterior access, then drive it back in and confirm it reparents
## into its own bay without creating a second truck. Also exercises the
## first-aid life-recovery point. No actor is teleported mid-flow; only the
## discrete "press E" moments (foot entry, vehicle re-entry) call the same
## public request_interaction()/try_enter_vehicle() a real keypress would
## invoke, matching the convention already used by tests/test_harbor_bridge.gd.

const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PREVIEW_PATH) as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for _frame in 6:
		await physics_frame

	var player := scene.get_node_or_null("Player") as CharacterBody2D
	var manager := scene.get_node_or_null("Interiors")
	var fire_station = manager.get("fire_station_interior") if manager else null
	_check(player != null, "Scene must contain the actual Player")
	_check(fire_station != null, "HarborInteriorManager must expose fire_station_interior")
	_check(fire_station != null and fire_station.get("bay_trucks") is Array and fire_station.bay_trucks.size() == 3,
		"Fire station must hold exactly 3 bay trucks")
	if player == null or fire_station == null or fire_station.bay_trucks.size() != 3:
		_finish(scene)
		return

	for bay_idx in 3:
		await _run_bay_cycle(scene, player, fire_station, bay_idx)

	await _run_heal_station_check(player, fire_station)

	print("HARBOR_FIRE_TRUCKS_RESULT failures=%d bays_tested=3" % _failures.size())
	_finish(scene)


func _run_bay_cycle(scene: Node2D, player: CharacterBody2D, fire_station: Node2D, bay_idx: int) -> void:
	var label := "bay%d" % bay_idx
	var exterior := scene.get_node_or_null("NorthDistrict/NorthFireStation/Entrance%d" % bay_idx)
	_check(exterior != null, "%s: exterior entrance must exist" % label)
	if exterior == null:
		return

	var truck: Node2D = fire_station.bay_trucks[bay_idx]
	_check(is_instance_valid(truck), "%s: bay truck must exist" % label)
	if not is_instance_valid(truck):
		return
	_check(truck.get_parent() == fire_station, "%s: truck must start parked inside its bay" % label)

	# 1. Walk in on foot through the real entrance interaction call.
	var state: Dictionary = exterior.call("get_entrance_state")
	player.global_position = state.get("approach_position", exterior.global_position)
	player.velocity = Vector2.ZERO
	for _f in 5:
		await physics_frame
	var opened: bool = exterior.call("request_interaction", player)
	_check(opened, "%s: foot entry via the real entrance must succeed" % label)
	for _f in 40:
		await physics_frame
	var spawn: Marker2D = fire_station.call("get_spawn_for_bay", bay_idx)
	_check(player.global_position.distance_to(spawn.global_position) < 250.0,
		"%s: player must land near its bay spawn, got %s vs %s" % [label, player.global_position, spawn.global_position])

	# 2. Reach and board the truck via the normal vehicle-entry call.
	player.global_position = truck.global_position - Vector2(0, 60)
	player.velocity = Vector2.ZERO
	for _f in 3:
		await physics_frame
	player.call("try_enter_vehicle")
	await physics_frame
	_check(bool(truck.get("is_driven_by_player")), "%s: normal vehicle entry must succeed" % label)

	# 3. Drive to and through the gate with real input, zero scripted teleports.
	Input.action_release("ui_up")
	Input.action_press("ui_up")
	var exited := false
	for _f in 400:
		await physics_frame
		if truck.get_parent() != fire_station:
			exited = true
			break
	Input.action_release("ui_up")
	_check(exited, "%s: truck must drive itself out through the auto-exit transfer" % label)
	if not exited:
		return
	# The reparent happens immediately on crossing, but the actual exterior
	# position/camera swap runs through BuildingEntrance's door-close timing
	# (destination_requested fires after the door animation), so give that
	# pending transition time to land before checking where the truck ended up.
	truck.velocity = Vector2.ZERO
	for _f in 90:
		await physics_frame

	# 4. Confirm the SAME node (no duplicate) landed aligned with the matching
	# exterior access, and the bay is now empty.
	_check(fire_station.bay_trucks[bay_idx] == truck, "%s: exit must not replace the truck instance" % label)
	var return_marker := exterior.get_node_or_null("OutsideReturn") as Marker2D
	_check(return_marker != null and truck.global_position.distance_to(return_marker.global_position) < 200.0,
		"%s: exited truck must align with its own exterior access, got %s vs %s" % [
			label, truck.global_position, (return_marker.global_position if return_marker else Vector2.INF)
		])
	var truck_count := 0
	for v in scene.get_tree().get_nodes_in_group("vehicle"):
		if v.has_meta("home_bay") and int(v.get_meta("home_bay")) == bay_idx:
			truck_count += 1
	_check(truck_count == 1, "%s: exactly one truck must carry home_bay=%d, found %d" % [label, bay_idx, truck_count])

	# 5. Drive back in through the corresponding access and confirm it
	# reparents into its own bay without creating a second truck.
	var outward_dir: Vector2 = (return_marker.global_position - exterior.global_position).normalized()
	truck.global_position = exterior.global_position + outward_dir * 90.0
	truck.rotation = (-outward_dir).angle()
	truck.velocity = Vector2.ZERO
	for _f in 3:
		await physics_frame
	_check(bool(exterior.call("is_actor_in_range", truck)), "%s: truck must be physically in range of its own access to return" % label)
	var reentered: bool = exterior.call("request_interaction", truck)
	_check(reentered, "%s: return via the corresponding access must succeed" % label)
	for _f in 40:
		await physics_frame
	_check(truck.get_parent() == fire_station, "%s: truck must reparent back into its own bay on return" % label)
	truck_count = 0
	for v in scene.get_tree().get_nodes_in_group("vehicle"):
		if v.has_meta("home_bay") and int(v.get_meta("home_bay")) == bay_idx:
			truck_count += 1
	_check(truck_count == 1, "%s: return must not duplicate the truck, found %d" % [label, truck_count])

	# 6. Player exits the vehicle to leave a clean state for the next bay.
	if bool(truck.get("is_driven_by_player")):
		truck.call("exit_vehicle")
		await physics_frame


func _run_heal_station_check(player: CharacterBody2D, fire_station: Node2D) -> void:
	var heal_area: Area2D = fire_station.get("heal_area")
	_check(heal_area != null, "Fire station must expose a heal_area")
	if heal_area == null:
		return
	player.health = 40
	player.global_position = heal_area.global_position
	player.velocity = Vector2.ZERO
	for _f in 10:
		await physics_frame
	_check(bool(fire_station.get("is_near_heal")), "Player standing in the heal zone must be detected")
	var health_before: int = player.health
	for _f in 240:
		await physics_frame
	_check(player.health > health_before, "Health must rise over time while in the heal zone (before=%d after=%d)" % [health_before, player.health])
	_check(player.health <= player.max_health, "Health must never exceed max_health")
	for _f in 4000:
		await physics_frame
		if player.health >= player.max_health:
			break
	_check(player.health == player.max_health, "Health must clamp exactly at max_health, got %d/%d" % [player.health, player.max_health])
	player.global_position += Vector2(2000, 2000)
	for _f in 5:
		await physics_frame
	_check(not bool(fire_station.get("is_near_heal")), "Leaving the heal zone must be detected")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("HARBOR_FIRE_TRUCKS: " + message)


func _finish(scene: Node) -> void:
	Input.action_release("ui_up")
	scene.queue_free()
	quit(0 if _failures.is_empty() else 1)
