extends SceneTree
## Real dispatch/Responder lifecycle after the incident source disappears.
## The timeout case advances only the already-running deadline to its boundary;
## travel, crew creation, event delivery and cleanup use production components.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var failures: Array[String] = []
var completed: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func scenario(timeout: bool) -> void:
	var label := "timeout" if timeout else "crew_death"
	var bundle := KIT.build(self,KIT.grid_roads(),Vector3(30,0,10))
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	controller.set_depots("medic",[Vector3(4,0,2)])
	await frames(3)
	var patient := KIT.add_patient(bundle.scene,Vector3(34,0,14))
	emergency.report_injury(patient,false)
	var incident_id: int = emergency.serial
	var unit: RefCounted = null
	for i in 300:
		await physics_frame
		for candidate in controller.units:
			if candidate.incident_id == incident_id:
				unit = candidate
				break
		if unit != null: break
	check(unit!=null,label+": productive dispatch created unit")
	if unit == null:
		KIT.teardown(bundle)
		return
	var notices := {"incident_invalid":0,"crew_lost":0,"incident_abandoned":0,"unit_finished":0}
	controller.dispatch_event.connect(func(event_name: String, data: Dictionary):
		if data.get("unit") == unit and notices.has(event_name): notices[event_name] += 1)
	# Remove the patient only after the actual responder has left the vehicle.
	# This guarantees returning takes time and exposes the repeated-loss bug.
	var working := false
	for i in 2400:
		await physics_frame
		if unit.finished: break
		if unit.state == "working" and is_instance_valid(unit.crew):
			if unit.crew.global_position.distance_to(unit.vehicle.global_position)>4.5:
				working = true
				break
	check(working,label+": real crew disembarked and walked toward patient")
	if not working:
		KIT.teardown(bundle)
		return
	var crew: CharacterBody3D = unit.crew
	patient.queue_free()
	await frames(4)
	check(notices.incident_invalid==1,label+": source loss is notified exactly once")
	check(is_instance_valid(crew) and crew.mode=="return",label+": surviving crew starts physical return")
	if not is_instance_valid(crew):
		KIT.teardown(bundle)
		return
	if timeout:
		# Bounded timer-boundary fixture: no 300-second wait or artificial movement.
		unit.state_age = RULES.MAX_INCIDENT_SECONDS - .005
	else:
		crew.receive_damage(crew.health+1.0)
		check(crew.dead,label+": productive damage killed responder")
	await frames(6)
	check(notices.incident_invalid==1,label+": subsequent ticks do not repeat source loss")
	check(notices.incident_abandoned==1 if timeout else notices.crew_lost==1,label+": cleanup branch remains reachable after source removal")
	check(not is_instance_valid(unit.crew),label+": unit released responder ownership")
	check(unit.state=="departing" or unit.finished,label+": unit leaves working state")
	if timeout:
		check(not is_instance_valid(crew),label+": expired live responder is released")
	else:
		# A dead responder remains an injury for the real emergency manager.
		check(is_instance_valid(crew) and crew.dead,label+": corpse is retained for the mortician")
	for i in 3600:
		if unit.finished: break
		await physics_frame
	await frames(3)
	check(unit.finished,label+": unit finishes after departure")
	check(not controller.units.has(unit),label+": dispatch slot released")
	check(notices.unit_finished==1,label+": finish emitted exactly once")
	check(not is_instance_valid(unit.vehicle),label+": departed vehicle freed")
	var incident: Dictionary = emergency.incidents.get(incident_id,{})
	check(incident.is_empty() or not incident.get("assigned",false),label+": original incident no longer assigned")
	completed.append(label)
	KIT.teardown(bundle)
	await frames(3)

func run() -> void:
	await scenario(false)
	await scenario(true)
	check(completed.size()==2,"both lifecycle scenarios reached their end")
	print("DISPATCH_ACTOR_LOSS groups=",completed.size(),"/2 checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
