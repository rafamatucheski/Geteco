class_name ResidenceManager
extends Node2D

const RULES := preload("res://world/harbor/residences/ResidenceRules.gd")
const PROPERTY_SCRIPT := preload("res://world/harbor/residences/ResidenceProperty.gd")
const INTERIOR_SCRIPT := preload("res://world/harbor/residences/ResidenceInterior.gd")
const MENU_SCRIPT := preload("res://world/harbor/residences/ResidenceMenu.gd")
const LOADOUT := preload("res://world/harbor/monaliza/PersonalLoadout.gd")
const VEHICLE_FACTORY := preload("res://emergency/ModernTrafficFactory.gd")

# As duas primeiras coordenadas correspondem às áreas marcadas pelo usuário no
# mapa do Porto; a terceira aproveita a frente residencial já autorada ao norte.
const PROPERTIES := {
	"westgate_garden": {
		"id": "westgate_garden", "name": "CASA", "price": 10000, "variant": 0,
		"position": Vector2(250, 150), "footprint": Vector2(200, 120), "standalone": true,
		"entrance_offset": Vector2(0, 120), "garage_offset": Vector2(88, 122),
		"monaliza_offset": Vector2(-60, 125), "extra_vehicle_offset": Vector2(40, 125),
		"checkpoint_offset": Vector2(-45, 135), "vehicle_rotation": 0.0,
		"driveway": [Vector2(-10,125),Vector2(30,190),Vector2(150,330)],
		"walkway": [Vector2(0,80),Vector2(110,80),Vector2(110,210)],
		"accent": Color("d2a95f"), "interior_position": Vector2(50000, 20000),
	},
	"quayside_house": {
		"id": "quayside_house", "name": "CASA", "price": 25000, "variant": 1,
		"position": Vector2(2775, 1670), "footprint": Vector2(200, 120), "standalone": true,
		"entrance_offset": Vector2(40, 116), "garage_offset": Vector2(-86, 120),
		"monaliza_offset": Vector2(5, 140), "extra_vehicle_offset": Vector2(5, 210),
		"checkpoint_offset": Vector2(42, 140), "vehicle_rotation": 0.0,
		"driveway": [Vector2(5,175),Vector2(120,175),Vector2(225,175)],
		"walkway": [Vector2(0,94),Vector2(65,94),Vector2(65,175)],
		"accent": Color("73b6b3"), "interior_position": Vector2(51000, 20000),
	},
	"canal_north": {
		"id": "canal_north", "name": "CASA", "price": 45000, "variant": 2,
		"position": Vector2(4915, -860), "footprint": Vector2(250, 180), "standalone": false,
		"entrance_offset": Vector2(0, 116), "garage_offset": Vector2(-78, 124),
		"monaliza_offset": Vector2(-105, 140), "extra_vehicle_offset": Vector2(-5, 140),
		"checkpoint_offset": Vector2(46, 132), "vehicle_rotation": 0.0,
		"driveway": [Vector2(-55,88),Vector2(-165,88),Vector2(-265,88)],
		"walkway": [Vector2(0,80),Vector2(90,80),Vector2(90,140)],
		"accent": Color("86ae78"), "interior_position": Vector2(52000, 20000),
	},
}

var world: Node2D
var player: Node2D
var interiors: Node
var weather: Node
var state: Dictionary = {}
var properties: Dictionary = {}
var residence_interiors: Dictionary = {}
var menu: ResidenceMenu
var deployed_vehicle: Node2D
var _action: Dictionary = {}
var _tick := 0.0
var _old_control_disabled := false
var _parking_tick := 0.0


func _ready() -> void:
	add_to_group("residence_manager")
	add_to_group("player_checkpoint_provider")
	# Player.try_enter_vehicle consults these groups before taking the same E input.
	add_to_group("harbor_entrance")
	add_to_group("harbor_interior_exit")
	world = get_parent() as Node2D
	player = world.get_node("Player") as Node2D
	interiors = world.get_node("Interiors")
	weather = get_tree().get_first_node_in_group("day_night_manager")
	var campaign := get_node("/root/CampaignState")
	state = RULES.normalize_state(campaign.residence_state, PROPERTIES)
	campaign.residence_state = state.duplicate(true)
	_build_properties_and_interiors()
	_build_menu()
	_restore_deployed_vehicle()
	_sync_active_visuals()


