extends "res://world/harbor/interiors/HarborFireStationInterior.gd"

var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var actor_presentation: Node
var truck_presentations := {}
var _render_active := false
var inline_mode := false
var inline_facade: Node2D
var inline_entrances: Array[BuildingEntrance] = []
var inline_floor_polygon := PackedVector2Array()
var inline_gate_blockers: Array[CollisionPolygon2D] = []
var _inline_occupied := false
var _gate_amounts := [0.0,0.0,0.0]

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func _build_bay_lanes() -> void: pass

func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(room_view)
	if inline_mode:
		room_view.build_view(preload("res://world/harbor/interiors/FireStationCompactArt3D.gd"),17.0,20.0,Vector3(0,1,0),Vector3(0,20,18),Vector2i(800,667))
	else:
		room_view.build_view(preload("res://world/harbor/interiors/FireStationArt3D.gd"),30.0,32.0,Vector3(0,1,0),Vector3(0,18,15),Vector2i(1600,1100))
	if inline_mode: room_view.set_background_static_preparation_enabled(false)
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	super._setup_interior_content()
	for child in get_children():
		if child == room_view or child.name == "Blackout" or not child is Node2D: continue
		child.position = _legacy_point(child.position)
		if child is Polygon2D and child not in [heal_bar_bg,heal_bar_fill]: child.hide()
		if child is Line2D or child is PointLight2D: child.hide()
	for child in get_children():
		if child is Label and child not in [alarm_badge,heal_badge]: child.hide()
		elif child is Label: child.position = _legacy_point(child.position)
	for door in bay_exits:
		door.get_node("Facade").hide()
		door.custom_prompt_text = "E"
	if inline_mode:
		captain_npc.position = project_floor(Vector2(2.7,-4.7))
		alarm_area.position = project_floor(Vector2(-5.55,-4.2))
		heal_area.position = project_floor(Vector2(5.55,-4.2))
		alarm_badge.position = alarm_area.position+Vector2(-34,-42)
		heal_badge.position = heal_area.position+Vector2(-46,-43)
		for area in [alarm_area,heal_area]:
			var shape := area.get_child(0) as CollisionShape2D
			if shape and shape.shape is RectangleShape2D: (shape.shape as RectangleShape2D).size = Vector2(54,54)
		for truck in bay_trucks:
			var index := int(truck.get_meta("home_bay",1))
			truck.position = project_floor(Vector2(float(index-1)*4.5,-.4))
	# Pedestrians arrive beside the full-size truck, outside its projected hull.
	# Vehicles use the middle of their own bay, separately from this foot access.
	for index in bay_spawns.size():
		bay_spawns[index].position = project_floor(Vector2((index-1)*(4.5 if inline_mode else 6.875)+(1.25 if inline_mode else 1.95),4.5 if inline_mode else 5.2))
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedFireStationSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(room_view.model,walls_body,project_floor)
	if inline_mode:
		inline_floor_polygon = _project_rect(Rect2(-7.48,-6.58,14.96,13.25))
		for index in 3:
			var gate := CollisionPolygon2D.new()
			gate.name = "BayGate%d" % index
			gate.polygon = _project_rect(Rect2(float(index-1)*4.5-1.78,6.54,3.56,.16))
			walls_body.add_child(gate)
			inline_gate_blockers.append(gate)
		room_view.sprite_3d.hide()
	room_size = Vector2(310,220) if inline_mode else Vector2(940,650)
	set_meta("fixed_camera",true)

func _legacy_point(point: Vector2) -> Vector2:
	return project_floor(Vector2(point.x/(48.8889 if inline_mode else 32.0),point.y/(42.4242 if inline_mode else 28.0)))

func project_floor(point: Vector2) -> Vector2: return room_view.project_floor(point)

func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point),inline_floor_polygon)
	return super.contains_point(point)

func get_camera_rect() -> Rect2:
	if inline_mode: return Rect2(global_position-Vector2(166,126),Vector2(332,252))
	return super.get_camera_rect()

func attach_inline_facade(facade: Node2D, entrances: Array[BuildingEntrance]) -> void:
	inline_facade = facade
	inline_entrances = entrances
	global_position = entrances[1].global_position-project_floor(Vector2(0,6.6))
	z_as_relative = false
	z_index = 6
	for entrance in entrances:
		entrance.interior_available = false
		entrance.handle_input_locally = false
		entrance.show_entrance_marker = false
		entrance.show_interaction_prompt = false
	var old_body := facade.get_node_or_null("BuildingSolid") as StaticBody2D
	if old_body:
		old_body.collision_layer = 0
		old_body.queue_free()
	for truck in bay_trucks:
		if not is_instance_valid(truck): continue
		var camera := truck.get_node_or_null("Camera") as Camera2D
		if camera:
			camera.limit_left = -100000
			camera.limit_top = -100000
			camera.limit_right = 100000
			camera.limit_bottom = 100000

