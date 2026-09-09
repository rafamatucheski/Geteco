extends RefCounted
static func apply(actor: Node, role: String) -> void:
	var build := preload("res://district/pedestrians/CitizenDetails.gd")
	var root: Node3D=actor.model_root
	var torso: Node3D=actor.torso_node
	var head: Node3D=actor.head_node
	root.scale=Vector3(randf_range(.93,1.10),randf_range(.94,1.10),1)
	var skin := [Color("c68c67"),Color("8f5f48"),Color("e1b599")].pick_random() as Color
	for child in head.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh and child.position.is_zero_approx():
			child.material_override=child.material_override.duplicate()
			child.material_override.albedo_color=skin
	for side in [-1,1]:
		build.piece(head,Vector3(.04,.06,.04),Vector3(side*.17,0,0),skin,true)
		build.piece(head,Vector3(.035,.017,.02),Vector3(side*.065,.015,-.16),Color("252728"))
	build.piece(head,Vector3(.045,.055,.05),Vector3(0,-.025,-.17),skin,true)
	build.piece(torso,Vector3(.36,.035,.35),Vector3(0,-.19,0),Color("272a2e"))
	build.piece(torso,Vector3(.065,.09,.04),Vector3(-.13,.09,-.19),Color("242b32"))
	build.piece(torso,Vector3(.012,.10,.012),Vector3(-.15,.18,-.19),Color("383d40"))
	if role=="fire":
		for y in [-.13,.08]: build.piece(torso,Vector3(.35,.035,.35),Vector3(0,y,0),Color("ded77a"))
		for side in [-1,1]:
			build.piece(root,Vector3(.11,.39,.13),Vector3(side*.08,.86,.24),Color("c8bd58"),true)
	elif role=="medic":
		build.piece(torso,Vector3(.31,.045,.035),Vector3(0,.09,-.18),Color("d8e4df"))
		build.piece(torso,Vector3(.08,.08,.025),Vector3(.09,.02,-.2),Color("eee5d4"))
		build.piece(torso,Vector3(.018,.065,.03),Vector3(.09,.02,-.215),Color("b6453d"))
		build.piece(torso,Vector3(.06,.018,.03),Vector3(.09,.02,-.215),Color("b6453d"))
	else:
		build.piece(torso,Vector3(.06,.025,.025),Vector3(.11,.12,-.19),Color("bdc2b3"))
		for side in [-1,1]: build.piece(torso,Vector3(.09,.10,.035),Vector3(side*.09,-.01,-.18),Color("1f2a3a"))
