extends SceneTree

class Checkpoint extends Node2D:
	var spawn: Marker2D
	func get_checkpoint_spawn() -> Node2D: return spawn

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	create_timer(20).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	# Cargo deliberately precedes the truck in the vehicle group.
	var factory = preload("res://world/shared/emergency/ModernTrafficFactory.gd")
	var cargo = factory.spawn_parked_vehicle(world, "Cargo", Vector2.ZERO, 0, "sport_coupe", 0)
	cargo.set_meta("tow_carried", true)
	cargo.hide()
	cargo.process_mode = Node.PROCESS_MODE_DISABLED
	cargo.collision_layer = 0
	var truck = factory.spawn_parked_vehicle(world, "NecoTowTruck", Vector2.ZERO, 0, "towmaster", 0)
	truck.add_to_group("mission_vehicle")
	truck.has_theft_alarm = false
	player.position = Vector2(0, -45)
	player.try_enter_vehicle()
	check(truck.is_driven_by_player, "Entry ignores hidden cargo sharing the truck position")
	truck._boarding._finish()
	await process_frame
	truck.exit_vehicle()
	truck._boarding._finish_exit()
	await physics_frame
	check(player.visible and not player.is_control_disabled and not truck.is_driven_by_player, "Exit restores on-foot controls")
	player.try_enter_vehicle()
	check(truck.is_driven_by_player and cargo.has_meta("tow_carried") and truck.is_in_group("mission_vehicle"), "Reentry preserves cargo and mission vehicle identity")
	# Fall during boarding, with a stale passenger position near the wrong hospital.
	var far_spawn := Marker2D.new()
	far_spawn.position = Vector2(0, 200)
	far_spawn.add_to_group("hospital_spawn")
	world.add_child(far_spawn)
	var near_spawn := Marker2D.new()
	near_spawn.position = Vector2(5000, 200)
	near_spawn.add_to_group("hospital_spawn")
	world.add_child(near_spawn)
	truck.position = Vector2(5000, 0)
	var fall = preload("res://world/mountain_pass/MountainCliffFall.gd").new()
	root.add_child(fall)
	fall.begin(truck, Vector2.DOWN)
	fall._impact()
	check(player.is_dead and not truck.is_driven_by_player and not truck.has_meta("vehicle_boarding"), "Impact cancels boarding and detaches the driver synchronously")
	await create_timer(2.4).timeout
	check(player.global_position.distance_to(near_spawn.global_position) < 1, "Recovery chooses the hospital nearest the fall, not stale passenger coordinates")
	check(player.is_physics_processing() and not player.is_control_disabled and not player.has_meta("mountain_falling") and player.visible, "Recovery clears fall and control state")
	var provider := Checkpoint.new()
	provider.spawn = far_spawn
	provider.add_to_group("player_checkpoint_provider")
	world.add_child(provider)
	check(player._get_recovery_position() == far_spawn.global_position, "Active checkpoint retains priority over nearest hospital")
	world.queue_free()
	await process_frame
	print("TOW_REENTRY_FALL failures=", failures)
	quit(0 if failures == 0 else 1)
