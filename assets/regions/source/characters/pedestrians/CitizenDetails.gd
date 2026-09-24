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

static func dress(actor: Node, variant: int) -> void:
	if actor.viewport == null:
		actor.set_meta("citizen_detail_variant", variant)
		actor.presentation_ready.connect(func(): dress(actor, variant), CONNECT_ONE_SHOT)
		return
	if actor.has_meta("citizen_dressed"): return
	preload("res://assets/regions/source/characters/pedestrians/CitizenSculpt.gd").build(actor)

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
	if role != "mortician":
		preload("res://assets/regions/source/characters/pedestrians/CitizenFace.gd").build(head,radius,skin,int(actor.get_meta("appearance_variant",0)))
	if role in ["clerk", "mortician"]:
		piece(head,Vector3(radius*2.04,.10,radius*1.95),Vector3(0,radius*.77,.012),Color("47362f"),true)
	for side in [-1,1]:
		# Collar, shoulder seam, rolled sleeve cuff and tailored trouser seam.
		if role != "civilian" or int(actor.get_meta("appearance_variant",0))%4 != 1:
			piece(torso,Vector3(.075,.075,.025),Vector3(side*.06,.18,-.14),cloth.lightened(.18)).rotation.z=side*.35
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
