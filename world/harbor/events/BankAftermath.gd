extends Node
## Consequência persistente do assalto; a saída continua livre durante a fuga.
var room: Node2D
var closure: Node2D
var patrol: Node2D
var officers: Array[Node2D] = []
var closed := false
var _crime_guard := false

func _ready() -> void:
	get_node("/root/WantedManager").crime_reported.connect(_on_crime)
	if is_instance_valid(room.actor): room.actor.weapon_fired.connect(_on_shot)
	_sync.call_deferred()

func report_robbery() -> void:
	var state := get_node("/root/CampaignState")
	if state.bank_incident.is_empty(): state.bank_incident={"phase":"pending","elapsed_days":0.0}

func _process(_delta: float) -> void: _sync()

func _sync() -> void:
	if get_tree().current_scene and get_tree().current_scene.get("gameplay_ready")==false: return
	var state := get_node("/root/CampaignState")
	var data: Dictionary=state.bank_incident
	if data.get("phase","")=="pending" and not room.actor_inside():
		data["phase"]="closed"
	var should_close: bool=data.get("phase","")=="closed" and float(data.get("elapsed_days",0))<4.0
	if should_close and not closed: _close()
	if not should_close and (closed or data.get("phase","")=="closed"):
		_reopen()
		state.bank_incident.clear()
	if closed:
		room.entrance.enabled=false
		if float(data.get("elapsed_days",0))<3.0:
			if not is_instance_valid(patrol) and (not is_instance_valid(room.blockade) or not room.blockade.active): _post_patrol()
		else: _remove_patrol()

func _close() -> void:
	closed=true
	room.entrance.enabled=false
	room.entrance._set_door_open(false)
	closure=Node2D.new()
	closure.name="BankClosure"
	room.entrance.add_child(closure)
	closure.z_index=20
	var barrier := StaticBody2D.new()
	barrier.collision_layer=1
	barrier.collision_mask=0
	closure.add_child(barrier)
	var shape := CollisionShape2D.new()
	shape.shape=RectangleShape2D.new()
	shape.shape.size=Vector2(56,10)
	shape.position.y=-10
	barrier.add_child(shape)
	var tape := Polygon2D.new()
	tape.polygon=PackedVector2Array([Vector2(-38,-24),Vector2(38,-24),Vector2(38,-4),Vector2(-38,-4)])
	tape.color=Color("dbb64e")
	closure.add_child(tape)
	var label := Label.new()
	label.text="INTERDITADO"
	label.position=Vector2(-38,-22)
	label.size=Vector2(76,16)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",Color("17242c"))
	closure.add_child(label)
	for x in [-34,34]:
		var leg := Line2D.new()
		leg.points=PackedVector2Array([Vector2(x,-24),Vector2(x,3)])
		leg.width=3
		leg.default_color=Color("414c51")
		closure.add_child(leg)

func _post_patrol() -> void:
	var parking := Vector2.ZERO
	var available := false
	for offset in [Vector2(205,90),Vector2(125,110),Vector2(-150,90)]:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape=RectangleShape2D.new()
		query.shape.size=Vector2(94,48)
		query.transform.origin=room.entrance.global_position+offset
		query.collision_mask=1|2|4
		if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
			parking=query.transform.origin
			available=true
			break
	if not available: return
	patrol=load("res://EmergencyVehicle.tscn").instantiate()
	patrol.type=0
	patrol.position=parking
	get_tree().current_scene.add_child(patrol)
	patrol.activate()
	patrol.set_physics_process(false)
	patrol.siren_audio.stop()
	patrol.set_meta("bank_watch",true)
	patrol.reset_physics_interpolation()
	for side in [-1,1]:
		var officer := preload("res://world/harbor/events/BankWatchOfficer.gd").new()
		officer.post=self
		officer.position=patrol.global_position+Vector2(side*38,-34)
		officer.home=officer.position
		get_tree().current_scene.add_child(officer)
		officers.append(officer)

func _on_shot() -> void: _on_crime(1)
func _on_crime(severity: int) -> void:
	if severity<=0 or _crime_guard or not closed or not is_instance_valid(patrol): return
	var actor: Node2D=get_node("/root/WantedManager").get_pursuit_target()
	if not is_instance_valid(actor) or room.actor_inside() or actor.global_position.distance_to(room.entrance.global_position)>350: return
	for officer in officers:
		if is_instance_valid(officer): officer.respond(actor)
	_crime_guard=true
	get_node("/root/WantedManager").ensure_minimum_wanted_level(1)
	_crime_guard=false

func _remove_patrol(force := false) -> void:
	for officer in officers:
		if not is_instance_valid(officer): continue
		if officer.responding and not force:
			officer.post=null
		else: officer.queue_free()
	officers.clear()
	if is_instance_valid(patrol):
		if force: patrol.queue_free()
		else:
			var departure := patrol.create_tween()
			departure.tween_property(patrol,"modulate:a",0.0,1.0)
			departure.tween_callback(patrol.queue_free)
	patrol=null

func _reopen() -> void:
	closed=false
	room.entrance.enabled=true
	if is_instance_valid(closure): closure.queue_free()
	_remove_patrol()
	room.reset_after_investigation()

func _exit_tree() -> void:
	_remove_patrol(true)
	if is_instance_valid(closure): closure.queue_free()
