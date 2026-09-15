extends "res://world/harbor/interiors/HarborClinicInterior.gd"
## Native hospital architecture with the existing clinic dialogue contracts.
var health_pickup: Area2D
var view: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var model: Node3D
var actor_scale: Node
var _last_door_amount := 0.0
const SCALE := .55
func _init() -> void:
	interior_id=&"clinic"
	display_name="BAY MEDICAL"
	room_size=Vector2(650,470)
	entrance_north=true
	set_meta("fixed_camera",true)
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func _setup_interior_content() -> void:
	view=SubViewport.new()
	view.size=Vector2i(1440,1040)
	view.transparent_bg=true
	view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(view)
	model=preload("res://world/harbor/interiors/HospitalRoom3D.gd").new()
	view.add_child(model)
	room_camera=Camera3D.new()
	view.add_child(room_camera)
	room_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size=22
	room_camera.look_at_from_position(Vector3(0,14,14),Vector3.ZERO)
	room_camera.current=true
	room_camera.force_update_transform()
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
	room_display.scale=Vector2.ONE*SCALE
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
	_create_spawn_and_exit(project_floor(Vector2(0,-4.4)),project_floor(Vector2(0,-6.5)),&"harbor/District/Clinic/Entrance/exit","SAIR",true)
	exit_door.get_node("Facade").hide()
	exit_door.get_node("Prompt").rotation=-exit_door.rotation
	_build_staff()
	_build_triage_station()
	var triage_position=project_floor(Vector2(2,-3.5))
	triage_badge.position+=triage_position-triage_area.position
	triage_area.position=triage_position
	triage_area.collision_mask=5
	triage_area.get_child(0).shape.size=Vector2(60,70)
	health_pickup=preload("res://world/harbor/interiors/HospitalHealthPickup.gd").new()
	health_pickup.name="HospitalHealth"
	health_pickup.position=project_floor(Vector2(2.0,-1.0))
	add_child(health_pickup)
func project_floor(point: Vector2) -> Vector2:
	return (room_camera.unproject_position(Vector3(point.x,0,point.y))-Vector2(view.size)*.5)*SCALE
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
		person.position=project_floor(Vector2(-5.5,-3.8) if i==0 else Vector2(2.2,3.8))
		add_child(person)
		if i==0: nurse_npc=person
		person.model_root.scale=Vector3.ONE*1.3
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
	actor_scale=preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
	add_child(actor_scale)
	actor_scale.configure(actor,room_camera,room_display)
	actor_scale.set_process(false)
func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if not active and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale=null
	if is_instance_valid(health_pickup): health_pickup.set_rendering_active(active)
func _physics_process(delta: float) -> void:
	if not is_instance_valid(exit_door): return
	var target := 1.0 if exit_door._door_open else 0.0
	var amount := move_toward(_last_door_amount,target,delta/maxf(exit_door.open_duration,.05))
	if not is_equal_approx(_last_door_amount,amount):
		_last_door_amount=amount
		model.set_door_amount(amount)
		view.render_target_update_mode=SubViewport.UPDATE_ONCE

func _refresh_triage_language() -> void:
	super._refresh_triage_language()
	triage_badge.text="E"
