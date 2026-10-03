extends RefCounted
## Identity survives FleetState; economy receipts persist each collected item.
const PREFIX := "police_loot_"
const WEAPONS := ["smg", "shotgun", "pistol"]

static func mark_unlocked(car) -> void:
	if not car.vehicle_id.begins_with(PREFIX):
		car.vehicle_id = PREFIX + "%x_%x" % [int(Time.get_unix_time_from_system()*1000000),randi()]

static func weapon(car) -> String:
	return WEAPONS[posmod(str(car.vehicle_id).hash(),WEAPONS.size())]

static func accessible(session, car) -> bool:
	if session == null or not session.ready_for_play or session.controller.save_invalid or session.is_transition_blocked(): return false
	if session.world.driving.occupied or session.world.gameplay.health <= 0: return false
	if not is_instance_valid(car) or not car.is_inside_tree() or car.is_queued_for_deletion() or not car.is_visible_in_tree(): return false
	if not car.vehicle_id.begins_with(PREFIX) or car.archetype not in ["police_cruiser","police_suv"]: return false
	if car.get_meta("police_locked",false) or car.get_meta("garage_suspended",false) or car.has_meta("awaiting_ground"): return false
	if car.health <= 0 or car.controlled or car.external_input or absf(car.speed) >= .2: return false
	var rear: Vector3 = car.global_position+car.global_basis.z*(car.half_length+.3)
	if session.world.player.global_position.distance_to(rear) > 2.2: return false
	var ray := PhysicsRayQueryParameters3D.create(session.world.player.global_position+Vector3.UP*.8,rear+Vector3.UP*.8,7)
	ray.exclude = [session.world.player.get_rid(),car.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

static func nearest(session):
	if session == null or not session.ready_for_play or session.modal or session.world.driving.occupied: return null
	for car in session.get_tree().get_nodes_in_group("drivable"):
		if accessible(session,car): return car
	return null

static func receipt(car, item: String) -> String:
	return str(car.vehicle_id)+"_"+item

static func taken(session, car, item: String) -> bool:
	return session.state.economy.has_reward_receipt(receipt(car,item))

static func open(session, car) -> void:
	if not accessible(session,car): session.close_menu(); return
	session._menu("Porta-malas · Viatura")
	var id := weapon(car)
	if not taken(session,car,"weapon"):
		var label: String = session.state.economy.Weapons.WEAPONS[id].label
		if session.state.economy.owns_weapon(id): label += " · Munição"
		session._button("Recolher "+label,func(): collect(session,car,"weapon"); open(session,car))
	if not taken(session,car,"armor"):
		session._button("Recolher colete",func(): collect(session,car,"armor"); open(session,car))
	if taken(session,car,"weapon") and taken(session,car,"armor"):
		session._button("Vazio",session.close_menu)
	session._button("Fechar",session.close_menu)

static func collect(session, car, item: String) -> bool:
	if not accessible(session,car) or item not in ["weapon","armor"] or taken(session,car,item): return false
	var wallet = session.state.economy
	var before: Dictionary = wallet.snapshot()
	if item == "armor":
		if session.world.gameplay.armor >= 100:
			session.show_message("Colete cheio")
			return false
	else:
		var id := weapon(car)
		var amount := 12 if id == "shotgun" else 60
		var granted: bool = wallet.add_ammo(id,amount) if wallet.owns_weapon(id) else wallet.grant_weapon(id)
		if not granted:
			session.show_message("Sem espaço para a arma ou munição")
			return false
	if not wallet.grant_reward(receipt(car,item),0):
		wallet.restore_snapshot(before)
		return false
	if item == "armor": session.world.gameplay.armor = 100.0
	session.world.gameplay.changed.emit()
	session.show_message("Colete recolhido" if item == "armor" else "Arma ou munição recolhida")
	session.save_game()
	return true
