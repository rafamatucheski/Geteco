extends SceneTree
## Rendered integration: real Main, real boarding, deterministic samples, no user save.
## --script res://tests/capture/capture_roadside_theft.gd -- --no-save --evidence-dir=...
var world: Node3D
var output := "res://evidence/roadside-theft"
var snapshots: Array[Dictionary] = []
var failed := false
var camera: Camera3D
var debris_drive := {}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		push_error("Rendered theft capture requires display and --no-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): output = argument.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if _ready_for_capture(): break
	if not _ready_for_capture():
		push_error("Theft capture: Main startup timeout")
		world.free()
		quit(1)
		return
	world.gameplay.god_mode = true
	world.player.set_meta("invulnerable", true)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .40
	world.session.set_process_input(false)
	world.driving.set_process_unhandled_input(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.locked = true
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.5
	world.add_child(camera)
	camera.make_current()
	var car: CharacterBody3D = world.driving.car
	var original_parking_transform := car.global_transform
	car.stop_boarding_motion()
	await create_timer(2.0).timeout
	await capture_case(car, -1, "window", true)
	# O alarme usa o tempo da cena e é dono do próprio Timer. Observa a expiração real, não um sinal simulado.
	var alarm_deadline := Time.get_ticks_msec() + 10000
	while car.has_node("EntryAlarm") and Time.get_ticks_msec() < alarm_deadline:
		await process_frame
	failed = failed or car.has_node("EntryAlarm")
	await snapshot("window_alarm_finished", car)
	await capture_debris_drive(car)
	world.driving.cancel_transition("capture_next_variant")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	# O primeiro carro agora tem o interior aberto de verdade e o vidro quebrado. Um carro
	# trancado novo é necessário para observar com justiça o vidro intacto da variante com ferramenta.
	var fresh: CharacterBody3D = load("res://scripts/Vehicle.gd").new()
	fresh.archetype = car.archetype
	fresh.paint_color = car.paint_color
	var parking_transform := original_parking_transform
	car.set_physics_process(false)
	car.collision_layer = 0
	car.collision_mask = 0
	car.hide()
	car.global_position += Vector3.DOWN * 200.0
	world.add_child(fresh)
	fresh.global_transform = parking_transform
	car = fresh
	await physics_frame
	await capture_case(car, 1, "tool", false)
	world.driving.cancel_transition("capture_restore")
	await process_frame
	failed = failed or world.driving.occupied or world.player.input_locked or world.player.collision_layer == 0
	await snapshot("controls_restored", car)
	var report := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":not failed,"snapshots":snapshots,"debris_drive":debris_drive,"performance_certified":false}, "\t"))
	print("ROADSIDE_THEFT_CAPTURE ", "FAIL" if failed else "PASS", " output=", output)
	world.free()
	await process_frame
	quit(1 if failed else 0)

func _ready_for_capture() -> bool:
	return is_instance_valid(world.production) and world.production.startup_streaming_settled and world.production.ready_for_play and world.session != null and world.session.ready_for_play

func capture_debris_drive(car: CharacterBody3D) -> void:
	var street: Node3D = preload("res://gameplay/street_physics/StreetPhysics.gd").instance
	var vertices := PackedVector3Array()
	for child in street.get_children():
		if not child is MeshInstance3D or not child.get_meta("surface_debris", false) or not child.visible: continue
		if child.global_position.distance_to(car.global_position) > 5.0: continue
		var mesh_node := child as MeshInstance3D
		for vertex in mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			vertices.append(mesh_node.to_global(vertex))
	var maximum_above_floor := 0.0
	var minimum_above_floor := INF
	var unsupported := 0
	var elevations: Array = []
	var space := car.get_world_3d().direct_space_state
	for vertex in vertices:
		var query := PhysicsRayQueryParameters3D.create(vertex + Vector3.UP * .15, vertex + Vector3.DOWN * 4.0, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			unsupported += 1
			continue
		var above: float = vertex.y - (hit.position as Vector3).y
		maximum_above_floor = maxf(maximum_above_floor, above)
		minimum_above_floor = minf(minimum_above_floor, above)
		elevations.append({"vertex_y":vertex.y,"floor_y":(hit.position as Vector3).y,"above_floor":above})
	var start := car.global_position
	await snapshot("glass_ground_before_departure", car)
	var forward: Vector3 = -car.global_basis.z
	var direction := -1.0 if car.test_move(car.global_transform, forward * 3.5) else 1.0
	var obstructed: bool = car.test_move(car.global_transform, forward * direction * 3.5)
	var covered := {}
	car.external_input = true
	car.controlled = true
	car.input_locked = false
	car.brake_input = false
	car.throttle_input = .4 * direction if not obstructed else 0.0
	car.steer_input = .55 * direction if not obstructed else 0.0
	var deadline := Time.get_ticks_msec() + 2300
	var captured_midpoint := false
	while Time.get_ticks_msec() < deadline and start.distance_to(car.global_position) < 3.0:
		await physics_frame
		for index in vertices.size():
			var local: Vector3 = car.to_local(vertices[index])
			if absf(local.x) < car.half_width and absf(local.z) < car.half_length and local.y < .12: covered[index] = true
		if not captured_midpoint and start.distance_to(car.global_position) > 1.0:
			captured_midpoint = true
			await snapshot("car_over_ground_glass", car)
	car.throttle_input = 0.0
	car.steer_input = 0.0
	car.brake_input = true
	await create_timer(.6).timeout
	car.external_input = false
	await snapshot("glass_ground_after_departure", car)
	var displacement := start.distance_to(car.global_position)
	debris_drive = {"static_vertices":vertices.size(),"unsupported_vertices":unsupported,
		"min_above_floor":minimum_above_floor,"max_above_floor":maximum_above_floor,
		"ground_samples":elevations,"car_displacement":displacement,"vertices_under_car_during_drive":covered.size(),
		"route_obstructed":obstructed,"physics_driven":true,"camera_fixed":true}
	# O asfalto da rua é uma sobreposição visual até .030 acima do apoio físico.
	# Os cacos precisam ficar acima dela sem passar de quatro centímetros do chão.
	failed = failed or vertices.is_empty() or unsupported > 0 or maximum_above_floor > .04 or minimum_above_floor < .030 or displacement < 1.0 or covered.is_empty()
	print("THEFT_DEBRIS_DRIVE ", JSON.stringify(debris_drive))

func capture_case(car: CharacterBody3D, side: int, method: String, alarm: bool) -> void:
	car.stop_boarding_motion()
	car.set_meta("ambient_parked", true)
	car.set_meta("vehicle_locked", true)
	car.remove_meta("parked_theft_reported")
	car.remove_meta("entry_alarm_triggered")
	world.player.input_locked = false
	world.player.teleport(car.driver_door_anchor(side))
	# A mão fica do lado de trás do tronco agora que o Dante encara o vidro
	# fechado real. Observa daquele quadrante em vez de através da jaqueta dele.
	camera.global_position = car.to_global(Vector3(float(side) * 5.0, 2.6, 3.2))
	camera.look_at(car.to_global(Vector3(float(side) * .55, .85, .3)), Vector3.UP)
	await process_frame
	await snapshot(method + "_before", car)
	if not world.driving._begin_entry(car, side):
		failed = true
		return
	var transition: Node = world.driving.transition
	if transition.break_in == null:
		push_error("Expected locked-car presentation")
		failed = true
		return
	transition.break_in.choose(0.0 if method == "window" else 1.0, 0.0 if alarm else 1.0)
	transition._motion.pause()
	var thresholds := [.12, .32, .46, .72, .86]
	var frame := 0
	for step in 350:
		if not is_instance_valid(world.driving.transition): break
		transition._motion.custom_step(.025)
		if transition.active: transition._apply()
		await process_frame
		if not is_instance_valid(world.driving.transition): break
		if transition._breaking and frame < thresholds.size() and transition._break_progress >= float(thresholds[frame]):
			await snapshot(method + "_gesture_%02d" % frame, car)
			frame += 1
	failed = failed or is_instance_valid(world.driving.transition) or not car.controlled or world.player.input_locked
	failed = failed or (car.has_meta("entry_alarm_triggered") != alarm)
	await snapshot(method + "_seated", car)

func snapshot(label: String, car: CharacterBody3D) -> void:
	# O renderizador em thread ainda pode ter a câmera/esqueleto anteriores na fila.
	# Duas submissões completas mantêm o PNG pareado com o estado deste snapshot.
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	var transition: Node = world.driving.transition
	var row := {"label":label,"controlled":car.controlled,"occupied":world.driving.occupied,
		"player_locked":world.player.input_locked,"player_collision":world.player.collision_layer,
		"player_visible":world.player.visible,"seated":world.player.seated,
		"tool":world.player.has_node("EntryTool"),"alarm":car.has_node("EntryAlarm"),
		"locked":car.get_meta("vehicle_locked",false),"broken_side":car.get_meta("broken_entry_window_side",0)}
	if is_instance_valid(transition):
		row.phase = transition.phase
		row.gesture_progress = transition._break_progress
		if transition._breaking:
			var side := "Right" if transition.side < 0 else "Left"
			var hand: Vector3 = world.player.combat_palm_position(side)
			var target: Vector3 = car.to_global(transition._break_layout.grip)
			row.hand_target_distance = hand.distance_to(target)
			row.hand_local = str(car.to_local(hand))
			row.contact_local = str(car.to_local(target))
			row.actor_local = str(car.to_local(world.player.global_position))
	snapshots.append(row)
	print("THEFT_FRAME ", JSON.stringify(row))
