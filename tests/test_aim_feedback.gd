extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for frame in count: await physics_frame

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session.ready_for_play, "Production session ready")
	var gameplay = world.gameplay
	var state = gameplay.state
	var controls = root.get_node("GameInput")
	state.economy.activate_arsenal_cheat()
	state.equip_weapon("pistol")
	controls.aim_direction = Vector2.LEFT
	for step in 10: controls._update_gamepad_aim(Vector2.RIGHT, 1.0 / 60.0)
	check(controls.aim_direction.distance_to(Vector2.RIGHT) < 0.01, "Full stick reverses aim within 167 ms")
	var direction: Vector2 = controls.aim_direction
	check(not controls._update_gamepad_aim(Vector2(0.1, 0), 1.0 / 60.0) and controls.aim_direction == direction, "Deadzone preserves direction")
	controls.touch_aim = Vector2.RIGHT
	Input.action_press("aim")
	await frames(12)
	check(gameplay.aim_feedback_active(), "Firearm aiming shows feedback")
	var reticle: Control = gameplay.find_child("AimReticle", true, false)
	reticle._process(0.0)
	check(reticle.visible and reticle.position.distance_to(world.camera.unproject_position(reticle.world_point)) < 0.1, "Visible reticle projects the firing path")
	check(world.camera._desired_lead(world.player.global_position, false).length() > 2.0, "Exterior camera looks ahead when aiming stationary")
	var origin: Vector3 = gameplay._muzzle_world_position()
	var line: Vector3 = gameplay.aim_point - origin
	line.y = 0
	line = line.normalized()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 3, 0.5)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = origin + line * 1.5
	await frames(3)
	var hit: Dictionary = gameplay.aim_feedback()
	check(hit.blocked and origin.distance_to(hit.point) < 2.0, "Solid before muzzle target marks actual obstruction")
	wall.queue_free()
	Input.action_release("aim")
	await frames(3)
	check(not gameplay.aim_feedback_active(), "Release removes aiming feedback")
	reticle._process(0.0)
	check(not reticle.visible, "Reticle control hides on release")
	Input.action_press("aim")
	# Exercise the combat permission contract without pretending a room was loaded.
	world.session.set_process(false)
	state.set_location("harbor", "maciota")
	await frames(3)
	check(not gameplay.aim_feedback_active() and not gameplay.fire_at(gameplay.aim_point), "Garage blocks aiming feedback and firing")
	check(state.equipped_weapon == "fists" and state.owns_weapon("pistol"), "Garage holsters without losing inventory")
	state.set_location("harbor", "")
	state.equip_weapon("pistol")
	world.player.input_locked = true
	await frames(3)
	check(not gameplay.aim_feedback_active(), "Locked input hides aiming feedback")
	Input.action_release("aim")
	print("AIM_FEEDBACK failures=", failures)
	quit(0 if failures.is_empty() else 1)
