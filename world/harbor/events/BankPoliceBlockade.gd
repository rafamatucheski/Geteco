extends Node2D
## Patrulhas entram pela avenida fora da câmera e ocupam pontos distintos diante do banco.
## O cerco usa a física, as portas e as duplas policiais existentes.
var room: Node2D
var entrance: Node2D
var slots: Array[Node2D] = []
var units: Array[Node2D] = []
var barriers: Array[Node2D] = []
var dispatch_clock := 0.0
var active := false
var escape_hint: Label

class Barricade extends StaticBody2D:
	func _ready() -> void:
		collision_layer=1
		collision_mask=0
		var shape := CollisionShape2D.new()
		shape.shape=RectangleShape2D.new()
		shape.shape.size=Vector2(38,8)
		add_child(shape)
		z_index=2
	func _draw() -> void:
		draw_rect(Rect2(-20,-3,40,9),Color(0.02,0.03,0.04,0.35))
		draw_rect(Rect2(-19,-7,38,8),Color("cbd1ce"))
		for x in [-14,0,14]: draw_line(Vector2(x-4,-7),Vector2(x+3,1),Color("325b79"),5)
		for x in [-14,14]: draw_line(Vector2(x,-1),Vector2(x,6),Color("414c51"),3)

func start(bank: Node2D, door: Node2D) -> void:
	room=bank
	entrance=door
	active=true
	room.actor.set_meta("bank_heist_active",true)
	for offset in [Vector2(-110,160),Vector2(105,200),Vector2(25,120)]:
		var slot := Node2D.new()
		add_child(slot)
		slot.global_position=entrance.global_position+offset
		slot.set_meta("police_search_position",true)
		slot.set_meta("bank_blockade",true)
		slot.set_meta("police_stop_distance",28.0)
		if slots.size()==2: slot.set_meta("bank_approach_position",entrance.global_position+Vector2(230,105))
		slots.append(slot)
	var wanted := get_node("/root/WantedManager")
	wanted.report_crime(60)
	wanted.police_spawn_timer=8.0
	var hud:=CanvasLayer.new()
	hud.layer=20
	add_child(hud)
	escape_hint=Label.new()
	escape_hint.size=Vector2(440,60)
	escape_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	escape_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	escape_hint.add_theme_font_size_override("font_size",18)
	escape_hint.add_theme_color_override("font_color",Color("f2d294"))
	escape_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	escape_hint.add_theme_constant_override("shadow_offset_x",2)
	escape_hint.add_theme_constant_override("shadow_offset_y",2)
	escape_hint.text="CERCO POLICIAL\nUse cobertura e abra caminho para sair do quarteirão."
	hud.add_child(escape_hint)
	escape_hint.hide()
	_dispatch_next()

func _dispatch_next() -> void:
	if units.size()>=slots.size(): return
	var spawn := _patrol_spawn()
	if spawn.is_empty():
		dispatch_clock=2.0
		return
	var pool := get_node("/root/EmergencyPool")
	var unit=pool.get_vehicle("police")
	if is_instance_valid(unit):
		unit.global_position=spawn.position
		unit.global_rotation=spawn.rotation
		unit.reset_physics_interpolation()
		unit.last_tracked_pos=unit.global_position
		unit.target=slots[units.size()]
		unit.set_meta("police_player_pursuit",false)
		unit.remove_meta("bank_barrier_built")
		units.append(unit)
	dispatch_clock=3.0

func _patrol_spawn() -> Dictionary:
	var camera:=get_viewport().get_camera_2d()
	var visible_rect:=Rect2()
	if camera:
		var size:=get_viewport_rect().size/camera.zoom
		visible_rect=Rect2(camera.get_screen_center_position()-size*.5,size).grow(100)
	for node in get_tree().get_nodes_in_group("unified_traffic_lane"):
		var lane:=node as Path2D
		if lane==null or not String(lane.get_meta("traffic_road_id","")).ends_with("/foundry_avenue"): continue
		if lane.get_meta("traffic_direction_name","")!="reverse": continue
		for distance in [700,900,1100,1300]:
			var offset:=lane.curve.get_closest_offset(lane.to_local(entrance.global_position+Vector2(distance,150)))
			var point:=lane.to_global(lane.curve.sample_baked(offset))
			if visible_rect.has_point(point): continue
			var next:=lane.to_global(lane.curve.sample_baked(minf(offset+10,lane.curve.get_baked_length())))
			var query:=PhysicsShapeQueryParameters2D.new()
			query.shape=RectangleShape2D.new()
			query.shape.size=Vector2(100,48)
			query.transform=Transform2D((next-point).angle(),point)
			query.collision_mask=1|2|4
			if get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
				return {"position":point,"rotation":(next-point).angle()}
	return {}

func is_ready() -> bool:
	var arrived := 0
	for unit in units:
		if is_instance_valid(unit) and unit.is_acting and unit.global_position.distance_to(entrance.global_position)<360: arrived+=1
	return arrived>=2

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(room) or not is_instance_valid(room.actor): return
	var player: Node2D=room.actor
	var wanted := get_node("/root/WantedManager")
	var inside: bool=room.actor_inside()
	escape_hint.hide()
	escape_hint.position=Vector2(get_viewport_rect().size.x*.5-220,145)
	if player.is_dead or player.is_arrested or (not inside and player.global_position.distance_to(entrance.global_position)>900):
		_release()
		return
	# Não perder estrelas enquanto o assaltante ainda está cercado no banco.
	wanted.time_hidden=0.0
	wanted.police_spawn_timer=maxf(wanted.police_spawn_timer,4.0)
	dispatch_clock-=delta
	if dispatch_clock<=0: _dispatch_next()
	for officer in get_tree().get_nodes_in_group("police_officer"):
		if not is_instance_valid(officer) or officer.is_dead or not officer.service_vehicle in units: continue
		if not officer.service_vehicle.target in slots: continue
		officer.target=officer.service_vehicle.target if inside else player
		if not inside: officer.response_aggression=12.0
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_acting or unit.has_meta("bank_barrier_built"): continue
		if not unit.target in slots: continue
		unit.set_meta("bank_barrier_built",true)
		var point: Vector2=unit.global_position+unit.transform.x*65
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape=RectangleShape2D.new()
		query.shape.size=Vector2(44,16)
		query.transform.origin=point
		query.collision_mask=1|2|4
		if not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		var barrier := Barricade.new()
		add_child(barrier)
		barrier.global_position=point
		barriers.append(barrier)

func _release() -> void:
	active=false
	if is_instance_valid(room) and is_instance_valid(room.actor): room.actor.remove_meta("bank_heist_active")
	var wanted := get_node("/root/WantedManager")
	for unit in units:
		if not is_instance_valid(unit): continue
		if not unit.target in slots: continue
		unit.remove_meta("bank_barrier_built")
		unit.set_meta("police_player_pursuit",true)
		unit.target=wanted.get_pursuit_target()
	for barrier in barriers:
		if is_instance_valid(barrier): barrier.queue_free()
	queue_free()
