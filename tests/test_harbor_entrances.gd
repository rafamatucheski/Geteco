extends SceneTree

## Exterior doors are animated interaction affordances, not invented interiors.
## Each scenario starts outside its building; all approach/retreat is native
## Player input, and crossing the facade is attempted by the real body sweep.
const PREVIEW := preload("res://world/harbor/HarborPreview.tscn")
const BUILDING := preload("res://world/harbor/HarborBuilding.gd")
const SITES := {
	"District/Garage": {"count": 1, "outward": Vector2.DOWN, "width": 120.0, "role": "garage"},
	"District/Police": {"count": 1, "outward": Vector2.DOWN, "width": 54.0, "role": "police"},
	"District/Clinic": {"count": 1, "outward": Vector2.DOWN, "width": 64.0, "role": "hospital"},
	"NorthDistrict/MotorWorkshop": {"count": 1, "outward": Vector2.DOWN, "width": 112.0, "role": "garage"},
	"NorthDistrict/NorthFireStation": {"count": 3, "outward": Vector2.DOWN, "width": 72.0, "role": "fire_station"},
}
var failures: Array[String] = []
var tested_doors := 0
var animated_doors := 0
var blocked_entries := 0
var native_distance := 0.0
var destination_requests := 0
var closing_animations := 0
var fixture_doors := 0
var driven_car_verified := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := PREVIEW.instantiate()
	var interiors := scene.get_node_or_null("Interiors")
	if interiors != null:
		interiors.enabled = false
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	var car := scene.get_node("PlayerCar") as CharacterBody2D
	var car_layer := car.collision_layer
	var car_mask := car.collision_mask
	scene.call("_walk")
	_quiet_ambient(scene, player)
	player.collision_mask = 1
	for site_path in SITES:
		var building := scene.get_node(site_path) as Node2D
		var expected: Dictionary = SITES[site_path]
		var entrances: Array[Node] = []
		for child in building.get_children():
			if child.has_method("get_entrance_state"):
				entrances.append(child)
		_check(entrances.size() == int(expected.count), "%s requires %d authored entrance(s), found %d" % [site_path, expected.count, entrances.size()])
		for entrance in entrances:
			await _test_entrance(scene, player, building, entrance, expected)
	_check(tested_doors == 7, "All seven doors in the five existing service buildings must be exercised")
	# These are isolated test fixtures, not new lots authored into the preview.
	# They prove future Ammunation/IML facade reuse without claiming either exists.
	for fixture_spec in [{"kind": "ammunation_shop", "role": "ammunation", "width": 58.0}, {"kind": "morgue", "role": "morgue", "width": 60.0}]:
		var fixture := BUILDING.new()
		fixture.name = "EntranceFixture%d" % fixture_doors
		fixture.position = Vector2(-2000 - fixture_doors * 600, 1000)
		fixture.footprint = Vector2(240, 200)
		fixture.building_kind = fixture_spec.kind
		fixture.business_name = "METADATA ONLY - DO NOT PAINT"
		root.add_child(fixture)
		await physics_frame
		var door := fixture.get_node_or_null("Entrance")
		_check(door != null, "Reusable %s fixture must create an exterior entrance" % fixture_spec.kind)
		if door != null:
			await _test_entrance(scene, player, fixture, door, {"outward": Vector2.DOWN, "width": fixture_spec.width, "role": fixture_spec.role})
			fixture_doors += 1
		fixture.queue_free()
		await physics_frame
	_check(fixture_doors == 2 and tested_doors == 9, "Seven authored doors plus exactly two out-of-district fixtures must pass")
	car.collision_layer = car_layer
	car.collision_mask = car_mask
	await _test_driven_car(scene, player, car)
	_check(destination_requests == 0, "Exterior-only preview must never emit an interior destination request")
	_release_input()
	print("HARBOR_ENTRANCES_PHASE_1_RESULT failures=%d doors=%d fixtures=%d animated=%d closing_animations=%d solid_entries=%d native_input_distance=%.1f destination_requests=%d driven_car=%s" % [failures.size(), tested_doors, fixture_doors, animated_doors, closing_animations, blocked_entries, native_distance, destination_requests, driven_car_verified])
	scene.queue_free()
	await process_frame

	# Phase 2: Verify default harbor preview has interiors enabled and properly wired on all doors
	var scene_enabled := PREVIEW.instantiate()
	root.add_child(scene_enabled)
	current_scene = scene_enabled
	for _frame in 4:
		await physics_frame
	var interiors_enabled := scene_enabled.get_node_or_null("Interiors")
	_check(interiors_enabled != null and interiors_enabled.enabled, "HarborPreview must have Interiors enabled by default")
	var enabled_verified_doors := 0
	for site_path in SITES:
		var building := scene_enabled.get_node(site_path) as Node2D
		for child in building.get_children():
			if child.has_method("get_entrance_state"):
				var state: Dictionary = child.call("get_entrance_state")
				_check(bool(state.get("interior_available", false)), "Door %s must report interior_available == true when interiors are enabled" % child.get_path())
				_check(not String(child.get("destination_id")).is_empty(), "Door %s must have non-empty destination_id when interiors are enabled" % child.get_path())
				enabled_verified_doors += 1
	_check(enabled_verified_doors == 7, "All 7 service doors must have interiors enabled in Phase 2")
	scene_enabled.queue_free()
	await process_frame
	print("HARBOR_ENTRANCES_TOTAL_RESULT failures=%d enabled_doors_verified=%d" % [failures.size(), enabled_verified_doors])
	quit(0 if failures.is_empty() else 1)


