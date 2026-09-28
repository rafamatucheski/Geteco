extends Node
## Session-owned adapter for productive Harbor behaviors that do not belong to
## NativeRegion geometry, the place catalog, Actor, combat or shared models.

var session
var port
var cemetery
var security
var cargo_handling
var secret_car
var freight
var passenger_terminal
var village
var village_quest
var village_residents
var village_fleet
var secret_network
var secret_file
var secret_passage

func configure(owner_session) -> void:
	session = owner_session
	name = "V1UrbanOperations"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	port = preload("res://gameplay/urban_v1/PortOperations.gd").new()
	port.configure(session)
	add_child(port)
	cemetery = preload("res://gameplay/urban_v1/CemeteryOperations.gd").new()
	cemetery.configure(session)
	add_child(cemetery)
	security = preload("res://gameplay/urban_v1/HarborPortSecurity.gd").new()
	security.configure(session)
	add_child(security)
	cargo_handling = preload("res://gameplay/urban_v1/PortLogistics.gd").new()
	cargo_handling.configure(session)
	add_child(cargo_handling)
	freight = preload("res://gameplay/urban_v1/PortFreightDelivery.gd").new()
	freight.configure(session, cargo_handling, security)
	add_child(freight)
	secret_car = preload("res://gameplay/urban_v1/CobraSecretCar3D.gd").new()
	secret_car.configure(session)
	add_child(secret_car)
	passenger_terminal = preload("res://gameplay/urban_v1/HarborPassengerTerminal.gd").new()
	passenger_terminal.configure(session)
	add_child(passenger_terminal)
	village = preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").new()
	add_child(village)
	village.configure_player(session.world.player)
	village.tonico.gameplay = session.world.gameplay
	village_residents = preload("res://gameplay/urban_v1/TruckersVillageResidents.gd").new()
	village_residents.configure(session)
	add_child(village_residents)
	village_residents.register_resident(village.tonico)
	village_quest = preload("res://gameplay/urban_v1/TruckersVillageQuest.gd").new()
	village_quest.configure(session,village)
	add_child(village_quest)
	village_quest.bind_residents(village_residents)
	village.homes.configure(session)
	village_residents.bind_homes(village.homes,village_quest)
	var house_loot = preload("res://gameplay/urban_v1/TruckersVillageHouseLoot.gd").new()
	house_loot.configure(session,village.homes)
	add_child(house_loot)
	village_fleet = preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").new()
	village_fleet.configure(session)
	add_child(village_fleet)
	secret_network = preload("res://runtime/SecretNetworkProgression.gd").new()
	secret_file = preload("res://runtime/SecretFileRuntime.gd").new()
	add_child(secret_file)
	secret_file.configure(session,secret_network)
	secret_passage = preload("res://gameplay/urban_v1/TruckersVillageSecretPassage.gd").new()
	add_child(secret_passage)
	secret_passage.configure(session,village,secret_network)
	secret_passage.set_physical_cut_ready(true)
	secret_passage.state_changed.connect(_secret_state_changed)

func refresh_context() -> void:
	if is_instance_valid(village): village.set_region_active(session.state.region_id == "harbor" and session.state.place_id.is_empty())
	if is_instance_valid(village) and is_instance_valid(village.homes): village.homes.set_region_active(session.state.region_id == "harbor" and session.state.place_id.is_empty())
	if is_instance_valid(village_residents): village_residents.set_region_active(session.state.region_id == "harbor" and session.state.place_id.is_empty())
	if is_instance_valid(port): port.refresh_context()
	if is_instance_valid(cemetery): cemetery.refresh_context()
	if is_instance_valid(cargo_handling): cargo_handling.refresh_context()
	if is_instance_valid(secret_passage): secret_passage.set_region_active(session.state.region_id == "harbor" and session.state.place_id.is_empty())

func nearest_action() -> Dictionary:
	var secret_action: Dictionary = secret_passage.nearest_action() if is_instance_valid(secret_passage) else {}
	if not secret_action.is_empty(): return secret_action
	var village_action: Dictionary = village_quest.nearest_action() if is_instance_valid(village_quest) else {}
	if not village_action.is_empty(): return village_action
	var checkpoint: Dictionary = security.nearest_action() if is_instance_valid(security) else {}
	if not checkpoint.is_empty(): return checkpoint
	var delivery: Dictionary = freight.nearest_action() if is_instance_valid(freight) else {}
	if not delivery.is_empty(): return delivery
	var company: Dictionary = cargo_handling.depot.nearest_action() if is_instance_valid(cargo_handling) and is_instance_valid(cargo_handling.depot) else {}
	if not company.is_empty(): return company
	return cemetery.nearest_action() if is_instance_valid(cemetery) else {}

func freight_status() -> Dictionary:
	return freight.freight_status() if is_instance_valid(freight) else {"active":false}

func perform(target: String) -> bool:
	if target.begins_with("truckers_village_secret_"): return is_instance_valid(secret_passage) and secret_passage.perform(target)
	if target.begins_with("truckers_village_"): return is_instance_valid(village_quest) and village_quest.perform(target)
	if target.begins_with("vertice_"): return is_instance_valid(cargo_handling) and cargo_handling.depot.perform(target)
	if target == "south_port_checkpoint": return is_instance_valid(security) and security.perform(target)
	if target.begins_with("south_port_freight_"): return is_instance_valid(freight) and freight.perform(target)
	return is_instance_valid(cemetery) and cemetery.perform(target)

