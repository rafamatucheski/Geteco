extends SceneTree
## Local functional contract with the real Responder, Fire, dispatch, native
## physics and WaterJet nodes. The incident starts already parked to isolate
## cleanup; this is not first-response coverage, visual approval or FPS evidence.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const FIRE := preload("res://gameplay/emergency/Fire.gd")
var failures: Array[String] = []
var checks := 0
var completed: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func jet_active(jet: Node3D) -> bool:
	if not is_instance_valid(jet) or not jet.visible: return false
	for emitter in [jet.drops, jet.mist, jet.splash]:
		if not emitter.emitting: return false
	return true

func water_active(crew: CharacterBody3D) -> bool:
	return jet_active(crew.stream) and jet_active(crew.cannon)

func activate_cannon_contract(crew: CharacterBody3D, fire: Node3D) -> void:
	# Explicit state injection for cleanup only. The real exported rescue_pumper
	# currently has no fire_monitor/tip after decoration; this does not repair or
	# approve its rig. Both actual WaterJet objects and their emitters are tested.
	crew.cannon.aim(crew.vehicle.global_position+Vector3.UP*3.0,fire.global_position)
	crew.cannon.set_active(true)

func water_stopped(crew: CharacterBody3D) -> bool:
	for jet in [crew.stream, crew.cannon]:
		if not is_instance_valid(jet) or jet.visible: return false
		for emitter in [jet.drops, jet.mist, jet.splash]:
			if emitter.emitting: return false
	for piece in crew.hose:
		if piece.visible: return false
	return true

func water_ids(crew: CharacterBody3D) -> Array[int]:
	var result: Array[int] = []
	for jet in [crew.stream, crew.cannon]:
		result.append(jet.get_instance_id())
		for emitter in [jet.drops, jet.mist, jet.splash]: result.append(emitter.get_instance_id())
	for piece in crew.hose: result.append(piece.get_instance_id())
	return result

func setup_case() -> Dictionary:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(20, 0, 12))
	var controller: Node3D = bundle.controller
	controller.set_physics_process(false)
	var gameplay: Node3D = bundle.gameplay
	gameplay.set_physics_process(false)
	bundle.player.set_physics_process(false)
	await frames(3)
	check(controller._ensure_bridge(), "real incident bridge exists")
	var car: CharacterBody3D = controller._create_vehicle("fire", Vector3(20, 0, 2), 0.0)
	var unit: RefCounted = controller._make_unit("fire", car, 10.0, 0.45)
	var emergency: Node3D = gameplay.emergency
	var fire := FIRE.new()
	fire.manager = emergency
	fire.position = Vector3(29, 0.03, 2)
	fire.intensity = 2.0
	emergency.add_child(fire)
	# Pause its lifetime while establishing the same active-service precondition.
	fire.set_physics_process(false)
	emergency.fires.append(fire)
	emergency.serial += 1
	var key: int = emergency.serial
	emergency.incidents[key] = {"actor":fire,"role":"fire","age":0.0,"assigned":true,"point":fire.global_position,"crew":car}
	unit.incident_id = key
	unit.actor = fire
	unit.state = "working"
	unit.crew = controller.spawn_responder(unit, Vector3(26.5, 0.05, 2))
	controller.claim_incident(unit)
	unit.crew.mode = "service"
	unit.driver.hold(true)
	controller.set_physics_process(true)
	bundle["unit"] = unit
	bundle["crew"] = unit.crew
	bundle["fire"] = fire
	bundle["key"] = key
	await frames(4)
	return bundle

func verify_boarding(bundle: Dictionary, label: String) -> void:
	var unit: RefCounted = bundle.unit
	var crew = bundle.crew
	var controller: Node3D = bundle.controller
	var started: Vector3 = crew.global_position
	var moved := false
	for i in 360:
		await physics_frame
		if is_instance_valid(crew): moved = moved or crew.global_position.distance_to(started) > 0.15
		if not controller.events_named("crew_boarded").is_empty(): break
	check(moved, label+": crew walks back through native physics")
	check(not controller.events_named("crew_boarded").is_empty(), label+": normal dispatch boarding occurs")
	check(unit.crew == null and unit.state == "departing", label+": vehicle departs only after boarding")
	await frames(2)
	check(not is_instance_valid(crew), label+": responder and water nodes are freed after boarding")

