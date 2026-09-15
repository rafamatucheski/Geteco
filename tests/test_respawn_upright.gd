extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var spawn := Marker2D.new()
	spawn.position = Vector2(500, 500)
	spawn.add_to_group("hospital_spawn")
	scene.add_child(spawn)
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.take_damage(999)
	check(player.is_dead, "Lethal damage starts death")
	await create_timer(0.6).timeout
	check(player.model_root.rotation.x > 1.0, "Death retains the fallen pose")
	while player.global_position != spawn.position:
		await process_frame
	check(not player.is_dead and not player.is_recovering, "Alive on the first hospital frame")
	check(is_zero_approx(player.model_root.rotation.x) and is_zero_approx(player.model_root.rotation.z), "Upright on the first hospital frame")
	check(player.is_physics_processing() and not player.is_control_disabled, "Controls available immediately")
	check(player.health == player.max_health, "Health restored")
	player.take_damage(50)
	check(player.health == player.max_health and player._respawn_grace_active, "Respawn damage protection preserved")
	await create_timer(3.1).timeout
	check(not player._respawn_grace_active, "Protection expires after three seconds")
	player.take_damage(10)
	check(player.health == player.max_health - 10, "Damage resumes after protection")
	var police := Marker2D.new()
	police.position = Vector2(800, 800)
	police.add_to_group("police_spawn")
	scene.add_child(police)
	player.arrest_and_respawn()
	while player.global_position != police.position:
		await process_frame
	check(not player.is_arrested and not player.is_recovering, "Arrest restores controls at the police station")
	print("RESPAWN_UPRIGHT failures=", failures)
	quit(1 if failures else 0)
