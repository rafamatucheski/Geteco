extends SceneTree
const MODEL = preload("res://runtime/cold/ThermalState.gd")
const ADAPTER = preload("res://runtime/ColdSurvival.gd")
const HEAT = preload("res://runtime/cold/OriginalHeatSources.gd")
var checks := 0
var errors: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message)
func close(a: float,b: float) -> bool: return absf(a-b)<.00001
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for hz in [10,30,60]:
		var model = MODEL.new()
		for i in 15*hz: model.tick(1.0/hz,{})
		check(close(model.temperature,100),"grace %s"%hz)
		for i in 15*hz: model.tick(1.0/hz,{})
		check(close(model.temperature,73.75),"integrated ramp %s"%hz)
		for i in 5*hz: model.tick(1.0/hz,{})
		check(close(model.temperature,56.25),"steady drain %s"%hz)
	for protection in [0.0,.15,.8,.9]:
		var model = MODEL.new()
		for i in 1800: model.tick(1.0/60,{"protection":protection,"intensity":1})
		check(close(model.temperature,100-5.5*(1-protection)*7.5),"outfit+storm %s"%protection)
	for pair in [[{"sheltered":true,"heat":true},15],[{"heat":true,"vehicle":true},35],[{"vehicle":true},20]]:
		var model = MODEL.new()
		model.temperature = 20
		model.exposure = 30
		model.tick(1,pair[0])
		check(close(model.temperature,20+pair[1]),"warming priority "+str(pair))
		check(close(model.exposure,28),"protected exposure recovery")
	var model = MODEL.new()
	model.temperature = 0
	model.exposure = 50
	var damage := 0
	for i in 60: damage += model.tick(1.0/60,{})
	check(damage==5,"hypothermia integer damage")
	model.tick(.1,{"vehicle":true})
	check(close(model.temperature,2) and model.damage_fraction==0,"warming stops damage")
	model.weather_clock = 119.25
	var resumed = MODEL.new()
	check(resumed.restore(model.snapshot()),"restore current")
	check(ADAPTER.validate_snapshot(JSON.parse_string(JSON.stringify(model.snapshot()))),"JSON numeric roundtrip")
	for i in 60:
		check(model.tick(1.0/60,{})==resumed.tick(1.0/60,{}),"save damage continuity")
	check(model.snapshot()==resumed.snapshot(),"save full continuity")
	for key in ["temperature","exposure","damage_fraction","weather_clock"]:
		for value in [NAN,INF,-1.0,"bad"]:
			var bad: Dictionary = model.snapshot()
			bad[key] = value
			check(not ADAPTER.validate_snapshot(bad),"reject invalid %s"%key)
	var before: Dictionary = resumed.snapshot()
	check(not resumed.restore({"version":2}) and resumed.snapshot()==before,"invalid restore atomic")
	check(resumed.restore({}) and resumed.temperature==100,"legacy absent cold defaults")
	for source in HEAT.SOURCES:
		var point := HEAT.to_world(source.point)
		check(HEAT.nearest(point).get("id")==source.id,"original heat source "+source.id)
		check(HEAT.nearest(point+Vector3(0,10,0)).is_empty(),"no heat across floors")
	var camp := HEAT.to_world(Vector2(5655,-990))
	check(not HEAT.nearest(camp+Vector3(13.74,0,0)).is_empty(),"effective V1 radius inside")
	check(HEAT.nearest(camp+Vector3(13.75,0,0)).is_empty(),"effective V1 radius strict boundary")
	check(HEAT.sheltered(HEAT.to_world(Vector2(5000,400))),"original tunnel shelter")
	check(not HEAT.sheltered(HEAT.to_world(Vector2(4900,400))),"outside tunnel exposed")
	check(HEAT.sheltered(HEAT.to_world(Vector2(5450,-1150))),"aircraft deck shelter")
	print("COLD_THERMAL checks=",checks," failures=",errors)
	quit(0 if errors.is_empty() else 1)
