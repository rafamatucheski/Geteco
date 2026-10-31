extends RefCounted
## A identidade canônica da captura sobrevive ao armazenamento em grade, bolsas largadas e saves JSON.
## O GridInventory carrega este catálogo; as dependências de transação só carregam quando pedidas.
const RULES := preload("res://activities/fishing/FishingRules.gd")
const PRICE_PER_KG := {"tilapia":12, "piau":14, "pacu":16, "carpa":15, "traira":18, "matrinxa":20, "tambacu":18, "pintado":24, "tucunare":26, "dourado":30, "pirarara":28}

static func make_id(fish: Dictionary) -> String:
	if not fish.get("id") is String or not RULES.valid_catch(fish): return ""
	return "fish:%s:%d" % [fish.id, int(fish.grams)]

static func parse_id(id: String) -> Dictionary:
	if id.length() > 128: return {}
	var parts := id.split(":", true)
	if parts.size() != 3 or parts[0] != "fish" or not parts[2].is_valid_int(): return {}
	var grams := parts[2].to_int()
	if str(grams) != parts[2]: return {}
	var fish := {"id":parts[1], "grams":grams}
	return fish if RULES.valid_catch(fish) else {}

static func spec(id: String) -> Dictionary:
	if id == "cooked_fish": return {"label":"Peixe assado", "description":"Recupera 35 de vida.", "heal":35, "stack":5, "icon":"cooked_fish"}
	var fish := parse_id(id)
	if fish.is_empty(): return {}
	return {"label":"%s · %s" % [RULES.definition(fish.id).name, RULES.kg(fish.grams)], "description":"Vender no Lago Sereno ou cozinhar em casa.", "stack":1, "icon":"fish"}

static func sale_price(id: String) -> int:
	var fish := parse_id(id)
	return 0 if fish.is_empty() else maxi(1, roundi(float(fish.grams) * int(PRICE_PER_KG[fish.id]) / 1000.0))

static func _candidate(snapshot: Dictionary):
	var economy = load("res://systems/economy/Economy.gd").new()
	if not economy.restore_snapshot(snapshot) or not economy.grid_enabled(): return null
	return economy

static func store_candidate(snapshot: Dictionary, fish: Dictionary) -> Dictionary:
	var id := make_id(fish)
	if id.is_empty(): return {}
	var economy = _candidate(snapshot)
	if economy == null or not economy.grant_item(id): return {}
	return economy.snapshot()

static func sale_candidate(snapshot: Dictionary, id: String, receipt: String) -> Dictionary:
	if parse_id(id).is_empty() or not _valid_receipt(receipt, "fishing_sale_"): return {}
	var economy = _candidate(snapshot)
	if economy == null or economy.has_reward_receipt(receipt): return {}
	if not economy.consume_item(id) or not economy.grant_reward(receipt, sale_price(id), "Venda de peixe"): return {}
	return economy.snapshot()

static func cook_candidate(snapshot: Dictionary, id: String, receipt: String) -> Dictionary:
	if parse_id(id).is_empty() or not _valid_receipt(receipt, "fishing_cook_"): return {}
	var economy = _candidate(snapshot)
	if economy == null or economy.has_reward_receipt(receipt): return {}
	# Remove and add on a detached candidate: a failed conversion loses nothing.
	if not economy.consume_item(id) or not economy.grant_item("cooked_fish") or not economy.grant_reward(receipt, 0): return {}
	return economy.snapshot()

static func _valid_receipt(receipt: String, prefix: String) -> bool:
	if not receipt.begins_with(prefix): return false
	var suffix := receipt.trim_prefix(prefix)
	return suffix.is_valid_int() and suffix == str(suffix.to_int()) and suffix.to_int() > 0 and suffix.to_int() <= 100000000

static func next_receipt(session, action: String, offset := 0) -> String:
	if action not in ["sale", "cook"]: return ""
	var prefix := "fishing_" + action + "_"
	var serial := 0
	for key in session.state.economy._data.transactions:
		var receipt := str(key).trim_prefix("reward:")
		if _valid_receipt(receipt, prefix): serial = maxi(serial, receipt.trim_prefix(prefix).to_int())
	return prefix + str(serial + 1 + offset)

static func _inventory_available(session) -> bool:
	return session != null and session.field_inventory != null and not session.controller.save_invalid and session.world.gameplay.health > 0

static func can_store(session, fish: Dictionary) -> bool:
	var id := make_id(fish)
	return _inventory_available(session) and not id.is_empty() and session.field_inventory.can_receive(id)

static func store(session, fish: Dictionary) -> bool:
	if not _inventory_available(session): return false
	var id := make_id(fish)
	# A pesca é dona do save final da decisão e deste item juntos.
	return not id.is_empty() and session.field_inventory.store_item(id)

static func carried(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _inventory_available(session): return result
	var grid: Dictionary = session.state.economy.grid_snapshot()
	for container in ["pockets", "storage"]:
		for index in grid[container].size():
			var id: String = grid[container][index].id
			if parse_id(id).is_empty(): continue
			result.append({"id":id, "label":spec(id).label, "price":sale_price(id), "container":container, "index":index})
	return result

static func _at_counter(session) -> bool:
	if not _inventory_available(session) or session.is_transition_blocked() or session.world.driving.occupied: return false
	var fishing = session.fishing
	return fishing != null and not fishing.active and fishing._outside() and is_instance_valid(fishing.site) and session.world.player.global_position.distance_to(fishing.site.entry_position()) <= 3.2

static func sell(session, id: String, receipt: String) -> bool:
	if not _at_counter(session): return false
	var before: Dictionary = session.state.economy.snapshot()
	var candidate := sale_candidate(before, id, receipt)
	return not candidate.is_empty() and session.field_inventory.commit_candidate(before, candidate, true)

static func cook(session, id: String, receipt: String) -> bool:
	if not _inventory_available(session): return false
	var services = session.residence_services
	if services == null or services._station != "food" or not services._menu_available(): return false
	var before: Dictionary = session.state.economy.snapshot()
	var candidate := cook_candidate(before, id, receipt)
	return not candidate.is_empty() and session.field_inventory.commit_candidate(before, candidate, true)

static func open_stock(session) -> void:
	if not _at_counter(session): session.show_message("Aproxime-se do balcão do Lago Sereno."); return
	session._menu("Vender peixes")
	var rows := carried(session)
	var wallet := Label.new()
	wallet.text = "R$ %d" % session.state.economy.balance
	session.column.add_child(wallet)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "Nenhum peixe na bagagem."
		session.column.add_child(empty)
	for index in rows.size():
		var row: Dictionary = rows[index]
		session._button("Vender · %s · R$ %d" % [row.label, row.price], _sell_from_menu.bind(session, row.id, next_receipt(session, "sale", index)))
		var button: Button = session.column.get_child(session.column.get_child_count() - 1)
		button.disabled = int(session.state.economy._data.balance) > session.state.economy.LIMIT - int(row.price)
	session._button("Fechar", session.close_menu)

static func _sell_from_menu(session, id: String, receipt: String) -> void:
	var ok := sell(session, id, receipt)
	if not _at_counter(session): session.close_menu(); return
	open_stock(session)
	session.show_message("Peixe vendido · R$ %d" % sale_price(id) if ok else "Não foi possível vender este peixe.")
