extends Node
## One finite city incident plus one funeral. Timers never depend on proximity.
const RESIDENT := preload("res://world/harbor/events/WorldEventResident.gd")
const STREET_ROBBERY := preload("res://world/harbor/events/HarborStreetRobbery.gd")
var rng := RandomNumberGenerator.new()
var next_funeral := 25.0
var event_age := 0.0
var incident: Node2D = null
var unit: Node2D = null
var victim: Node2D = null
var funeral_age := 0.0
var funeral_phase := "idle"
var guests: Array[Node2D] = []
var coffin: Polygon2D
var street_incident: Node2D
var robbery_cooldown := 45.0
var calm_area_cooldown := 180.0
var _robbery_probe := 0.0

func _ready() -> void:
	rng.randomize()
	next_funeral=rng.randf_range(25,55)

func _process(delta: float) -> void:
	if not get_parent().get("gameplay_ready"): return
	robbery_cooldown = maxf(0,robbery_cooldown-delta)
	calm_area_cooldown = maxf(0,calm_area_cooldown-delta)
	if is_instance_valid(street_incident):
		street_incident.tick(delta)
		if street_incident.complete: end_incident()
	else:
		_robbery_probe -= delta
		if _robbery_probe <= 0:
			_robbery_probe = 5
			_try_neighborhood_robbery()
	next_funeral-=delta
	if next_funeral<=0 and funeral_phase=="idle": start_funeral()
	if funeral_phase!="idle": _tick_funeral(delta)
	if is_instance_valid(incident):
		event_age+=delta
		if event_age>150 or incident.get("is_dead")==true or incident.get("is_exploding")==false:
			end_incident()
	elif is_instance_valid(unit):
		end_incident()

func _try_neighborhood_robbery() -> void:
	if robbery_cooldown>0 or is_instance_valid(incident) or is_instance_valid(street_incident): return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player): return
	var wanted := get_node_or_null("/root/WantedManager")
	if wanted and wanted.current_stars>0: return
	var territory := get_parent().get_node_or_null("CobraTerritory")
	if territory and (territory.get("_encounter_active")==true or territory.get("state")!="calm"): return
	for candidate in STREET_ROBBERY.SITES:
		if not candidate.hotspot and calm_area_cooldown>0: continue
		var distance := player.global_position.distance_to(candidate.point)
		if distance<440 or distance>1050: continue
		# Introduce all three on foot beyond immediate personal space.
		var clear := true
		for offset in [-285,-145,105]:
			var spawn: Vector2 = candidate.point+candidate.axis*offset
			if player.global_position.distance_to(spawn)<320 or _point_on_screen(spawn): clear=false
		if clear:
			start_street_robbery(candidate)
			return

func _point_on_screen(point: Vector2) -> bool:
	var screen := get_viewport().get_canvas_transform()*point
	return get_viewport().get_visible_rect().grow(90).has_point(screen)

func start_street_robbery(site: Dictionary = STREET_ROBBERY.SITES[0]) -> bool:
	if is_instance_valid(incident) or is_instance_valid(street_incident): return false
	street_incident = STREET_ROBBERY.new()
	street_incident.name = "StreetRobbery"
	street_incident.site = site
	get_parent().add_child(street_incident)
	robbery_cooldown = rng.randf_range(180,300)
	if not site.hotspot: calm_area_cooldown = rng.randf_range(480,720)
	return true

func start_funeral() -> bool:
	if funeral_phase!="idle": return false
	var cemetery := get_parent().get_node("Cemetery") as Node2D
	funeral_phase="arriving"
	funeral_age=0
	coffin=Polygon2D.new()
	coffin.polygon=PackedVector2Array([Vector2(-11,-24),Vector2(11,-24),Vector2(15,-15),Vector2(12,24),Vector2(-12,24),Vector2(-15,-15)])
	coffin.color=Color("694737")
	coffin.z_index=4
	coffin.position=cemetery.global_position+Vector2(0,45)
	get_parent().add_child(coffin)
	_spawn_funeral_guests_staggered(cemetery)
	return true

func _spawn_funeral_guests_staggered(cemetery: Node2D) -> void:
	for i in 5:
		if not is_inside_tree() or funeral_phase != "arriving": return
		var guest := RESIDENT.new()
		var lane_x := -14.0 if i % 2 == 0 else 14.0
		var row := i / 2
		guest.coat_color=Color("343543") if i%2 else Color("45434b")
		guest.lines=[]
		guest.position=cemetery.get_gate_position()+Vector2(0,24+i*28)
		guest.set_meta("funeral_lane_x", lane_x)
		get_parent().add_child(guest)
		guest.set_route(PackedVector2Array([
			cemetery.global_position+Vector2(lane_x,-288+i*28),
			cemetery.global_position+Vector2(lane_x,65),
			cemetery.global_position+Vector2(-60+(i%2)*120,30+row*32)
		]))
		guests.append(guest)
		await get_tree().process_frame

func _tick_funeral(delta: float) -> void:
	funeral_age+=delta
	var cemetery := get_parent().get_node("Cemetery") as Node2D
	if funeral_phase=="arriving":
		var arrived := true
		for guest in guests:
			if is_instance_valid(guest) and not guest.finished and not guest.is_dead: arrived=false
		if arrived or funeral_age>40:
			funeral_phase="ceremony"
			funeral_age=0
	elif funeral_phase=="ceremony" and funeral_age>25:
		funeral_phase="leaving"
		funeral_age=0
		if is_instance_valid(coffin): coffin.hide()
		for guest in guests:
			if is_instance_valid(guest):
				var lane_x := float(guest.get_meta("funeral_lane_x", 0.0))
				guest.set_route(PackedVector2Array([
					cemetery.global_position+Vector2(lane_x,105),
					cemetery.global_position+Vector2(lane_x,-260),
					cemetery.global_position+Vector2(0,-300),
					cemetery.get_gate_position()+Vector2(0,-18)
				]))
	elif funeral_phase=="leaving":
		var left := true
		for guest in guests:
			if is_instance_valid(guest) and not guest.finished and not guest.is_dead: left=false
		if left or funeral_age>45:
			for guest in guests:
				if is_instance_valid(guest): guest.queue_free()
			guests.clear()
			if is_instance_valid(coffin): coffin.queue_free()
			funeral_phase="idle"
			next_funeral=rng.randf_range(180,320)

func start_incident(kind: String) -> bool:
	if kind=="robbery": return start_street_robbery()
	if is_instance_valid(incident) or is_instance_valid(street_incident): return false
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if not director: return false
	incident=preload("res://world/harbor/events/WorldFire.gd").new()
	incident.position=Vector2(2410,2110)
	get_parent().add_child(incident)
	unit=director.request_dispatch("fire",incident,false)
	if not is_instance_valid(unit):
		incident.queue_free()
		if is_instance_valid(victim): victim.queue_free()
		incident=null
		return false
	unit.set_meta("ambient_response",true)
	event_age=0
	return true

func end_incident() -> void:
	if is_instance_valid(street_incident):
		street_incident.queue_free()
		street_incident=null
		robbery_cooldown=rng.randf_range(180,300)
	if is_instance_valid(unit):
		unit.target=null
		if unit.type==0: unit._request_officers_return()
	if is_instance_valid(incident): incident.queue_free()
	if is_instance_valid(victim): victim.queue_free()
	victim=null
	incident=null
	unit=null
	event_age=0