func _build_properties_and_interiors() -> void:
	# Replace only the authored placeholder house; neighbouring buildings and
	# their road/access records remain owned by the district.
	var old_house := world.get_node_or_null("NorthDistrict/CanalHomesWest")
	if old_house != null:
		old_house.hide()
		old_house.process_mode = Node.PROCESS_MODE_DISABLED
		for shape in old_house.find_children("*", "CollisionShape2D", true, false):
			shape.set_deferred("disabled", true)
		for shape in old_house.find_children("*", "CollisionPolygon2D", true, false):
			shape.set_deferred("disabled", true)
	var index := 0
	for property_id in PROPERTIES:
		var definition: Dictionary = PROPERTIES[property_id]
		var property := PROPERTY_SCRIPT.new() as ResidenceProperty
		property.name = "Residence_" + String(property_id)
		property.position = definition.position
		property.configure(definition)
		world.add_child(property)
		properties[property_id] = property

		var room := INTERIOR_SCRIPT.new() as ResidenceInterior
		room.name = "Residence_" + String(property_id)
		room.position = definition.interior_position
		room.configure(definition, index, self)
		interiors.get_node("InteriorSpaces").add_child(room)
		residence_interiors[property_id] = room
		index += 1


func _build_menu() -> void:
	menu = MENU_SCRIPT.new() as ResidenceMenu
	menu.name = "ResidenceMenu"
	add_child(menu)
	menu.purchase_confirmed.connect(purchase_home)
	menu.outfit_selected.connect(equip_outfit)
	menu.loadout_selected.connect(apply_loadout)
	menu.time_selected.connect(set_time_period)
	menu.closed.connect(_on_menu_closed)


func _process(delta: float) -> void:
	_tick += delta
	_parking_tick += delta
	if _parking_tick >= .5:
		_parking_tick = 0.0
		capture_parking_for_save()
	if _tick < 0.1:
		return
	_tick = 0.0
	_snapshot_deployed_vehicle()
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if menu.is_open or not event.is_action_pressed("interact") or event.is_echo():
		return
	var actor := _controlled_actor()
	_action = _find_action(actor)
	if _action.is_empty():
		return
	get_viewport().set_input_as_handled()
	_run_action(_action, actor)


func is_actor_in_range(actor: Node2D) -> bool:
	return not _find_action(actor).is_empty()


func _controlled_actor() -> Node2D:
	var controlled := get_node("/root/RegionTravel").controlled_car() as Node2D
	return controlled if is_instance_valid(controlled) else player


func _find_action(actor: Node2D) -> Dictionary:
	if not is_instance_valid(actor) or menu.is_open or player.is_dead or player.is_in_dialogue:
		return {}
	for property_id in residence_interiors:
		var room: ResidenceInterior = residence_interiors[property_id]
		if room.contains_point(player.global_position):
			var station := room.station_near(player.global_position)
			if not station.is_empty():
				return {"kind": String(station.kind), "property_id": property_id, "label": String(station.label)}
			return {}

	var driving := actor != player
	var best := INF
	var result: Dictionary = {}
	for property_id in properties:
		var property: ResidenceProperty = properties[property_id]
		if driving:
			if property_id != active_home_id():
				continue
			var garage_distance := actor.global_position.distance_to(property.garage_position())
			if garage_distance <= 86.0 and garage_distance < best:
				best = garage_distance
				var personal := actor.is_in_group("personal_vehicle")
				result = {"kind": "park_monaliza" if personal else "store_vehicle", "property_id": property_id,
					"label": "[E] GUARDAR MONALIZA" if personal else "[E] GUARDAR VEÍCULO"}
		else:
			var entrance_distance := player.global_position.distance_to(property.entrance_position())
			if entrance_distance <= 62.0 and entrance_distance < best:
				best = entrance_distance
				var owned: bool = property_id == active_home_id()
				result = {"kind": "enter" if owned else "purchase", "property_id": property_id,
					"label": "[E] ENTRAR" if owned else "[E] COMPRAR · $ %d" % property.price}
			if property_id == active_home_id() and has_stored_vehicle():
				var garage_distance := player.global_position.distance_to(property.garage_position())
				if garage_distance <= 72.0 and garage_distance < best:
					best = garage_distance
					result = {"kind": "retrieve_vehicle", "property_id": property_id, "label": "[E] RETIRAR CARRO GUARDADO"}
	return result


