extends RefCounted
## Uma carga por recibo; o estado e a carteira viajam no mesmo snapshot da sessão.
const KEY := "desert_cargo_heist"
const DROP_POINT := Vector3(-650,0,-1510)
const START := Vector3(-1080,.08,-1537.5)
const END := Vector3(260,.08,-1537.5)
const PHASES := ["driving","intercepted","stolen","opened","looted","destroyed","departed"]

static func is_departure_time(time: float) -> bool:
	return is_finite(time) and time >= 0.0 and time < 5.0/24.0

static func initial(day: int, slot: int) -> Dictionary:
	return {"version":1,"day":day,"slot":slot,"phase":"driving","distance":0.0,"region":"desert",
		"position":[START.x,START.y,START.z],"yaw":-PI*.5,"health":900.0,
		"guards":[{"health":80.0,"armor":100.0,"dead":false},{"health":80.0,"armor":100.0,"dead":false}]}

static func receipt(data: Dictionary) -> String:
	return "desert_cargo:%d:%d"%[int(data.day),int(data.slot)]

static func reward(data: Dictionary) -> int:
	return 4500 if int(data.slot)==0 else 7200

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["version","day","slot","phase","distance","position","yaw","health","guards"]:
		if not value.has(key): return false
	for key in ["version","day","slot"]:
		if not _number(value[key]) or float(value[key])!=floorf(float(value[key])): return false
	if int(value.version)!=1 or int(value.day)<0 or int(value.slot) not in [0,1] or value.phase not in PHASES: return false
	if value.get("region","desert") not in ["harbor","mountain","desert"]: return false
	if not _number(value.distance) or value.distance<0 or value.distance>START.distance_to(END): return false
	if not _number(value.yaw) or not _number(value.health) or value.health<0 or value.health>900: return false
	if not value.position is Array or value.position.size()!=3: return false
	for coordinate in value.position:
		if not _number(coordinate) or absf(float(coordinate))>100000: return false
	if not value.guards is Array or value.guards.size()!=2: return false
	for guard in value.guards:
		if not guard is Dictionary or not guard.has_all(["health","armor","dead"]): return false
		if not _number(guard.health) or guard.health<0 or guard.health>80: return false
		if not _number(guard.armor) or guard.armor<0 or guard.armor>100 or not guard.dead is bool: return false
		if guard.dead != (guard.health<=0): return false
		if guard.has("position"):
			if not guard.position is Array or guard.position.size()!=3: return false
			for coordinate in guard.position:
				if not _number(coordinate) or absf(float(coordinate))>100000: return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
