extends "res://world/harbor/interiors/HarborClinicInterior.gd"
## Native hospital architecture with the existing clinic dialogue contracts.
var health_pickup: Area2D
var view: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var model: Node3D
var actor_scale: Node
var inline_mode := false
var inline_facade: Node2D
var inline_entrance: BuildingEntrance
var inline_floor_polygon := PackedVector2Array()
var inline_door_blocker: CollisionPolygon2D
var _inline_occupied := false
var _inline_door_amount := 0.0
var camera_3d: Camera3D:
	get: return room_camera
var sprite_3d: Sprite2D:
	get: return room_display
var _last_door_amount := 0.0
const SCALE := .55
func _init() -> void:
	interior_id=&"clinic"
	display_name="BAY MEDICAL"
	room_size=Vector2(650,470)
	entrance_north=false
	set_meta("fixed_camera",true)
func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func _setup_interior_content() -> void:
	view=SubViewport.new()
	view.size=Vector2i(800,667) if inline_mode else Vector2i(1440,1040)
	view.transparent_bg=true
	view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(view)
	model=preload("res://world/harbor/interiors/HospitalRoom3D.gd").new()
	model.compact_mode=inline_mode
	view.add_child(model)
	room_camera=Camera3D.new()
	view.add_child(room_camera)
	room_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size=12.0 if inline_mode else 22.0
	if inline_mode:
		room_camera.look_at_from_position(Vector3(0,24,20),Vector3(0,1.1,0))
	else:
		room_camera.look_at_from_position(Vector3(0,18,15),Vector3.ZERO)
	room_camera.current=true
	room_camera.force_update_transform()
	room_camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.reset_physics_interpolation()
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-65,-25,0)
	sun.light_energy=.8
	sun.shadow_enabled=true
	view.add_child(sun)
	var env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("d6e7ee")
	env.environment.ambient_light_energy=.32
	view.add_child(env)
	room_display=Sprite2D.new()
	room_display.texture=view.get_texture()
	var unit_x: float = room_camera.unproject_position(Vector3.RIGHT).distance_to(room_camera.unproject_position(Vector3.ZERO))
	room_display.scale=Vector2.ONE*(20.0/unit_x) if inline_mode else Vector2.ONE*SCALE
	if inline_mode:
		room_display.position=-(room_camera.unproject_position(Vector3.ZERO)-Vector2(view.size)*.5)*room_display.scale
	add_child(room_display)
	walls_body=StaticBody2D.new()
	walls_body.collision_layer=1
	add_child(walls_body)
	for rect in model.solids:
		var a=project_floor(rect.position)
		var b=project_floor(rect.end)
		var shape=CollisionShape2D.new()
		var box=RectangleShape2D.new()
		box.size=(b-a).abs()
		shape.shape=box
		shape.position=(a+b)*.5
		walls_body.add_child(shape)
	if inline_mode:
		spawn_point=Marker2D.new()
		spawn_point.name="SpawnPoint"
		spawn_point.position=project_floor(Vector2(2.5,4.6))
		add_child(spawn_point)
		inline_floor_polygon=_project_rect(Rect2(-3.72,-5.65,7.44,11.38))
		inline_door_blocker=CollisionPolygon2D.new()
		inline_door_blocker.name="DoorLeaves"
		inline_door_blocker.polygon=_project_rect(Rect2(1.43,5.72,2.14,.18))
		walls_body.add_child(inline_door_blocker)
		room_display.hide()
	else:
		_create_spawn_and_exit(project_floor(Vector2(0,4.4)),project_floor(Vector2(0,6.5)),&"harbor/District/Clinic/Entrance/exit","SAIR",false)
		exit_door.get_node("Facade").hide()
		exit_door.get_node("Prompt").rotation=-exit_door.rotation
	_build_staff()
	_build_triage_station()
	var triage_position=project_floor(Vector2(1.15,-2.25) if inline_mode else Vector2(2,-3.5))
	triage_badge.position+=triage_position-triage_area.position
	triage_area.position=triage_position
	triage_area.collision_mask=5
	triage_area.get_child(0).shape.size=Vector2(60,70)
	health_pickup=preload("res://world/harbor/interiors/HospitalHealthPickup.gd").new()
	health_pickup.name="HospitalHealth"
	health_pickup.position=project_floor(Vector2(1.15,.65) if inline_mode else Vector2(2.0,-1.0))
	add_child(health_pickup)
	if inline_mode:
		# The pickup keeps its full collision radius, but the visual sits inside
		# the small lobby without covering its beds or staff.
		health_pickup.visual_root.scale=Vector2.ONE*.62
func project_floor(point: Vector2) -> Vector2:
	return room_display.position+(room_camera.unproject_position(Vector3(point.x,0,point.y))-Vector2(view.size)*.5)*room_display.scale
