extends Node3D
## Real illumination for the existing fittings; spatial lookup at 4 Hz.
## One reusable pool, no shadows or scans of the complete scene tree.
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const SOURCE_GROUP := &"city_local_light_source"
const CAPACITY := 6
const REACH := 50.0
var controller
var lights: Array[OmniLight3D] = []
var assignments: Dictionary = {}
var _elapsed := 0.0

func _ready() -> void:
	name = "CityLocalLighting"
	for index in CAPACITY:
		var light := OmniLight3D.new()
		light.name = "LocalLamp%d" % index
		light.shadow_enabled = false
		light.omni_attenuation = 1.35
		light.distance_fade_enabled = true
		light.distance_fade_begin = 30.0
		light.distance_fade_length = 20.0
		light.light_specular = .35
		light.visible = false
		add_child(light)
		lights.append(light)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .25: return
	_elapsed = 0.0
	refresh()

func refresh() -> void:
	var night := 0.0
	if controller != null and controller.session != null and is_instance_valid(controller.session.weather):
		if controller.state.place_id.is_empty() and controller.state.region_id == "harbor":
			night = 1.0-smoothstep(.25,.70,ATMOSPHERE.daylight_at(controller.session.weather.time_of_day))
	if night <= .01:
		apply_sources([],Vector3.ZERO,0.0)
		return
	var focus := ATMOSPHERE.focus_position(controller)
	apply_sources(nearby_sources(focus),focus,night)

func nearby_sources(focus: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in FRAGILE.query(focus,REACH):
		if item.kind != "lamp": continue
		var chunk = item.chunk.get_ref()
		if not is_instance_valid(chunk) or not chunk.is_visible_in_tree(): continue
		var point: Vector3 = item.point+Vector3(0,5.0,0)
		var pool: Dictionary = item.get("pool",{})
		if is_instance_valid(pool.get("multimesh")):
			var transform: Transform3D = pool.multimesh.get_instance_transform(pool.index)
			if transform.basis.x.length_squared()<.001: continue
			point = chunk.global_transform*transform.origin+Vector3(0,5.0,0)
		var id := "street:%s:%s" % [chunk.get_instance_id(),str(item.point)]
		result.append({"id":id,"point":point,"range":14.0,"energy":1.8,"color":Color("ffe4ba")})
	for source in get_tree().get_nodes_in_group(SOURCE_GROUP):
		if not source is Node3D or not source.is_visible_in_tree(): continue
		var item: Dictionary = source.get_meta("local_light",{})
		if item.is_empty(): continue
		var copy := item.duplicate()
		copy.id = "fitting:"+str(source.get_instance_id())
		copy.point = source.global_transform*item.get("offset",Vector3.ZERO)
		result.append(copy)
	return result

func apply_sources(sources: Array[Dictionary], focus: Vector3, night: float) -> void:
	var ranked: Array[Dictionary] = []
	if night > .01:
		for source in sources:
			var point: Vector3 = source.point
			var distance := Vector2(point.x-focus.x,point.z-focus.z).length()
			if distance >= REACH: continue
			var item := source.duplicate()
			item.distance = distance
			# Keep active fittings through small camera/player movements.
			item.score = distance-(4.0 if assignments.has(source.id) else 0.0)
			ranked.append(item)
	ranked.sort_custom(func(a,b): return a.score<b.score)
	var chosen: Array[Dictionary] = []
	for item in ranked:
		# Twin globes and duplicate chunk-edge entries share one real light.
		var duplicate := false
		for other in chosen:
			if (item.point as Vector3).distance_squared_to(other.point)<16.0: duplicate = true; break
		if duplicate: continue
		chosen.append(item)
		if chosen.size() == CAPACITY: break
	var ids: Array = chosen.map(func(item): return item.id)
	for id in assignments.keys():
		if id not in ids:
			lights[assignments[id]].visible = false
			assignments.erase(id)
	for item in chosen:
		if not assignments.has(item.id):
			for index in lights.size():
				if index not in assignments.values(): assignments[item.id] = index; break
		var light := lights[assignments[item.id]]
		light.global_position = item.point
		light.omni_range = item.get("range",14.0)
		light.light_color = item.get("color",Color("ffe4ba"))
		light.light_energy = item.get("energy",1.8)*night*(1.0-smoothstep(45.0,REACH,item.distance))
		light.visible = light.light_energy>.01