func _refresh_prompt() -> void:
	if not is_instance_valid(menu):
		return
	_action = _find_action(_controlled_actor())
	menu.show_prompt(String(_action.get("label", "")))


func _run_action(action: Dictionary, actor: Node2D) -> void:
	match String(action.get("kind", "")):
		"purchase":
			open_purchase(String(action.property_id))
		"enter":
			enter_home(String(action.property_id))
		"exit":
			exit_home(String(action.property_id))
		"wardrobe":
			_open_modal(func(): menu.open_wardrobe(player))
		"arsenal":
			_open_modal(func(): menu.open_arsenal(player))
		"food":
			use_food()
		"time":
			_open_modal(menu.open_time_selection)
		"store_vehicle":
			store_vehicle(actor)
		"retrieve_vehicle":
			retrieve_vehicle()
		"park_monaliza":
			park_monaliza(actor)


func active_home_id() -> String:
	return String(state.get("active_home", ""))


func open_purchase(property_id: String) -> Dictionary:
	var quote := get_purchase_quote(property_id)
	if not bool(quote.get("valid", false)):
		return quote
	_open_modal(func(): menu.open_purchase(quote))
	return quote


func get_purchase_quote(property_id: String) -> Dictionary:
	return RULES.purchase_quote(PROPERTIES, active_home_id(), property_id, int(player.money))


func purchase_home(property_id: String) -> Dictionary:
	var quote := get_purchase_quote(property_id)
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		_notice("DINHEIRO INSUFICIENTE" if bool(quote.get("valid", false)) else "COMPRA INDISPONÍVEL", Color("ef8b78"))
		return quote
	_recall_deployed_vehicle()
	player.money -= int(quote.due)
	state = RULES.apply_purchase(state, quote)
	_commit_state()
	_sync_active_visuals()
	_transfer_monaliza()
	player._refresh_weapon_ui()
	_notice("%s AGORA É O CHECKPOINT ATIVO" % String(quote.target_name), Color("71d3a0"))
	var saves := get_node_or_null("/root/SaveManager")
	if saves != null:
		saves.call_deferred("request_autosave", "Residência: " + String(quote.target_name))
	return quote


func enter_home(property_id: String) -> bool:
	if property_id != active_home_id() or not residence_interiors.has(property_id) or interiors.is_transitioning():
		return false
	var room: ResidenceInterior = residence_interiors[property_id]
	interiors.request_transition(func(): _complete_enter_home(room))
	return true


func _complete_enter_home(room: ResidenceInterior) -> void:
	player.set_meta("police_exterior_position", properties[room.property_id].entrance_position())
	player.set_meta("harbor_interior", true)
	player.set_meta("interior_camera_overview", true)
	player.global_position = room.spawn_point.global_position
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	interiors._frame_interior_camera(player, room.get_camera_rect())
	room.set_npc_rendering_active(true)
	if is_instance_valid(weather):
		weather.set_interior_mode(true)
	interiors._fade_in()


func exit_home(property_id: String) -> bool:
	if not residence_interiors.has(property_id) or not properties.has(property_id) or interiors.is_transitioning():
		return false
	interiors.request_transition(func(): _complete_exit_home(property_id))
	return true


func _complete_exit_home(property_id: String) -> void:
	var property: ResidenceProperty = properties[property_id]
	player.global_position = property.checkpoint_position()
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	for key in ["police_exterior_position", "harbor_interior", "interior_camera_overview"]:
		if player.has_meta(key):
			player.remove_meta(key)
	interiors._reset_exterior_camera(player)
	residence_interiors[property_id].set_npc_rendering_active(false)
	if is_instance_valid(weather):
		weather.set_interior_mode(false)
	interiors._fade_in()


func equip_outfit(outfit_id: String) -> bool:
	var owned: Dictionary = player.owned_outfits
	if outfit_id != "dante_classic" and not owned.get(outfit_id, false):
		return false
	player.apply_outfit(outfit_id)
	_notice("ROUPA EQUIPADA", Color("71d3a0"))
	return true


