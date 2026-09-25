extends SceneTree
## Dano e granada seguem o contato visível, com cancelamento real de combate.
var world
var gameplay
var player
var victim
var failures: Array[String] = []
const POSE = preload("res://gameplay/WeaponRigPose.gd")
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("CONTACT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func grenades() -> Array:
	return gameplay.get_children().filter(func(node): return node.get_script() == gameplay.PROJECTILE and node.grenade)
func prepare(id: String) -> void:
	gameplay.cooldown = 0.0
	gameplay.reload_timer = 0.0
	gameplay.state.equip_weapon(id)
	await frames(25)
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(90).timeout.connect(func(): quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for tick in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main pronto")
	if not failures.is_empty(): quit(1); return
	gameplay = world.gameplay
	player = world.player
	player.controlled_automatically = true
	player.automatic_direction = Vector3.ZERO
	gameplay.health = 1000000
	gameplay.state.economy.activate_arsenal_cheat()
	var direction := Vector3.FORWARD
	for candidate in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, player.global_position + Vector3.UP + candidate * 3.0, 1)
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): direction = candidate; break
	var controls = root.get_node("GameInput")
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0; down.y = 0
	controls.touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))
	Input.action_press("aim")
	victim = load("res://scripts/Actor.gd").new()
	victim.health = 1000000
	victim.controlled_automatically = true
	world.add_child(victim)
	victim.teleport(player.global_position + direction * 1.2)
	victim.set_physics_process(false)
	await frames(30)
	for id in POSE.MELEE_CONTACT:
		await prepare(id)
		var before: float = victim.health
		check(gameplay.fire_at(victim.global_position), id + " aceita golpe")
		check(victim.health == before, id + " não causa dano ao apertar")
		await frames(3)
		check(victim.health == before, id + " antecipação não causa dano")
		for tick in 35:
			await physics_frame
			if victim.health < before: break
		var age: float = gameplay._rig_pose.action_age
		check(is_equal_approx(before - victim.health, float(gameplay.weapon_data(id).damage)), id + " causa exatamente um impacto")
		check(age >= float(POSE.MELEE_CONTACT[id]) - 0.018 and age <= float(POSE.MELEE_CONTACT[id]) + 0.05, "%s contato no tempo da pose: %.3f" % [id, age])
		await frames(25)
		check(is_equal_approx(before - victim.health, float(gameplay.weapon_data(id).damage)), id + " recuperação não repete dano")
	await prepare("axe")
	var hp: float = victim.health
	gameplay.fire_at(victim.global_position)
	gameplay.state.equip_weapon("pistol")
	await frames(30)
	check(victim.health == hp and gameplay._pending_contact.is_empty(), "troca cancela golpe pendente")
	await prepare("fists")
	gameplay.fire_at(victim.global_position)
	gameplay.health = 0
	await frames(20)
	check(victim.health == hp and gameplay._pending_contact.is_empty(), "morte cancela golpe pendente")
	gameplay.health = 1000000
	await prepare("grenade")
	var ammo: int = gameplay.state.get_ammo("grenade").magazine
	var count := grenades().size()
	check(gameplay.fire_at(player.global_position + direction * 8), "granada aceita arremesso")
	check(grenades().size() == count and gameplay.state.get_ammo("grenade").magazine == ammo, "granada permanece na mão durante preparação")
	await frames(8)
	check(grenades().size() == count, "não duplica granada antes da saída da mão")
	await frames(7)
	check(grenades().size() == count + 1 and gameplay.state.get_ammo("grenade").magazine == ammo - 1, "soltura cria uma granada e consome uma munição")
	check(not gameplay.gun.visible, "modelo da mão desaparece na soltura")
	for shot in grenades(): shot.queue_free()
	await prepare("grenade")
	ammo = gameplay.state.get_ammo("grenade").magazine
	gameplay.fire_at(player.global_position + direction * 8)
	gameplay.state.equip_weapon("pistol")
	await frames(20)
	check(grenades().is_empty() and gameplay.state.get_ammo("grenade").magazine == ammo, "troca cancela arremesso sem perder munição")
	Input.action_release("aim")
	controls.touch_aim = Vector2.ZERO
	print("DANTE_COMBAT_TIMING failures=", failures)
	quit(0 if failures.is_empty() else 1)