func _update_inline_access(delta: float) -> void:
	if not is_instance_valid(inline_facade) or inline_entrances.size()!=3: return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player): return
	var controlled := get_node("/root/RegionTravel").controlled_car() as Node2D
	if not is_instance_valid(controlled): controlled = player
	var available: bool = controlled.visible and controlled.get("is_dead") != true
	var inside: bool = available and contains_point(controlled.global_position)
	for index in 3:
		var entrance := inline_entrances[index]
		var near: bool = available and controlled.global_position.distance_to(entrance.global_position)<86.0
		if near:
			entrance._away_time = 0.0
			if not entrance._door_open: entrance.open_door()
		var amount: float = move_toward(_gate_amounts[index],1.0 if near and entrance._door_open else 0.0,delta/.5)
		if not is_equal_approx(amount,_gate_amounts[index]):
			_gate_amounts[index] = amount
			room_view.model.call("set_gate_amount",index,amount)
			inline_gate_blockers[index].set_deferred("disabled",amount>=.6)
			room_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if inside else SubViewport.UPDATE_ONCE
	if inside and not _inline_occupied:
		_inline_occupied = true
		inline_facade.set("inline_cutaway",true)
		inline_facade.queue_redraw()
		for entrance in inline_entrances: entrance.get_node("Facade").hide()
		room_view.model.call("set_cutaway_occupied",true)
		room_view.sprite_3d.show()
		set_npc_rendering_active(true)
		player.set_meta("harbor_interior",true)
		player.set_meta("police_exterior_position",inline_entrances[1].global_position)
		var camera := controlled.get_node_or_null("Camera") as Camera2D
		if camera:
			camera.set_meta("compact_interior",get_camera_rect())
			camera.reset_smoothing()
		if controlled==player: on_actor_entered(player)
		get_parent().get_parent().emit_signal("actor_entered_interior",controlled,interior_id)
	elif not inside and _inline_occupied:
		_inline_occupied = false
		inline_facade.set("inline_cutaway",false)
		inline_facade.queue_redraw()
		for entrance in inline_entrances: entrance.get_node("Facade").show()
		room_view.model.call("set_cutaway_occupied",false)
		room_view.sprite_3d.hide()
		set_npc_rendering_active(false)
		player.remove_meta("harbor_interior")
		player.remove_meta("police_exterior_position")
		var camera := controlled.get_node_or_null("Camera") as Camera2D
		if camera: camera.remove_meta("compact_interior")
		get_parent().get_parent().emit_signal("actor_returned_to_exterior",controlled,interior_id)

func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])

func _build_three_bay_doors() -> void:
	if not inline_mode:
		super._build_three_bay_doors()
		return
	for index in 3:
		var marker := Marker2D.new()
		marker.name = "SpawnPoint%d" % index
		marker.position = Vector2(float(index-1)*220,150)
		add_child(marker)
		bay_spawns.append(marker)
	spawn_point = bay_spawns[1]

func get_entry_position(actor: Node2D, marker: Marker2D) -> Vector2:
	if not actor.is_in_group("vehicle"): return marker.global_position
	var index := int(actor.get_meta("home_bay",bay_spawns.find(marker)))
	index = clampi(index,0,2)
	return to_global(project_floor(Vector2((index-1)*6.875,1.1)))

func orient_actor_on_entry(actor: Node2D) -> void:
	if actor.is_in_group("vehicle"): actor.rotation = PI*.5

func _on_actor_entered_interior(actor: Node2D, entered_id: StringName) -> void:
	if inline_mode: return
	if entered_id != interior_id or not is_instance_valid(actor) or not actor.has_meta("home_bay"): return
	if actor.get_parent()!=self: actor.reparent(self,true)
	actor.global_position = get_entry_position(actor,spawn_point)
	actor.rotation = PI*.5
	if "velocity" in actor: actor.velocity = Vector2.ZERO

func on_actor_entered(actor: Node2D) -> void:
	if actor.is_in_group("vehicle"): return
	if is_instance_valid(actor_presentation): actor_presentation.restore(); actor_presentation.queue_free()
	actor_presentation = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	add_child(actor_presentation)
	actor_presentation.configure(actor,camera_3d,sprite_3d)

func set_npc_rendering_active(active: bool) -> void:
	if inline_mode and active and is_instance_valid(captain_npc): captain_npc.show()
	if inline_mode and active:
		for truck in bay_trucks:
			if is_instance_valid(truck) and contains_point(truck.global_position): truck.show()
	super.set_npc_rendering_active(active)
	_render_active = active
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		if inline_mode and is_instance_valid(captain_npc): captain_npc.hide()
		if is_instance_valid(actor_presentation): actor_presentation.restore(); actor_presentation.queue_free()
		actor_presentation = null
		for helper in truck_presentations.values():
			if is_instance_valid(helper): helper.restore(); helper.queue_free()
		truck_presentations.clear()
		if inline_mode:
			for truck in bay_trucks:
				if is_instance_valid(truck) and contains_point(truck.global_position):
					truck.hide()
					if truck.get("body_viewport") is SubViewport: truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else: _sync_trucks()

func _sync_trucks() -> void:
	for truck in truck_presentations.keys():
		if not is_instance_valid(truck) or not contains_point(truck.global_position):
			var helper: Node = truck_presentations[truck]
			if is_instance_valid(helper): helper.restore(); helper.queue_free()
			truck_presentations.erase(truck)
	for truck in bay_trucks:
		if not is_instance_valid(truck) or not contains_point(truck.global_position) or truck_presentations.has(truck): continue
		var helper := preload("res://systems/interiors/InteriorVehiclePresentation.gd").new()
		add_child(helper)
		helper.configure(truck,room_view)
		truck_presentations[truck] = helper

func _process(delta: float) -> void:
	if inline_mode: _update_inline_access(delta)
	if not _render_active: return
	_sync_trucks()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(player) and player.visible and not player.get("is_control_disabled") and not player.get("is_dead") and contains_point(player.global_position) and not player.has_meta("interior_actor_presentation"):
		on_actor_entered(player)

func _exit_tree() -> void:
	if is_instance_valid(actor_presentation): actor_presentation.restore()
	for helper in truck_presentations.values():
		if is_instance_valid(helper): helper.restore()
