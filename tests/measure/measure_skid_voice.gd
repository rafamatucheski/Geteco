extends SceneTree
## Sonda (não é contrato): mede volume_db/pitch da voz de derrapagem em cenários reais.
## Uso: run_godot_locked.sh --path . --script res://tests/measure/measure_skid_voice.gd -- id1,id2
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	stage.add_child(ground)
	var ids := ["sport_coupe", "american_dump_truck"]
	for a in OS.get_cmdline_user_args():
		ids = a.split(",")
	for id in ids:
		for scenario in ["handbrake", "drift", "brake", "launch"]:
			await _case(stage, str(id), scenario)
	quit(0)

func _case(stage: Node3D, id: String, scenario: String) -> void:
	var input = root.get_node("/root/GameInput")
	var car: CharacterBody3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.position = Vector3(0, 0.05, 0)
	stage.add_child(car)
	if STREET.has(id): preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car)
	car.controlled = true
	for i in 10: await physics_frame
	var target := 15.0 if scenario == "handbrake" else 22.0
	if scenario != "launch":
		input.touch_move = Vector2(0, -1)
		for i in 60 * 14:
			await physics_frame
			if Vector2(car.velocity.x, car.velocity.z).length() >= target: break
	var tires = car.effects.tire_effects
	var frames := 75
	match scenario:
		"handbrake": input.touch_move = Vector2.ZERO; Input.action_press("handbrake")
		"drift": input.touch_move = Vector2(1, -1)
		"brake": input.touch_move = Vector2(0, 1)
		"launch": input.touch_move = Vector2(0, -1)
	var n := 0; var vmin := 99.0; var vmax := -99.0; var pmin := 9.0; var pmax := 0.0; var latmax := 0.0; var spd := 0.0
	var kind := ""
	for i in frames:
		await physics_frame
		var h: Vector3 = car.horizontal_velocity
		latmax = maxf(latmax, absf(h.dot(car.global_basis.x)))
		spd = h.length()
		var a = tires.skid_audio
		if is_instance_valid(a) and a.playing:
			n += 1
			vmin = minf(vmin, a.volume_db); vmax = maxf(vmax, a.volume_db)
			pmin = minf(pmin, a.pitch_scale); pmax = maxf(pmax, a.pitch_scale)
			kind = str(a.stream.resource_path.get_file()) if a.stream else ""
	Input.action_release("handbrake")
	input.touch_move = Vector2.ZERO
	print("MEDIDA %s %s tocando=%d/%d vol=[%.1f..%.1f] pitch=[%.2f..%.2f] lat_max=%.1f vel_fim=%.1f" % [id, scenario, n, frames, vmin, vmax, pmin, pmax, latmax, spd])
	car.queue_free()
	for i in 5: await physics_frame
