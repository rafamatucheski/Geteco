extends "res://tests/test_combat_flow.gd"
## Reuses input helpers only; Main, session, gameplay and residents are real.
## Mandatory --no-save. Runner must isolate APPDATA. Does not benchmark FPS.
const PROTECTION = preload("res://gameplay/DamageProtection.gd")
const STORE = preload("res://runtime/SaveStore.gd")
var fired := 0
var exit_diagnostic: Dictionary = {}

func _inventory() -> Dictionary:
	var value: Dictionary = state.economy.snapshot()
	# Automatic holstering is the expected equipment change, not inventory loss.
	value.erase("equipped_weapon")
	return value

func _weapon_event(_id: String, _origin: Vector3) -> void:
	fired += 1

func _finish_safety() -> void:
	Input.action_release("fire")
	Input.action_release("aim")
	var report := {"checks": checks, "failures": failures, "exit_diagnostic": exit_diagnostic, "limits": "Maciota real; entrada/saída, APIs e Input, restauração de GameState via SaveStore temporário. Não recarrega Main; não simula atropelamento físico, fogo externo persistente ou todos os eventos de missão. Explosão externa dirigida e dano direto não certificam todas as fontes."}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			var file := FileAccess.open(argument.trim_prefix("--evidence-dir=").path_join("maciota-transition-safety.json"), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("MACIOTA_TRANSITION_SAFETY ", JSON.stringify(report))
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(120.0).timeout.connect(func(): Input.action_release("fire"); push_error("MACIOTA SAFETY TIMEOUT"); quit(2))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main real pronta")
	if world.session == null or not world.session.ready_for_play: _finish_safety(); return
	check(world.production.no_save, "save pessoal desabilitado")
	if not world.production.no_save: _finish_safety(); return
	gameplay = world.gameplay
	state = world.session.state
	player = world.player
	gameplay.weapon_fired.connect(_weapon_event)
	for id in ["pistol", "knife", "grenade"]:
		if not state.owns_weapon(id): check(state.grant_weapon(id), "fixture adquire " + id)
	# Grants qualify for armed_up. Commit that legitimate reward before the
	# baseline; leave_place also refreshes achievements through save_game.
	world.session.activities.refresh_achievements()
	check(state.equip_weapon("pistol"), "pistola equipada antes da entrada")
	var inventory_before := _inventory()
	var saved: Dictionary = state.snapshot()
	var entered: bool = await world.session.enter_place("maciota", false)
	check(entered and state.place_id == "maciota", "entrada produtiva em Maciota")
	if not entered or state.place_id != "maciota": _finish_safety(); return
	await frames(5)
	check(not player.input_locked and not world.driving.occupied and gameplay.health > 0, "recusa de armas não depende de jogador travado, ocupado ou morto")
	check(state.equipped_weapon == "fists" and not state.weapons_allowed(), "entrada guarda arma e ativa área sem armas")
	check(_inventory() == inventory_before, "entrada preserva inventário completo, munição e carteira")
	check(not state.equip_weapon("pistol") and not gameplay.equip_slot("pistol") and not gameplay.cycle_weapon(1), "saque e troca recusados por APIs produtivas")
	check(not state.equip_weapon("knife") and not state.equip_weapon("grenade"), "arma branca e granada não podem ser sacadas")
	await digit(2)
	check(state.equipped_weapon == "fists", "tecla de arma não saca dentro da garagem")
	var serial: int = gameplay._attack_serial
	check(not gameplay.attack_allowed() and not gameplay.fire_at(player.global_position+Vector3.FORWARD), "ataque corpo a corpo recusado pelo fluxo real")
	Input.action_press("fire")
	await frames(12)
	Input.action_release("fire")
	await frames(2)
	check(gameplay._attack_serial == serial and fired == 0 and gameplay._pending_contact.is_empty(), "ação de disparo não inicia tiro nem golpe")
	check(not state.consume_ammo("pistol") and not state.reload_weapon("pistol") and not gameplay.reload_weapon(), "consumo e recarga bloqueados")
	var health_before: float = gameplay.health
	var fires_before: int = gameplay.emergency.fires.size()
	gameplay.explode(player.global_position, 4.0, 90.0, player)
	check(gameplay.health == health_before and gameplay.emergency.fires.size() == fires_before, "explosivo do jogador não causa dano nem cria fogo")
	check(gameplay.emergency.ignite(player.global_position, player, 1.0) == null, "ignição produtiva recusada na garagem")
	check(not gameplay.activate_arsenal_cheat(), "atalho de arsenal não contorna restrição")
	check(_inventory() == inventory_before, "tentativas bloqueadas preservam inventário e munição")
	# A non-player source exercises the explosion path beyond its player guard.
	var external_source := Node3D.new()
	world.add_child(external_source)
	var residents: Array = [world.maciota_place.maciota, world.maciota_place.mechanic]
	for resident in residents:
		var body: StaticBody3D = resident.get_node("ResidentBody")
		check(PROTECTION.is_protected(resident) and PROTECTION.is_protected(body), resident.name+" e corpo herdam proteção")
		check(not resident.has_method("receive_damage") and not body.has_method("receive_damage"), resident.name+" permanece sem rotina de dano")
		gameplay._damage(resident, 1000.0, player)
		gameplay._damage(body, 1000.0, external_source)
		gameplay._damage(body, 1000.0, external_source, true)
		gameplay.explode(body.global_position+Vector3.UP*.85, 2.0, 1000.0, external_source, false)
		await frames(3)
		check(is_instance_valid(resident) and not resident.is_queued_for_deletion() and is_instance_valid(body) and body.collision_layer == 2 and PROTECTION.is_protected(body), resident.name+" conserva corpo protegido após dano direto, contínuo e explosão externa")
	external_source.queue_free()
	# Synthetic armed interior record, as in the existing combat regression.
	# Real SaveStore validates/loads it; its only path is in the isolated user://.
	saved.place_id = "maciota"
	var store := STORE.new()
	store.path = "user://tests/maciota-transition-safety/armed-interior.json"
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(store.path.get_base_dir()))
	check(directory_error == OK, "diretório de save temporário isolado criado")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	check(file != null, "arquivo de fixture temporário aberto")
	if file == null: _finish_safety(); return
	file.store_string(JSON.stringify(saved))
	file.close()
	var loaded: Dictionary = store.load_into(state)
	check(loaded.get("ok", false) and state.place_id == "maciota" and state.equipped_weapon == "fists", "SaveStore restaura na garagem guardando pistola do registro")
	check(_inventory() == inventory_before and not gameplay.attack_allowed(), "restauração preserva inventário e bloqueio")
	var left: bool = world.session.leave_place()
	exit_diagnostic["inventory_immediate"] = _inventory()
	await frames(5)
	check(left and state.place_id.is_empty() and not player.input_locked, "saída produtiva devolve jogador ao exterior")
	exit_diagnostic.merge({"inventory_before": inventory_before, "inventory_after": _inventory(), "weapons_allowed": state.weapons_allowed(), "attack_allowed": gameplay.attack_allowed(), "state_can_attack": state.can_attack(), "gameplay_enabled": gameplay.enabled, "health": gameplay.health, "paused": paused, "surrendering": gameplay.police_surrendering(), "equipped": state.equipped_weapon, "occupied": world.driving.occupied, "input_locked": player.input_locked})
	print("MACIOTA_EXIT_DIAGNOSTIC ", JSON.stringify(exit_diagnostic))
	check(_inventory() == inventory_before, "saída preserva inventário completo")
	check(state.weapons_allowed(), "saída libera regra de armas")
	check(gameplay.attack_allowed(), "saída libera ataque produtivo")
	check(state.equip_weapon("pistol"), "pistola pode ser sacada no exterior")
	var ammo_before: int = int(state.get_ammo("pistol").magazine)
	var fired_before := fired
	check(gameplay.fire_at(player.global_position+Vector3.FORWARD*8.0), "disparo produtivo liberado após saída")
	check(fired == fired_before+1 and int(state.get_ammo("pistol").magazine) == ammo_before-1, "disparo exterior emite evento e consome uma munição")
	_finish_safety()
