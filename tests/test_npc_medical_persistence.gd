extends SceneTree
var failures: Array[String] = []
class Unit:
	extends Node2D
	signal arrived_at_depot(vehicle: Node, depot: String)
	var is_broken := false
	var target: Node
	var is_returning_to_base := false
	var hearse: Node2D
	var is_dead := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var care = root.get_node("NPCMedicalCare")
	care.set_process(false)
	var campaign = root.get_node("CampaignState")
	var unit := Unit.new()
	world.add_child(unit)
	var worker := Unit.new()
	worker.hearse = unit
	world.add_child(worker)
	for resource in ["res://characters/AnimatedPedestrian3D.gd", "res://world/harbor/HarborDockWorker.gd", "res://world/mountain_pass/WinterResident.gd", "res://world/harbor/cemetery/CemeteryKeeper.gd", "res://police/PoliceOfficer.tscn", "res://emergency/Firefighter.tscn", "res://emergency/Paramedic.tscn", "res://emergency/Mortician.tscn", "res://characters/CarjackedDriver.tscn"]:
		var loaded = load(resource)
		var actor = loaded.instantiate() if loaded is PackedScene else loaded.new()
		actor.name = "Resident_" + str(resource.hash())
		actor.position = Vector2(100,100)
		if "work_points" in actor:
			actor.work_points = PackedVector2Array([Vector2(100,100),Vector2(200,100)])
			actor.work_route = actor.work_points
		world.add_child(actor)
		actor.set_physics_process(false)
		care._register(actor)
		actor.take_damage(1000)
		care.report_injury(actor)
		var key: String = actor.get_meta("medical_identity", "")
		var coroner := root.get_node("CoronerCare")
		check(actor.is_dead and coroner.records().has(key), resource+" creates a persistent death record")
		unit.target = actor
		unit.hearse = unit
		check(not care.begin_carry(actor,unit,unit), resource+" cannot enter ambulance recovery after confirmed death")
		coroner.assigned(actor,unit)
		check(coroner.begin_collection(actor,worker), resource+" can be collected by the IML")
		check(not coroner.begin_collection(actor,worker), resource+" cannot be collected twice")
		coroner.board(worker,unit)
		check(coroner.records()[key].phase == "transport", resource+" records custody only after boarding")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
		check(campaign.restore_from_save(saved), "Campaign save restores")
		care.advance_days(3.0)
		check(actor.is_dead and not actor.visible, resource+" remains dead after three game days")
		check(coroner.records()[key].phase == "transport", resource+" save retains the body in transport")
		actor.queue_free()
		await process_frame
	# Hospital state survives unloading and re-creating an authored resident.
	var first = load("res://characters/AnimatedPedestrian3D.gd").new()
	first.name = "PersistentCitizen"
	world.add_child(first)
	first.set_physics_process(false)
	care._register(first)
	first.get_run_over(Vector2(50,0))
	var id: String = first.get_meta("medical_identity")
	unit.target = first
	care.begin_carry(first,unit,unit)
	care.board_patient(first,unit)
	unit.arrived_at_depot.emit(unit,"hospital")
	care.advance_days(.4)
	first.queue_free()
	await process_frame
	var replacement = load("res://characters/AnimatedPedestrian3D.gd").new()
	replacement.name = "PersistentCitizen"
	world.add_child(replacement)
	care._register(replacement)
	check(replacement.get_meta("medical_identity") == id and not replacement.visible, "Region reload does not resurrect a hospitalized citizen")
	care.advance_days(.61)
	check(replacement.visible and not replacement.is_incapacitated, "Nonfatal patient returns after one game day across reload")
	# Lost ambulance returns its patient to the rescue queue, never to recovery.
	replacement.get_run_over(Vector2(50,0))
	unit.target = replacement
	care.begin_carry(replacement,unit,unit)
	care.board_patient(replacement,unit)
	unit.is_broken = true
	care._process(.6)
	check(replacement.visible and care.incidents[id].phase == "reported", "Broken ambulance leaves patient available for another rescue")
	check(care.records()[id].phase == "down", "Interrupted transport cannot count as hospital admission")
	unit.is_broken = false
	care.begin_carry(replacement,unit,unit)
	care.board_patient(replacement,unit)
	unit.arrived_at_depot.emit(unit,"hospital")
	replacement.queue_free()
	await process_frame
	care.advance_days(2.01)
	check(care.records()[id].phase == "discharged", "Discharge remains pending while region is unloaded")
	var discharged = load("res://characters/AnimatedPedestrian3D.gd").new()
	discharged.name = "PersistentCitizen"
	world.add_child(discharged)
	care._register(discharged)
	check(discharged.visible and not discharged.is_dead and not care.records().has(id), "Reload applies pending discharge once")
	print("NPC_MEDICAL_PERSISTENCE failures=",failures.size()," ",failures)
	world.queue_free()
	await process_frame
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
