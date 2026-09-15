extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var spawn := Marker2D.new()
	spawn.position = Vector2(500, 500)
	spawn.add_to_group("hospital_spawn")
	scene.add_child(spawn)
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	for balance in [350, 60, 0]:
		player._respawn_grace_active = false
		player.money = balance
		player.take_damage(999)
		check(player.is_dead, "Lethal damage starts death")
		await create_timer(2.3).timeout
		check(not player.is_dead and not player.is_recovering, "Discharge immediately clears death and recovery")
		check(is_zero_approx(player.model_root.rotation.x) and is_zero_approx(player.model_root.rotation.z), "Discharge is upright")
		check(player.health == player.max_health, "Health restored")
		check(player.money == maxi(0, balance - 100), "Fee once, clamped to available money")
		check(player.is_control_disabled and player._hospital_exit_remaining > 0.0, "Walkout controls active")
		var start: Vector2 = player.global_position
		player.take_damage(50)
		check(player.health == player.max_health, "Walkout protected from damage")
		await create_timer(1.6).timeout
		check(player.global_position.distance_to(start) > 15.0, "Walkout moves character")
		check(player.global_position.distance_to(spawn.position) < 3.0, "Walkout reaches discharge marker")
		check(not player.is_control_disabled and player.is_physics_processing(), "Controls restored")
		check(player.money == maxi(0, balance - 100), "No repeated charge during exit")
	player.money = 350
	player.arrest_and_respawn()
	await create_timer(2.4).timeout
	check(player.money == 350 and not player.is_arrested, "Arrest remains separate from medical fee")
	print("HOSPITAL_RESPAWN failures=", failures)
	quit(1 if failures else 0)

