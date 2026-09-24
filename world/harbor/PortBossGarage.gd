extends Node2D
const VIEW = preload("res://world/mountain_pass/MountainStaticModelView.gd")
const VEHICLE_VIEW = preload("res://systems/interiors/InteriorVehiclePresentation.gd")
const ACTOR_VIEW = preload("res://systems/interiors/InteriorActorPresentation.gd")
const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
const SECURITY = preload("res://world/harbor/HarborPortSecurity.gd")
const EXTERIOR := Vector2(5515,5870)
const ORIGIN := Vector2(30600,20000)
const REWARD := 50000
var interior_id := &"port_boss_garage"
var inline_mode := true
var showroom: Node2D
var portal: Node2D
var spawn_point: Marker2D
var boss: CharacterBody2D
var cars: Array[CharacterBody2D] = []
var guards: Array[Node2D] = []
var presentations := {}
var actor_presentations := {}
var actor_ground_patches := {}
var alerted := false
var initialized := false
var active := false
var cooldown := 0.0
var checkpoint_clock := 0.0
var label: Label
var shutter_shape: CollisionPolygon2D
var _gate_open := false
var _alarm_timer: Timer
var inline_floor_polygon := PackedVector2Array()

static func is_open(hour: float) -> bool:
	return hour >= 1.0 and hour < 5.0

func data() -> Dictionary:
	var state: Dictionary = get_node("/root/CampaignState").salvage_state
	if not state.has("port_boss"):
		state.port_boss = {"status":"parked","alarm_remaining":-1.0,"police_called":false}
	if is_instance_valid(_alarm_timer) and not _alarm_timer.is_stopped():
		state.port_boss.alarm_remaining = _alarm_timer.time_left
	return state.port_boss

func player() -> CharacterBody2D:
	return get_tree().get_first_node_in_group("player") as CharacterBody2D

func actor() -> Node2D:
	var car: Node2D = get_node("/root/RegionTravel").controlled_car()
	return car if car != null else player()

