extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(800, 600)
		var camera := Camera2D.new()
		camera.position = Vector2(65, 0)
		camera.zoom = Vector2.ONE * 5.0
		world.add_child(camera)
	var care = root.get_node("NPCMedicalCare")
	care.set_process(false)
	root.get_node("WantedManager").set_process(false)
	var patient := AnimatedPedestrian3D.new()
	world.add_child(patient)
	patient.set_physics_process(false)
	await process_frame
	await process_frame
	patient.take_damage(1000)
	var key: String = patient.get_meta("medical_identity")
	care._process(30.0)
	check(care.incidents[key].phase == "noticed", "Time alone does not dispatch an ambulance")
	var witness := AnimatedPedestrian3D.new()
	witness.position = Vector2(100, 0)
	world.add_child(witness)
	witness.set_physics_process(false)
	witness.is_gangster = false
	for attempt in 30:
		witness.is_scared = false
		witness.panic()
		check(not "ARMADO" in witness._panic_label.text, "Generic panic does not claim a weapon")
	witness.is_scared = false
	await process_frame
	await process_frame
	care._process(0.5)
	var caller = care.incidents[key].witness
	check(is_instance_valid(caller), "One nearby resident stops to call")
	caller.set_physics_process(false)
	caller._physics_process(0.61)
	check(caller.phase == "call" and caller._phone.visible, "Caller raises a visible phone")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/witness-0911/phone.png")
	caller._physics_process(4.9)
	check(care.incidents[key].phase == "noticed", "No dispatch before five seconds")
	witness.is_scared = true
	caller._physics_process(0.2)
	await process_frame
	check(care.incidents[key].phase == "noticed", "Interrupted call does not report casualty")
	witness.is_scared = false
	care._process(0.5)
	caller = care.incidents[key].witness
	caller.set_physics_process(false)
	caller._physics_process(0.61)
	caller._physics_process(5.01)
	check(care.incidents[key].phase == "reported", "Completed five-second call reports casualty")
	check(not caller._phone.visible, "Caller puts phone away after reporting")
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	print("WITNESS_CALL failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
