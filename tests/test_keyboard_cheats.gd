extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func type_code(value: String, echo := false) -> void:
	for letter in value:
		var event := InputEventKey.new()
		event.keycode = letter.to_upper().unicode_at(0)
		event.unicode = letter.unicode_at(0)
		event.pressed = true
		event.echo = echo
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.personal_loadout_enabled = true
	for key in [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_SHIFT, KEY_F1, KEY_ESCAPE, KEY_TAB]:
		for physical_only in [false, true]:
			player._cheat_sequence = "dukenuk"
			var special := InputEventKey.new()
			special.pressed = true
			if physical_only:
				special.physical_keycode = key
			else:
				special.keycode = key
			check(not player._handle_cheat_key(special), "Tecla especial não ativa cheat: %s physical=%s" % [key, physical_only])
			check(player._cheat_sequence.is_empty(), "Tecla especial interrompe sequência")
	type_code("dukenuk")
	check(not player.weapon_inventory.get("rpg", false), "Sequência incompleta não ativa")
	type_code("x")
	type_code("dukenuke", true)
	check(not player.weapon_inventory.get("rpg", false), "Erro e repetição automática não ativam")
	player.is_in_dialogue = true
	type_code("dukenuke")
	player.is_in_dialogue = false
	check(not player.weapon_inventory.get("rpg", false), "Diálogo bloqueia cheat")
	var field := LineEdit.new()
	world.add_child(field)
	field.grab_focus()
	type_code("dukenuke")
	check(not player.weapon_inventory.get("rpg", false), "Campo de texto bloqueia cheat")
	field.release_focus()
	field.queue_free()
	type_code("DUKENUKE")
	for id in WeaponCatalog.ORDER:
		check(player.can_carry_weapon(id), "Arma acessível com loadout restrito: " + id)
		var capacity := int(WeaponCatalog.get_weapon(id).get("magazine_size", -1))
		check(player.weapon_ammo[id].clip == capacity and player.weapon_ammo[id].reserve == (9999 if capacity >= 0 else -1), "Munição correta: " + id)
	check(player.weapon_wheel.notice == "Cheat ativado", "Mensagem de ativação")
	await process_frame
	check(player.weapon_wheel._notice_panel.visible, "Aviso fica visível")
	player.weapon_ammo.pistol.reserve = 1
	type_code("dukenuke")
	check(player.weapon_ammo.pistol.reserve == 9999, "Pode reabastecer repetindo o código")
	player.money = 321
	type_code("dirtybagmone")
	check(player.money == 321, "Sequência de dinheiro incompleta não ativa")
	type_code("y")
	check(player.money == 100321, "dirtybagmoney adiciona exatamente $100.000")
	check(player.weapon_wheel.notice == "Cheat ativado: +$100.000", "Cheat de dinheiro mostra confirmação")
	type_code("DIRTYBAGMONEY")
	check(player.money == 200321, "Cheat de dinheiro pode ser repetido")
	world.queue_free()
	await process_frame
	print("Keyboard cheats: %d failures" % failures)
	quit(0 if failures == 0 else 1)
