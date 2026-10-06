extends RefCounted
## Catálogo de performance dos carros civis, medido por simulação e não lido da
## ficha: o deserto usa um motor com marchas, turbo e resistência do ar, enquanto o
## jogo base usa aceleração linear com teto (Vehicle.gd). A ficha dos dois não é
## comparável (o "max_speed" do deserto é teórico, de rotação máxima sem arrasto).
const FLEET := preload("res://runtime/FleetCatalog.gd")
const DESERT := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const DRIVETRAIN := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const STEP := 1.0/120.0
const HUNDRED_KMH := 100.0/3.6
const QUARTER_KM := 400.0
const SIM_SECONDS := 60.0
# Veículos de serviço e de carga têm papel próprio no mundo; não entram no tuning.
const EXCLUDED := ["american_dump_truck","american_tanker_truck","boxrunner","cargo_flatbed_truck",
	"courier_van","dock_delivery_van","medic_box","polar_van","police_cruiser","police_suv","police_transport",
	"port_forklift","rescue_pumper","route_city","snow_plow_truck","towmaster","army_tank",
	"bike_cruiser","bike_sport","bike_urban","bike_police"]
const CLASSES := [["S",80.0],["A",65.0],["B",50.0],["C",35.0],["D",0.0]]
static var _cache := {}

static func tunable_ids() -> Array:
	var ids: Array = DESERT.ids()
	for id in FLEET.all():
		if eligible(str(id)) and str(id) not in ids: ids.append(str(id))
	return ids

static func eligible(id: String) -> bool:
	if id in EXCLUDED: return false
	if id in DESERT.IDS: return true
	return FLEET.all().has(id)

## Mede 0-100 km/h, 400 m, velocidade final e devolve as notas 0-100.
## `parts` só tem efeito nos carros do deserto, que já têm motor completo.
static func measure(id: String, parts: Dictionary = {}) -> Dictionary:
	var key := id+"|"+JSON.stringify(parts)
	if _cache.has(key): return _cache[key]
	var spec := FLEET.spec(id)
	var run := _run_desert(id,parts) if id in DESERT.IDS else _run_linear(spec)
	run["braking"] = float(spec.get("braking",1000.0))
	run["turn_speed"] = float(spec.get("turn_speed",2.5))
	run["id"] = id
	run["label"] = str(spec.get("label",id))
	run["model"] = "motor" if id in DESERT.IDS else "linear"
	run.merge(_ratings(run),true)
	_cache[key] = run
	return run

static func _run_linear(spec: Dictionary) -> Dictionary:
	# Mesmas contas de Vehicle.gd: aceleração constante até o teto de velocidade.
	var vmax := clampf(float(spec.max_speed)/16.0,5.0,45.0)
	var a := clampf(float(spec.acceleration)/160.0,2.0,10.0)
	var quarter: float
	if vmax*vmax/(2.0*a) >= QUARTER_KM: quarter = sqrt(2.0*QUARTER_KM/a)
	else: quarter = vmax/a+(QUARTER_KM-vmax*vmax/(2.0*a))/vmax
	return {"zero_to_100":HUNDRED_KMH/a if vmax >= HUNDRED_KMH else INF, "quarter":quarter, "top_kmh":vmax*3.6}

static func _run_desert(id: String, parts: Dictionary) -> Dictionary:
	var d = DRIVETRAIN.new()
	d.configure(id,parts)
	d.stage(5.0,.5)
	d.launch()
	var t := 0.0
	var zero_to_100 := INF
	var quarter := INF
	while t < SIM_SECONDS:
		d.step(STEP,1.0,true)
		if d.rpm >= d.ideal_shift_rpm and d.gear < d.spec.gears.size(): d.shift_up()
		t += STEP
		if zero_to_100 == INF and d.speed_mps >= HUNDRED_KMH: zero_to_100 = t
		if quarter == INF and d.distance_m >= QUARTER_KM: quarter = t
	return {"zero_to_100":zero_to_100, "quarter":quarter, "top_kmh":d.speed_mps*3.6}

static func _scale(value: float, worst: float, best: float) -> float:
	return clampf((value-worst)/(best-worst),0.0,1.0)*100.0

static func _ratings(run: Dictionary) -> Dictionary:
	var quarter := float(run.quarter) if float(run.quarter) != INF else 40.0
	var r := {
		"rate_accel": _scale(quarter,30.0,15.0),
		"rate_speed": _scale(float(run.top_kmh),120.0,260.0),
		"rate_handling": _scale(float(run.turn_speed),1.8,3.7),
		"rate_braking": _scale(float(run.braking),700.0,1800.0)}
	r["score"] = .34*r.rate_accel+.30*r.rate_speed+.20*r.rate_handling+.16*r.rate_braking
	r["class"] = class_for(float(r.score))
	return r

static func class_for(score: float) -> String:
	for row in CLASSES:
		if score >= float(row[1]): return str(row[0])
	return "D"
