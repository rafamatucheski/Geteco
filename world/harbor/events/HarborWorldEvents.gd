extends Node
## One finite city incident plus one funeral. Timers never depend on proximity.
const RESIDENT := preload("res://world/harbor/events/WorldEventResident.gd")
var rng := RandomNumberGenerator.new()
var next_event := 90.0
var next_funeral := 25.0
var event_age := 0.0
var incident: Node2D
var unit: Node2D
var victim: Node2D
var funeral_age := 0.0
var funeral_phase := "idle"
var guests: Array[Node2D] = []
var coffin: Polygon2D

func _ready() -> void:
	rng.randomize()
	next_event=rng.randf_range(65,110)
	next_funeral=rng.randf_range(25,55)

func _process(delta: float) -> void:
	if not get_parent().get("gameplay_ready"): return
	next_event-=delta
	next_funeral-=delta
	if next_funeral<=0 and funeral_phase=="idle": start_funeral()
	if funeral_phase!="idle": _tick_funeral(delta)
	if is_instance_valid(incident):
		event_age+=delta
		if event_age>150 or incident.get("is_dead")==true or incident.get("is_exploding")==false:
			end_incident()
	elif is_instance_valid(unit):
		end_incident()
	elif next_event<=0:
		start_incident("fire" if rng.randf()<.5 else "robbery")

func start_funeral() -> bool:
	if funeral_phase!="idle": return false
	var cemetery := get_parent().get_node("Cemetery") as Node2D
	funeral_phase="arriving"
	funeral_age=0
	for i in 5:
		var guest := RESIDENT.new()
		guest.coat_color=Color("343543") if i%2 else Color("45434b")
		guest.lines=[]
		guest.position=cemetery.get_gate_position()+Vector2((i%2)*12-6,-55-i*16)
		get_parent().add_child(guest)
		guest.set_route(PackedVector2Array([cemetery.get_gate_position(),cemetery.global_position+Vector2(0,65),cemetery.global_position+Vector2(-48+(i%2)*96,35+(i/2)*22)]))
		guests.append(guest)
	coffin=Polygon2D.new()
	coffin.polygon=PackedVector2Array([Vector2(-11,-24),Vector2(11,-24),Vector2(15,-15),Vector2(12,24),Vector2(-12,24),Vector2(-15,-15)])
	coffin.color=Color("694737")
	coffin.z_index=4
	coffin.position=cemetery.global_position+Vector2(0,45)
	get_parent().add_child(coffin)
	return true

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
			if is_instance_valid(guest): guest.set_route(PackedVector2Array([cemetery.global_position+Vector2(0,80),cemetery.global_position+Vector2(0,-330),cemetery.get_gate_position()+Vector2(0,-80)]))
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
	if is_instance_valid(incident): return false
	next_event=rng.randf_range(100,180)
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if not director: return false
	if kind=="fire":
		incident=preload("res://world/harbor/events/WorldFire.gd").new()
		incident.position=Vector2(2410,2110)
	else:
		incident=RESIDENT.new()
		incident.position=Vector2(845,1150)
		incident.travel_speed=85
		incident.lines.clear()
		incident.set_meta("ambient_crime",true)
	get_parent().add_child(incident)
	if kind!="fire":
		incident.set_route(PackedVector2Array([Vector2(1100,1150),Vector2(1190,1150),Vector2(1190,1600)]))
		victim=RESIDENT.new()
		victim.position=Vector2(820,1150)
		victim.lines.clear()
		get_parent().add_child(victim)
		victim.speech.text="Minha bolsa! Chamem a polícia!" if TranslationServer.get_locale().begins_with("pt") else "My bag! Call the police!"
		var bag:=Polygon2D.new()
		bag.polygon=PackedVector2Array([Vector2(-5,-4),Vector2(5,-4),Vector2(6,5),Vector2(-5,5)])
		bag.color=Color("915c35")
		bag.position=Vector2(10,-5)
		incident.add_child(bag)
	unit=director.request_dispatch("fire" if kind=="fire" else "police",incident,false)
	if not is_instance_valid(unit):
		incident.queue_free()
		if is_instance_valid(victim): victim.queue_free()
		incident=null
		return false
	unit.set_meta("ambient_response",true)
	event_age=0
	return true

func end_incident() -> void:
	if is_instance_valid(unit):
		unit.target=null
		if unit.type==0: unit._request_officers_return()
	if is_instance_valid(incident): incident.queue_free()
	if is_instance_valid(victim): victim.queue_free()
	victim=null
	incident=null
	unit=null
	event_age=0
	next_event=rng.randf_range(100,180)
