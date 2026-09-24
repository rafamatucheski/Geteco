extends RefCounted
## Numerical rules from V1 ColdSurvivalController; no scene or player dependencies.
const PROTECTION := {"dante_ski":.9,"dante_arctic":.8,"dante_trench":.6,"dante_lumberjack":.35,"dante_classic":.15,"dante_suit":.1,"dante_cowboy":.1,"dante_madmax":.1,"dante_ghillie":.25}
var temperature := 100.0
var exposure := 0.0
var damage_fraction := 0.0
var weather_clock := 0.0
static func integral(seconds: float) -> float:
	var t := maxf(0,seconds-15.0)
	return t*t/30.0 if t<15 else t-7.5
static func weather_intensity(clock: float) -> float:
	return weather_front(clock)*(.86+.14*sin(clock*.19))
static func weather_front(clock: float) -> float:
	var phase := fposmod(clock,240.0)/240.0
	return smoothstep(.16,.40,phase)*(1.0-smoothstep(.67,.92,phase))
static func weather_sample(clock: float) -> Dictionary:
	var phase := fposmod(clock,240.0)/240.0
	var front := weather_front(clock)
	var storm_state := 0
	if front > .08: storm_state = 1
	if front > .65: storm_state = 2
	if front > .92 and phase < .60: storm_state = 3
	return {"phase":phase,"front":front,"intensity":front*(.86+.14*sin(clock*.19)),"state":storm_state}
func tick(delta: float, context: Dictionary) -> int:
	if delta <= 0 or not is_finite(delta): return 0
	var sheltered: bool = context.get("sheltered",false)
	var heat: bool = context.get("heat",false)
	var vehicle: bool = context.get("vehicle",false)
	var previous := exposure
	var exposed := not sheltered and not heat and not vehicle
	exposure = exposure+delta if exposed else maxf(0,exposure-delta*2)
	var drain_seconds := integral(exposure)-integral(previous) if exposed else 0.0
	if sheltered: temperature = minf(100,temperature+15*delta)
	elif heat: temperature = minf(100,temperature+35*delta)
	elif vehicle: temperature = minf(100,temperature+20*delta)
	else:
		var protection := clampf(float(context.get("protection",0)),0,1)
		var intensity := clampf(float(context.get("intensity",0)),0,1)
		temperature = maxf(0,temperature-(3.5+2*intensity)*(1-protection)*drain_seconds)
	if temperature > 0:
		damage_fraction = 0
		return 0
	damage_fraction += 5*delta
	var damage := int(damage_fraction+0.000000001)
	damage_fraction = maxf(0,damage_fraction-damage)
	return damage
func snapshot() -> Dictionary:
	return {"version":1,"temperature":temperature,"exposure":exposure,"damage_fraction":damage_fraction,"weather_clock":weather_clock}
static func validate_snapshot(data: Dictionary) -> bool:
	if data.is_empty(): return true
	if typeof(data.get("version")) not in [TYPE_INT,TYPE_FLOAT] or data.version != 1: return false
	for key in ["temperature","exposure","damage_fraction","weather_clock"]:
		if typeof(data.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])): return false
	if data.temperature<0 or data.temperature>100 or data.exposure<0 or data.exposure>315360000: return false
	if data.damage_fraction<0 or data.damage_fraction>=1 or data.weather_clock<0 or data.weather_clock>=240: return false
	if data.temperature>0 and data.damage_fraction!=0: return false
	return true
func restore(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	temperature = float(data.get("temperature",100))
	exposure = float(data.get("exposure",0))
	damage_fraction = float(data.get("damage_fraction",0))
	weather_clock = float(data.get("weather_clock",0))
	return true
