extends RefCounted
## Visual-only gait. All profiles share a planted support phase and backward knees.
const PROFILES := [
	Vector4(1.14,.85,.65,.020), # relaxed: longer steps, quiet arms
	Vector4(.90,1.05,1.05,.012), # brisk: shorter, purposeful cadence
	Vector4(.82,.72,.45,.010), # measured: small, careful steps
	Vector4(1.02,1.22,1.20,.028), # buoyant: higher clearance and torso rotation
]
var profile_id := 0
var phase := 0.0
var move_weight := 0.0
var run_weight := 0.0
var profile := Vector4.ONE
var actor: Node
var feet: Array[Node3D]=[]
var shoulders: Array[Vector3]=[]
var thigh_length := .28
var shin_length := .26
var support_fraction := .5
var rest_hip := .5685
var coffee: MeshInstance3D
var cane: MeshInstance3D
func configure(target: Node, identity: int) -> bool:
	# A pending/deferred rig is not an animation target yet. Validate before
	# touching geometry so callers can retry after presentation_ready.
	if not is_instance_valid(target):
		return false
	for property in ["torso_node", "head_node", "left_upper_leg", "right_upper_leg", "left_lower_leg", "right_lower_leg", "left_upper_arm", "right_upper_arm", "left_lower_arm", "right_lower_arm"]:
		if not is_instance_valid(target.get(property)):
			return false
	actor=target
	feet.clear()
	shoulders.clear()
	profile_id=posmod(identity,PROFILES.size())
	profile=PROFILES[profile_id]
	phase=fposmod(identity*.618,1.0)*TAU
	for side in 2:
		var lower: Node3D=actor.left_lower_leg if side==0 else actor.right_lower_leg
		var upper: Node3D=actor.left_upper_leg if side==0 else actor.right_upper_leg
		var width=upper.scale
		upper.scale=Vector3.ONE
		for mesh in upper.find_children("*","MeshInstance3D",true,false):
			mesh.scale*=width
		var foot := lower.get_node_or_null("GaitFoot") as Node3D
		if foot == null:
			foot=Node3D.new()
			foot.name="GaitFoot"
			foot.position=Vector3(0,-.26,0)
			lower.add_child(foot)
		for child in lower.get_children():
			if child is MeshInstance3D and child.mesh is BoxMesh and child.position.y<-.20:
				child.reparent(foot,true)
		feet.append(foot)
		var arm: Node3D=actor.left_upper_arm if side==0 else actor.right_upper_arm
		shoulders.append(actor.torso_node.transform.affine_inverse()*arm.position)
	thigh_length = absf(actor.left_lower_leg.position.y)
	shin_length = absf(feet[0].position.y)
	rest_hip = thigh_length + shin_length + .0285
	coffee=actor.left_lower_arm.get_node_or_null("HeldCoffee")
	cane=actor.right_lower_arm.get_node_or_null("WalkingStick")
	return true
func advance(delta: float, speed_ratio: float, running: bool) -> void:
	# Preview/contract entry point; live actors supply their measured displacement.
	advance_distance(delta, Vector2(0, speed_ratio*actor.base_walk_speed*delta), running)

func advance_distance(delta: float, displacement: Vector2, running: bool) -> void:
	var distance := displacement.length()
	var moving := distance > .001
	move_weight = move_toward(move_weight, 1.0 if moving else 0.0, delta*6.0)
	run_weight = move_toward(run_weight, 1.0 if moving and running else 0.0, delta*3.5)
	support_fraction = lerpf(.5,.35,run_weight)
	if not moving: return
	var pixels_per_unit := 24.0
	if is_instance_valid(actor.viewport) and is_instance_valid(actor.sprite_3d_display):
		var camera: Camera3D = actor.viewport.get_camera_3d()
		var direction := displacement.normalized()
		var axis := Vector3(direction.x,0,direction.y)*.01
		pixels_per_unit = (camera.unproject_position(axis)-camera.unproject_position(-axis)).length()*actor.sprite_3d_display.scale.x/.02
		var interior: Node = actor.get_meta("interior_actor_presentation") if actor.has_meta("interior_actor_presentation") else null
		if is_instance_valid(interior): pixels_per_unit = interior.pixels_per_rig_unit(direction)
	var stride := lerpf(.18,.245,run_weight)*profile.x*(thigh_length+shin_length)/.61
	phase = fposmod(phase + distance*TAU*support_fraction/maxf(2.0*stride*pixels_per_unit,.001),TAU)

