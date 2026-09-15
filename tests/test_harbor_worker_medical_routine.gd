extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	seed(4183)
	Engine.time_scale = 3.0
	create_timer(300).timeout.connect(func(): print("HARBOR_MEDICAL timeout"); quit(2))
	var world = load("res://world/harbor/HarborPreview.tscn").instantiate()
	world.review_mode = false
	root.add_child(world)
	current_scene = world
	while not world.world_build_ready: await process_frame
	root.get_node("WantedManager").set_process(false)
	var patient: Node2D = world.get_node("SouthPort").workers[0]
	var player: Node2D = world.get_node("Player")
	player.global_position = patient.global_position + Vector2(-100,90)
	player.set_physics_process(false)
	player.set_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE*2.5
	camera.make_current()
	camera.global_position = patient.global_position
	var care = root.get_node("NPCMedicalCare")
	await process_frame
	patient.take_damage(1000)
	var key: String = patient.get_meta("medical_identity")
	var last_phase := ""
	var unit: Node
	var last_report := 0.0
	var elapsed := 0.0
	while elapsed < 280:
		await physics_frame
		elapsed += 1.0/Engine.physics_ticks_per_second*Engine.time_scale
		if care.incidents.has(key):
			var candidate: Variant = care.incidents[key].unit
			if is_instance_valid(candidate): unit = candidate
		if is_instance_valid(unit):
			var phase: String = unit.get_meta("medical_phase", "driving")
			if DisplayServer.get_name() != "headless" and unit.has_meta("medical_sequence"):
				var sequence: Node = unit.get_meta("medical_sequence")
				camera.global_position = unit.global_position + Vector2(0,-65)
				camera.make_current()
				camera.force_update_scroll()
				if is_instance_valid(sequence) and sequence.phase_time > .7 and phase in ["open_rear","treat","lift_patient","return_with_patient","load_patient"] and not unit.has_meta("captured_"+phase):
					unit.set_meta("captured_"+phase,true)
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("D:/geteco/artifacts/harbor-medical-"+phase+".png")
			if phase != last_phase:
				last_phase = phase
				print("HARBOR_MEDICAL ",phase," unit=",unit.global_position," patient=",patient.global_position)
			if elapsed-last_report > 15:
				last_report = elapsed
				print("HARBOR_MEDICAL progress ",elapsed," ",unit.global_position," return=",unit.is_returning_to_base)
				var ray := PhysicsRayQueryParameters2D.create(unit.global_position,unit.global_position+unit.global_transform.x*100,7,[unit.get_rid()])
				var hit: Dictionary = unit.get_world_2d().direct_space_state.intersect_ray(ray)
				if not hit.is_empty(): print("HARBOR_MEDICAL ahead ",hit.collider.get_path()," ",hit.position)
				for i in unit.get_slide_collision_count(): print("HARBOR_MEDICAL collision ",unit.get_slide_collision(i).get_collider())
		if care.records().get(key,{}).get("phase","") == "hospital":
			care.advance_days(2.01)
			var ok: bool = patient.visible and not patient.is_dead and patient.health == patient.max_health
			print("HARBOR_MEDICAL completed=",ok)
			world.queue_free()
			await process_frame
			quit(0 if ok else 1)
			return
	print("HARBOR_MEDICAL incomplete ",care.incidents.get(key,{}))
	quit(1)
