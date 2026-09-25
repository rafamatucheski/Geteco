extends SceneTree
## Ownership/persistence regression independent of truck physics and GPU timing.
const DELIVERY := preload("res://gameplay/urban_v1/PortFreightDelivery.gd")
const FLEET := preload("res://runtime/FleetState.gd")

class ParkedCar extends CharacterBody3D:
	var archetype := "sport_coupe"
	var vehicle_id := "previous_personal_coupe"
	var controlled := false
	var external_input := false
	var paint_color := Color("31577a")
	var health := 70.0
	var equipment: Node
	var equipment_state := {}
class Selection extends RefCounted:
	var car: CharacterBody3D
	func _watch_car(_car: CharacterBody3D) -> void: pass
class WorldFixture extends Node3D:
	var driving := Selection.new()
class SessionFixture extends RefCounted:
	var state = preload("res://runtime/GameState.gd").new()
	var world: WorldFixture

var checks := 0
var failed := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("FREIGHT_PREVIOUS ", "PASS " if ok else "FAIL ", label)
func run() -> void:
	var fixture := SessionFixture.new()
	fixture.world = WorldFixture.new()
	root.add_child(fixture.world)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(21,-.1,44)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12,.2,8)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	fixture.world.add_child(floor_body)
	var prior := ParkedCar.new()
	fixture.world.add_child(prior)
	prior.position = Vector3(21,.08,44)
	await physics_frame
	await physics_frame
	var record := FLEET.capture(prior, "harbor")
	var delivery := DELIVERY.new()
	delivery.session = fixture
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = weakref(prior)
	prior.health = 44
	prior.position.x += 3
	var snapshot: Dictionary = delivery.snapshot()
	check(snapshot.previous_vehicle.health == 44 and snapshot.previous_vehicle.position[0] == 24, "live prior car stores current damage and position")
	check(DELIVERY.validate_snapshot(JSON.parse_string(JSON.stringify(snapshot))), "optional previous vehicle survives JSON serialization")
	fixture.state.world_state.vehicles = []
	delivery._restore_previous_selection()
	check(fixture.world.driving.car == prior and fixture.state.world_state.vehicles[0].health == 44, "return preserves the live personal car without healing")
	# A loaded saved car is allowed to remain unmaterialized until selected by
	# the existing Fleet restore; keep its identity and position verbatim.
	fixture.world.driving.car = null
	fixture.state.world_state.vehicles = []
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = null
	delivery._restore_previous_selection()
	check(fixture.state.world_state.vehicles == [record], "new-session handback returns the previous saved ID and position")
	var replacement := ParkedCar.new()
	replacement.vehicle_id = "new_personal_car"
	fixture.world.add_child(replacement)
	var replacement_record := FLEET.capture(replacement, "harbor")
	fixture.world.driving.car = replacement
	fixture.state.world_state.vehicles = [replacement_record]
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = weakref(prior)
	delivery._restore_previous_selection()
	check(fixture.world.driving.car == replacement and fixture.state.world_state.vehicles == [replacement_record], "newly selected personal car is never replaced by the old loan snapshot")
	fixture.world.driving.car = null
	delivery.previous_vehicle = record.duplicate(true)
	delivery._restore_previous_selection()
	check(fixture.state.world_state.vehicles == [replacement_record], "different saved vehicle also wins without a live selection")
	fixture.state.world_state.vehicles = []
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = weakref(prior)
	prior.health = 0
	delivery._restore_previous_selection()
	check(fixture.state.world_state.vehicles[0].health == 0, "destroyed previous car stays a wreck instead of being resurrected")
	fixture.world.driving.car = null
	fixture.state.world_state.vehicles = []
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = weakref(prior)
	prior.queue_free()
	await process_frame
	delivery._restore_previous_selection()
	check(fixture.state.world_state.vehicles.is_empty() and delivery.previous_vehicle.is_empty(), "explicitly removed previous car is retired")
	var streamed := ParkedCar.new()
	fixture.world.add_child(streamed)
	streamed.health = 55
	delivery.previous_vehicle = record.duplicate(true)
	delivery._previous_ref = weakref(streamed)
	delivery._watch_previous(streamed)
	streamed.set_meta("distance_despawn", true)
	streamed.queue_free()
	var same_frame: Dictionary = delivery.snapshot()
	check(same_frame.previous_vehicle.health == 55, "snapshot before deferred deletion preserves distance-despawn state")
	await process_frame
	check(delivery._previous_ref == null and delivery.previous_vehicle.health == 55, "distance cleanup captures the final vehicle state without retaining physics")
	delivery._restore_previous_selection()
	check(fixture.state.world_state.vehicles.size() == 1 and fixture.state.world_state.vehicles[0].health == 55, "streamed prior car remains restorable after the loan")
	var invalid := {"version":1,"jobs":[0,0,0],"active_bay":-1,"truck":{},"previous_vehicle":record.duplicate(true)}
	invalid.previous_vehicle.vehicle_id = "south_port_cargo_truck_00"
	check(not DELIVERY.validate_snapshot(invalid), "a port work truck cannot masquerade as the previous personal vehicle")
	delivery.free()
	fixture.world.queue_free()
	fixture = null
	await process_frame
	print("FREIGHT_PREVIOUS_RESULT checks=", checks, " failures=", failed)
	quit(0 if failed == 0 else 1)