func _ready() -> void:
	name = "PortBossGarage"
	position = Vector2(5295,5870)
	z_as_relative = false
	z_index = 6
	add_to_group("port_boss_garage")
	# The room is suspended after exit. Its pending security alarm must keep
	# counting down outside, while still respecting a paused game.
	_alarm_timer = Timer.new()
	_alarm_timer.name = "SecurityAlarm"
	_alarm_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_alarm_timer.one_shot = true
	_alarm_timer.timeout.connect(_dispatch_police)
	add_child(_alarm_timer)
	if not bool(data().police_called) and float(data().alarm_remaining) > 0:
		_resume_saved_alarm.call_deferred()
	portal = VIEW.new()
	add_child(portal)
	portal.build_view(preload("res://world/harbor/PortBossGaragePortal.gd"),25.0,20.0,Vector3.ZERO,Vector3(0,40,25),Vector2i(1000,800))
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	portal.add_child(body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(portal.model,body,portal.project_floor)
	shutter_shape = body.get_node("Shutter")
	preload("res://systems/interiors/ExteriorOcclusion.gd").attach(portal.sprite_3d,portal.project_floor(Vector2(0,8)).y)
	var hud := CanvasLayer.new()
	hud.layer = 23
	add_child(hud)
	label = Label.new()
	label.position = Vector2(28,115)
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",5)
	hud.add_child(label)
	label.hide()
	# The shutter opens by proximity during visiting hours; no entry marker or E action.

func build_interior() -> void:
	if showroom != null: return
	showroom = VIEW.new()
	add_child(showroom)
	showroom.build_view(preload("res://world/harbor/PortBossGarageArt.gd"),25.0,20.0,Vector3(0,.5,0),Vector3(0,40,25),Vector2i(1000,800))
	showroom.set_background_static_preparation_enabled(false)
	showroom.viewport_3d.msaa_3d = Viewport.MSAA_2X
	showroom.sprite_3d.hide()
	inline_floor_polygon = PackedVector2Array([
		showroom.project_floor(Vector2(-10.8,-7.9)),showroom.project_floor(Vector2(10.75,-7.9)),
		showroom.project_floor(Vector2(10.75,7.9)),showroom.project_floor(Vector2(-10.8,7.9))])
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	showroom.add_child(body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(showroom.model,body,showroom.project_floor)
	spawn_point = Marker2D.new()
	spawn_point.position = showroom.project_floor(Vector2(9.2,0))
	add_child(spawn_point)
	var ids := ["sedan_classic","sport_estate","porto_rosso","winter_suv_heavy","sport_coupe"]
	for i in 5:
		if i == 2 and String(data().status) != "parked": continue
		var car := FACTORY.spawn_parked_vehicle(self,"PortGarageCar%d" % i,showroom.project_floor(Vector2(-8+i*4,-4)),PI/2,ids[i],i)
		car.set_meta("port_boss_garage_stock",true)
		cars.append(car)
		if i == 2:
			boss = car
			boss.player_entered.connect(_on_boss_stolen)
		attach_car(car)
	for point in [Vector2(7.3,5.7),Vector2(-8,1)]:
		var guard := SECURITY.new()
		guard.checkpoint = self
		guard.position = showroom.project_floor(point)
		add_child(guard)
		# This garage's uniforms keep a human silhouette next to Dante; do not
		# change the shared police/security rig used elsewhere in the city.
		guard.model_root.scale = Vector3(.84,1.0,.90)
		guards.append(guard)
		attach_actor(guard)
	set_npc_rendering_active(active)

func attach_car(car: CharacterBody2D) -> void:
	if presentations.has(car): return
	car.ensure_presentation()
	var adapter := VEHICLE_VIEW.new()
	add_child(adapter)
	adapter.configure(car,showroom)
	presentations[car] = adapter

func attach_actor(person: CharacterBody2D) -> void:
	if actor_presentations.has(person):
		if person.has_meta("interior_actor_presentation"): return
		detach_actor(person)
	var adapter := ACTOR_VIEW.new()
	add_child(adapter)
	adapter.configure(person,showroom.camera_3d,showroom.sprite_3d)
	actor_presentations[person] = adapter
	var patches: Array = []
	for node in person.model_root.find_children("*","Node3D",true,false):
		if node.top_level:
			patches.append({"node":node,"transform":node.transform})
			node.top_level = false
			node.transform = patches[-1].transform
	actor_ground_patches[person] = patches

func detach_actor(person: Node2D) -> void:
	if not actor_presentations.has(person): return
	for patch in actor_ground_patches.get(person,[]):
		if is_instance_valid(patch.node):
			patch.node.top_level = true
			patch.node.transform = patch.transform
	actor_ground_patches.erase(person)
	actor_presentations[person].restore()
	actor_presentations[person].queue_free()
	actor_presentations.erase(person)

func detach_car(car: Node2D) -> void:
	if not presentations.has(car): return
	presentations[car].restore()
	presentations[car].queue_free()
	presentations.erase(car)

func contains_point(point: Vector2) -> bool:
	return is_instance_valid(showroom) and Geometry2D.is_point_in_polygon(showroom.to_local(point),inline_floor_polygon)

func get_camera_rect() -> Rect2:
	return Rect2(global_position-Vector2(245,195),Vector2(490,390))

func set_npc_rendering_active(value: bool) -> void:
	active = value
	if not value and player() != null: detach_actor(player())
	if showroom == null: return
	showroom.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	showroom.sprite_3d.visible = value
	for guard in guards:
		if is_instance_valid(guard) and contains_point(guard.global_position): guard.set_physics_process(value)

func enter() -> bool:
	var controlled := actor()
	if controlled == null or cooldown > 0 or not is_open(hour()) or controlled.global_position.distance_to(EXTERIOR)>100: return false
	build_interior()
	# Compatibility helper: the caller still has to walk or drive across the gate.
	_gate_open = true
	shutter_shape.set_deferred("disabled",true)
	portal.model.gate.position.y = 3.6
	return true

func leave() -> bool:
	var controlled := actor()
	if controlled == null or cooldown>0 or not contains_point(controlled.global_position): return false
	# The open gate remains the only route out. No instant relocation.
	_gate_open = true
	shutter_shape.set_deferred("disabled",true)
	portal.model.gate.position.y = 3.6
	return true

func _on_inline_enter(controlled: Node2D) -> void:
	active = true
	portal.sprite_3d.hide()
	set_npc_rendering_active(true)
	if controlled == player() and player().visible: attach_actor(player())
	elif controlled is CharacterBody2D: attach_car(controlled)
	player().set_meta("harbor_interior",true)
	player().set_meta("police_exterior_position",EXTERIOR)
	var cam := controlled.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.set_meta("compact_interior",get_camera_rect())
		cam.reset_smoothing()
	get_parent().get_parent().emit_signal("actor_entered_interior",controlled,interior_id)

func _on_inline_exit(controlled: Node2D) -> void:
	detach_actor(player())
	if controlled != player(): detach_car(controlled)
	player().remove_meta("harbor_interior")
	player().remove_meta("police_exterior_position")
	var cam := controlled.get_node_or_null("Camera") as Camera2D
	if cam: cam.remove_meta("compact_interior")
	if alerted:
		for i in guards.size():
			var guard := guards[i]
			if not is_instance_valid(guard) or guard.is_dead: continue
			detach_actor(guard)
			guard.global_position = EXTERIOR+Vector2(-55,(-1 if i==0 else 1)*34)
			guard.reset_physics_interpolation()
	set_npc_rendering_active(false)
	portal.sprite_3d.show()
	get_parent().get_parent().emit_signal("actor_returned_to_exterior",controlled,interior_id)
	capture_for_save()

func hour() -> float:
	var clock := get_tree().get_first_node_in_group("day_night_manager")
	return float(clock.time_of_day)*24.0 if clock else 12.0

func raise_alarm() -> void:
	if alerted: return
	alerted = true
	if not data().police_called:
		data().alarm_remaining = 15.0
		_alarm_timer.start(15.0)
	for guard in guards:
		if is_instance_valid(guard): guard.set_physics_process(true)

func _dispatch_police() -> void:
	if bool(data().police_called): return
	data().alarm_remaining = 0.0
	data().police_called = true
	var wanted := get_node("/root/WantedManager")
	wanted.report_crime(60)
	wanted.ensure_minimum_wanted_level(3)
	wanted.police_spawn_timer = 0

func _resume_saved_alarm() -> void:
	# Loading a saved district is not playable time. Resume even if the empty
	# room is suspended, but only after the real game has finished loading.
	var game := get_parent().get_parent().get_parent()
	while is_inside_tree() and game.get("gameplay_ready") != true:
		await get_tree().process_frame
	if is_inside_tree() and not bool(data().police_called) and float(data().alarm_remaining) > 0:
		_alarm_timer.start(float(data().alarm_remaining))

func _on_boss_stolen(_car: CharacterBody2D) -> void:
	if String(data().status) != "parked": return
	data().status = "stolen"
	raise_alarm()
	capture_for_save()

func capture_for_save() -> void:
	if not is_instance_valid(boss): return
	if String(data().status) in ["delivered","destroyed"]: return
	if boss.health <= 0:
		data().status = "destroyed"
		return
	if String(data().status) == "stolen":
		data().car = {"position":[boss.global_position.x,boss.global_position.y],"rotation":boss.global_rotation,"health":boss.health}

func _restore_boss() -> void:
	if String(data().status) in ["delivered","destroyed"]: return
	for car in get_tree().get_nodes_in_group("vehicle"):
		if car.get("active_archetype_id") == "porto_rosso":
			boss = car
			return
	var stored: Dictionary = get_node("/root/CampaignState").residence_state.get("stored_vehicle",{})
	if stored.get("archetype_id","") == "porto_rosso": return
	if String(data().status) != "stolen" or not data().has("car"): return
	var saved: Dictionary = data().car
	var p := Vector2(saved.position[0],saved.position[1])
	if Rect2(ORIGIN-Vector2(500,400),Vector2(1000,800)).has_point(p):
		build_interior()
		p = showroom.to_global(showroom.project_floor(Vector2(0,-2.0)))
		data().car.position = [p.x,p.y]
	if Rect2(global_position-Vector2(250,205),Vector2(500,410)).has_point(p): build_interior()
	boss = FACTORY.spawn_parked_vehicle(self,"PortoRossoRecovered",to_local(p),float(saved.rotation),"porto_rosso",2,Color("e01824"))
	boss.health = int(saved.health)
	if contains_point(p):
		build_interior()
		attach_car(boss)

func _process(delta: float) -> void:
	var p := player()
	if p == null: return
	var game := get_parent().get_parent().get_parent()
	if game.get("gameplay_ready") != true: return
	if not initialized:
		initialized = true
		_restore_boss()
		alerted = float(data().alarm_remaining)>0 or bool(data().police_called)
	cooldown = maxf(0,cooldown-delta)
	var controlled := actor()
	if controlled == null: return
	var near: bool = controlled.global_position.distance_to(EXTERIOR)<700
	if near and showroom == null: build_interior()
	var inside := contains_point(controlled.global_position)
	for car in presentations.keys():
		if not is_instance_valid(car):
			presentations[car].queue_free()
			presentations.erase(car)
		elif not contains_point(car.global_position): detach_car(car)
	var at_gate: bool = controlled.global_position.distance_to(EXTERIOR)<115
	var opened: bool = (is_open(hour()) and at_gate) or (inside and at_gate)
	if opened != _gate_open:
		_gate_open = opened
		shutter_shape.set_deferred("disabled",opened)
		portal.model.gate.position.y = 3.6 if opened else 1.15
		portal.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if inside and not active:
		_on_inline_enter(controlled)
	elif not inside and active:
		_on_inline_exit(controlled)
	if inside:
		if controlled != p:
			detach_actor(p)
			attach_car(controlled)
		elif p.visible and not p.is_control_disabled: attach_actor(p)
	if is_instance_valid(boss) and boss.is_driven_by_player and String(data().status)=="parked":
		data().status = "stolen"
		raise_alarm()
		capture_for_save()
	checkpoint_clock += delta
	if checkpoint_clock>0.25:
		checkpoint_clock=0
		if not is_instance_valid(boss) and String(data().status)=="stolen": _restore_boss()
		capture_for_save()
	label.visible = (at_gate and not is_open(hour())) or (alerted and not bool(data().police_called))
	if alerted and not bool(data().police_called):
		label.text = "SEGURANÇA ALERTADA • POLÍCIA EM %02ds" % ceili(float(data().alarm_remaining))
	else:
		label.text = "" if is_open(hour()) else "GARAGEM FECHADA • 01:00–05:00"

func _unhandled_input(event: InputEvent) -> void:
	pass

func _exit_tree() -> void:
	for adapter in presentations.values():
		if is_instance_valid(adapter): adapter.restore()
	for person in actor_presentations.keys():
		if is_instance_valid(person): detach_actor(person)
