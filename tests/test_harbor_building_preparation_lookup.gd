extends SceneTree
## Local preparation parity. FullSession admission/recovery is tested separately.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PLACE := preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")
const RUNTIME := preload("res://runtime/HarborBuildingRuntime.gd")
const TRACE := preload("res://runtime/StallWorkTrace.gd")
var failures: Array[String] = []
var checks := 0

class FixtureRegion extends RefCounted:
	var focus := Vector3.INF
	func set_focus(point: Vector3) -> void: focus = point

class FixtureWorld extends Node3D:
	var gameplay := {"health":100.0}
	var camera: Node3D

class FixtureSession extends Node:
	var transition_generation := 1
	var state := {"region_id":"harbor", "place_id":"", "world_state":{}}
	var controller: Dictionary
	var world: Node3D
	var room: Node3D
	var ready_for_play := true
	var rescue_pending := false
	var arrest_pending := false

class FixtureFacade extends Node3D:
	var access_ready := false
	func set_open_amount(amount: float) -> void: access_ready = amount > .01
	func restore_exterior() -> void: access_ready = false

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("BUILDING_LOOKUP timeout"); quit(3))
	var baseline := {}
	for definition in PLACES.definitions(): baseline[definition.id] = definition
	for definition in CATALOG.definitions():
		check(baseline.has(definition.id) and baseline[definition.id] == CATALOG.find(definition.id), "Full definition parity " + str(definition.id))
	var stage := FixtureWorld.new()
	root.add_child(stage)
	var session := FixtureSession.new()
	session.world = stage
	session.controller = {"region":FixtureRegion.new()}
	stage.add_child(session)
	var runtime := RUNTIME.new()
	runtime.session = session
	stage.add_child(runtime)
	var facade := FixtureFacade.new()
	facade.set_meta("place_id", "harbor_customs_house")
	stage.add_child(facade)
	facade.add_to_group("harbor_building_facade")
	TRACE.enabled = true
	TRACE.take()
	var prepared: Node3D = await runtime.prepare_room("harbor_customs_house", true)
	var events := TRACE.take()
	TRACE.enabled = false
	check(is_instance_valid(prepared), "Actual runtime returns prepared room")
	if not is_instance_valid(prepared): finish(); return
	check(prepared.get_script() == PLACE, "Same HarborBuildingPlace implementation")
	check(prepared.definition == baseline.harbor_customs_house, "Prepared definition matches public factory")
	check(not runtime.preparing and prepared == runtime.staged, "Preparation finishes with one owned candidate")
	check(prepared.global_position == prepared.definition.exterior_position, "Exterior placement retained")
	check(is_equal_approx(prepared.rotation.y, prepared.definition.exterior_rotation), "Exterior orientation retained")
	check(session.controller.region.focus == prepared.definition.entry_position, "Streaming focus retained")
	var labels: Array[String] = []
	for event in events:
		if str(event.get("label", "")).begins_with("building.prepare."):
			labels.append(str(event.label))
			check(event.details.get("place", "") == "harbor_customs_house", "Timing identifies prepared place")
	check(labels == ["building.prepare.lookup", "building.prepare.instantiate", "building.prepare.add_child"], "Separate preparation stages recorded")
	var reference: Node3D = PLACES.create_place("harbor_customs_house")
	reference.prepare_session(session, true)
	# Compare identical transforms: this fixture does not move actors between them.
	reference.position = prepared.position
	reference.rotation = prepared.rotation
	stage.add_child(reference)
	check(prepared.floor_room.get_script() == reference.floor_room.get_script(), "Same floor adapter")
	check(prepared.floor_room.solid_bounds == reference.floor_room.solid_bounds, "Identical furniture collision envelopes")
	check(prepared.floor_room.solid_bodies.size() == reference.floor_room.solid_bodies.size(), "Identical solid body count")
	check(prepared.find_children("*", "", true, false).size() == reference.find_children("*", "", true, false).size(), "Identical constructed subtree size")
	var actual_rewards: Array[String] = []
	var expected_rewards: Array[String] = []
	for reward in prepared.reward_points: actual_rewards.append(str(reward.id))
	for reward in reference.reward_points: expected_rewards.append(str(reward.id))
	check(actual_rewards == expected_rewards, "Persistent reward identifiers retained")
	check(await runtime.prepare_room("harbor_customs_house", true) == prepared, "Repeated request reuses prepared room")
	runtime.reset()
	await process_frame
	check(not is_instance_valid(prepared) and not facade.access_ready, "Reset releases candidate and restores exterior")
	check(not is_instance_valid(await runtime.prepare_room("harbor_building_missing_fixture", true)), "Unknown building returns no room")
	check(not runtime.preparing, "Unknown building releases preparing flag")
	stage.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print(JSON.stringify({"test":"harbor_building_preparation_lookup", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