func apply_loadout(loadout: Dictionary) -> bool:
	player.personal_loadout = LOADOUT.normalize(loadout, player.weapon_inventory)
	player.personal_loadout_enabled = true
	if not player.can_carry_weapon(player.active_weapon_id):
		player.equip_weapon("fists")
	player._refresh_weapon_ui()
	_notice("ARSENAL EQUIPADO", Color("71d3a0"))
	return true


func use_food() -> bool:
	if player.health >= player.max_health:
		_notice("VIDA JÁ ESTÁ COMPLETA", Color("aebbc0"))
		return false
	var recovered := mini(35, player.max_health - player.health)
	player.health += recovered
	player._refresh_weapon_ui()
	_notice("REFEIÇÃO · +%d VIDA" % recovered, Color("71d3a0"))
	return true


func set_time_period(period: String) -> bool:
	if not is_instance_valid(weather) or period not in ["day", "night"]:
		return false
	var target := 0.36 if period == "day" else 0.84
	var bridge := world.get_node_or_null("CobraCampaign")
	if is_instance_valid(bridge) and bridge.ledger != null:
		if not String(bridge.ledger.data.active_id).is_empty() or int(get_node("/root/WantedManager").current_stars)>0:
			_notice("TERMINE O TRABALHO E DESPISTE A POLÍCIA PARA DESCANSAR",Color("e8b77d"))
			return false
		# The campaign owns the clock and overwrites weather every tick. Move
		# that saved clock forward too, so sleeping survives the next frame/save.
		var day_seconds: float = bridge.LEDGER.DAY_SECONDS
		var current := fposmod(.35+float(bridge.ledger.data.day_elapsed)/day_seconds,1.0)
		var skipped := fposmod(target-current,1.0)
		bridge.ledger.tick(skipped*day_seconds)
		get_node("/root/NPCMedicalCare").advance_days(skipped)
	weather.time_of_day = target
	weather._update_lighting()
	_notice("AMANHECEU" if period == "day" else "ANOITECEU", Color("e8b77d"))
	return true


func park_monaliza(vehicle: Node2D) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.is_in_group("personal_vehicle") or active_home_id().is_empty():
		return false
	vehicle.force_exit_vehicle()
	var property: ResidenceProperty = properties[active_home_id()]
	vehicle.global_position = property.monaliza_position()
	vehicle.rotation = float(PROPERTIES[active_home_id()].vehicle_rotation)
	vehicle.velocity = Vector2.ZERO
	var personal_manager := get_tree().get_first_node_in_group("personal_car_manager")
	if is_instance_valid(personal_manager):
		personal_manager.capture_state()
	_notice("MONALIZA GUARDADA", Color("71d3a0"))
	_refresh_interior_drawings()
	return true


func store_vehicle(vehicle: Node2D) -> bool:
	if not is_instance_valid(vehicle) or vehicle.is_in_group("personal_vehicle") or active_home_id().is_empty():
		return false
	var existing: Dictionary = state.get("stored_vehicle", {})
	if not existing.is_empty() and (not is_instance_valid(deployed_vehicle) or vehicle != deployed_vehicle):
		_notice("A VAGA EXTRA JÁ ESTÁ OCUPADA", Color("ef8b78"))
		return false
	var snapshot := _vehicle_snapshot(vehicle)
	if snapshot.is_empty():
		_notice("ESTE VEÍCULO NÃO PODE SER GUARDADO", Color("ef8b78"))
		return false
	if vehicle.has_method("force_exit_vehicle"):
		vehicle.force_exit_vehicle()
	snapshot["status"] = "stored"
	snapshot.erase("position")
	snapshot.erase("rotation")
	state["stored_vehicle"] = snapshot
	if vehicle == deployed_vehicle:
		deployed_vehicle = null
	vehicle.queue_free()
	var property: ResidenceProperty = properties[active_home_id()]
	player.global_position = property.checkpoint_position()
	player.velocity = Vector2.ZERO
	_commit_state()
	_refresh_interior_drawings()
	_notice("VEÍCULO GUARDADO · VAGA 2", Color("71d3a0"))
	return true