func _test_entrance(scene: Node, player: CharacterBody2D, building: Node2D, entrance: Node, expected: Dictionary) -> void:
	var label := str(entrance.get_path())
	var state: Dictionary = entrance.call("get_entrance_state")
	for field in ["role", "width", "open_amount", "threshold_position", "approach_position", "outward", "interior_available"]:
		_check(state.has(field), "%s missing contract field %s" % [label, field])
	if not state.has_all(["threshold_position", "approach_position", "outward", "width", "open_amount"]):
		return
	_check(state.threshold_position is Vector2 and state.approach_position is Vector2 and state.outward is Vector2, label + " must expose world-space Vector2 access geometry")
	_check(not bool(state.get("interior_available", true)), label + " must explicitly report that no interior is integrated")
	_check(String(state.get("role", "")) == String(expected.role), label + " exterior entrance role does not match its existing building use")
	_check(String(entrance.get("display_name")).is_empty(), label + " must not populate facade lettering")
	_check_blank_prompt(entrance, label)
	var threshold: Vector2 = state.threshold_position
	var approach: Vector2 = state.approach_position
	var outward: Vector2 = state.outward
	_check(outward.distance_to(expected.outward) < 0.01, label + " faces away from its real authored access strip")
	_check(is_equal_approx(float(state.width), float(expected.width)), label + " door width does not match its authored frontage")
	_check((approach - threshold).dot(outward) >= 25.0, label + " approach marker must stay outside the solid facade")
	var return_marker := entrance.get_node_or_null("OutsideReturn") as Marker2D
	_check(return_marker != null and return_marker.global_position.distance_to(approach) < 0.01, label + " future return point must be an actual exterior Marker2D")
	_check(not _point_solid(player, approach), label + " future return marker is obstructed")
	var solid := building.get_node_or_null("BuildingSolid") as StaticBody2D
	_check(solid != null and solid.collision_layer == 1, label + " must preserve the physical building shell")
	_check(_point_solid(player, building.global_position), label + " building center is not solid before interaction")
	if solid == null:
		return
	entrance.connect("destination_requested", _on_destination_requested)
	# This is the only placement in a case: on its exterior apron, never inside.
	player.set_physics_process(false)
	player.global_position = threshold + outward * 108.0
	player.velocity = Vector2.ZERO
	await create_timer(1.5).timeout
	_check(float(entrance.call("get_entrance_state").open_amount) < 0.02, label + " should be closed while Player is outside its approach sensor")
	_check(not entrance.call("request_interaction", player), label + " must reject interaction outside its sensor")
	var observed_tween := await _walk_input(player, approach, entrance)
	await create_timer(0.7).timeout
	state = entrance.call("get_entrance_state")
	_check(float(state.open_amount) > 0.98, label + " did not open fully on actual Player proximity")
	_check(observed_tween, label + " opening must animate through intermediate states")
	if observed_tween:
		animated_doors += 1
	_check(entrance.call("is_actor_in_range", player), label + " native approach did not enter the reusable entrance sensor")
	_check_blank_prompt(entrance, label)
	var before_interaction := player.global_position
	entrance.call("request_interaction", player)
	await create_timer(0.65).timeout
	_check(current_scene == scene and player.global_position.distance_to(before_interaction) < 1.0, label + " interaction must not teleport Player or switch to an unbuilt interior")
	var collision := player.move_and_collide(threshold - outward * 35.0 - player.global_position)
	_check(collision != null and collision.get_collider() == solid, label + " opened animation must not let Player enter a nonexistent interior")
	_check((player.global_position - threshold).dot(outward) > 0.0, label + " Player crossed the solid facade")
	_check(_point_solid(player, building.global_position), label + " building collision disappeared after opening")
	if collision != null and collision.get_collider() == solid:
		blocked_entries += 1
	await _walk_input(player, threshold + outward * 108.0, entrance)
	var saw_closing := false
	for _frame in 96:
		await physics_frame
		var fraction := float(entrance.call("get_entrance_state").open_amount)
		saw_closing = saw_closing or (fraction > 0.02 and fraction < 0.98)
	_check(saw_closing, label + " closing must also animate through intermediate states")
	if saw_closing:
		closing_animations += 1
	_check(float(entrance.call("get_entrance_state").open_amount) < 0.02, label + " did not close after Player physically walked away")
	tested_doors += 1