func apply_pose() -> void:
	if not is_instance_valid(actor) or feet.size()!=2 or not is_instance_valid(actor.torso_node): return
	support_fraction = lerpf(.5,.35,run_weight)
	var leg_length := thigh_length+shin_length
	var stride := lerpf(.18,.245,run_weight)*profile.x*move_weight*leg_length/.61
	var lift := lerpf(.052,.23,run_weight)*profile.y*move_weight*leg_length/.61
	var half_cycle := fposmod(phase,PI)/TAU
	var progress := minf(half_cycle/support_fraction,1.0)
	var support_z := lerpf(-stride,stride,progress)
	var hip := .0325+sqrt(pow(leg_length-.004,2)-support_z*support_z)
	hip -= sin(progress*PI)*.017*run_weight*move_weight
	if half_cycle>support_fraction:
		hip += sin((half_cycle-support_fraction)/(.5-support_fraction)*PI)*.032*run_weight*move_weight
	var bob := hip-rest_hip
	var lean := -lerpf(.022,.20,run_weight)*move_weight
	actor.torso_node.position=Vector3(0,.85+bob,0)
	actor.torso_node.rotation=Vector3(lean,sin(phase)*profile.w*move_weight,cos(phase)*profile.w*.4*move_weight)
	actor.head_node.position=actor.torso_node.transform*Vector3(0,.40,0)
	actor.head_node.rotation=actor.torso_node.rotation*.30
	for side in 2:
		var cycle := fposmod(phase+side*PI,TAU)/TAU
		var foot_z := lerpf(-stride,stride,minf(cycle/support_fraction,1.0))
		var foot_lift := 0.0
		if cycle>support_fraction:
			var t := (cycle-support_fraction)/(1.0-support_fraction)
			var ratio := (1.0-support_fraction)/support_fraction
			foot_z = stride*(1+2*ratio*t-(6+6*ratio)*t*t+(4+4*ratio)*t*t*t)
			var recovery := pow(t,lerpf(1.0,.75,run_weight))
			foot_lift = pow(sin(recovery*PI),2)*lift
		var upper: Node3D=actor.left_upper_leg if side==0 else actor.right_upper_leg
		var lower: Node3D=actor.left_lower_leg if side==0 else actor.right_lower_leg
		upper.position.y=hip
		var down := hip-.0325-foot_lift
		var reach := clampf(Vector2(down,foot_z).length(),.04,leg_length-.001)
		var knee := -acos(clampf((reach*reach-thigh_length*thigh_length-shin_length*shin_length)/(2*thigh_length*shin_length),-1,1))
		upper.rotation.x=atan2(-foot_z,down)-atan2(shin_length*sin(knee),thigh_length+shin_length*cos(knee))
		lower.rotation.x=knee
		feet[side].rotation.x=-(upper.rotation.x+knee)
		var arm: Node3D=actor.left_upper_arm if side==0 else actor.right_upper_arm
		var forearm: Node3D=actor.left_lower_arm if side==0 else actor.right_lower_arm
		if side==1 and actor.is_gangster and is_instance_valid(actor.combat_target): continue
		arm.position=actor.torso_node.transform*shoulders[side]
		var carry: bool=(actor.has_coffee_cup or actor.has_surfboard) if side==0 else (actor.has_briefcase or actor.has_walking_stick)
		var swing := -cos(phase+side*PI)*lerpf(.26,.65,run_weight)*profile.z*move_weight
		var clearance := .22 if actor.body_type==2 else .10 if actor.body_type==4 else .025
		arm.rotation=Vector3(swing*(.12 if carry else 1.0),0,(-clearance if side==0 else clearance))
		# Limbs point down local -Y; positive X folds the wrist toward -Z
		# (the face). Negative X was bending both elbows backwards when running.
		forearm.rotation=Vector3(lerpf(.13,.95,run_weight)+absf(swing)*.12,0,0)
		if carry:
			forearm.rotation.x=.18
			if side==0 and actor.has_coffee_cup:
				arm.rotation.x=.25
				forearm.rotation.x=.95
	# Carried props keep their own support: a cup stays upright and the cane
	# reaches the floor at the grip, independently of body height and arm swing.
	if is_instance_valid(coffee):
		coffee.global_transform=Transform3D(actor.model_root.global_basis,actor.left_lower_arm.to_global(Vector3(0,-.20,-.035)))
	if is_instance_valid(cane):
		var hand: Vector3=actor.right_lower_arm.to_global(Vector3(.025,-.215,0))
		var height := maxf(.05,hand.y-actor.model_root.global_position.y)
		var thickness: float=actor.model_root.global_basis.x.length()
		cane.global_transform=Transform3D(Basis.from_scale(Vector3(thickness,height/.55,thickness)),hand-Vector3(0,height*.5,0))
