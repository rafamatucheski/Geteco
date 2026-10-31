extends RefCounted
## O tempo de calendário é o moon_day + time salvo existente, nunca o relógio do sistema.
## Valor por carro-forte vem da tabela de economia (era 40.000). Salvar fica bloqueado com
## saque pendente, então nenhum save guarda o valor antigo em "pending".
const CASH_PER_TRUCK: int = preload("res://data/catalogs/EconomyBalance.gd").ARMORED_CASH_PER_TRUCK
const DAYS := [1, 3, 5]
const HOURS := [9, 14, 17]
const BANKS := ["harbor_bank", "desert_bank"]
const KEY := "armored_transport"
const MAX_SECURITY := 6
const PHASES := ["loading", "boarding", "driving", "unloading", "departing", "finished"]

static func security(level: int) -> Dictionary:
	var rank := clampi(level,0,MAX_SECURITY)
	return {
		"level":rank,
		"guard_count":[6,6,8,8,8,10,10][rank],
		"crew_count":[6,6,8,8,8,10,10][rank],
		"guard_health":[110,120,130,145,155,170,180][rank],
		"weapon":["pistol","pistol","smg","smg","m4a1","m4a1","m4a1"][rank],
		"shot_damage":[8,8,9,9,10,11,12][rank],
		"shot_interval":[.95,.85,.65,.52,.45,.38,.32][rank],
		"reaction_time":[1.25,1.0,.85,.65,.5,.35,.25][rank],
		"detection_range":[18.0,20.0,22.0,24.0,25.0,26.0,26.875][rank],
		"move_speed":[2.6,2.7,2.8,2.9,3.0,3.1,3.2][rank],
		"city_report_delay":[3.0,2.5,1.8,1.0,.5,.2,0.0][rank],
		"road_report_delay":[16.0,12.0,9.0,6.0,3.0,1.0,0.0][rank],
		"lock_stages":[1,1,2,2,2,3,3][rank],
		"blast_hits":[1,1,1,2,2,2,3][rank],
		"armor_health":[1200,1300,1400,1550,1700,1850,2000][rank],
		# Off-screen travel estimate; visible vehicles obey the shared traffic speed.
		"cruise_speed":[10.0,10.0,10.5,11.0,11.5,12.0,13.0][rank],
	}

static func departure(day: int, time: float) -> Dictionary:
	var slot := DAYS.find(posmod(day, 7))
	if slot < 0: return {}
	var hour := float(HOURS[slot])
	if time * 24.0 < hour or time * 24.0 >= hour + 1.0: return {}
	var origin := posmod(int(float(day) / 7.0) + slot, 2)
	return {"id": "%d:%d" % [day, slot], "origin": BANKS[origin], "destination": BANKS[1-origin]}

static func initial(event: Dictionary, security_level := 0) -> Dictionary:
	return {"version": 1, "service_layout":1, "id": event.id, "origin": event.origin, "destination": event.destination,
		"phase": "loading", "elapsed": 0.0, "hostile": false, "reported": false,
		"report_remaining": -1.0, "pending": 0, "taken": [false, false],
		"opened": [false, false], "vehicles": [], "guards": [], "virtual_poses": true,
		"security_level":clampi(security_level,0,MAX_SECURITY), "escalated":false,
		"route_offset":0.0, "reported_point":[0.0,0.0,0.0],
		"secured":[false,false], "delivered":[false,false], "door_damage":[0,0], "cargo_cycles":[0,0],
		"lock_progress":[0,0], "virtual_elapsed":0.0}

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,minimum,maximum) and float(value) == floorf(float(value))

static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate in value:
		if not _number(coordinate,-100000,100000): return false
	return true

static func _id(value: Variant) -> bool:
	if not value is String: return false
	var parts: PackedStringArray = value.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[0].to_int() >= 0 and parts[1] in ["0","1","2"]

static func restore(value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty(): return {}
	if value.get("version",0) != 1 or not _id(value.get("id")): return {}
	if value.get("origin","") not in BANKS or value.get("destination","") not in BANKS or value.origin == value.destination: return {}
	var row := initial(value)
	row.merge(value,true)
	row.service_layout = value.get("service_layout",0)
	if not _integer(row.service_layout,0,1): return {}
	# Older records with physical poses retain their exact saved placement.
	# Simulated poses explicitly opt into terrain-supported first admission.
	if not value.has("virtual_poses"):
		row.virtual_poses = row.vehicles is Array and row.vehicles.is_empty()
	if row.phase not in PHASES or not _integer(row.security_level,0,MAX_SECURITY): return {}
	for field in ["hostile","reported","escalated","virtual_poses"]:
		if not row[field] is bool: return {}
	for field in ["elapsed","virtual_elapsed","route_offset"]:
		if not _number(row[field],0,10000000): return {}
	if not _number(row.report_remaining,-1,120) or not _point(row.reported_point): return {}
	if not _integer(row.pending,0,CASH_PER_TRUCK*2) or int(row.pending)%CASH_PER_TRUCK != 0: return {}
	for field in ["taken","opened","secured","delivered"]:
		if not row[field] is Array or row[field].size() != 2: return {}
		for flag in row[field]:
			if not flag is bool: return {}
	var expected_pending := 0
	for index in 2:
		if row.taken[index] and not row.opened[index]: return {}
		if row.secured[index] and not row.taken[index]: return {}
		if row.delivered[index] and row.taken[index]: return {}
		if row.taken[index] and not row.secured[index]: expected_pending += CASH_PER_TRUCK
	if row.phase != "finished" and row.pending != expected_pending: return {}
	if row.phase == "finished" and row.pending != 0: return {}
	for field in ["door_damage","cargo_cycles","lock_progress"]:
		if not row[field] is Array or row[field].size() != 2: return {}
		for amount in row[field]:
			if not _integer(amount,0,10000): return {}
	if not row.vehicles is Array or row.vehicles.size() not in [0,4]: return {}
	for vehicle in row.vehicles:
		if not vehicle is Dictionary or not _point(vehicle.get("point")): return {}
		if not preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").valid_records(vehicle.get("body_dents",[])): return {}
		if not preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").valid_records(vehicle.get("broken_glass",[])): return {}
		if not preload("res://gameplay/vehicle_effects/VehicleBreakawayParts.gd").valid_state(vehicle.get("breakaway_parts",{})): return {}
		if not preload("res://gameplay/vehicle_effects/VehicleBlood.gd").valid(vehicle.get("blood_stains",0)): return {}
		if not _number(vehicle.get("yaw"),-100000,100000) or not _number(vehicle.get("health"),0,10000): return {}
	if not row.guards is Array or row.guards.size() > 10: return {}
	for guard in row.guards:
		if not guard is Dictionary or not _point(guard.get("point")): return {}
		if not _number(guard.get("health"),0,1000) or not _integer(guard.get("seat"),0,3): return {}
		if guard.get("phase","") not in ["bank","car","post","board"]: return {}
	return row.duplicate(true)

static func valid_saved(value: Variant) -> bool:
	if not value is Dictionary or value.get("version",1) != 1: return false
	if not _integer(value.get("security_level",0),0,MAX_SECURITY): return false
	var previous: Variant = value.get("last_event","")
	if previous != "" and not _id(previous): return false
	var event: Variant = value.get("event",{})
	if not event is Dictionary: return false
	if event.is_empty(): return true
	var row := restore(event)
	if row.is_empty() or row.id != previous: return false
	return int(row.security_level) <= int(value.get("security_level",0))
