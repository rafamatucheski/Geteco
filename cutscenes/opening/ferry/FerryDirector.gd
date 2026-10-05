extends Node3D
## Offline film direction over the actual Harbor set. Never instantiated by gameplay.
const ACTOR := preload("res://scripts/Actor.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var world
var terminal
var ferry: Node3D
var dante
var passenger
var camera: Camera3D
var phone: Node3D
var bag: Node3D
var elapsed := 0.0
var length := 73.0
var shots := [0.0,7.0,12.0,16.0,21.0,25.0,29.0,36.5,42.0,49.0,54.0,61.0,67.5]
var extras: Array = []
var night_set

func configure(p_world) -> void:
	world = p_world
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().scaling_3d_scale = 1.0
	terminal = world.session.urban_operations.passenger_terminal
	terminal.prepare_arrival()
	terminal.set_process(false)
	ferry = terminal.ferry
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.set_process_unhandled_input(false)
	world.session.arrival.active = false
	night_set = preload("res://cutscenes/opening/ferry/FerryNightSet.gd").new()
	add_child(night_set)
	night_set.configure(world,ferry)
	for node in world.find_children("*", "CanvasLayer", true, false): node.hide()
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false): node.hide()
	world.player.hide()
	world.player.set_physics_process(false)
	world.player.input_locked = true
	dante = ACTOR.new()
	dante.is_player = true
	ferry.add_child(dante)
	dante.set_physics_process(false)
	dante.input_locked = true
	dante.position = Vector3(0,.48,4.3)
	dante.visual.rotation.y = PI
	dante.collision_layer = 0
	dante.collision_mask = 0
	dante.show()
	passenger = preload("res://cutscenes/opening/ferry/FerryPassenger.gd").new()
	ferry.add_child(passenger)
	passenger.position = Vector3(1.25,.48,4.30)
	passenger.rotation.y = -.85
	passenger.visual.rotation.y = PI
	passenger.set_process(false)
	for i in 2:
		var extra := CIVILIAN.new()
		extra.appearance_locked = true
		extra.appearance_variant = 8 + i * 7
		extra.wardrobe_overrides = {"top":2,"bottom":0,"hat":0,"bag":0}
		ferry.add_child(extra)
		extra.position = Vector3(-.85 if i == 0 else .85, .48, 2.0)
		extra.rotation.y = PI
		extra.sit_amount = 1.0
		extra.seat_height = .34
		extra.set_process(false)
		_prepare_closeup_materials(extra)
		extras.append(extra)
	phone = Node3D.new()
	ferry.add_child(phone)
	_box(phone,Vector3.ZERO,Vector3(.070,.145,.009),Color("15232a"))
	_box(phone,Vector3(0,0,.005),Vector3(.062,.128,.001),Color("526e7b"))
	_box(phone,Vector3(-.023,.052,-.005),Vector3(.012,.019,.002),Color("090e13"))
	bag = Node3D.new()
	dante.visual.add_child(bag)
	bag.position = Vector3(0,1.10,.20)
	_box(bag,Vector3.ZERO,Vector3(.34,.43,.16),Color("69503b"))
	_box(bag,Vector3(0,-.075,.098),Vector3(.28,.19,.055),Color("866c4f"))
	for x in [-.12,.12]:
		_box(bag,Vector3(x,.04,-.15),Vector3(.041,.46,.035),Color("513f30"))
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = .06
	camera.far = 1400.0
	camera.fov = 46.0
	add_child(camera)
	camera.make_current()
	var timing_path := "res://cutscenes/opening/ferry/timing.json"
	if FileAccess.file_exists(timing_path):
		var timing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(timing_path))
		length = timing.duration
		shots.assign(timing.shots)
	sample(0.0,1.0/30.0)

func _prepare_closeup_materials(model) -> void:
	# The civilian's segmented wardrobe includes open cuffs and shoulder shells.
	# Close cinematic cameras see their reverse faces; keep this override local.
	for joint in model._joints:
		joint.material_override = model.KIT.material(true)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = model.wardrobe.top_color
	cloth.roughness = .9
	for shoulder in model.upper_arms:
		var cap := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .069
		sphere.height = .138
		cap.mesh = sphere
		cap.material_override = cloth
		cap.position.y = -.018
		shoulder.add_child(cap)

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)

func shot_at(t: float) -> int:
	for index in range(shots.size()-1,-1,-1):
		if t >= shots[index]: return index
	return 0