func exercise(kind: String) -> void:
	var bundle: Dictionary = await setup_case()
	var crew: CharacterBody3D = bundle.crew
	var fire = bundle.fire
	var unit: RefCounted = bundle.unit
	var controller: Node3D = bundle.controller
	check(crew.mode == "service" and jet_active(crew.stream), kind+": real hand jet emits before transition")
	check(fire.intensity < 2.0 and not fire.is_queued_for_deletion(), kind+": active service still extinguishes fire")
	print("RIG_COVERAGE ", JSON.stringify({"case":kind,"monitor":crew.vehicle.has_meta("fire_monitor"),"tip":crew.vehicle.has_meta("fire_monitor_tip"),"cannon_active":jet_active(crew.cannon),"native_cannon_coverage":"observed only; missing rig is a separate unresolved defect"}))
	var ids := water_ids(crew)
	if kind == "natural_decay":
		# Exercise Fire's actual expiration callback before DispatchController,
		# matching the production parent order; do not call callbacks manually.
		fire.age = FIRE.BURN_SECONDS + 1.0
		fire._fade_from = 1.0
		fire.intensity = 0.00001
		fire.set_physics_process(true)
	elif kind == "removed_source":
		fire.queue_free()
	elif kind == "cancel_and_reuse":
		activate_cannon_contract(crew,fire)
		check(water_active(crew), "explicit dual-jet cleanup precondition: both real WaterJets emit")
		check(controller.cancel_incident(bundle.key), "cancel accepts the active fire incident")
		check(crew.mode == "return" and water_stopped(crew), "cancel stops all jets before returning to caller")
		check(unit.state == "working" and is_instance_valid(unit.crew), "cancel keeps crew alive for physical return")
		# Re-enter using the same supported property/API, without allocating jets.
		crew.mode = "service"
		controller.claim_incident(unit)
		await frames(3)
		check(jet_active(crew.stream), "real service reentry resumes the existing hand jet")
		check(water_ids(crew) == ids, "reentry reuses jets, emitters and hose pieces")
		activate_cannon_contract(crew,fire)
		check(water_active(crew), "explicit dual-jet reentry precondition reuses the same cannon")
		check(controller.cancel_incident(bundle.key), "second cancellation remains valid")
	else:
		# Extinction performed by Responder itself remains a supported exit.
		fire.intensity = 0.00001
	await frames(2)
	check(crew.mode == "return", kind+": service changes to return without delay")
	check(water_stopped(crew), kind+": hand jet, cannon and hose are inactive while returning")
	check(water_ids(crew) == ids, kind+": stopping does not replace water resources or nodes")
	if kind != "cancel_and_reuse":
		check(not is_instance_valid(fire) or fire.is_queued_for_deletion(), kind+": source has ended")
	if kind in ["natural_decay", "removed_source"]:
		check(not controller.events_named("incident_invalid").is_empty(), kind+": dispatch observes source loss before return")
	await verify_boarding(bundle, kind)
	KIT.teardown(bundle)
	await frames(2)
	completed.append(kind)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("This contract requires --no-save and isolated runner storage")
		quit(2)
		return
	create_timer(28.0).timeout.connect(func(): push_error("RESPONDER_WATER_RECOVERY timeout"); quit(3))
	if "--probe-rig" in OS.get_cmdline_user_args():
		var bundle: Dictionary = await setup_case()
		var crew: CharacterBody3D = bundle.crew
		var car: CharacterBody3D = bundle.unit.vehicle
		var parts: Array[Dictionary] = []
		for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			var material := part.get_active_material(0) as StandardMaterial3D
			parts.append({"name":str(part.name),"instance_aabb":str(part.get_aabb()),"mesh_aabb":str(part.mesh.get_aabb()),"transform":str(part.transform),"color":str(material.albedo_color) if material != null else "none"})
		print("RIG_DIAGNOSTIC ", JSON.stringify({"archetype":car.archetype,"monitor":car.has_meta("fire_monitor"),"tip":car.has_meta("fire_monitor_tip"),"stream":[crew.stream.visible,crew.stream.drops.emitting,crew.stream.mist.emitting,crew.stream.splash.emitting],"cannon":[crew.cannon.visible,crew.cannon.drops.emitting,crew.cannon.mist.emitting,crew.cannon.splash.emitting],"parts":parts}))
		KIT.teardown(bundle)
		quit(0)
		return
	for kind in ["natural_decay", "removed_source", "cancel_and_reuse", "responder_extinguishes"]:
		await exercise(kind)
	check(completed.size() == 4 and checks >= 48, "all four finite recovery groups completed")
	print("RESPONDER_WATER_RECOVERY groups=%d/4 checks=%d failures=%d" % [completed.size(),checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
