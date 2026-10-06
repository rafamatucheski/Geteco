extends "res://tests/test_vehicle_doors.gd"
## Actual Driving -> boarding -> Actor/door path, with a deterministic animation clock.
const BREAK_IN := preload("res://gameplay/VehicleBreakIn.gd")

class DrivingFixture extends "res://scripts/Driving.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class CameraFixture extends Node3D:
	var locked := false
	var initialized := false
	var target: Node3D

class CrimeFixture extends Node:
	var health := 100.0
	var crimes := 0
	func report_observed_crime(_severity: int, _point: Vector3, _kind: String, _source: Node) -> void:
		crimes += 1

class WorldFixture extends Node3D:
	var production: Node
	var session: Node
	var dispatch: Node
	var player: CharacterBody3D
	var camera: Node3D
	var gameplay: Node
	var driving: Node

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		push_error("VEHICLE_BREAK_IN timeout: contract did not finish within 30 seconds")
		quit(2))
	run.call_deferred()

func run() -> void:
	stage = WorldFixture.new()
	root.add_child(stage)
	actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	stage.player = actor
	stage.camera = CameraFixture.new()
	stage.add_child(stage.camera)
	stage.gameplay = CrimeFixture.new()
	stage.add_child(stage.gameplay)
	stage.driving = DrivingFixture.new()
	stage.driving.world = stage
	stage.add_child(stage.driving)
	await process_frame
	var car := spawn("sedan_classic", 0.0)
	car.set_meta("ambient_parked", true)
	car.set_meta("vehicle_locked", true)
	check(BREAK_IN.required(car), "unoccupied parked civilian uses automatic break-in")
	car.traffic = true
	check(not BREAK_IN.required(car), "occupied traffic retains its driver ejection path")
	car.traffic = false
	for protection in ["dispatch_unit", "police_locked"]:
		car.set_meta(protection, true)
		check(not BREAK_IN.required(car), protection + " keeps its existing admission rule")
		car.remove_meta(protection)
	car.external_input = true
	check(not BREAK_IN.required(car), "an NPC parking maneuver cannot be interrupted by locked-door animation")
	car.external_input = false
	car.remove_meta("ambient_parked")
	check(not BREAK_IN.required(car), "owned/mission cars without ambient ownership enter normally")
	car.free()
	await _entry_case("sedan_classic", "window", true)
	await _entry_case("arctic_jeep", "tool", false)
	await _entry_case("sport_coupe", "window", false)
	await _cancel_case(false)
	await _cancel_case(true)
	print("VEHICLE_BREAK_IN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	stage.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _start(car: CharacterBody3D, method: String, alarm: bool) -> Node:
	actor.release_seated(false)
	actor.set_physics_process(false)
	actor.input_locked = false
	actor.teleport(car.driver_door_anchor(-1))
	car.set_meta("ambient_parked", true)
	car.set_meta("vehicle_locked", true)
	var crimes_before: int = stage.gameplay.crimes
	check(stage.driving._begin_entry(car, -1), "locked car admits automatic entry")
	var transition: Node = stage.driving.transition
	check(transition.break_in != null, "Driving transfers lock state into actual boarding presentation")
	transition.break_in.choose(0.0 if method == "window" else 1.0, 0.0 if alarm else 1.0)
	transition._motion.pause()
	check(stage.gameplay.crimes == crimes_before + 1, "parking theft reports once through existing witness/crime path")
	check(actor.input_locked and actor.collision_layer == 0, "entry owns player controls and collision")
	return transition

func _entry_case(id: String, method: String, alarm: bool) -> void:
	var car := spawn(id, .6)
	var transition := _start(car, method, alarm)
	var saw_gesture := false
	var checked_geometry := false
	var checked_contact := false
	for index in 250:
		if not is_instance_valid(stage.driving.transition): break
		transition._motion.custom_step(.04)
		if not transition.active: break
		transition._apply()
		if transition._breaking:
			saw_gesture = true
			check(absf(car.door_presentation.hinges[-1].rotation.y) < .001, "door stays shut throughout " + method + " gesture")
			check(absf(car.to_local(actor.global_position).x) >= car.half_width + BODY_RADIUS, "entire actor capsule stays outside the car during gesture")
			if not checked_geometry:
				checked_geometry = true
				var spec: Dictionary = car.door_presentation.spec
				var hand_target: Vector3 = car.visual.to_local(car.to_global(transition._break_layout.grip))
				var stance: Vector3 = car.visual.to_local(actor.global_position)
				check(hand_target.z > float(spec.zf) + .1 and hand_target.z < float(spec.zr) - .1, id + ": gesture targets inside the closed front window, not its rear pillar")
				check(hand_target.y > float(spec.belt) and hand_target.y < float(spec.top), id + ": gesture contacts glazing above the door belt")
				check(stance.z > float(spec.zf) and stance.z < float(spec.zr), id + ": actor stands beside the closed door instead of the rear wheel")
				check(not car.has_meta("interior_view"), id + ": intact glass stays opaque through break-in gesture")
			var contact_phase: bool = (method == "window" and transition._break_progress >= .44 and transition._break_progress <= .55) or (method == "tool" and transition._break_progress >= .3 and transition._break_progress <= .7)
			if contact_phase and not checked_contact:
				checked_contact = true
				var target: Vector3 = car.to_global(transition._break_layout.grip)
				var palm: Vector3 = actor.combat_palm_position("Right")
				check(palm.distance_to(target) <= .10, id + ": working hand contacts closed pane within 10 cm (%s)" % palm.distance_to(target))
		await process_frame
	check(saw_gesture and stage.driving.transition == null and car.controlled, method + " completes without another button press")
	check(checked_contact, id + ": contact phase was exercised")
	check(not actor.input_locked and stage.driving.occupied and actor.seated, "driver controls and seated pose restored after " + method)
	check(not BREAK_IN.required(car) and not car.has_meta("ambient_parked"), "claimed car is not locked again on re-entry")
	check(car.has_node("EntryAlarm") == alarm, "alarm result follows independent chance")
	check(car.has_meta("broken_entry_window_side") == (method == "window"), "only window variation breaks glass")
	if method == "window":
		var removed := 0
		for part in car.door_presentation.hinges[-1].find_children("*", "MeshInstance3D", true, false):
			if not part.visible and part.material_override is BaseMaterial3D and part.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED: removed += 1
			for surface in part.mesh.get_surface_count():
				if part.get_surface_override_material(surface) == BREAK_IN._missing_glass: removed += 1
		check(removed > 0, "broken door window is actually removed from the rendered mesh")
		var opposite_removed := 0
		for part in car.door_presentation.hinges[1].find_children("*", "MeshInstance3D", true, false):
			if not part.visible and part.material_override is BaseMaterial3D and part.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED: opposite_removed += 1
			for surface in part.mesh.get_surface_count():
				if part.get_surface_override_material(surface) == BREAK_IN._missing_glass: opposite_removed += 1
		check(opposite_removed == 0, "opposite door glazing is preserved")
	check(actor.get_node_or_null("EntryTool") == null, "temporary prop cleaned after boarding")
	stage.driving.cancel_transition("test_exit")
	actor.set_physics_process(false)
	car.free()
	await process_frame

func _cancel_case(after_impact: bool) -> void:
	var car := spawn("sedan_classic", 0.0)
	var transition := _start(car, "window", true)
	for index in 180:
		transition._motion.custom_step(.02)
		transition._apply()
		if transition._breaking and (not after_impact or transition.break_in.committed): break
	check(transition._breaking, "cancel scenario reached gesture")
	stage.driving.cancel_transition("test_cancel")
	check(not stage.driving.occupied and stage.driving.transition == null, "cancel clears transition ownership")
	check(actor.visible and not actor.input_locked and actor.collision_layer == 2 and actor.collision_mask == 7, "cancel returns visible movable player with collision")
	check(bool(car.get_meta("vehicle_locked", false)) != after_impact, "only completed break-in unlocks car on interruption")
	check(car.has_node("EntryAlarm") == after_impact, "cancel before impact is silent; completed impact keeps its finite alarm")
	actor.set_physics_process(false)
	var alarm_node := car.get_node_or_null("EntryAlarm")
	car.free()
	await process_frame
	check(not is_instance_valid(alarm_node), "vehicle deletion leaves no orphan alarm")
