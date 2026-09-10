extends RefCounted
## Extra low-poly pieces inherit the existing articulated rig and viewport LOD.
static func piece(parent: Node3D, size: Vector3, point: Vector3, color: Color, round_shape := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	if round_shape:
		var sphere := SphereMesh.new()
		sphere.radius = .5
		sphere.height = 1.0
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
	if actor.viewport == null:
		actor.set_meta("citizen_detail_variant", variant)
		actor.presentation_ready.connect(func(): dress(actor, variant), CONNECT_ONE_SHOT)
		return
	if actor.has_meta("citizen_dressed"): return
	variant = int(actor.get_meta("citizen_detail_variant", variant))
	actor.set_meta("citizen_dressed", true)
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
	finish_rig(actor, "civilian")

static func finish_rig(actor: Node, role: String) -> void:
	if actor.has_meta("rig_tailored"): return
	actor.set_meta("rig_tailored", true)
	var head: Node3D = actor.head_node
	var torso: Node3D = actor.torso_node
	var cloth := Color("525d68")
	var skin := Color("c38f71")
	var radius := .17
	for part in head.get_children():
		if part is MeshInstance3D and part.mesh is SphereMesh and part.position.is_zero_approx():
			radius = part.mesh.radius
			if part.material_override: skin = part.material_override.albedo_color
	for part in torso.get_children():
		if part is MeshInstance3D and part.material_override:
			cloth = part.material_override.albedo_color
			break
	# Facial features follow each rig's head size, including smaller shop staff.
	for side in [-1, 1]:
		piece(head, Vector3(.050,.015,.020), Vector3(side*radius*.39,.044,-radius*.94), skin.darkened(.52))
	if role in ["clerk", "mortician"]:
		for side in [-1, 1]:
			piece(head, Vector3(.034,.022,.022), Vector3(side*radius*.4,.012,-radius*.98), Color("292c31"))
			piece(head, Vector3(.045,.065,.05), Vector3(side*radius,-.01,0), skin,true)
		piece(head,Vector3(.045,.06,.055),Vector3(0,-.025,-radius),skin,true)
		# A solid crown of hair also reads from the top-down shop camera.
		piece(head,Vector3(radius*2.04,.10,radius*1.95),Vector3(0,radius*.77,.012),Color("47362f"),true)
	if role != "mortician":
		piece(head, Vector3(.054,.012,.012), Vector3(0,-.074,-radius*.89), skin.darkened(.42))
	for side in [-1,1]:
		# Collar, shoulder seam, rolled sleeve cuff and tailored trouser seam.
		piece(torso,Vector3(.095,.095,.025),Vector3(side*.065,.17,-.165),cloth.lightened(.18)).rotation.z=side*.35
		var upper: Node3D = actor.left_upper_arm if side<0 else actor.right_upper_arm
		piece(upper,Vector3(.112,.025,.115),Vector3(0,-.185,0),cloth.darkened(.20))
		var lower: Node3D = actor.left_lower_arm if side<0 else actor.right_lower_arm
		if not lower.has_node("Palm"):
			var palm := piece(lower,Vector3(.075,.07,.085),Vector3(0,-.20,0),skin)
			palm.name="Palm"
	if role in ["clerk", "medic", "mortician"]:
		piece(torso,Vector3(.065,.085,.025),Vector3(.10,.08,-.185),Color("ecede2"))
		piece(torso,Vector3(.035,.025,.008),Vector3(.10,.09,-.202),Color("536f81"))
		piece(torso,Vector3(.085,.10,.025),Vector3(-.10,.035,-.18),cloth.darkened(.18))
		piece(torso,Vector3(.012,.07,.025),Vector3(-.10,.085,-.19),Color("d5c6b1"))
	if role == "civilian":
		piece(torso,Vector3(.027,.29,.02),Vector3(0,-.01,-.177),cloth.darkened(.2))
		piece(torso,Vector3(.075,.045,.035),Vector3(0,-.22,-.16),Color("9a9587"))
	actor.set_meta("detail_role", role)
