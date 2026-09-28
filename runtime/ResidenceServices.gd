extends RefCounted
## Production V1: HarborGame -> ResidenceManager._run_action -> ResidenceMenu.
## Physical furniture actions; residence owns persistence, backpack owns inventory.
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const HOMES := preload("res://data/catalogs/ResidenceCatalog.gd")
var session
var _home := ""
var _menu_health := 0.0
var _station := ""
var storage := preload("res://runtime/ResidenceStorage.gd").new()
const LABELS := {"wardrobe":"Trocar de roupa","chest":"Abrir baú","food":"Abrir geladeira","save":"Salvar jogo","time":"Descansar","arsenal":"Usar arsenal"}

func configure(owner_session) -> void:
	session = owner_session

func _accessible() -> bool:
	if session == null or not session.ready_for_play or session.controller.save_invalid: return false
	if session.world.driving.occupied or session.world.gameplay.health <= 0: return false
	if session.state.region_id != "harbor" or not HOMES.PROPERTIES.has(session.state.place_id): return false
	if not session.activities.residence.can_enter(session.state.place_id) or not is_instance_valid(session.room): return false
	return not session.is_transition_blocked()

func _near_station(station: String) -> bool:
	var point: Variant = session.room.interaction_points.get(station)
	return point is Vector3 and session.world.player.position.distance_to(point) < .95

func nearest_action() -> Dictionary:
	if session == null or session.modal or not _accessible(): return {}
	var nearest := ""
	var distance := .95
	for station in LABELS:
		var point: Variant = session.room.interaction_points.get(station)
		if not point is Vector3: continue
		var separation: float = session.world.player.position.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = station
	if nearest.is_empty(): return {}
	var label: String = LABELS[nearest]
	if nearest == "chest" and not storage.unlocked(): label = "Baú · desbloqueie a mochila"
	return {"id":"residence_services","target":"residence_services","station":nearest,"label":label}

func perform(target: String) -> bool:
	if target != "residence_services" or nearest_action().is_empty(): return false
	_station = nearest_action().station
	_home = session.state.place_id
	_menu_health = session.world.gameplay.health
	_open()
	return true

func _menu_available() -> bool:
	if not _accessible() or session.state.place_id != _home or not _near_station(_station) or session.world.gameplay.health < _menu_health:
		session.close_menu()
		return false
	return true

func _focus() -> void:
	for child in session.column.get_children():
		if child is Button:
			session._focus_menu_button.call_deferred(weakref(child))
			return

func _open() -> void:
	if not _menu_available(): return
	match _station:
		"wardrobe": _wardrobe()
		"chest": _chest()
		"food": _fridge()
		"save": _save()
		"time": _rest_menu()
		"arsenal": _arsenal()

func _wardrobe() -> void:
	if not _menu_available(): return
	session._menu("Guarda-roupa")
	for item in session.state.economy.storefront("outfit"):
		if not item.owned: continue
		session._button(str(item.get("name",item.get("label",item.id))),_wear.bind(str(item.id)))
	session._button("Fechar",session.close_menu)
	_focus()

func _wear(id: String) -> void:
	if _station != "wardrobe" or not _menu_available(): return
	if session.state.economy.equip_outfit(id):
		session.apply_outfit()
		session.close_menu()
		session.save_game()

func _arsenal() -> void:
	if not _menu_available(): return
	session._menu("Arsenal")
	var selected: Dictionary = session.state.economy.personal_loadout()
	for slot in session.state.economy.PERSONAL_SLOTS:
		var title: String = {"curta":"Curta","longa":"Longa","corpo":"Corpo a corpo","granada":"Granada"}[slot]
		var weapon: String = str(selected.get(slot,""))
		session._button(title+" · "+str(WEAPONS.WEAPONS.get(weapon,{}).get("label","Vazio")),_select_slot.bind(slot))
	session._button("Fechar",session.close_menu)
	_focus()

func _select_slot(slot: String) -> void:
	if not _menu_available(): return
	session._menu("Arsenal")
	session._button("Guardar arma",_set_slot.bind(slot,""))
	for id in session.state.economy.PERSONAL_SLOTS[slot]:
		if session.state.economy.owns_weapon(id):
			session._button(str(WEAPONS.WEAPONS[id].label),_set_slot.bind(slot,id))
	session._button("Voltar",_arsenal)
	_focus()

func _set_slot(slot: String, id: String) -> void:
	if not _menu_available(): return
	# Activating residential storage must never award Monaliza's starter case.
	session.state.economy.enable_personal_loadout()
	if session.state.economy.set_personal_slot(slot,id):
		if not session.state.weapons_allowed(): session.state.equip_weapon("fists")
		session.save_game()
	_arsenal()

func _rest_menu() -> void:
	if not _menu_available(): return
	session._menu("Descansar")
	session._button("Dia",_rest.bind(.36))
	session._button("Noite",_rest.bind(.84))
	session._button("Fechar",session.close_menu)
	_focus()

func _rest(target: float) -> void:
	if not _menu_available(): return
	if session.advance_residence_time(target):
		session.close_menu()
		if session.save_game(): session.show_message("Amanheceu." if target < .5 else "Anoiteceu.")
	else:
		session.close_menu()
		session.show_message("Termine o trabalho e despiste a polícia para descansar.")

func _fridge() -> void:
	if not _menu_available(): return
	session._menu("Geladeira")
	session._button("Comer uma refeição · +35 vida",_consume.bind("meal"))
	session._button("Beber suco · +15 vida",_consume.bind("drink"))
	session._button("Fechar",session.close_menu)
	_focus()

func _consume(kind: String) -> void:
	if kind not in ["meal","drink"] or _station != "food" or not _menu_available(): return
	var recovered: bool = session.world.gameplay.heal(35 if kind == "meal" else 15)
	session.close_menu()
	if recovered and not session.save_game(): return
	session.show_message("Refeição concluída." if recovered and kind == "meal" else "Bebida consumida." if recovered else "Vida já está completa.")

func _save() -> void:
	if _station != "save" or not _menu_available(): return
	session.close_menu()
	if session.save_game(true): session.show_message("Jogo salvo.")

func _chest() -> void:
	if not _menu_available(): return
	if not storage.unlocked():
		session.close_menu()
		session.show_message("Desbloqueie a mochila para usar o baú.")
		return
	session._menu("Baú")
	var chest: Dictionary = session.activities.residence.data.chest
	var items := storage.items()
	for id in items:
		if not items[id] is Dictionary or int(items[id].get("count",0)) < 1: continue
		session._button("Guardar · "+str(items[id].get("label",id)),_transfer.bind(str(id),true))
	for id in chest:
		var label: String = str(items.get(id,{}).get("label",id))
		session._button("Retirar · %s ×%d"%[label,int(chest[id])],_transfer.bind(str(id),false))
	session._button("Fechar",session.close_menu)
	_focus()

func _transfer(id: String, deposit: bool) -> void:
	if _station != "chest" or not _menu_available() or not storage.unlocked(): return
	var chest: Dictionary = session.activities.residence.data.chest
	var changed := storage.deposit(chest,id) if deposit else storage.withdraw(chest,id)
	if changed: session.save_game()
	else: session.show_message("Sem espaço para transferir este item.")
	_chest()