func sample(t: float, delta: float) -> void:
	elapsed = t
	var arrival_u := smoothstep(0.0, shots[11], t)
	# Approach along open water east of the cargo ship, then reverse into the berth.
	var curve_u := smoothstep(0.0, shots[10], t)
	if t < shots[10]:
		ferry.position = Vector3(257,0,145).lerp(Vector3(233,0,173),curve_u)
		ferry.rotation.y = lerpf(2.433,0.0,smoothstep(.40,.90,curve_u))
	else:
		ferry.position = Vector3(233,0,173).lerp(terminal.BERTH,smoothstep(shots[10],shots[11],t))
		ferry.rotation.y = 0.0
	ferry.position.y = .025*sin(t*.85)*(1.0-arrival_u)
	ferry.rotation.z = .003*sin(t*.7)*(1.0-arrival_u)
	night_set.sample(t,delta)
	dante.position = Vector3(0,.48,4.3)
	dante._idle_clock = t
	dante._pose_delta = delta
	dante._apply_pose(dante._idle_pose)
	dante._apply_idle_breath()
	var memory := smoothstep(shots[6],shots[6]+1.0,t)*(1.0-smoothstep(shots[10]-1.0,shots[10],t))
	var look_passenger := smoothstep(11.3,12.5,t)*(1.0-smoothstep(26.0,29.0,t))
	look_passenger = maxf(look_passenger,smoothstep(shots[11],shots[11]+1.0,t))
	var head: int = dante.skeleton.find_bone("Head")
	if head >= 0:
		var rest: Quaternion = dante.skeleton.get_bone_pose_rotation(head)
		dante.skeleton.set_bone_pose_rotation(head,rest*Quaternion(Vector3.UP,.35*look_passenger)*Quaternion(Vector3.RIGHT,.28*memory+.012*sin(t*1.6)))
	var holding := smoothstep(26.5,29.5,t)*(1.0-smoothstep(shots[10],shots[10]+1.5,t))
	preload("res://cutscenes/opening/ferry/FerryPhonePose.gd").apply(dante,phone,holding)
	var speaking := (t >= 12 and t < 15) or (t >= 21 and t < 24) or (t >= 57 and t < 60.2) or (t >= 65 and t < 67)
	passenger.pose_at(t,speaking,delta)
	for i in extras.size():
		extras[i].clock = t + i*2.0
		extras[i]._speed = 0.0
		extras[i]._travel = 0.0
		extras[i]._pose(delta)
	var index := shot_at(t)
	var end: float = shots[index+1] if index+1 < shots.size() else length
	var u := clampf((t-shots[index])/maxf(.01,end-shots[index]),0.0,1.0)
	var eye := Vector3.ZERO
	var focus := Vector3.ZERO
	camera.fov = 46.0
	match index:
		0:
			eye = Vector3(21,11,25).lerp(Vector3(17,9,22),u)
			focus = Vector3(-2,1,0)
		1:
			eye = Vector3(-4,3.5,10).lerp(Vector3(-3,2.8,8),u)
			focus = Vector3(.1,1.65,4)
		2,4:
			eye = Vector3(-1.1,2.05,7.15).lerp(Vector3(-.75,2.0,6.9),u)
			focus = Vector3(.92,1.83,4.3)
		3,5,7,9:
			eye = Vector3(1.65,2.0,6.9).lerp(Vector3(1.35,2.0,6.6),u)
			focus = Vector3(0,1.81,4.3)
			camera.fov = 35.0 if index in [7,9] else 42.0
		6:
			eye = Vector3(-1.45,2.05,6.9).lerp(Vector3(-1.05,2.07,6.35),u)
			focus = Vector3(0,1.95,4.3)
			camera.fov = 32.0
		8:
			eye = Vector3(-.9,2.2,6.6).lerp(Vector3(-.7,2.2,6.25),u)
			focus = Vector3(0,1.98,4.3)
			camera.fov = 34.0
		10:
			eye = Vector3(15,9,13).lerp(Vector3(12,7,15),u)
			focus = Vector3(-6,1,11)
		11:
			eye = Vector3(-2.6,2.3,8.6).lerp(Vector3(-2.15,2.2,8.0),u)
			focus = Vector3(.55,1.7,4.4)
		12:
			eye = Vector3(5,4,11).lerp(Vector3(14,15,20),smoothstep(0.0,1.0,u))
			focus = Vector3(-2,1,7)
			camera.fov = 50.0
	camera.global_position = ferry.to_global(eye)
	camera.look_at(ferry.to_global(focus),Vector3.UP)
	if index == 0:
		camera.global_position = ferry.global_position + Vector3(15,11,17).lerp(Vector3(12,9,15),u)
		camera.look_at(ferry.global_position + Vector3(-2,.9,-1),Vector3.UP)
