extends "res://world/harbor/cobras/CobraResident.gd"
## The campaign leader shares the existing combat and articulated animation rig.
## Visual identity only: no extra health, collision scale or weapon advantage.
func _init() -> void:
	combat_role = "leader"
	guard = true

func _setup_district_and_archetype() -> void:
	super._setup_district_and_archetype()
	body_height_scale = 1.10
	body_width_scale = 1.08
	shirt_color = Color("214d35")
	appearance_gender = 1
	appearance_seed = 208
	hair_style_override = 5
	set_meta("character_name", "Takeshi")
	pants_color = Color("26282d")
	shoe_color = Color("211d1c")
	skin_color = Color("a8795d")
	hair_color = Color("25201f")
	accessory_color = Color("254735")
	has_bandana = false
	has_beanie = false
	has_vest = false
	has_beard = false

func _ready() -> void:
	super._ready()
	add_to_group("cobra_boss")
	presentation_ready.connect(_build_boss_details, CONNECT_ONE_SHOT)

func _build_boss_details() -> void:
	# Panels follow the torso; shoulder caps follow arms, boots follow shins.
	_detail(torso_node,"LeatherLeft",Vector3(.10,.30,.025),Vector3(-.075,0,-.145),Color("29543b"))
	_detail(torso_node,"LeatherRight",Vector3(.10,.30,.025),Vector3(.075,0,-.145),Color("29543b"))
	_detail(torso_node,"CopperZip",Vector3(.009,.29,.009),Vector3(0,0,-.171),Color("9b704c"))
	for side in [-1,1]:
		var lapel := _detail(torso_node,"Lapel%d" % side,Vector3(.035,.13,.018),Vector3(side*.055,.10,-.169),Color("638464"))
		lapel.rotation.z = side*.22
		var arm: Node3D = left_upper_arm if side == -1 else right_upper_arm
		var shoulder := SphereMesh.new()
		shoulder.radius = .081
		shoulder.height = .115
		_round_detail(arm,"ShoulderCap",shoulder,Vector3(0,-.035,0),Color("343035"))
		var leg: Node3D = left_lower_leg if side == -1 else right_lower_leg
		var cuff := CylinderMesh.new()
		cuff.top_radius = .063
		cuff.bottom_radius = .059
		cuff.height = .12
		_round_detail(leg,"BootCuff",cuff,Vector3(0,-.20,0),shoe_color)
		_detail(head_node,"Brow%d" % side,Vector3(.068,.019,.018),Vector3(side*.068,.035,-.15),hair_color)
	_detail(head_node,"Nose",Vector3(.035,.052,.035),Vector3(0,-.008,-.17),skin_color.darkened(.08))
	_detail(head_node,"SilverTemple",Vector3(.025,.055,.10),Vector3(-.154,.07,-.015),Color("77716b"))
	_detail(torso_node,"CobraPin",Vector3(.018,.026,.01),Vector3(-.08,.07,-.166),Color("9b704c"))

func _round_detail(parent: Node3D, label: String, mesh: Mesh, at: Vector3, color: Color) -> void:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.mesh = mesh
	piece.position = at
	piece.material_override = _make_mat(color,.65)
	parent.add_child(piece)

func _detail(parent: Node3D, label: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.position = at
	piece.material_override = _make_mat(color,.45)
	parent.add_child(piece)
	return piece
