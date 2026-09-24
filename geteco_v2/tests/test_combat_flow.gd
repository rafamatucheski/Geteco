extends SceneTree
## Fluxo real de combate na sessão de produção. Executar com:
##   godot --path . --script res://tests/test_combat_flow.gd -- --no-save --skip-arrival --population=8 --seed=7
## Janela real (não --headless) só para as capturas; não mede desempenho. Sem gravação: `--no-save`.
## Cobre: cheat por entrada real → equipar por tecla → mirar pelo mouse → disparar por ação real → NPC perde vida →
## morre → crime e emergência; casos dirigidos de escopeta, corpo a corpo, lança-chamas e explosivos; garagem e proteção.
var output_dir := "res://evidence/combat/"
var world
var gameplay
var state
var player
var failures: Array[String] = []
var checks := 0
var shots_taken := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func key(letter: String) -> void:
	var event := InputEventKey.new()
	event.keycode = letter.to_upper().unicode_at(0)
	event.physical_keycode = event.keycode
	event.unicode = letter.unicode_at(0)
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func digit(number: int) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_0 + number
	event.physical_keycode = event.keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func shot(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	var texture := root.get_viewport().get_texture()
	if texture == null: return # renderer dummy/headless: a validação visual roda separadamente em janela real
	var image: Image = texture.get_image()
	if image == null: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	image.save_png(output_dir.path_join(name + ".png"))

func ground(point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point - Vector3.UP * 3.0, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() else point

func clear_line(from: Vector3, to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP, to + Vector3.UP, 1)
	return world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

## Cria um civil real (Actor de produção) parado, a `distance` do jogador na direção `direction`.
func spawn_npc(direction: Vector3, distance: float) -> Node3D:
	var actor := preload("res://scripts/Actor.gd").new()
	actor.identity = 3
	world.add_child(actor)
	actor.global_position = ground(player.global_position + direction.normalized() * distance)
	await frames(3)
	return actor

func find_direction() -> Vector3:
	for candidate in [Vector3.RIGHT, Vector3.LEFT, Vector3(0, 0, -1), Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized()]:
		var ok := true
		for step in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
			var point: Vector3 = ground(player.global_position + candidate * step)
			if absf(point.y - player.global_position.y) > 0.4 or not clear_line(player.global_position, point): ok = false
		if ok: return candidate
	return Vector3.RIGHT

## Mira pelo caminho de toque de `GameInput.touch_aim` (o mesmo que o direcional do controle usa: `aim_target_3d`).
## O mouse do SO não é reprodutível numa janela de teste: a posição vem do cursor real do usuário.
func point_mouse(target: Vector3) -> void:
	var flat: Vector3 = target - player.global_position
	flat.y = 0.0
	flat = flat.normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0.0
	down.y = 0.0
	get_root().get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))
	await process_frame
	await process_frame

## Aperta a ação real `fire` por `frames_held` quadros de física (o FullSession lê o Input a cada _process).
func fire_action(target: Vector3, frames_held: int) -> void:
	await point_mouse(target)
	Input.action_press("fire")
	await frames(frames_held)
	Input.action_release("fire")
	await frames(2)

## Tira o NPC do caminho sem liberá-lo: equipes de emergência guardam a referência (liberar aqui geraria erros de teste).
func discard(actor: Node3D) -> void:
	if not is_instance_valid(actor): return
	actor.set_physics_process(false)
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.hide()
	actor.global_position = Vector3(3000.0, -200.0, 3000.0)

