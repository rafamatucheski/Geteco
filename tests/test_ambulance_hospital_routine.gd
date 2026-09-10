extends SceneTree
## Ciclo médico completo no porto: despacho, acesso a pé, transporte e alta.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	create_timer(90).timeout.connect(func(): printerr("AMBULANCE_HOSPITAL TIMEOUT"); quit(2))
	Engine.time_scale = 3.0
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for frame in 30: await physics_frame
	paused = false
	get_first_node_in_group("player").global_position = Vector2(600, 600)
	var wanted := root.get_node("WantedManager")
	wanted.clear_wanted_level()
	wanted.set_process(false)
	var patient = load("res://AnimatedPedestrian3D.gd").new()
	patient.position = Vector2(1920, 1760)
	current_scene.add_child(patient)
	await physics_frame
	patient.get_run_over(Vector2(120, 0))
	wanted.clear_wanted_level()
	check(patient.is_incapacitated and not patient.is_dead, "Impacto leve produz vítima resgatável")
	var ambulance: Node2D
	for frame in 120:
		for unit in get_nodes_in_group("emergency_vehicle"):
			if unit.visible and unit.type == 1 and unit.target == patient: ambulance = unit
		if is_instance_valid(ambulance): break
		await physics_frame
	check(is_instance_valid(ambulance), "Hospital despacha ambulância para a vítima")
	if not is_instance_valid(ambulance):
		quit(1)
		return
	var traveled := 0.0
	var last: Vector2 = ambulance.global_position
	for frame in 600:
		await physics_frame
		traveled += last.distance_to(ambulance.global_position)
		last = ambulance.global_position
		if patient.emergency_rescue_in_progress: break
	check(traveled > 1.0, "Ambulância se desloca fisicamente até o atendimento")
	check(patient.emergency_rescue_in_progress and not patient.visible, "Socorristas atendem e embarcam a vítima")
	for frame in 900:
		await physics_frame
		if patient.visible and not patient.is_incapacitated: break
	check(patient.visible and not patient.is_incapacitated and patient.health == patient.max_health, "Vítima retorna recuperada após chegar ao hospital")
	check(not patient.fall_presentation.started and absf(patient.model_root.rotation.x) < 0.01, "Alta restaura postura de pé após a animação de queda")
	check(patient.fall_presentation.shadow.scale.is_equal_approx(Vector3.ONE) and is_equal_approx(patient.viewport.get_camera_3d().fov, 36.0), "Alta restaura sombra e enquadramento normal")
	check(ambulance.returned_paramedics == 2, "Os dois paramédicos voltam à ambulância")
	Engine.time_scale = 1.0
	print("AMBULANCE_HOSPITAL: ", failures)
	quit(0 if failures.is_empty() else 1)
