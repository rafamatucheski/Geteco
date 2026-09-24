extends Node
## V1 PersonalCarManager/PersonalLoadout, using V2's existing garage vehicle owner.
## No second vehicle snapshot: GarageRewards persists identity, location and damage.
const ID := "personal_monaliza"
const FEES := 50
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const TRUNK_VIEW := preload("res://runtime/TrunkView.gd")
var session
var _menu_health := 0.0
var _trunk_view: Node3D

func configure(owner_session) -> void:
	session = owner_session

func refresh() -> void:
	if session == null or not session.ready_for_play or session.controller.save_invalid: return
	if not session.state.campaign.snapshot().completed.has("primeiro_giro"): return
	var garage = session.garage_rewards
	if garage == null or garage.data.vehicles.has(ID): return
	# Keep the pre-existing player_coupe and its save. This is the earned personal car.
	garage.data.vehicles[ID] = garage._initial_record("monaliza",Vector3(0,.04,0),-PI,"maciota")
	garage.on_location_changed()

func _car():
	return session.garage_rewards.cars.get(ID) if session != null and session.garage_rewards != null else null

func _available() -> bool:
	return session != null and session.ready_for_play and not session.controller.save_invalid and session.garage_rewards != null and session.garage_rewards.data.vehicles.has(ID)

func _rear() -> Vector3:
	var car = _car()
	return car.global_position+car.global_basis.z*(car.half_length+.3)

