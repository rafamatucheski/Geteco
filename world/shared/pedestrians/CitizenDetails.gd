extends RefCounted
## Extra low-poly pieces inherit the existing articulated rig and viewport LOD.
static func piece(parent: Node3D, size: Vector3, point: Vector3, color: Color, round_shape := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	if round_shape:
		var sphere := SphereMesh.new()
		sphere.radial_segments=8
		sphere.rings=4
		part.mesh=sphere
		part.scale=size
	else:
		var box := BoxMesh.new()
		box.size=size
		part.mesh=box
	part.position=point
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.85
	part.material_override=mat
	parent.add_child(part)
	return part

static func dress(actor: AnimatedPedestrian3D, variant: int) -> void:
	var head := actor.head_node
	for side in [-1,1]:
		piece(head,Vector3(.045,.065,.04),Vector3(side*.17,-.015,0),actor.skin_color,true)
		piece(head,Vector3(.035,.019,.015),Vector3(side*.065,.005,-.157),Color("292a2b"))
	piece(head,Vector3(.045,.05,.055),Vector3(0,-.025,-.17),actor.skin_color,true)
	if variant%4==0:
		# Tied-back hair, visible from the gameplay camera.
		piece(head,Vector3(.18,.19,.18),Vector3(0,.02,.18),actor.hair_color,true)
	elif variant%4==1:
		for i in 5:
			piece(head,Vector3(.10,.10,.10),Vector3((i-2)*.06,.15,.015),actor.hair_color,true)
	elif variant%4==2:
		for side in [-1,1]:
			piece(head,Vector3(.065,.23,.18),Vector3(side*.145,-.015,.05),actor.hair_color,true)
	var shirt := actor.shirt_color
	for side in [-1,1]:
		piece(actor.torso_node,Vector3(.10,.07,.025),Vector3(side*.09,.035,-.17),shirt.darkened(.22))
	for i in 3:
		piece(actor.torso_node,Vector3(.016,.016,.02),Vector3(0,.08-i*.065,-.183),Color("b8b6a6"))
	if variant%3==0:
		piece(actor.torso_node,Vector3(.04,.38,.025),Vector3(.10,0,-.19),Color("514433")).rotation.z=-.4
		piece(actor.torso_node,Vector3(.19,.19,.13),Vector3(-.19,-.15,-.02),Color("71563e"))