func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])
func _build_staff() -> void:
	for i in 2:
		var person=NPC_SCRIPT.new()
		person.name="NurseClara" if i==0 else "DoctorMiguel"
		person.character_name="Enfermeira Clara" if i==0 else "Dr. Miguel"
		person.shirt_color=Color("65adae") if i==0 else Color("e5ece8")
		person.pants_color=Color("34767e") if i==0 else Color("385264")
		person.skin_color=Color("b87b58") if i==0 else Color("dcad8e")
		person.is_female=i==0
		person.resting_facing_y=PI
		person.dialogues=["Pode pegar a vida junto aos leitos. Vou cuidar de você.","Procure atendimento sempre que precisar."]
		person.position=project_floor((Vector2(-2.85,3.15) if i==0 else Vector2(1.55,-3.5)) if inline_mode else (Vector2(-5.5,-3.8) if i==0 else Vector2(2.2,3.8)))
		add_child(person)
		if i==0: nurse_npc=person
		person.model_root.scale=Vector3.ONE
		person.model_root.rotation.y=PI
		person.viewport_3d.size=Vector2i(192,192)
		var camera=person.viewport_3d.get_camera_3d()
		camera.size=2.5
		camera.look_at_from_position(Vector3(0,8,8),Vector3(0,.75,0))
		camera.force_update_transform()
		person.sprite_3d_display.scale=Vector2.ONE*.34
		person.sprite_3d_display.position=-(camera.unproject_position(Vector3.ZERO)-Vector2(person.viewport_3d.size)*.5)*.34
		var detail=preload("res://characters/pedestrians/CitizenDetails.gd")
		detail.piece(person.torso_node,Vector3(.075,.11,.025),Vector3(-.09,.035,-.155),Color("f0f5ee"))
		detail.piece(person.torso_node,Vector3(.05,.025,.03),Vector3(-.09,.055,-.17),Color("438c91"))
		for side in [-1,1]:
			detail.piece(person.torso_node,Vector3(.018,.19,.022),Vector3(side*.08,.07,-.17),Color("364a52"))
		detail.piece(person.torso_node,Vector3(.055,.055,.025),Vector3(.08,-.04,-.18),Color("a7b7bc"),true)
		for part in person.model_root.find_children("*","MeshInstance3D",true,false):
			if part.material_override: part.material_override.roughness=.85
func on_actor_entered(actor: Node2D) -> void:
	if is_instance_valid(actor_scale): return
	actor_scale=preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	add_child(actor_scale)
	actor_scale.configure(actor,room_camera,room_display)
func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point),inline_floor_polygon)
	return super.contains_point(point)
func get_camera_rect() -> Rect2:
	if inline_mode: return Rect2(global_position-Vector2(100,125),Vector2(200,250))
	return super.get_camera_rect()
func attach_inline_facade(facade: Node2D, entrance: BuildingEntrance) -> void:
	inline_facade=facade
	inline_entrance=entrance
	global_position=facade.global_position+Vector2(-50,23)
	z_as_relative=false
	z_index=6
	entrance.interior_available=false
	entrance.handle_input_locally=false
	entrance.show_entrance_marker=false
	entrance.show_interaction_prompt=false
	var old_body := facade.get_node_or_null("BuildingSolid") as StaticBody2D
	if old_body and old_body.get_child_count()>0:
		(old_body.get_child(0) as CollisionShape2D).set_deferred("disabled",true)
func _update_inline_access(delta: float) -> void:
	if not is_instance_valid(inline_facade) or not is_instance_valid(inline_entrance): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(actor): return
	var inside: bool = actor.visible and actor.get("is_dead") != true and contains_point(actor.global_position)
	var near: bool = actor.visible and actor.get("is_dead") != true and actor.global_position.distance_to(inline_entrance.global_position)<80.0
	if near:
		inline_entrance._away_time=0.0
		if not inline_entrance._door_open: inline_entrance.open_door()
	var target := 1.0 if near and inline_entrance._door_open else 0.0
	var amount := move_toward(_inline_door_amount,target,delta/.4)
	if not is_equal_approx(amount,_inline_door_amount):
		_inline_door_amount=amount
		model.set_door_amount(amount)
		inline_door_blocker.set_deferred("disabled",amount>=.6)
		view.render_target_update_mode=SubViewport.UPDATE_ONCE if not inside else SubViewport.UPDATE_ALWAYS
	if inside and not _inline_occupied:
		_inline_occupied=true
		room_display.show()
		set_npc_rendering_active(true)
		on_actor_entered(actor)
		actor.set_meta("harbor_interior",true)
		actor.set_meta("police_exterior_position",inline_entrance.global_position)
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.set_meta("compact_interior",get_camera_rect())
			cam.reset_smoothing()
		get_parent().get_parent().emit_signal("actor_entered_interior",actor,interior_id)
	elif not inside and _inline_occupied:
		_inline_occupied=false
		room_display.hide()
		set_npc_rendering_active(false)
		actor.remove_meta("harbor_interior")
		actor.remove_meta("police_exterior_position")
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam: cam.remove_meta("compact_interior")
		get_parent().get_parent().emit_signal("actor_returned_to_exterior",actor,interior_id)
	elif not near and is_zero_approx(_inline_door_amount) and is_instance_valid(view):
		view.render_target_update_mode=SubViewport.UPDATE_DISABLED
func set_npc_rendering_active(active: bool) -> void:
	if inline_mode and active:
		for resident in get_children():
			if resident is CharacterBody2D: resident.show()
	super.set_npc_rendering_active(active)
	if inline_mode:
		if not active:
			for resident in get_children():
				if resident is CharacterBody2D: resident.hide()
		if is_instance_valid(health_pickup):
			health_pickup.visible=active
			health_pickup.set_deferred("monitoring",active)
		if not active and is_instance_valid(triage_badge): triage_badge.hide()
	if is_instance_valid(view): view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale=null
	if is_instance_valid(health_pickup): health_pickup.set_rendering_active(active)
func _physics_process(delta: float) -> void:
	if inline_mode:
		_update_inline_access(delta)
		return
	if not is_instance_valid(exit_door): return
	var target := 1.0 if exit_door._door_open else 0.0
	var duration: float = exit_door.open_duration if exit_door._door_open else exit_door.close_duration
	var amount := move_toward(_last_door_amount,target,delta/maxf(duration,.05))
	if not is_equal_approx(_last_door_amount,amount):
		_last_door_amount=amount
		model.set_door_amount(amount)
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if view.get_meta("interior_actor_count", 0) > 0 else SubViewport.UPDATE_ONCE

func _refresh_triage_language() -> void:
	super._refresh_triage_language()
	triage_badge.text="E"
