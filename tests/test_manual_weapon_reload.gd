extends SceneTree

var failures: Array[String] = []

class ReloadHUD extends Node:
	var ammo: Dictionary = {}
	func set_money(_value): pass
	func update_health(_value): pass
	func set_armor(_value, _maximum): pass
	func set_weapon_info(_id, value): ammo = value.duplicate()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)

func press_r(echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.physical_keycode = KEY_R
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var hud := ReloadHUD.new()
	hud.add_to_group("hud")
	world.add_child(hud)
	var player = preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.active_weapon_id = "pistol"
	player.weapon_ammo.pistol = {"clip": 5, "reserve": 20}
	press_r()
	check(player.weapon_ammo.pistol == {"clip": 12, "reserve": 13}, "R completa o carregador usando a reserva")
	check(hud.ammo == player.weapon_ammo.pistol, "HUD atualiza assim que recarrega")
	press_r()
	check(player.weapon_ammo.pistol == {"clip": 12, "reserve": 13}, "Carregador cheio preserva a reserva")
	player.weapon_ammo.pistol = {"clip": 0, "reserve": 3}
	press_r()
	check(player.weapon_ammo.pistol == {"clip": 3, "reserve": 0}, "Reserva parcial recarrega apenas as balas disponíveis")
	press_r()
	check(player.weapon_ammo.pistol == {"clip": 3, "reserve": 0}, "Sem reserva não cria munição")
	player.weapon_ammo.pistol = {"clip": 5, "reserve": 20}
	press_r(true)
	check(player.weapon_ammo.pistol.clip == 5, "Repetição automática da tecla é ignorada")
	for property in ["is_control_disabled", "is_in_dialogue", "is_dead", "is_arrested", "is_recovering"]:
		player.set(property, true)
		press_r()
		check(player.weapon_ammo.pistol.clip == 5, "Recarga bloqueada: " + property)
		player.set(property, false)
	player.hide()
	press_r()
	check(player.weapon_ammo.pistol.clip == 5, "Jogador oculto no veículo não recarrega")
	player.show()
	var store := Node.new()
	store.add_to_group("weapon_store_open")
	world.add_child(store)
	press_r()
	check(player.weapon_ammo.pistol.clip == 5, "Loja aberta bloqueia recarga")
	store.free()
	player.active_weapon_id = "fists"
	press_r()
	check(player.weapon_ammo.fists == {"clip": -1, "reserve": -1}, "Punhos não usam munição")
	world.queue_free()
	await process_frame
	print("Recarga manual: %d falhas" % failures.size())
	quit(0 if failures.is_empty() else 1)