func _near_trunk() -> bool:
	var car = _car()
	if not is_instance_valid(car) or not car.is_visible_in_tree() or car.controlled or car.external_input or car.get_meta("garage_suspended",false) or car.has_meta("awaiting_ground") or car.health<=0 or absf(car.speed)>=.2: return false
	if session.world.player.position.distance_to(_rear())>=3.6: return false
	var ray := PhysicsRayQueryParameters3D.create(session.world.player.global_position+Vector3.UP*.8,_rear()+Vector3.UP*.8,7)
	ray.exclude = [session.world.player.get_rid(),car.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _near_service() -> bool:
	return session.state.place_id=="maciota" and session.world.player.position.distance_to(session.world.maciota_place.interaction_points.workbench)<2.0

func nearest_action() -> Dictionary:
	if not _available() or session.modal or session.world.driving.occupied or session.world.gameplay.health<=0: return {}
	# In the compact V1 garage the parked rear can overlap the workbench radius.
	# The authored service point owns that interaction while Dante is inside;
	# otherwise the trunk swallowed the repair/recovery menu entirely.
	if _near_service(): return {"id":"personal_car","target":"service","label":"Cuidar da Monaliza"}
	if _near_trunk(): return {"id":"personal_car","target":"trunk","label":"Abrir porta-malas"}
	return {}

func perform(target: String) -> bool:
	if nearest_action().get("target","")!=target: return false
	_menu_health = session.world.gameplay.health
	if target=="trunk":
		if session.state.economy.claim_monaliza_starter():
			# Go through GameState: the garage still refuses drawing any weapon.
			if session.state.equipped_weapon=="fists": session.state.equip_weapon("pistol")
			session.save_game()
		if session.state.economy.personal_loadout().is_empty():
			session.show_message("Libere espaço na reserva da pistola para recolher a maleta.")
			return true
		_open_trunk()
	else: _open_service()
	return true

func _open_trunk() -> void:
	session._menu("Porta-malas · Monaliza")
	session.menu_closed = _close_trunk_view
	var economy = session.state.economy
	var slots: Dictionary = economy.personal_loadout()
	for slot in economy.PERSONAL_SLOTS:
		var selected: String = str(slots.get(slot,""))
		var title: String = {"curta":"Curta","longa":"Longa","corpo":"Corpo a corpo","granada":"Granada"}[slot]
		session._button(title+" · "+str(WEAPONS.WEAPONS.get(selected,{}).get("label","Vazio")),_select_slot.bind(slot))
	session._button("Fechar",session.close_menu)
	_focus_menu()
	_show_trunk_view(slots)

func _show_trunk_view(slots: Dictionary) -> void:
	var car = _car()
	if not is_instance_valid(car): return
	if not is_instance_valid(_trunk_view):
		_trunk_view = TRUNK_VIEW.new()
		add_child(_trunk_view)
	_trunk_view.open(car,session.world.camera)
	_trunk_view.update_loadout(slots)

func _close_trunk_view() -> void:
	if is_instance_valid(_trunk_view):
		_trunk_view.close()
	_trunk_view = null

func _select_slot(slot: String) -> void:
	if not _near_trunk() or session.world.gameplay.health<_menu_health: session.close_menu(); return
	session._menu("Porta-malas · "+slot)
	session.menu_closed = _close_trunk_view
	session._button("Guardar arma",_set_slot.bind(slot,""))
	for id in session.state.economy.PERSONAL_SLOTS[slot]:
		if not session.state.economy.owns_weapon(id): continue
		session._button(str(WEAPONS.WEAPONS[id].label),_set_slot.bind(slot,id))
	session._button("Voltar",_open_trunk)
	_focus_menu()

func _set_slot(slot: String, id: String) -> void:
	if not _near_trunk() or session.world.gameplay.health<=0 or session.world.gameplay.health<_menu_health: session.close_menu(); return
	if session.state.economy.set_personal_slot(slot,id):
		if not session.state.weapons_allowed(): session.state.equip_weapon("fists")
		session.save_game()
	_open_trunk()

func _open_service() -> void:
	if session.storefronts != null and session.storefronts.open_maciota_service(): return
	session._menu("Monaliza")
	session._button("Reparar · R$ 50",_service.bind(false))
	session._button("Recuperar à baia · R$ 50",_service.bind(true))
	session._button("Fechar",session.close_menu)
	_focus_menu()

func _focus_menu() -> void:
	for child in session.column.get_children():
		if child is Button:
			child.grab_focus.call_deferred()
			break

func _notice(text: String) -> void:
	session.close_menu()
	session.show_message(text)

func _service(recover: bool) -> void:
	if not _available() or not _near_service() or session.world.driving.occupied or session.world.gameplay.health<=0 or session.world.gameplay.health<_menu_health:
		session.close_menu()
		return
	var economy = session.state.economy
	var garage = session.garage_rewards
	var car = _car()
	if economy.balance<FEES: _notice("Saldo insuficiente."); return
	if is_instance_valid(car) and (car.controlled or absf(car.speed)>.2):
		_notice("Pare e saia da Monaliza antes do serviço.")
		return
	var record: Dictionary = garage.data.vehicles[ID]
	var point: Vector3 = garage._origin("maciota")+Vector3(0,.04,0)
	if not recover:
		if not is_instance_valid(car) or record.place_id!="maciota" or car.get_meta("garage_suspended",false):
			_notice("Traga a Monaliza para a garagem.")
			return
		if car.health>=car.max_health: _notice("A Monaliza já está reparada."); return
	else:
		if is_instance_valid(car) and record.place_id=="maciota" and car.health>=car.max_health and car.position.distance_to(point)<1:
			_notice("A Monaliza já está na baia.")
			return
		if is_instance_valid(car):
			if not session.controller.vehicle_position_clear(car,point,-PI): _notice("Libere a baia para recuperar a Monaliza."); return
		else:
			car=session.controller.spawn_vehicle("monaliza",point,-PI)
			if not is_instance_valid(car): _notice("Libere a baia para recuperar a Monaliza."); return
			car.vehicle_id=ID
			car.paint_color=Color.html(record.paint)
			garage.cars[ID]=car
	if not economy.spend(FEES,session._transaction()): return
	if recover:
		car.place(point,-PI)
		car.set_meta("garage_reward",true)
		car.set_meta("garage_place","maciota")
		car.set_meta("garage_origin",garage._origin("maciota"))
		car.set_meta("region_id","harbor")
		car.remove_meta("garage_suspended")
		car.remove_meta("awaiting_ground")
		car.collision_layer=4
		car.collision_mask=7
		car.show()
		car.set_physics_process(true)
		car.add_to_group("drivable")
		car.add_to_group("personal_vehicle")
		if not session.controller.vehicles.has(car): session.controller.vehicles.append(car)
	car.repair()
	garage._capture_all()
	session.close_menu()
	session.save_game()
	session.show_message("Monaliza pronta.")
