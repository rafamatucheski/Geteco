extends Node
## Session adapter; root owns installation, persistent world.cold and HUD presentation.
const THERMAL = preload("res://runtime/cold/ThermalState.gd")
const SOURCES = preload("res://runtime/cold/OriginalHeatSources.gd")
const CONNECTION = preload("res://world/regions/WorldConnection3D.gd")
signal temperature_changed(current: float, maximum: float)
signal hypothermia_started
signal hypothermia_ended
var session
var model = THERMAL.new()
var context: Dictionary = {}
var _hypothermic := false
var active := true
var _in_cold_zone := false
var presentation: Node3D
func configure(owner_session) -> void:
	session = owner_session
	if not is_instance_valid(presentation):
		presentation = preload("res://runtime/cold/HeatPresentation.gd").new()
		add_child(presentation)
func _process(delta: float) -> void:
	if not active or not is_instance_valid(session) or not session.ready_for_play: return
	var point: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied else session.world.player.global_position
	presentation.update_sources(delta,point,session.state.region_id=="mountain" and session.state.place_id.is_empty())
	if session.state.region_id != "mountain": return # V1 pauses its controller in Harbor.
	var gameplay = session.world.gameplay
	if gameplay.health<=0: return
	model.weather_clock = fposmod(model.weather_clock+delta,240)
	if not _cold_zone_active():
		context.clear()
		model.exposure = 0.0
		return
	context = sample_context()
	var previous: float = model.temperature
	var damage: int = model.tick(delta,context)
	if damage>0:
		if gameplay.has_method("damage_environment"): gameplay.damage_environment(damage)
		else: push_error("ColdSurvival requires Gameplay.damage_environment; armor must not absorb cold")
	if previous != model.temperature: temperature_changed.emit(model.temperature,100)
	var hypothermic: bool = model.temperature<=0
	if hypothermic != _hypothermic:
		_hypothermic = hypothermic
		if hypothermic: hypothermia_started.emit()
		else: hypothermia_ended.emit()
func sample_context() -> Dictionary:
	var world = session.world
	var driving: bool = world.driving.occupied
	var point: Vector3 = world.driving.car.global_position if driving else world.player.global_position
	var sheltered: bool = not session.state.place_id.is_empty() or SOURCES.sheltered(point) or world.player.get_meta("mountain_shelter",false)
	var heat := SOURCES.nearest(point) if not sheltered else {}
	var outfit: String = session.state.economy.outfit
	if session.mountain_progression != null and session.mountain_progression.data.rental: outfit = "dante_ski"
	return {"sheltered":sheltered,"vehicle":driving,"heat":not heat.is_empty(),"heat_id":heat.get("id",""),"protection":THERMAL.PROTECTION.get(outfit,0.0),"intensity":THERMAL.weather_intensity(model.weather_clock)}
func snapshot() -> Dictionary: return model.snapshot()
func weather_sample() -> Dictionary: return THERMAL.weather_sample(model.weather_clock)
static func validate_snapshot(data: Dictionary) -> bool: return THERMAL.validate_snapshot(data)
func restore(data: Dictionary) -> bool:
	if not model.restore(data): return false
	_hypothermic = model.temperature<=0
	_in_cold_zone = false
	return true
func _cold_zone_active() -> bool:
	if not is_instance_valid(session) or session.state.region_id != "mountain":
		_in_cold_zone = false
		return false
	if not session.state.place_id.is_empty(): return true
	var point: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied else session.world.player.global_position
	var weight := CONNECTION.mountain_weight(point)
	# Both thresholds are on land. Walking back and forth at entry cannot flicker the HUD.
	_in_cold_zone = weight > (0.10 if _in_cold_zone else 0.25)
	return _in_cold_zone
func status() -> Dictionary:
	var visible := _cold_zone_active()
	var key := "sheltered" if context.get("sheltered",false) else "heat" if context.get("heat",false) else "vehicle" if context.get("vehicle",false) else "grace" if model.exposure<=15 else "exposed"
	if model.temperature<=0: key = "hypothermia"
	var text: String = {"sheltered":"Aquecendo no abrigo","heat":"Aquecendo junto ao fogo","vehicle":"Aquecendo no veículo","grace":"Frio intenso","exposed":"Perdendo calor","hypothermia":"Hipotermia"}[key]
	if key == "hypothermia": text = "Hipotermia: perdendo vida"
	if key in ["grace", "exposed", "hypothermia"]:
		text += "\nAqueça-se no abrigo, fogo ou veículo."
		text += "\nRoupa: %d%% de proteção ao frio" % roundi(float(context.get("protection", 0.0)) * 100.0)
	return {"visible":visible,"key":key,"text":text,"temperature":model.temperature,"maximum":100,"exposure":model.exposure,"heat_id":context.get("heat_id","")}

func recover_after_rescue() -> void:
	# V2 continuity improvement requested by integration: avoid a rescue/death loop.
	model.temperature = 100
	model.exposure = 0
	model.damage_fraction = 0
	if _hypothermic:
		_hypothermic = false
		hypothermia_ended.emit()
	temperature_changed.emit(100,100)

func prepare_collision_at(point: Vector3) -> bool:
	# Admission is only allowed after the physics server has seen newly spawned solids.
	if not is_instance_valid(session) or session.state.region_id!="mountain": return true
	if not point.is_finite() or not is_instance_valid(presentation) or not presentation.is_inside_tree(): return false
	# Reconcile providers synchronously: a streamed source may have appeared or
	# disappeared since the last quarter-second presentation update.
	presentation.elapsed = 1
	presentation.update_sources(1,point,true,true,8.0)
	var local_ready := true
	for source in SOURCES.SOURCES:
		if SOURCES.to_world(source.point).distance_squared_to(point)>64: continue
		if not presentation.visuals.has(source.id) or not is_instance_valid(presentation.visuals[source.id]):
			local_ready = false
		elif int(presentation.visuals[source.id].get_meta("thermal_created_frame",-1))>=Engine.get_physics_frames():
			local_ready = false
	return local_ready
