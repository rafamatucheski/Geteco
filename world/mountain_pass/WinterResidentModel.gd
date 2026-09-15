extends Node3D
## Moradores com casacos, gorros/capuzes, luvas e identidade por profissão.
## O construtor de peças abaixo também é usado pelos animais da serra.
var coat_color := Color("3f6872")
var role := "ranger"
var limbs: Array[Node3D] = []
var breath: MeshInstance3D
var clock := 0.0
var walking := false
var motion_speed := 0.0
var gait_phase := 0.0
var attack_age := 0.0
var appearance_variant := 0
var appearance_female := false
var sit_amount := 0.0
var seat_height := 0.45
var seated_variant := 0
var knees: Array[Node3D] = []
var elbows: Array[Node3D] = []
var pose_root: Node3D
var activity := "idle"
var mug: Node3D
var axe: Node3D
var steam: MeshInstance3D
var gesture_blend := 0.0
var work_pose_active := false
var work_target := Vector3.ZERO
var work_time := 0.0
var chop_pose: Node3D

func _ready() -> void:
	preload("res://world/shared/pedestrians/WinterWardrobe.gd").build(self)
	prepare_seated_rig()
	if role == "logger":
		chop_pose = preload("res://world/mountain_pass/LoggerChopPose.gd").new()
		add_child(chop_pose)
		chop_pose.configure(self)

func prepare_seated_rig() -> void:
	knees.clear()
	pose_root = Node3D.new()
	pose_root.name = "RestPose"
	for child in get_children():
		remove_child(child)
		pose_root.add_child(child)
	add_child(pose_root)
	for index in [0,2]:
		var leg := limbs[index]
		for child in leg.get_children():
			leg.remove_child(child)
			child.queue_free()
		var parts = preload("res://world/shared/pedestrians/CitizenDetails.gd")
		parts.piece(leg,Vector3(.185,.36,.21),Vector3(0,-.17,0),Color("344353"))
		var knee := Node3D.new()
		knee.name="Knee"
		knee.position.y=-.35
		leg.add_child(knee)
		knees.append(knee)
		parts.piece(knee,Vector3(.18,.31,.20),Vector3(0,-.15,0),Color("344353"))
		parts.piece(knee,Vector3(.195,.18,.29),Vector3(0,-.34,.035),Color("2c3036"))
	preload("res://world/mountain_pass/MountainWinterTailoring.gd").refine(self)
	set_meta("standing_rig_height", 1.79 * scale.y)
	_build_activity_props()

func _build_activity_props() -> void:
	var parts = preload("res://world/shared/pedestrians/CitizenDetails.gd")
	mug = Node3D.new()
	mug.name = "HotDrink"
	limbs[3].add_child(mug)
	mug.position = Vector3(0,-.48,.07)
	parts.piece(mug,Vector3(.14,.16,.14),Vector3.ZERO,Color("d9c7a5"),true)
	parts.piece(mug,Vector3(.105,.012,.105),Vector3(0,.081,0),Color("503022"),true)
	parts.piece(mug,Vector3(.055,.09,.04),Vector3(.09,0,0),Color("d9c7a5"),true)
	steam = parts.piece(mug,Vector3(.055,.16,.06),Vector3(0,.19,0),Color(.9,.95,1,.2),true)
	steam.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	axe = Node3D.new()
	axe.name = "WoodAxe"
	limbs[3].add_child(axe)
	axe.position = Vector3(0,-.47,.03)
	parts.piece(axe,Vector3(.04,.04,.58),Vector3(0,0,.17),Color("856040"))
	parts.piece(axe,Vector3(.23,.12,.06),Vector3(.06,0,.44),Color("919fa6"))
	mug.hide()
	axe.hide()

func set_seat_pose(amount:float,height:float,variant:int) -> void:
	sit_amount=clampf(amount,0.0,1.0)
	seat_height=height
	seated_variant=variant

func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.mesh.radial_segments = 10
	mesh.mesh.rings = 5
	mesh.mesh.height = 2
	mesh.mesh.radius = 1
	mesh.scale = size * 0.5
	mesh.position = point
	mesh.material_override = StandardMaterial3D.new()
	mesh.material_override.albedo_color = color
	mesh.material_override.roughness = 0.9
	parent.add_child(mesh)
	return mesh