func retrieve_vehicle() -> Node2D:
	if not has_stored_vehicle() or active_home_id().is_empty():
		return null
	var data: Dictionary = state.stored_vehicle
	var property: ResidenceProperty = properties[active_home_id()]
	deployed_vehicle = VEHICLE_FACTORY.spawn_parked_vehicle(
		world, "ResidenceStoredVehicle", property.extra_vehicle_position(),
		float(PROPERTIES[active_home_id()].vehicle_rotation), String(data.get("archetype_id", "sedan_classic")),
		0, Color(String(data.get("color", "b3b9bd")))
	)
	deployed_vehicle.set_meta("residence_stored_vehicle", true)
	_apply_vehicle_snapshot(deployed_vehicle, data)
	data["status"] = "deployed"
	data["position"] = [deployed_vehicle.global_position.x, deployed_vehicle.global_position.y]
	data["rotation"] = deployed_vehicle.rotation
	state["stored_vehicle"] = data
	_commit_state()
	_refresh_interior_drawings()
	_notice("CARRO RETIRADO · VAGA EXTERNA", Color("71d3a0"))
	return deployed_vehicle


func _vehicle_snapshot(vehicle: Node2D) -> Dictionary:
	if not "health" in vehicle: return {}
	var archetype := ""
	if "active_archetype_id" in vehicle:
		archetype = String(vehicle.active_archetype_id)
	elif "vehicle_id" in vehicle:
		archetype = String(vehicle.vehicle_id)
	if archetype.is_empty() or VehicleCatalog.get_vehicle_spec(archetype).is_empty():
		return {}
	var paint := Color("b3b9bd")
	if "paint_color" in vehicle:
		paint = vehicle.paint_color
	elif "_pending_color" in vehicle:
		paint = vehicle._pending_color
	elif "visual" in vehicle and is_instance_valid(vehicle.visual):
		paint = vehicle.visual.modulate
	return {
		"archetype_id": archetype,
		"color": paint.to_html(false),
		"health": maxi(1, int(vehicle.get("health"))),
		"has_nitro": bool(vehicle.has_nitro) if "has_nitro" in vehicle else false,
		"nitro_amount": maxf(0.0, float(vehicle.nitro_amount)) if "nitro_amount" in vehicle else 0.0,
		"puncture_proof": bool(vehicle.has_puncture_proof_tires) if "has_puncture_proof_tires" in vehicle else false,
	}


func _apply_vehicle_snapshot(vehicle: Node2D, data: Dictionary) -> void:
	if "health" in vehicle:
		vehicle.health = clampi(int(data.get("health", 100)), 1, int(vehicle.get("max_health")) if "max_health" in vehicle else 100)
	if "has_nitro" in vehicle:
		vehicle.has_nitro = bool(data.get("has_nitro", false))
	if "nitro_amount" in vehicle:
		vehicle.nitro_amount = float(data.get("nitro_amount", 0.0))
	if "has_puncture_proof_tires" in vehicle:
		vehicle.has_puncture_proof_tires = bool(data.get("puncture_proof", false))


func _snapshot_deployed_vehicle() -> void:
	if not is_instance_valid(deployed_vehicle):
		return
	if deployed_vehicle.get("is_broken") == true or int(deployed_vehicle.get("health")) <= 0:
		state["stored_vehicle"] = {}
		deployed_vehicle.remove_meta("residence_stored_vehicle")
		deployed_vehicle = null
		_commit_state()
		return
	var data := _vehicle_snapshot(deployed_vehicle)
	if data.is_empty():
		return
	var property: ResidenceProperty = properties.get(active_home_id())
	data["status"] = "parked" if property != null and property.contains_parked_vehicle(deployed_vehicle) and deployed_vehicle.get("is_driven_by_player") != true else "deployed"
	if deployed_vehicle.get("is_driven_by_player") == true:
		data["status"] = "driven"
	data["position"] = [deployed_vehicle.global_position.x, deployed_vehicle.global_position.y]
	data["rotation"] = deployed_vehicle.rotation
	state["stored_vehicle"] = data
	_commit_state()


func _restore_deployed_vehicle() -> void:
	var data: Dictionary = state.get("stored_vehicle", {})
	if data.is_empty() or String(data.get("status", "stored")) not in ["deployed","parked"]:
		return
	var position_data: Variant = data.get("position", [])
	if not (position_data is Array) or position_data.size() < 2:
		data["status"] = "stored"
		state["stored_vehicle"] = data
		_commit_state()
		return
	var position := Vector2(float(position_data[0]), float(position_data[1]))
	deployed_vehicle = VEHICLE_FACTORY.spawn_parked_vehicle(
		world, "ResidenceStoredVehicle", position, float(data.get("rotation", 0.0)),
		String(data.get("archetype_id", "sedan_classic")), 0, Color(String(data.get("color", "b3b9bd")))
	)
	deployed_vehicle.set_meta("residence_stored_vehicle", true)
	_apply_vehicle_snapshot(deployed_vehicle, data)