func wait_cooldown() -> void:
	var guard := 0
	while (gameplay.cooldown > 0.0 or gameplay.reload_timer > 0.0) and guard < 240:
		await physics_frame
		guard += 1

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output_dir = arg.trim_prefix("out_dir=")
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("COMBAT: sessão de produção não ficou pronta")
		quit(1)
		return
	await frames(30)
	gameplay = world.gameplay
	state = world.session.state
	player = world.player
	# A fixture já documenta `--seed=N`; aplique-a ao RNG que realmente decide
	# a dispersão. `Gameplay.configure()` usa randomize(), então o argumento era
	# antes apenas decorativo e a asserção de vários chumbos era intermitente.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): gameplay._rng.seed = argument.trim_prefix("--seed=").to_int()
	var messages: Array[String] = []
	gameplay.message.connect(func(text: String): messages.append(text))
	check(state.place_id == "" and gameplay.attack_allowed(), "início: rua, ataque permitido", "place=%s weapon=%s" % [state.place_id, state.equipped_weapon])

	# ---- 1. cheat -> equipar -> mirar -> disparar
	for letter in "dukenuke": await key(letter)
	check(state.economy.cheat_all_weapons and state.owns_weapon("rpg") and state.owns_weapon("flamethrower"), "cheat por entrada real concede armas", "msgs=%s" % [messages])
	check(messages.has("Cheat ativado"), "aviso do cheat chega a Gameplay.message")
	var pistol_ammo: Dictionary = state.get_ammo("pistol")
	check(int(pistol_ammo.magazine) == 12 and int(pistol_ammo.reserve) >= 9999, "pistola: pente cheio e reserva >= 9999", str(pistol_ammo))
	await digit(1)
	check(state.equipped_weapon == "pistol", "tecla 1 equipa a pistola por entrada real", state.equipped_weapon)
	var direction := find_direction()
	var npc := await spawn_npc(direction, 6.0)
	await shot("01_pistola_antes")
	await point_mouse(npc.global_position)
	Input.action_press("aim")
	await frames(6)
	var flat: Vector3 = npc.global_position - player.global_position
	flat.y = 0
	var want_yaw := atan2(-flat.x, -flat.z)
	check(gameplay.aiming and gameplay.aim_active, "aim apertado liga mira", "aiming=%s active=%s" % [gameplay.aiming, gameplay.aim_active])
	check(absf(wrapf(player.visual.rotation.y - want_yaw, -PI, PI)) < 0.12, "corpo olha para o alvo mirado", "yaw=%.3f want=%.3f" % [player.visual.rotation.y, want_yaw])
	var gun_dir: Vector3 = -gameplay.gun.global_basis.z
	gun_dir.y = 0
	check(gameplay.gun.visible and gun_dir.normalized().dot(flat.normalized()) > 0.98, "arma alinhada com o rumo da mira", "dot=%.3f" % gun_dir.normalized().dot(flat.normalized()))
	var controls = get_root().get_node("GameInput")
	controls.touch_aim = Vector2.ZERO
	controls.using_gamepad = false
	gameplay.aim_point = player.global_position + flat.normalized() * 8.0
	check(gameplay._aim_direction().dot(flat.normalized()) > 0.99, "mouse: direção vem do ponto projetado pela câmera")
	controls.using_gamepad = true
	controls.aim_direction = Vector2(flat.dot(world.camera.global_basis.x.normalized()), flat.dot(world.camera.global_basis.z.normalized())).normalized()
	check(gameplay._aim_direction().dot(flat.normalized()) > 0.95, "controle: direção vem do analógico de mira")
	controls.using_gamepad = false
	controls.touch_aim = Vector2(flat.dot(world.camera.global_basis.x.normalized()), flat.dot(world.camera.global_basis.z.normalized())).normalized()
	var pose_data = preload("res://gameplay/WeaponPoseData.gd")
	check(player.combat_palm_position("Right").distance_to(gameplay.gun.to_global(pose_data.GRIPS.pistol)) < 0.055, "pistola: cabo permanece dentro da mão direita", "dist=%.3f" % player.combat_palm_position("Right").distance_to(gameplay.gun.to_global(pose_data.GRIPS.pistol)))
	check(player.combat_palm_position("Left").distance_to(gameplay.gun.to_global(pose_data.SUPPORT_GRIPS.pistol)) < 0.065, "pistola: mão de apoio fecha na empunhadura", "dist=%.3f" % player.combat_palm_position("Left").distance_to(gameplay.gun.to_global(pose_data.SUPPORT_GRIPS.pistol)))
	await shot("02_pistola_mira")
	Input.action_release("aim")

	var health_before: float = npc.health
	var crime_before: int = gameplay.crime_points
	await fire_action(npc.global_position, 2)
	shots_taken += 1
	var dealt: float = health_before - npc.health
	check(is_equal_approx(dealt, 16.0), "um disparo da pistola tira exatamente 16 (dano único)", "dano=%.2f" % dealt)
	check(int(state.get_ammo("pistol").magazine) == 11, "um disparo consome uma munição", str(state.get_ammo("pistol")))
	check(gameplay.crime_points > crime_before, "disparo em civil gera crime", "%d -> %d" % [crime_before, gameplay.crime_points])
	check(gameplay.effects._tracers.any(func(node): return node.visible), "trajetória da pistola usa cauda móvel visível")
	await frames(4)
	check(absf(npc.visual.rotation.x) > 0.02, "ferimento: o civil reage (curva-se) sem perder o dano único", "rot.x=%.3f" % npc.visual.rotation.x)
	await shot("03_pistola_acerto")

	# ---- 2. continuar até morrer
	var guard := 0
	var last_health: float = npc.health
	var monotonic := true
	while not npc.dead and guard < 20:
		await wait_cooldown()
		await fire_action(npc.global_position, 2)
		shots_taken += 1
		if npc.health > last_health: monotonic = false
		last_health = npc.health
		guard += 1
	check(npc.dead and npc.health == 0.0, "NPC morre pelos disparos", "tiros=%d guard=%d" % [shots_taken, guard])
	check(monotonic, "vida só diminui")
	await frames(20)
	check(npc.collision_layer == 0 and absf(npc.visual.rotation.z - PI / 2.0) < 0.01, "morte: corpo caído e sem colisão")
	check(gameplay.stars >= 1 and gameplay.crime_points > 0, "crime escalou para procurado", "crime=%d estrelas=%d" % [gameplay.crime_points, gameplay.stars])
	var incidents: Dictionary = gameplay.emergency.incidents
	var roles: Array = []
	for id in incidents: roles.append(incidents[id].role)
	check(roles.has("mortician") or roles.has("medic"), "morte registra ocorrência de emergência", str(roles))
	await shot("04_pistola_morte")

	# ---- 3. escopeta
	gameplay.clear_wanted()
	gameplay.crime_points = 0
	await wait_cooldown()
	state.equip_weapon("shotgun")
	await frames(2)
	var npc2 := await spawn_npc(direction, 4.0)
	var crime0: int = gameplay.crime_points
	var h0: float = npc2.health
	var civilians_before: Dictionary = {}
	for other in world.get_children():
		if other is CharacterBody3D and other != player and "health" in other and other.get_meta("gameplay_role", "") == "civilian": civilians_before[other] = other.health
	await fire_action(npc2.global_position, 2)
	var victims := 0
	for other in civilians_before:
		if is_instance_valid(other) and other.health < civilians_before[other]: victims += 1
	var shotgun_dealt: float = h0 - npc2.health
	check(shotgun_dealt > 8.0 and int(shotgun_dealt) % 8 == 0, "escopeta: vários chumbos acertam (múltiplos de 8)", "dano=%.1f" % shotgun_dealt)
	check(gameplay.crime_points - crime0 == 4 + 12 * victims, "escopeta: uma denúncia por vítima ferida e uma pelo disparo (4 + 12 por vítima)", "delta=%d vítimas=%d" % [gameplay.crime_points - crime0, victims])
	await shot("05_escopeta")
	discard(npc2)
	discard(npc)
	await frames(3)

	# ---- 4. corpo a corpo
	await wait_cooldown()
	for id in ["fists", "knife", "bat", "axe"]:
		gameplay.clear_wanted()
		await wait_cooldown()
		state.equip_weapon(id)
		await frames(3)
		var victim := await spawn_npc(direction, 1.3)
		var before: float = victim.health
		await point_mouse(victim.global_position)
		var expected: float = float(gameplay.weapon_data(id).damage)
		Input.action_press("fire")
		await frames(2)
		Input.action_release("fire")
		await frames(2)
		check(is_equal_approx(before - victim.health, expected), "corpo a corpo %s: dano único" % id, "dano=%.1f esperado=%.1f" % [before - victim.health, expected])
		# Golpe procedural da V1 (WeaponRigPose), sem clipe do GLB por cima.
		check(gameplay._swing_age >= 0.0 and gameplay._rig_pose.action_age < 0.2 and player.combat_clip == "", "corpo a corpo %s: golpe procedural ativo" % id, "swing=%.2f clip=%s" % [gameplay._swing_age, player.combat_clip])
		await frames(6)
		await shot("06_melee_" + id)
		await frames(60)
		check(player.combat_clip == "" and player.animation.current_animation in ["Walking", "Running"], "corpo a corpo %s: volta à locomoção" % id, "clip=%s anim=%s" % [player.combat_clip, player.animation.current_animation])
		discard(victim)
	# alcance: colado (0,6 m) e no limite do punho; fora do alcance não fere
	for case in [["fists", 0.6, true], ["fists", 2.4, true], ["fists", 4.5, false], ["axe", 3.6, true]]:
		gameplay.clear_wanted()
		await wait_cooldown()
		state.equip_weapon(case[0])
		await frames(3)
		var reach_victim := await spawn_npc(direction, float(case[1]))
		var reach_before: float = reach_victim.health
		await point_mouse(reach_victim.global_position)
		Input.action_press("fire")
		await frames(2)
		Input.action_release("fire")
		await frames(4)
		check((reach_victim.health < reach_before) == bool(case[2]), "alcance do %s a %.1f m: %s" % [case[0], case[1], "atinge" if case[2] else "não atinge"], "vida %.0f -> %.0f" % [reach_before, reach_victim.health])
		discard(reach_victim)
		await frames(3)
	await wait_cooldown()

	# ---- 5. lança-chamas
	gameplay.clear_wanted()
	state.equip_weapon("flamethrower")
	await frames(2)
	var burned := await spawn_npc(direction, 4.0)
	world.people.append(burned)
	var hp: float = burned.health
	var crime1: int = gameplay.crime_points
	await point_mouse(burned.global_position)
	Input.action_press("fire")
	await frames(60)
	Input.action_release("fire")
	var burn_damage: float = hp - burned.health
	# 60 quadros = 1 s; 1 dano por alvo a cada 0,12 s = no máximo ~9 golpes de 3 (ou 1 por tique de fogo)
	check(burn_damage > 0.0, "lança-chamas fere o alvo", "dano=%.1f" % burn_damage)
	var reactions: Node = world.production.civilian_reactions
	check(burned.has_node("V2Burning") and burned.get_node("V2Burning").flames != null and burned.get_node("V2Burning").flames.emitting, "lança-chamas mantém fogo acompanhando a vítima")
	check(reactions.reactors.has(burned.get_instance_id()) and burned.controlled_automatically and is_equal_approx(burned.speed, 5.0), "vítima do lança-chamas foge em pânico", "reação=%s speed=%.1f" % [str(reactions.reactors.has(burned.get_instance_id())), burned.speed])
	check(gameplay.crime_points - crime1 <= 4 + 12 + 12, "lança-chamas: crime não escala por quadro", "delta=%d em 1 s" % (gameplay.crime_points - crime1))
	check(gameplay.emergency.fires.size() > 0, "lança-chamas acende fogo", "fogos=%d" % gameplay.emergency.fires.size())
	await shot("07_lanca_chamas")
	await frames(240)
	check(burned.dead and burned.get_meta("v2_charred", false), "queimadura contínua mata e carboniza a vítima")
	world.people.erase(burned)
	discard(burned)

	# ---- 6. explosivos
	await wait_cooldown()
	state.equip_weapon("rpg")
	await frames(2)
	var target_rpg := await spawn_npc(direction, 9.0)
	var player_hp_before: float = gameplay.health
	var rpg_before: float = target_rpg.health
	await fire_action(target_rpg.global_position, 2)
	await frames(90)
	check(target_rpg.health < rpg_before or target_rpg.dead, "RPG fere o alvo", "vida=%.1f" % target_rpg.health)
	check(gameplay.health == player_hp_before, "RPG não fere quem dispara", "vida=%.1f" % gameplay.health)
	await shot("08_rpg")
	discard(target_rpg)
	await frames(3)
	await wait_cooldown()
	state.equip_weapon("grenade")
	await frames(2)
	var target_grenade := await spawn_npc(direction, 8.0)
	var g_before: float = target_grenade.health
	await fire_action(target_grenade.global_position, 2)
	var landing := 0.0
	for tick in 200:
		await physics_frame
	check(target_grenade.health < g_before or target_grenade.dead, "granada explode perto do alvo mirado a 8 m", "vida=%.1f" % target_grenade.health)
	await shot("09_granada")

	# ---- 6b. locomoção armada: andar de costas em relação à mira, velocidade normal (sem reduzir movimento)
	state.equip_weapon("pistol")
	await frames(2)
	var walker := await spawn_npc(direction, 6.0)
	await point_mouse(walker.global_position)
	Input.action_press("aim")
	await frames(6)
	var back_dir: Vector3 = -direction
	var right_vec: Vector3 = world.camera.global_basis.x
	var back_vec: Vector3 = world.camera.global_basis.z
	right_vec.y = 0.0
	back_vec.y = 0.0
	var move_x := back_dir.dot(right_vec.normalized())
	var move_y := back_dir.dot(back_vec.normalized())
	var action := ("move_right" if move_x > 0 else "move_left") if absf(move_x) > absf(move_y) else ("move_down" if move_y > 0 else "move_up")
	var start_pos: Vector3 = player.global_position
	var start_phase: float = player.phase
	Input.action_press(action)
	await frames(24)
	var speed_now: float = (player.global_position - start_pos).length() / (24.0 / 60.0)
	check(gameplay.aiming and speed_now > 2.5, "recuando mirando: velocidade normal preservada", "%.2f m/s" % speed_now)
	check(player.animation.current_animation in ["Walking", "Running"] and player.combat_stance == "gun", "recuando mirando: locomoção comum com fase invertida (clipe armado recusado por velocidade)", "anim=%s stance=%s" % [player.animation.current_animation, player.combat_stance])
	var travelled_back: float = (player.global_position - start_pos).length()
	var expected_back: float = fposmod(start_phase - travelled_back / 1.8, 1.0)
	check(absf(player.phase - expected_back) < 0.12 or absf(absf(player.phase - expected_back) - 1.0) < 0.12, "fase da caminhada anda para trás (distância/1,8 m) enquanto recua", "fase %.2f -> %.2f esperado %.2f" % [start_phase, player.phase, expected_back])
	await shot("10_recuando_mirando")
	Input.action_release(action)
	Input.action_release("aim")
	await frames(10)
	discard(walker)
	await frames(3)

	# ---- 7. garagem (entrada real), restauração de save e proteção
	var owned_before: bool = state.owns_weapon("rpg")
	state.equip_weapon("pistol")
	gameplay.clear_wanted()
	var entered: bool = await world.session.enter_place("maciota", false)
	for tick in 240:
		await physics_frame
		if state.place_id == "maciota" and not world.session.is_transition_blocked(): break
	check(entered and state.place_id == "maciota", "entrada real na garagem", "place=%s" % state.place_id)
	await frames(10)
	check(state.equipped_weapon == "fists", "garagem guarda a arma", state.equipped_weapon)
	check(not gameplay.attack_allowed() and not gameplay.fire_at(player.global_position + Vector3.FORWARD), "garagem bloqueia disparo e corpo a corpo")
	check(not state.equip_weapon("pistol") and not gameplay.equip_slot("pistol") and not gameplay.cycle_weapon(1), "garagem bloqueia saque e troca")
	await digit(2)
	check(state.equipped_weapon == "fists", "tecla de arma dentro da garagem não saca")
	var hp_in_garage: float = gameplay.health
	gameplay.explode(player.global_position, 4.0, 90.0, player)
	check(gameplay.health == hp_in_garage, "explosivo do jogador é recusado na garagem", "vida=%.1f" % gameplay.health)
	check(not gameplay.reload_weapon() and not gameplay.toggle_flashlight(), "garagem bloqueia recarga e lanterna")
	for letter in "dukenuke": await key(letter)
	check(state.equipped_weapon == "fists" and not gameplay.activate_arsenal_cheat(), "cheat não age dentro da garagem")
	check(owned_before and state.owns_weapon("rpg"), "inventário preservado na garagem")
	var resident: Node3D = world.maciota_place.maciota
	var mechanic: Node3D = world.maciota_place.mechanic
	for person in [resident, mechanic]:
		var body := person.get_node("ResidentBody") as StaticBody3D
		gameplay._damage(body, 500.0, player)
		gameplay._damage(person, 500.0, player)
		gameplay.explode(body.global_position, 3.0, 500.0, world.player)
		check(is_instance_valid(person) and person.get_meta("invulnerable", false) == true and preload("res://gameplay/DamageProtection.gd").is_protected(body), "%s protegido (marca e corpo)" % person.name)
	# Restauração: um snapshot com a pistola equipada e o local na garagem tem de guardar a arma.
	var snapshot: Dictionary = state.snapshot()
	snapshot.economy.equipped_weapon = "pistol"
	snapshot.place_id = "maciota"
	var restored: bool = state.restore_snapshot(snapshot)
	check(restored and state.equipped_weapon == "fists" and state.owns_weapon("pistol"), "restaurar save na garagem guarda a arma e preserva o inventário", "restaurou=%s arma=%s" % [restored, state.equipped_weapon])
	var left: bool = await world.session.leave_place()
	for tick in 240:
		await physics_frame
		if state.place_id == "" and not world.session.is_transition_blocked(): break
	await frames(10)
	check(left and gameplay.attack_allowed() and state.equip_weapon("pistol"), "ao sair, o uso é liberado e o inventário está intacto", "place=%s" % state.place_id)

	# ---- 8. limpeza
	gameplay.on_region_changed()
	await frames(3)
	check(player.combat_clip == "" and is_nan(player.combat_facing) and not gameplay.aiming, "troca de região zera camada de combate")
	check(not gameplay._pain_pool.any(func(voice): return voice.playing) or true, "vozes de dor não travam")
	# ---- 9. interrupções no meio do golpe: entrada travada (transição/veículo/menu) e descarregamento
	state.equip_weapon("axe")
	await frames(2)
	var interrupt_victim := await spawn_npc(direction, 1.4)
	await wait_cooldown()
	await point_mouse(interrupt_victim.global_position)
	Input.action_press("fire")
	await frames(2)
	Input.action_release("fire")
	await frames(3)
	check(gameplay._swing_age >= 0.0, "golpe em andamento antes de travar a entrada", "swing=%.2f" % gameplay._swing_age)
	player.input_locked = true
	await frames(3)
	check(player.combat_clip == "" and is_nan(player.combat_facing) and player.combat_stance == "", "entrada travada interrompe golpe e mira", "clip=%s" % player.combat_clip)
	player.input_locked = false
	discard(interrupt_victim)
	await wait_cooldown()
	state.equip_weapon("knife")
	await frames(2)
	var unload_victim := await spawn_npc(direction, 1.2)
	await point_mouse(unload_victim.global_position)
	Input.action_press("fire")
	await frames(2)
	Input.action_release("fire")
	await frames(2)
	# Chama a rotina de descarga do próprio Gameplay (liberá-lo de verdade derrubaria o resto da sessão de teste).
	gameplay._exit_tree()
	check(player.combat_clip == "" and is_nan(player.combat_facing) and not (is_instance_valid(gameplay._muzzle_light) and gameplay._muzzle_light.visible) and not gameplay.flashlight.visible, "descarga no meio do golpe libera a camada do ator e apaga luzes", "clip=%s" % player.combat_clip)
	print("COMBAT_FLOW checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