func _process(delta: float) -> void:
	clock += delta
	attack_age += delta
	gait_phase += delta * clampf(motion_speed * 0.17, 3.0, 12.0)
	var bend := smoothstep(0.0,1.0,sit_amount)
	var thigh_angle := acos(clampf((seat_height/maxf(.1,scale.y)+.03-.43)/.35,-.1,.8))
	if is_instance_valid(pose_root):
		pose_root.position.y=(seat_height/maxf(.1,scale.y)-.75)*bend
		pose_root.rotation.x=sin(sit_amount*PI)*.18
	for i in limbs.size():
		var walking_angle := sin(gait_phase + (PI if i in [0,3] else 0.0)) * (clampf(motion_speed * 0.008, 0.20, 0.65) if walking else 0.015)
		var resting_angle := -thigh_angle if i in [0,2] else -.65 + sin(clock*.8+i)*.025
		limbs[i].rotation.x=lerpf(walking_angle,resting_angle,bend)
		limbs[i].rotation.z=sin(clock*.45+i)*.025*bend if i in [1,3] else (0.04 if i==0 else -.04)*bend
	for knee in knees:knee.rotation.x=thigh_angle*bend
	for elbow in elbows: elbow.rotation.x = -.12 if not walking else -.18
	var head:=pose_root.get_node_or_null("Head") if is_instance_valid(pose_root) else null
	if head:head.rotation.y=PI+sin(clock*.45+seated_variant)*.12*bend
	var active := not walking and activity in ["drink","talk","warm","work"]
	gesture_blend = move_toward(gesture_blend,1.0 if active else 0.0,delta*2.5)
	if is_instance_valid(mug):
		mug.visible = active and activity == "drink"
		axe.visible = (active and activity == "work") or activity in ["angry", "attack"]
		if activity in ["angry", "attack"]:
			var swing := sin(clampf(attack_age / 0.45, 0.0, 1.0) * PI) if activity == "attack" else 0.0
			limbs[3].rotation.x = -0.8 - swing * 1.8
			pose_root.rotation.x = swing * 0.16
		if mug.visible:
			var sip := smoothstep(.25,.65,sin(clock*.65))
			limbs[3].rotation.x = lerpf(limbs[3].rotation.x,-1.1-sip*1.3,gesture_blend)
			limbs[3].rotation.z = -.23*gesture_blend
			mug.rotation.x = -limbs[3].rotation.x - sip*.25
			steam.position.y = .17+fposmod(clock*.08,.14)
			steam.material_override.albedo_color.a = (.12+.08*sin(clock*2.0))*(1.0-sip*.7)
		elif active and activity == "talk":
			var speaking := sin(clock*.55)>-.2
			limbs[1].rotation.x = (-.55+sin(clock*2.1)*.24)*gesture_blend if speaking else -.12
			limbs[1].rotation.z = -.22*gesture_blend
			if head:
				head.rotation.y = PI+sin(clock*.7)*.14
				head.rotation.x = sin(clock*2.0)*(.035 if speaking else .09)
		elif active and activity == "warm":
			for i in [1,3]:
				limbs[i].rotation.x = -1.0*gesture_blend
				limbs[i].rotation.z = (1.0 if i==1 else -1.0)*(.35+sin(clock*5.0)*.035)*gesture_blend
		if head and activity != "talk": head.rotation.x = lerpf(head.rotation.x,0.0,minf(1.0,delta*4.0))
	if is_instance_valid(chop_pose):
		var chopping := work_pose_active and activity == "work" and not walking
		chop_pose.visible = chopping
		for index in [1,3]: limbs[index].visible = not chopping
		for index in [0,2]:
			limbs[index].position.x = (-1.0 if index==0 else 1.0)*(.18 if chopping else .115)
			limbs[index].position.z = (-.08 if index==0 else .08) if chopping else 0.0
		if activity == "work": axe.hide()
		if chopping:
			pose_root.rotation = Vector3.ZERO
			pose_root.position = Vector3.ZERO
			for index in [0,2]: limbs[index].rotation = Vector3.ZERO
			for knee in knees: knee.rotation = Vector3.ZERO
			chop_pose.target = work_target
			chop_pose.sample(work_time)
			if head: head.rotation.x = -.12
	if not is_instance_valid(breath): return
	var exhale := fposmod(clock,3.4)/3.4
	breath.position.z = 0.36 + exhale*0.38
	breath.material_override.albedo_color.a = sin(exhale*PI)*0.16