func snapshot() -> Dictionary:
	return {
		"version":1,
		"port":port.snapshot() if is_instance_valid(port) else {},
		"cemetery":cemetery.snapshot() if is_instance_valid(cemetery) else {},
		"security":security.snapshot() if is_instance_valid(security) else {},
		"freight":freight.snapshot() if is_instance_valid(freight) else {},
		"logistics":cargo_handling.snapshot() if is_instance_valid(cargo_handling) else {},
		"harbor_life":_life_snapshot(),
		"truckers_village":village_quest.snapshot() if is_instance_valid(village_quest) else {},
		"truckers_village_fleet":village_fleet.snapshot() if is_instance_valid(village_fleet) else {},
		"secret_network":secret_network.snapshot() if secret_network != null else {},
	}

func _secret_state_changed() -> void:
	if is_instance_valid(secret_file): secret_file.refresh()

func _life_snapshot() -> Dictionary:
	var routines = session._routine_director()
	return {"terminal":passenger_terminal.snapshot(),"workers":routines.port_respawn.duplicate() if routines!=null else {},"loaders":port.worker_respawn.duplicate(),"guards":security._staff_respawn.duplicate()}

func restore_snapshot(data: Dictionary) -> bool:
	if not is_instance_valid(port) or not is_instance_valid(cemetery) or not is_instance_valid(security) or not is_instance_valid(freight) or not validate_snapshot(data): return false
	var checkpoint: Dictionary = data.get("security", {"version":1,"authorized_entry":false,"authorized_visit":false,"exiting_port":false})
	var delivery: Dictionary = data.get("freight", {"version":1,"jobs":[0,0,0],"active_bay":-1,"truck":{}})
	if data.has("truckers_village") and (not is_instance_valid(village_quest) or not village_quest.restore_snapshot(data.truckers_village)): return false
	if data.has("truckers_village_fleet") and (not is_instance_valid(village_fleet) or not village_fleet.restore_snapshot(data.truckers_village_fleet)): return false
	if data.has("secret_network") and (secret_network == null or not secret_network.restore_snapshot(data.secret_network)): return false
	if is_instance_valid(secret_passage): secret_passage.refresh_state()
	if is_instance_valid(secret_file): secret_file.refresh()
	if data.has("harbor_life"):
		var life: Dictionary = data.harbor_life
		passenger_terminal.restore_snapshot(life.terminal)
		var routines = session._routine_director()
		if routines!=null:
			routines.port_respawn = life.workers.duplicate()
			for id in routines.port_respawn:
				if routines.actors.has(id) and is_instance_valid(routines.actors[id]): routines._suspend(id,routines.actors[id])
				routines.suspended_states.erase(id)
		port.worker_respawn.assign(life.loaders)
		for i in 2: port.worker_was_dead[i] = float(life.loaders[i])>0
		security._staff_respawn.assign(life.guards)
		for i in 3:
			if float(life.guards[i])>0 and is_instance_valid(security._staff[i]): security._staff[i].queue_free()
	return port.restore_snapshot(data.port) and cemetery.restore_snapshot(data.cemetery) and security.restore_snapshot(checkpoint) and freight.restore_snapshot(delivery) \
		and (not data.has("logistics") or cargo_handling.restore_snapshot(data.logistics))

static func validate_snapshot(data: Dictionary) -> bool:
	if data.has("secret_network") and (not data.secret_network is Dictionary or not preload("res://runtime/SecretNetworkProgression.gd").validate_snapshot(data.secret_network)): return false
	if data.has("truckers_village_fleet") and (not data.truckers_village_fleet is Dictionary or not preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").validate_snapshot(data.truckers_village_fleet)): return false
	if data.has("truckers_village") and (not data.truckers_village is Dictionary or not preload("res://gameplay/urban_v1/TruckersVillageQuest.gd").validate_snapshot(data.truckers_village)): return false
	if data.has("harbor_life") and not _validate_life(data.harbor_life): return false
	if data.has("logistics") and (not data.logistics is Dictionary or not preload("res://gameplay/urban_v1/PortLogistics.gd").validate_snapshot(data.logistics)): return false
	return data.get("version") == 1 and data.get("port") is Dictionary and data.get("cemetery") is Dictionary \
		and preload("res://gameplay/urban_v1/PortOperations.gd").validate_snapshot(data.port) \
		and preload("res://gameplay/urban_v1/CemeteryOperations.gd").validate_snapshot(data.cemetery) \
		and (not data.has("security") or (data.security is Dictionary \
			and preload("res://gameplay/urban_v1/HarborPortSecurity.gd").validate_snapshot(data.security))) \
		and (not data.has("freight") or (data.freight is Dictionary \
			and preload("res://gameplay/urban_v1/PortFreightDelivery.gd").validate_snapshot(data.freight)))

static func _validate_life(value: Variant) -> bool:
	if not value is Dictionary or not value.get("terminal") is Dictionary or not preload("res://gameplay/urban_v1/HarborPassengerTerminal.gd").validate_snapshot(value.terminal): return false
	if not value.get("workers") is Dictionary or value.workers.size()>40: return false
	for id in value.workers:
		if not id is String or not (id.begins_with("south_port_worker_") or id.begins_with("harbor_ship_dock_operator_")): return false
	if not value.get("loaders") is Array or value.loaders.size()!=2 or not value.get("guards") is Array or value.guards.size()!=3: return false
	for timer in value.workers.values()+value.loaders+value.guards:
		if typeof(timer) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(timer)) or float(timer)<0 or float(timer)>180: return false
	return true
