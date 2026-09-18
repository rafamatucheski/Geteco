extends SceneTree
## Production-scene observation of the filmed rescue and terminal service.
const OUTPUT := "D:/geteco/artifacts/hospital-parking-0911/return-near"
var phases: Array[String] = []
var observations: Array[Dictionary] = []
var photos: Dictionary = {}
var previous: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func picture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 20: await physics_frame
	paused = false
	world.get_node("Player").global_position = Vector2(1400, 1370)
	var wanted := root.get_node("WantedManager")
	wanted.clear_wanted_level()
	wanted.set_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(1900, 1510)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	world.weather.time_of_day = 0.45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0.0)
	world.weather._update_lighting()
	var patient = load("res://characters/AnimatedPedestrian3D.gd").new()
	patient.name = "RefinementPatient"
	patient.position = Vector2(2220, 1730)
	world.add_child(patient)
	await physics_frame
	patient.take_damage(1000)
	wanted.clear_wanted_level()
	var care := root.get_node("NPCMedicalCare")
	var unit: Node2D = null
	var start := Time.get_ticks_msec()
	var last_status := start
	var parked_at := 0
	while Time.get_ticks_msec() - start < 240000:
		await physics_frame
		if not is_instance_valid(unit):
			for candidate in get_nodes_in_group("emergency_vehicle"):
				if candidate.visible and candidate.type == 1 and candidate.target == patient:
					unit = candidate
		if is_instance_valid(unit):
			var phase := String(unit.get_meta("medical_phase", "driving"))
			if phase == "transport" or phase.begins_with("hospital"):
				camera.position = Vector2(1900, 1510)
				camera.zoom = Vector2.ONE * 2.1
			var sequence: Node = unit.get_meta("medical_sequence") if unit.has_meta("medical_sequence") else null
			if phases.is_empty() or phases.back() != phase:
				phases.append(phase)
				print("PRODUCTION_RESCUE_PHASE ", phase, " ambulance=", unit.global_position)
			if is_instance_valid(sequence):
				var actors: Array = sequence.crew.duplicate()
				actors.append(patient)
				if is_instance_valid(sequence.stretcher): actors.append(sequence.stretcher)
				for actor in actors:
					if not is_instance_valid(actor): continue
					var key: int = actor.get_instance_id()
					if actor.visible and previous.has(key) and previous[key].visible:
						var step: float = actor.global_position.distance_to(previous[key].position)
						if step > 12.0:
							observations.append({"actor": str(actor.name), "phase": phase, "step": step})
					previous[key] = {"position": actor.global_position, "visible": actor.visible}
				var photo_phase := ("admission-" if sequence.hospital_delivery else "") + phase
				if sequence.phase_time > 0.45 and not photos.has(photo_phase):
					photos[photo_phase] = true
					await picture("production-rescue-" + photo_phase)
		if Time.get_ticks_msec() - last_status > 15000:
			last_status = Time.get_ticks_msec()
			print("PRODUCTION_RESCUE_STATUS elapsed=", (last_status-start)/1000, " unit=", unit.global_position if is_instance_valid(unit) else Vector2.INF, " phases=", phases)
			if is_instance_valid(unit):
				var active_sequence: Node = unit.get_meta("medical_sequence") if unit.has_meta("medical_sequence") else null
				var crew_status: Array = []
				if is_instance_valid(active_sequence):
					for medic in active_sequence.crew:
						if is_instance_valid(medic):
							crew_status.append({"position":medic.global_position,"velocity":medic.velocity,"dead":medic.is_dead,"health":medic.health,"visible":medic.visible,"side":medic.crew_side})
				print("PRODUCTION_RESCUE_CREW ", crew_status, " heading=",unit.rotation," broken=",unit.is_broken," target_original=",unit.target==patient," phase_elapsed=",active_sequence.phase_time if is_instance_valid(active_sequence) else -1)
		if is_instance_valid(unit) and String(unit.get_meta("medical_phase", "")) == "parked":
			if parked_at == 0: parked_at = Time.get_ticks_msec()
			if Time.get_ticks_msec() - parked_at > 6500:
				if not unit.visible: failures.append("Parked ambulance disappeared")
				await picture("production-hospital-delivered")
				break
	if not phases.has("load_patient"): failures.append("Production rescue did not reach loading")
	if not phases.has("parked"): failures.append("Production admission did not end with ambulance visibly parked")
	if not observations.is_empty(): failures.append("Visible actor position jumps observed")
	camera.position = Vector2(1800, 1010)
	camera.zoom = Vector2.ONE * 1.6
	await picture("production-terminal-overview")
	var terminal = world.get_node("ArrivalStop").terminal_operations
	print("PRODUCTION_TERMINAL_STATUS ", terminal.get_operation_status())
	var report := {"phases": phases, "jumps": observations, "failures": failures, "terminal": terminal.get_operation_status()}
	var file := FileAccess.open(OUTPUT.path_join("production-observation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PRODUCTION_LIFE_REFINEMENT ", report)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


