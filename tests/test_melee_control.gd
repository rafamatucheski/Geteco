extends SceneTree
## Contratos focados do controlador de produção. Usa uma fixture física elevada isolada
## depois do início da sessão; não é playtest renderizado nem benchmark de FPS.
## Rode só com --no-save e o ambiente .NET compilado do projeto.

class Target extends CharacterBody3D:
	var dead := false
	var hits := 0
	func receive_damage(_amount: float, _source: Node = null) -> void:
		hits += 1

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("MELEE_CONTROL ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func target_at(parent: Node3D, point: Vector3) -> Target:
	var target := Target.new()
	target.collision_layer = 2
	target.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 1.8, 0.3)
	collider.shape = shape
	collider.position.y = 1.0
	target.add_child(collider)
	parent.add_child(target)
	target.global_position = point
	return target

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("test_melee_control requires --no-save")
		quit(2)
		return
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false, "production session becomes ready")
		quit(1)
		return
	var gameplay = world.gameplay
	var state = gameplay.state
	var controls = root.get_node("GameInput")
	# Mantém o código real de permissão, ataque, seletor e buffer. Para os ticks
	# automáticos deles para que cada asserção controle só a fase de relógio/entrada que exercita.
	world.session.set_process(false)
	gameplay.set_physics_process(false)
	world.player.set_physics_process(false)
	world.player.global_position += Vector3.UP * 60.0
	state.set_location("harbor", "")
	state.economy.activate_arsenal_cheat()
	check(state.equip_weapon("bat"), "test can equip owned bat")
	controls.using_gamepad = false
	controls.touch_aim = Vector2.ZERO
	controls.set_meta("touch_controls_active", false)
	gameplay._clear_melee_action()
	gameplay.cooldown = 0.0
	gameplay.reload_timer = 0.0
	gameplay._update_weapon_pose(0.0)
	gameplay._update_visual()
	var origin: Vector3 = world.player.global_position + Vector3.UP * 1.05
	var aim: Vector3 = origin + Vector3.FORWARD * 4.0
	gameplay.aim_point = aim
	var aligned := target_at(world, world.player.global_position + Vector3.FORWARD * 2.5)
	var nearer := target_at(world, world.player.global_position + Vector3(0.8, 0, -1.2))
	await frames(3)
	var data: Dictionary = gameplay.weapon_data("bat")
	var pick: Dictionary = gameplay._melee_pick(origin, Vector3.FORWARD, data, "bat")
	check(pick.get("actor") == aligned, "aligned target wins over nearer off-axis target")
	Input.action_release("aim")
	check(not gameplay.melee_feedback_active(), "equipping melee alone does not show an overlay")
	Input.action_press("aim")
	check(gameplay.melee_feedback_active(), "deliberate melee aiming exposes directional feedback")
	var feedback: Dictionary = gameplay.melee_feedback()
	check(feedback.in_range and not feedback.blocked, "feedback identifies an unobstructed reachable target")
	check((feedback.point as Vector3).distance_to(aligned.global_position + Vector3.UP) < 0.01, "feedback marks the same target as the contact selector")
	check(is_equal_approx(float(feedback.reach), float(data.melee_range) / 16.0), "feedback uses the effective weapon reach")
	Input.action_release("aim")
	check(not gameplay.melee_feedback_active(), "releasing aim hides idle melee feedback")

	# A fixture fora do eixo não pode oferecer uma alternativa contornando esta parede.
	nearer.collision_layer = 0
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.7, 3.0, 0.35)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = origin + Vector3.FORWARD * 1.3
	await frames(3)
	feedback = gameplay.melee_feedback()
	check(feedback.blocked and not feedback.in_range, "solid wall blocks melee feedback")
	gameplay._melee(origin, Vector3.FORWARD, data, "bat")
	check(aligned.hits == 0 and nearer.hits == 0, "melee does not damage a target through the wall")
	wall.collision_layer = 0
	aligned.collision_layer = 0
	await frames(3)

	Input.action_press("aim")
	gameplay.aim_point = aim
	check(gameplay.fire_at(aim), "first melee click starts an attack")
	var contact: float = float(gameplay._melee_action.contact)
	var window: float = float(gameplay._melee_action.window)
	gameplay._rig_pose.action_age = maxf(0.0, contact - 0.10)
	gameplay.aim_point = origin + Vector3.RIGHT * 4.0
	gameplay._update_aim(0.0)
	check((gameplay._melee_action.direction as Vector3).dot(Vector3.RIGHT) > 0.99, "preparation follows a deliberate aim correction")
	gameplay.aim_point = aim
	gameplay._rig_pose.action_age = contact
	gameplay._update_aim(0.0)
	gameplay.aim_point = origin + Vector3.RIGHT * 4.0
	gameplay._update_aim(0.0)
	check(gameplay._melee_direction().dot(Vector3.FORWARD) > 0.99, "active contact keeps the committed direction")
	check(float(world.player.get_meta("melee_movement_scale")) < 1.0, "commitment applies the weapon movement reduction")
	await frames(2)
	feedback = gameplay.melee_feedback()
	check((feedback.direction as Vector3).dot(Vector3.FORWARD) > 0.99, "feedback follows committed contact rather than the moved cursor")
	gameplay._rig_pose.action_age = contact + window + 0.02
	gameplay._update_aim(0.0)
	check(gameplay._melee_direction().dot(Vector3.RIGHT) > 0.99, "recovery releases the committed direction")
	check(is_equal_approx(float(world.player.get_meta("melee_movement_scale")), 1.0), "recovery restores normal movement")

	# Dois cliques antecipados ainda enfileiram um ataque só; consumi-lo é observável
	# pelo serial real de ataque, sem substituir a função de disparo.
	gameplay.cooldown = 0.10
	var serial: int = gameplay._attack_serial
	check(not gameplay.fire_at(aim) and not gameplay._melee_buffer.is_empty(), "early click queues instead of starting a second attack")
	gameplay.fire_at(aim)
	gameplay._pending_contact.clear()
	gameplay.cooldown = 0.0
	gameplay._update_melee_buffer()
	check(gameplay._attack_serial == serial + 1 and gameplay._melee_buffer.is_empty(), "repeated early clicks consume exactly one buffered attack")
	gameplay._update_melee_buffer()
	check(gameplay._attack_serial == serial + 1, "empty buffer cannot replay its attack")

	gameplay.cooldown = 0.10
	gameplay.fire_at(aim)
	check(not gameplay._melee_buffer.is_empty(), "garage scenario starts with an actual queued click")
	state.set_location("harbor", "maciota")
	gameplay._update_aim(0.0)
	check(gameplay._melee_buffer.is_empty() and gameplay._pending_contact.is_empty(), "garage cancels queued and pending melee contacts")
	check(not gameplay.melee_feedback_active() and not gameplay.fire_at(aim), "garage blocks melee feedback and attacks")
	check(state.owns_weapon("bat"), "garage cancellation preserves inventory")
	state.set_location("harbor", "")
	state.equip_weapon("bat")
	gameplay.cooldown = 0.10
	gameplay.fire_at(aim)
	check(not gameplay._melee_buffer.is_empty(), "pause scenario starts with an actual queued click")
	paused = true
	await process_frame
	check(gameplay._melee_buffer.is_empty(), "tree pause discards the queued click")
	check(not gameplay.melee_feedback_active(), "pause hides melee feedback")
	paused = false
	serial = gameplay._attack_serial
	gameplay.cooldown = 0.0
	gameplay._update_melee_buffer()
	check(gameplay._attack_serial == serial, "unpausing cannot execute the discarded click")
	Input.action_release("aim")
	gameplay._clear_melee_action()
	print("MELEE_CONTROL failures=", failures)
	quit(0 if failures.is_empty() else 1)