func capture_parking_for_save() -> void:
	if active_home_id().is_empty(): return
	if not is_instance_valid(deployed_vehicle):
		# A car restored by RegionTravel while driving is the same saved car,
		# never a second spawn from the garage's record.
		for vehicle in get_tree().get_nodes_in_group("vehicle"):
			if vehicle.get_meta("residence_stored_vehicle",false):
				deployed_vehicle = vehicle
				break
	if is_instance_valid(deployed_vehicle):
		_snapshot_deployed_vehicle()
		return
	if not state.get("stored_vehicle",{}).is_empty(): return
	var property: ResidenceProperty = properties[active_home_id()]
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion(): continue
		if vehicle.is_in_group("personal_vehicle") or vehicle.get("is_driven_by_player") == true: continue
		if not "health" in vehicle: continue
		if vehicle.get("is_broken") == true or int(vehicle.get("health")) <= 0: continue
		if "velocity" in vehicle and vehicle.velocity.length() > 2.0: continue
		if not property.contains_parked_vehicle(vehicle): continue
		if _vehicle_snapshot(vehicle).is_empty(): continue
		deployed_vehicle = vehicle
		deployed_vehicle.set_meta("residence_stored_vehicle",true)
		deployed_vehicle.add_to_group("parked_vehicle")
		_snapshot_deployed_vehicle()
		return


func _recall_deployed_vehicle() -> void:
	var data: Dictionary = state.get("stored_vehicle", {})
	if data.is_empty():
		return
	if is_instance_valid(deployed_vehicle):
		data = _vehicle_snapshot(deployed_vehicle)
		deployed_vehicle.queue_free()
		deployed_vehicle = null
	data["status"] = "stored"
	data.erase("position")
	data.erase("rotation")
	state["stored_vehicle"] = data
	_commit_state()


func _transfer_monaliza() -> void:
	var personal_manager := get_tree().get_first_node_in_group("personal_car_manager")
	if not is_instance_valid(personal_manager) or not is_instance_valid(personal_manager.car):
		return
	var car: Node2D = personal_manager.car
	if car.is_driven_by_player or personal_manager.impounded:
		return
	var property: ResidenceProperty = properties[active_home_id()]
	car.global_position = property.monaliza_position()
	car.rotation = float(PROPERTIES[active_home_id()].vehicle_rotation)
	car.velocity = Vector2.ZERO
	personal_manager.capture_state()
	_refresh_interior_drawings()


func get_checkpoint_spawn() -> Node2D:
	var active := active_home_id()
	return properties[active].checkpoint if properties.has(active) else null


func map_position_for_actor(actor: Node2D) -> Variant:
	for property_id in residence_interiors:
		if residence_interiors[property_id].contains_point(actor.global_position):
			return properties[property_id].entrance_position()
	return null


func has_monaliza() -> bool:
	var personal_manager := get_tree().get_first_node_in_group("personal_car_manager")
	return is_instance_valid(personal_manager) and is_instance_valid(personal_manager.car) and personal_manager.car.unlocked


func has_stored_vehicle() -> bool:
	var stored: Dictionary = state.get("stored_vehicle", {})
	return not stored.is_empty() and String(stored.get("status", "stored")) == "stored"


func _sync_active_visuals() -> void:
	for property_id in properties:
		properties[property_id].set_active(property_id == active_home_id())
	_refresh_interior_drawings()


func _refresh_interior_drawings() -> void:
	for room in residence_interiors.values():
		room.queue_redraw()


func _commit_state() -> void:
	get_node("/root/CampaignState").residence_state = state.duplicate(true)


func _open_modal(open_action: Callable) -> void:
	if menu.is_open:
		return
	_old_control_disabled = bool(player.is_control_disabled)
	player.is_control_disabled = true
	player.velocity = Vector2.ZERO
	open_action.call()


func _on_menu_closed() -> void:
	player.is_control_disabled = _old_control_disabled


func _notice(text: String, color: Color) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if is_instance_valid(hud) and hud.has_method("show_notice"):
		hud.show_notice(text, color)
