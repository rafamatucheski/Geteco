extends SceneTree
var failures: Array[String] = []

class Resident extends CharacterBody2D:
	var health := 100
	var is_dead := false
	var is_incapacitated := false
	var is_scared := false

class Unit extends Node2D:
	signal arrived_at_depot(vehicle: Node, depot: String)
	var target: Node
	var visual_3d: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var care := root.get_node("NPCMedicalCare")
	care.set_process(false)
	var patient := Resident.new()
	patient.name = "LivingPatient"
	world.add_child(patient)
	var older := Resident.new()
	older.name = "EarlierCasualty"
	older.position = Vector2(800, 0)
	world.add_child(older)
	await process_frame
	patient.is_incapacitated = true
	patient.health = 1
	older.is_dead = true
	older.health = 0
	care.report_injury(patient)
	care.report_injury(older)
	var key: String = patient.get_meta("medical_identity")
	var old_key: String = older.get_meta("medical_identity")
	care.incidents[key].age = 0.0
	care.incidents[old_key].age = 20.0
	check(care._dispatch_priority(care.incidents[key]) > care._dispatch_priority(care.incidents[old_key]), "Recent living patient receives priority over a recent fatal casualty")
	care.incidents[old_key].age = 90.0
	check(care._dispatch_priority(care.incidents[old_key]) > care._dispatch_priority(care.incidents[key]), "Long waiting casualties eventually outrank new arrivals")
	care.incidents[key].phase = "reported"
	care.incidents[key].age = 45.0
	check(not care._cleanup_incident(key, .5), "Reported patient survives the old 30 second unattended timeout")
	care.incidents[key].phase = "dispatched"
	care.incidents[key].age = 119.0
	care.incidents[key].rescue_age = 0.0
	check(not care._cleanup_incident(key, 2.0), "Dispatch starts its own rescue deadline after a long queue")
	care.incidents[key].phase = "noticed"
	var responder := Resident.new()
	responder.position = Vector2(100, 0)
	responder.add_to_group("firefighter")
	world.add_child(responder)
	responder.set_physics_process(true)
	var wall := StaticBody2D.new()
	wall.position = Vector2(50, 0)
	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	collider.shape.size = Vector2(12, 120)
	wall.add_child(collider)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	care._notice_by_responder(patient, care.incidents[key], 2.0)
	check(care.incidents[key].phase == "noticed", "Responder cannot report a casualty through a wall")
	wall.queue_free()
	await physics_frame
	await physics_frame
	care._notice_by_responder(patient, care.incidents[key], .5)
	check(care.incidents[key].phase == "noticed", "Responder needs sustained visual recognition")
	care._notice_by_responder(patient, care.incidents[key], .5)
	check(care.incidents[key].phase == "reported", "Responder reports a visible casualty without civilian witnesses")
	check(responder.is_physics_processing(), "Reporting does not take over the responder's assignment")
	var unit := Unit.new()
	world.add_child(unit)
	unit.target = patient
	var sequence := preload("res://world/shared/emergency/MedicalRescueSequence.gd").new()
	unit.add_child(sequence)
	sequence.set_physics_process(false)
	sequence.ambulance = unit
	sequence.patient = patient
	sequence.carrying = true
	sequence.delivered = true
	sequence.hospital_delivery = true
	care.begin_carry(patient, unit, sequence)
	care.board_patient(patient, unit)
	var actual_position := patient.global_position
	sequence._abort("test_interrupted_hospital_handoff")
	check(patient.visible and care.incidents[key].phase == "reported", "Interrupted hospital unload puts the boarded patient back in the rescue queue")
	check(patient.global_position == actual_position and care.records()[key].phase == "down", "Interrupted handoff preserves the patient's actual location without granting admission")
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	print("MEDICAL_TRIAGE_REPORTING failures=", failures)
	quit(0 if failures.is_empty() else 1)
