extends SceneTree
var failures: Array[String] = []

class Resident extends CharacterBody2D:
	var health := 100
	var is_dead := false
	var is_incapacitated := false

class Unit extends Node2D:
	var is_broken := false

class Worker extends Node2D:
	var hearse: Node2D
	var is_dead := false
	var burial_position := Vector2.ZERO

class Cemetery extends HarborCemetery:
	func _ready() -> void:
		add_to_group("cemetery")
		_build_plot_grid()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var medical := root.get_node("NPCMedicalCare")
	var care := root.get_node("CoronerCare")
	medical.set_process(false)
	care.set_process(false)
	var victim := Resident.new()
	victim.name = "Victim"
	victim.set_meta("display_name", "João")
	world.add_child(victim)
	await process_frame
	victim.is_dead = true
	victim.health = 0
	medical.report_injury(victim)
	var key: String = care.identity(victim)
	check(care.records().has(key), "A confirmed death has a persistent identity")
	medical.incidents[key].age = 1000.0
	check(not medical._cleanup_incident(key,500), "Fatal casualties never enter medical recycling")
	var unit := Unit.new()
	world.add_child(unit)
	var worker := Worker.new()
	worker.hearse = unit
	world.add_child(worker)
	var partner := Worker.new()
	partner.hearse = unit
	world.add_child(partner)
	care.assigned(victim,unit)
	check(not medical.claim_patient(victim,unit,worker), "Ambulance cannot claim a confirmed death")
	check(care.begin_collection(victim,worker), "One worker acquires custody")
	check(not care.begin_collection(victim,partner), "Second worker cannot duplicate the body")
	check(not care.has_cargo(unit) and not victim.visible, "Collection hides the body but does not teleport cargo into the van")
	care.board(worker,unit)
	care.board(worker,unit)
	check(unit.get_meta("coroner_cargo").size()==1 and care.records()[key].phase=="transport", "Physical boarding records exactly one body")
	check(not medical.records().has(key), "Hospital recovery no longer owns the victim")
	var state := root.get_node("CampaignState")
	var saved: Dictionary = state.to_save_data()
	check(saved.coroner_cases[key].phase=="transport", "Save serializes custody during transport")
	care.records()[key].phase = "morgue"
	check(saved.coroner_cases[key].phase=="transport", "Save snapshot does not alias live records")
	check(state.restore_from_save(saved), "Campaign restores the saved transport record")
	unit.is_broken = true
	unit.position = Vector2(120,120)
	care._process(1.1)
	check(care.records()[key].phase=="recovery" and not care.has_cargo(unit), "Broken hearse relinquishes cargo without erasing the death")
	check(care.active[key].recovery is WeakRef and is_instance_valid(care.active[key].recovery.get_ref()), "Lost cargo has a recoverable bag in free space")
	var bag: Node = care.active[key].recovery.get_ref()
	var replacement := Unit.new()
	world.add_child(replacement)
	worker.hearse = replacement
	care.assigned(bag,replacement)
	check(care.begin_collection(bag,worker), "Replacement team can recover the saved body")
	care.board(worker,replacement)
	care.morgue_arrival(replacement)
	check(care.records()[key].phase=="morgue", "IML admission is distinct from burial")
	var cemetery := Cemetery.new()
	cemetery.position = Vector2(1000,1000)
	world.add_child(cemetery)
	check(care.start_burial(replacement,worker), "Burial reserves a real cemetery plot")
	var plot: int = care.records()[key].plot
	check(cemetery.reserve_plot(key)==worker.burial_position and care.records()[key].plot==plot, "Plot reservation is idempotent")
	check(not care.bury(worker), "A distant worker cannot certify burial")
	worker.position = worker.burial_position
	check(care.bury(worker), "A worker at the assigned plot completes burial")
	check(not care.bury(worker), "Duplicate burial is rejected")
	cemetery.restore_burials()
	cemetery.restore_burials()
	check(cemetery._graves.size()==1, "One permanent marker per victim")
	check(care.restore_actor(victim) and victim.is_dead and not victim.visible, "Restoring a buried resident never resurrects them")
	check(care.registry_text().contains("João") and care.registry_text().contains("Sepultado"), "Forensic registry reflects real identity and completed burial")
	var copy: Dictionary = state.to_save_data()
	check(copy.coroner_cases[key].plot==plot and copy.coroner_cases[key].phase=="buried", "Save retains burial and plot ownership")
	for slot in range(1,cemetery._plots.size()):
		care.records()["occupied_%d"%slot] = {"phase":"buried","plot":slot,"scene":"","name":"Reserved","identified":true}
	var waiting := victim.duplicate()
	waiting.set_meta("medical_identity","cemetery_full")
	waiting.set_meta("coroner_identity","cemetery_full")
	world.add_child(waiting)
	care.register_death(waiting)
	worker.hearse = replacement
	check(care.begin_collection(waiting,worker),"Additional victim enters custody normally")
	care.board(worker,replacement)
	care.morgue_arrival(replacement)
	var full_result: bool = care.start_burial(replacement,worker)
	if full_result or care.records()["cemetery_full"].phase!="awaiting_plot": print("CAPACITY diagnostic=",care.records()["cemetery_full"]," cargo=",replacement.get_meta("coroner_cargo")," slots=",cemetery._plots.size())
	check(not full_result and care.records()["cemetery_full"].phase=="awaiting_plot","Full cemetery queues cargo without overwriting an occupied grave")
	check(care.records()[key].plot==plot and care.has_cargo(replacement),"Capacity failure preserves both earlier burial and pending cargo")
	print("CORONER_CUSTODY failures=",failures)
	world.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
