extends "res://tests/measure/measure_katana_session.gd"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene = world
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	var session = world.session
	var field = session.field_inventory
	var economy = session.state.economy
	check(economy.grid_snapshot().bag == "","Dante começa sem mochila")
	check(not session.personal_car.award_first_backpack(),"sem recompensa antes da missão")
	session.show_inventory(); await frames(3)
	check(field.ui.visible and field.ui.find_child("ToggleTrunk",true,false) == null,"TAB abre inventário sem Monaliza")
	check(field.ui.boards.size() == 1 and field.ui.boards[0].container_id == "pockets","sem mochila só há bolsos")
	field.close()
	check(session.state.campaign.begin("primeiro_giro"),"primeira missão começa")
	check(session.mission_world._event("bank_receipt_received","helena"),"retirada do comprovante")
	check(session.mission_world._event("harbor_parcel_collected","harbor_parcel"),"retirada da peça")
	check(economy.grid_snapshot().bag == "","etapas intermediárias não entregam mochila")
	check(await session.enter_place("maciota",false,"maciota"),"retorno à garagem real")
	check(session.mission_world._event("maciota_delivery_received","maciota"),"entrega final aceita")
	check(economy.grid_snapshot().bag == "backpack","Maciota entrega mochila sem abrir porta-malas")
	check(is_instance_valid(field.carried) and field.carried.kind == "backpack" and is_instance_valid(field.carried_mount),"mochila equipada no osso das costas imediatamente")
	check(not session.personal_car.award_first_backpack(),"recompensa não se repete")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.state.snapshot()))
	var restored = preload("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(saved) and restored.economy.grid_snapshot().bag == "backpack","mochila e missão persistem juntas")
	check(not session.state.weapons_allowed() and not session.state.equip_weapon("pistol"),"garagem continua sem armas")
	var original: Dictionary = economy.grid_snapshot()
	# Older completed saves receive the missing award, retaining their contents.
	var legacy: Dictionary = original.duplicate(true)
	legacy.bag = ""; legacy.claimed.erase(session.personal_car.BACKPACK_CLAIM)
	economy._data.grid_inventory = legacy
	check(session.personal_car.award_first_backpack() and economy.grid_snapshot().bag == "backpack","save antigo de missão completa recebe mochila")
	var uid: int = economy.grid_drop_bag("harbor","maciota",Vector3.ZERO)
	check(uid > 0 and not session.personal_car.award_first_backpack() and economy.grid_snapshot().bag == "","mochila solta não duplica recompensa")
	economy._data.grid_inventory = original
	for language in ["pt","en"]:
		var lines: Array = preload("res://systems/campaign/OriginalDialogue.gd").new().lines("primeiro_giro_finish",language)
		check(lines.any(func(row): return ("mochila" if language == "pt" else "backpack") in row.message),"diálogo entrega mochila em "+language)
	world.queue_free(); await process_frame
	print("FIRST_MISSION_BACKPACK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