func _check_blank_prompt(entrance: Node, label: String) -> void:
	var prompt := entrance.get_node_or_null("Prompt") as Label
	_check(prompt != null and prompt.text.is_empty() and not prompt.visible, label + " must keep the inherited lettering/prompt blank and hidden")


func _test_driven_car(scene: Node, player: CharacterBody2D, car: CharacterBody2D) -> void:
	var before_failures := failures.size()
	var entrance := scene.get_node("District/Garage/Entrance")
	var state: Dictionary = entrance.call("get_entrance_state")
	var threshold: Vector2 = state.threshold_position
	var outward: Vector2 = state.outward
	# The real car is parked outside; Player remains away after the last fixture.
	car.set_physics_process(false)
	car.global_position = state.approach_position + outward * 10.0
	car.rotation = -PI / 2.0
	car.velocity = Vector2.ZERO
	await create_timer(1.5).timeout
	_check(not bool(car.get("is_driven_by_player")), "Garage car fixture must initially be unoccupied")
	_check(float(entrance.call("get_entrance_state").open_amount) < 0.02, "A parked/unoccupied car must not hold the garage open")
	var initial_car_position := car.global_position
	car.call("enter_vehicle", player)
	await create_timer(0.8).timeout
	_check(bool(car.get("is_driven_by_player")) and not player.visible, "Actual PlayerCar boarding API must activate the driver")
	_check(entrance.call("is_actor_in_range", car), "Already-overlapping car must become an accepted actor when driven")
	_check(float(entrance.call("get_entrance_state").open_amount) > 0.98, "Boarding a parked car inside the sensor must open the garage without recrossing it")
	_check(car.global_position.distance_to(initial_car_position) < 0.01, "Garage opening must not move the car into an unbuilt interior")
	_check_blank_prompt(entrance, "Driven-car garage")
	var solid := scene.get_node("District/Garage/BuildingSolid")
	var hit := car.move_and_collide(threshold - outward * 30.0 - car.global_position)
	_check(hit != null and hit.get_collider() == solid, "Open garage must preserve BuildingSolid against the real PlayerCar too")
	_check((car.global_position - threshold).dot(outward) > 0.0, "Driven car crossed the garage facade")
	car.call("exit_vehicle")
	await physics_frame
	_check(not bool(car.get("is_driven_by_player")) and player.visible, "Actual PlayerCar exit API must restore the walking player")
	await _walk_input(player, threshold + outward * 130.0, entrance)
	await create_timer(1.5).timeout
	_check(float(entrance.call("get_entrance_state").open_amount) < 0.02, "Abandoned car inside the sensor must not prevent closure after Player walks away")
	_check(not entrance.call("is_actor_in_range", car), "Former driver vehicle must be removed from accepted actors after parking")
	driven_car_verified = failures.size() == before_failures


func _walk_input(player: CharacterBody2D, target: Vector2, entrance: Node) -> bool:
	var start := player.global_position
	var saw_intermediate := false
	player.set_physics_process(true)
	for _frame in 240:
		var delta := target - player.global_position
		if delta.length() < 4.0:
			break
		_release_input()
		var direction := delta.normalized()
		if absf(direction.x) > 0.1:
			Input.action_press("ui_right" if direction.x > 0.0 else "ui_left", absf(direction.x))
		if absf(direction.y) > 0.1:
			Input.action_press("ui_down" if direction.y > 0.0 else "ui_up", absf(direction.y))
		await physics_frame
		var fraction := float(entrance.call("get_entrance_state").open_amount)
		saw_intermediate = saw_intermediate or (fraction > 0.02 and fraction < 0.98)
	_release_input()
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	native_distance += start.distance_to(player.global_position)
	_check(player.global_position.distance_to(target) < 8.0, "Actual Player input blocked approaching/retreating %s: at %s, target %s" % [entrance.get_path(), player.global_position, target])
	return saw_intermediate


func _point_solid(player: CharacterBody2D, position: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = position
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return not player.get_world_2d().direct_space_state.intersect_point(query).is_empty()


func _quiet_ambient(node: Node, player: CharacterBody2D) -> void:
	if node is CollisionObject2D and node != player and not node is StaticBody2D and not node is Area2D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_physics_process(false)
	for child in node.get_children():
		_quiet_ambient(child, player)


func _release_input() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)


func _on_destination_requested(_entrance: Node, _actor: Node, _id: StringName, _scene: PackedScene, _spawn: StringName) -> void:
	destination_requests += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
