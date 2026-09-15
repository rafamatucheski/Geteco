extends SceneTree
var failures: Array[String] = []
var world: Node2D
var care: Node
var units: Array = []
var victims: Array = []
var sequences: Array = []
var phases := [{},{}]
var blocked := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func run() -> void:
	create_timer(80).timeout.connect(func(): print("MULTIPLE_TIMEOUT ",phases); quit(2))
	blocked = "--blocked" in OS.get_cmdline_user_args()
	care = root.get_node("NPCMedicalCare")
	care.set_process(false)
	root.get_node("WantedManager").set_process(false)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	for i in 2:
		var victim := preload("res://AnimatedPedestrian3D.gd").new()
		victim.name = "Casualty%d"%i
		victim.position = Vector2(i*220,130)
		world.add_child(victim)
		victim.is_gangster = false
		victim.set_physics_process(false)
		victims.append(victim)
	await process_frame
	await process_frame
	for victim in victims:
		victim.health = 0
		victim.is_dead = true
		victim._start_fall()
		care.report_injury(victim)
	if blocked:
		# A closed room, with walls derived from the same visible polygons.
		for entry in [[Vector2(-48,130),Vector2(8,104)],[Vector2(48,130),Vector2(8,104)],[Vector2(0,82),Vector2(104,8)],[Vector2(0,178),Vector2(104,8)]]:
			var wall := StaticBody2D.new()
			wall.position = entry[0]
			var polygon := Polygon2D.new()
			var size: Vector2 = entry[1]
			polygon.polygon = PackedVector2Array([-size*.5,Vector2(size.x,-size.y)*.5,size*.5,Vector2(-size.x,size.y)*.5])
			wall.add_child(polygon)
			var collision := CollisionPolygon2D.new()
			collision.polygon = polygon.polygon
			wall.add_child(collision)
			world.add_child(wall)
	for i in 2:
		var unit: Node2D
		for frame in 60:
			unit = root.get_node("EmergencyPool").get_vehicle("ambulance")
			if is_instance_valid(unit): break
			await process_frame
		unit.position = Vector2(i*220+78,0)
		unit.rotation = 0
		unit.target = victims[i]
		unit.is_acting = true
		unit.set_physics_process(false)
		unit._deploy_paramedics()
		units.append(unit)
		sequences.append(unit.get_meta("medical_sequence"))
	check(not care.claim_patient(victims[0],units[1],sequences[1]),"A second team cannot reserve the first team's casualty")
	check(not care.begin_carry(victims[0],units[1],sequences[1]),"A competing carrier cannot steal the reserved patient at pickup")
	for frame in 3600:
		await physics_frame
		for i in 2:
			if is_instance_valid(sequences[i]): phases[i][sequences[i].phase] = true
		if frame%600==0:
			for i in 2: print("MULTIPLE_STATE ",i," ",units[i].get_meta("medical_phase","")," abort=",units[i].get_meta("medical_abort_reason",""))
		if units[1].returned_paramedics == 2 and units[0].returned_paramedics == 2: break
	for i in 2:
		check(units[i].returned_paramedics == 2,"Both medics physically reboard team %d"%i)
		if i == 0 and blocked:
			check(victims[i].visible,"Inaccessible casualty stays at the original location")
			check(victims[i].position.distance_to(Vector2(0,130)) < .01,"Failure does not relocate the inaccessible casualty")
			check(victims[i].get_meta("medical_access_failure","") == "patient_inaccessible","Inaccessible casualty has an explicit failure reason")
			var incident: Dictionary = care.incidents[victims[i].get_meta("medical_identity")]
			check(incident.unit == null and incident.retry > 0,"Failed team releases the target with a dispatch cooldown")
		else:
			for phase in ["exit","fetch","unload_stretcher","approach_patient","treat","lift_patient","return_with_patient","load_patient","crew_boarding"]:
				check(phases[i].has(phase),"Team %d executes %s"%[i,phase])
			check(not victims[i].visible,"Patient %d is aboard their own ambulance"%i)
	print("MULTIPLE_RESULT blocked=",blocked," failures=",failures)
	for seq in sequences:
		if is_instance_valid(seq): seq.finish_transport_without_entrance()
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
