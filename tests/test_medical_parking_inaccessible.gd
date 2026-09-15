extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var care := root.get_node("NPCMedicalCare")
	care.set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var patient := preload("res://AnimatedPedestrian3D.gd").new()
	patient.position = Vector2(200,130)
	world.add_child(patient)
	patient.set_physics_process(false)
	patient.is_gangster = false
	await process_frame
	patient.health = 0
	patient.is_dead = true
	care.report_injury(patient)
	var unit: Node2D
	for frame in 60:
		unit = root.get_node("EmergencyPool").get_vehicle("ambulance")
		if is_instance_valid(unit): break
		await process_frame
	unit.set_physics_process(false)
	unit.position = Vector2.ZERO
	unit.rotation = 0
	unit.target = patient
	var key: String = patient.get_meta("medical_identity")
	care.incidents[key].unit = unit
	care.incidents[key].phase = "dispatched"
	for entry in [[Vector2(-90,0),Vector2(8,160)],[Vector2(90,0),Vector2(8,160)],[Vector2(0,-76),Vector2(188,8)],[Vector2(0,76),Vector2(188,8)]]:
		var wall := StaticBody2D.new()
		wall.position = entry[0]
		var visual := Polygon2D.new()
		var half: Vector2 = entry[1]*.5
		visual.polygon = PackedVector2Array([-half,Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)])
		wall.add_child(visual)
		var solid := CollisionPolygon2D.new()
		solid.polygon = visual.polygon
		wall.add_child(solid)
		world.add_child(wall)
	await physics_frame
	var previous: Vector2 = unit.position
	var max_step := 0.0
	for frame in 300:
		unit._ambulance_approach.tick(unit,patient,.25)
		max_step = maxf(max_step,unit.position.distance_to(previous))
		previous = unit.position
		if unit.is_returning_to_base: break
		await physics_frame
	check(unit.get_meta("medical_abort_reason","") == "parking_access_blocked","Unreachable parking ends with an explicit reason")
	check(unit.target == null and unit.is_returning_to_base,"Failed dispatch releases its target and requests a physical return")
	check(care.incidents[key].unit == null and care.incidents[key].retry == 30,"Casualty reservation is released with a cooldown")
	check(patient.visible and patient.position.distance_to(Vector2(200,130)) < .01,"Blocked parking never relocates or hides the casualty")
	check(unit.deployed_paramedics == 0,"Unsafe parking never deploys a crew")
	check(absf(unit.position.x) < 45 and absf(unit.position.y) < .01 and max_step <= 7.51,"Finite reverse recovery remains inside the physical enclosure without teleporting")
	print("PARKING_INACCESSIBLE failures=",failures," max_step=",max_step)
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
