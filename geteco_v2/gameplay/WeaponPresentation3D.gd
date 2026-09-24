extends RefCounted
## Shared, human-scale weapon geometry. Origin is the firing hand, muzzle faces -Z.
## The same meshes appear equipped and as floor loot, preserving their silhouette.

static func build(root: Node3D, id: String) -> void:
	var steel := _mat(Color("697782"), 0.78, 0.32)
	var dark := _mat(Color("222b30"), 0.62, 0.42)
	var rubber := _mat(Color("252629"), 0.0, 0.86)
	var wood := _mat(Color("714331"), 0.0, 0.62)
	var brass := _mat(Color("b7955b"), 0.65, 0.38)
	if id == "axe":
		var trail := preload("res://gameplay/AxeSwingTrail.gd").new()
		trail.name = "AxeSwingTrail"
		root.add_child(trail)
		_cylinder(root,"AshHandle",Vector3(0,0,-0.17),0.018,0.65,wood,Vector3(90,0,0))
		_cylinder(root,"GripWrap",Vector3(0,0,0.065),0.020,0.10,rubber,Vector3(90,0,0))
		_cylinder(root,"HandleHeel",Vector3(0,0,0.15),0.023,0.018,wood,Vector3(90,0,0))
		var head := Node3D.new()
		head.name = "ForgedHead"
		head.rotation.z = -PI * 0.5
		root.add_child(head)
		_profile(head,"SteelHead",PackedVector2Array([Vector2(-0.49,-0.055),Vector2(-0.40,-0.055),Vector2(-0.405,0.045),Vector2(-0.365,0.155),Vector2(-0.37,0.18),Vector2(-0.51,0.19),Vector2(-0.525,0.16),Vector2(-0.49,0.045)]),0.045,dark)
		_profile(head,"CuttingEdge",PackedVector2Array([Vector2(-0.525,0.16),Vector2(-0.51,0.19),Vector2(-0.37,0.18),Vector2(-0.365,0.155),Vector2(-0.39,0.14),Vector2(-0.50,0.15)]),0.012,steel)
	elif id == "knife":
		_profile(root, "Grip", PackedVector2Array([Vector2(0.045,-0.017),Vector2(0.085,-0.012),Vector2(0.085,0.012),Vector2(-0.015,0.017),Vector2(-0.035,0.012),Vector2(-0.035,-0.012)]), 0.028, rubber)
		_box(root,"Guard",Vector3(0,0,-0.04),Vector3(0.054,0.025,0.012),brass)
		# Full-tang drop-point blade: angular silhouette, central ridge and cutting bevel.
		var blade := PackedVector2Array([Vector2(-0.045,-0.018),Vector2(-0.15,-0.018),Vector2(-0.235,0.006),Vector2(-0.17,0.021),Vector2(-0.045,0.019)])
		_profile(root,"Blade",blade,0.007,steel)
		for z in [0.015,0.059]:
			_cylinder(root,"TangRivet",Vector3(0,0,z),0.005,0.031,brass,Vector3(0,0,90))
		for z in [-0.016,0.0,0.032,0.048]:
			_box(root,"GripGroove",Vector3(0,0,z),Vector3(0.030,0.032,0.004),dark)
	elif id == "knuckles":
		var gold_brass := _mat(Color("d4ac0d"), 0.82, 0.28)
		_box(root, "PalmBar", Vector3(0, -0.015, 0.02), Vector3(0.082, 0.018, 0.014), gold_brass)
		for x in [-0.038,0.038]:
			_box(root,"PalmSupport",Vector3(x,-0.008,0),Vector3(0.012,0.018,0.055),gold_brass)
		for i in range(4):
			var x_off := -0.033 + i * 0.022
			var ring := MeshInstance3D.new()
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.007
			mesh.outer_radius = 0.012
			mesh.rings = 12
			mesh.ring_segments = 6
			ring.mesh = mesh
			ring.position = Vector3(x_off,0.005,-0.025)
			ring.rotation.x = PI/2
			ring.material_override = gold_brass
			root.add_child(ring)
		_box(root, "StrikingRidge", Vector3(0, 0.008, -0.038), Vector3(0.084, 0.016, 0.012), gold_brass)
		for i in range(4):
			var x_off := -0.033 + i * 0.022
			_box(root, "KnucklePyramid_%d" % i, Vector3(x_off, 0.008, -0.045), Vector3(0.012, 0.012, 0.010), steel)
	elif id in ["bat", "taco", "baseball"]:
		_cylinder(root, "BatBarrel", Vector3(0, 0, -0.28), 0.032, 0.42, wood, Vector3(90, 0, 0))
		_cylinder(root, "BatTaper", Vector3(0, 0, -0.04), 0.022, 0.16, wood, Vector3(90, 0, 0))
		_cylinder(root, "BatGrip", Vector3(0, 0, 0.08), 0.018, 0.16, rubber, Vector3(90, 0, 0))
		_cylinder(root, "BatPommel", Vector3(0, 0, 0.17), 0.025, 0.022, wood, Vector3(90, 0, 0))
	elif id == "hunting_rifle":
		_profile(root,"WalnutStock",PackedVector2Array([Vector2(0.18,-0.085),Vector2(0.175,0.042),Vector2(0.13,0.037),Vector2(0.085,0.045),Vector2(-0.25,0.018),Vector2(-0.25,-0.017),Vector2(-0.065,-0.025),Vector2(-0.012,-0.035),Vector2(0.035,-0.07),Vector2(0.065,-0.052),Vector2(0.10,-0.014),Vector2(0.14,-0.052)]),0.046,wood)
		_box(root,"ButtPad",Vector3(0,-0.02,0.182),Vector3(0.050,0.135,0.015),rubber)
		_box(root,"Receiver",Vector3(0,0.04,-0.055),Vector3(0.041,0.035,0.19),dark)
		_cylinder(root,"Barrel",Vector3(0,0.055,-0.375),0.012,0.43,steel,Vector3(90,0,0))
		_cylinder(root,"Bore",Vector3(0,0.055,-0.591),0.007,0.003,rubber,Vector3(90,0,0))
		_cylinder(root,"Bolt",Vector3(0.023,0.053,-0.021),0.008,0.042,steel,Vector3(0,0,90))
		_cylinder(root,"BoltLever",Vector3(0.046,0.035,-0.021),0.006,0.039,steel,Vector3(0,0,-25))
		_box(root,"BoltKnob",Vector3(0.052,0.015,-0.021),Vector3(0.020,0.019,0.020),dark)
		for z in [-0.145,-0.015]:
			_box(root,"ScopeMount",Vector3(0,0.074,z),Vector3(0.048,0.035,0.022),dark)
			_cylinder(root,"ScopeRing",Vector3(0,0.097,z),0.025,0.022,brass,Vector3(90,0,0))
		_cylinder(root,"ScopeBody",Vector3(0,0.097,-0.087),0.021,0.235,dark,Vector3(90,0,0))
		_cylinder(root,"ObjectiveBell",Vector3(0,0.097,-0.216),0.030,0.038,dark,Vector3(90,0,0))
		var lens := _mat(Color("356574"),0.58,0.12)
		_cylinder(root,"ObjectiveLens",Vector3(0,0.097,-0.237),0.025,0.003,lens,Vector3(90,0,0))
		_box(root,"ElevationDial",Vector3(0,0.127,-0.09),Vector3(0.025,0.022,0.025),dark)
		_trigger_guard(root, Vector3(0,-0.032,-0.04),dark)
		for z in [-0.18,-0.15,-0.12]:
			_box(root,"ForestockCheckering",Vector3(0,-0.019,z),Vector3(0.048,0.004,0.011),rubber)
	else:
		_profile(root,"Frame",PackedVector2Array([Vector2(0.035,0.033),Vector2(-0.14,0.033),Vector2(-0.14,0.016),Vector2(-0.025,0.003),Vector2(-0.004,-0.062),Vector2(0.035,-0.066),Vector2(0.042,-0.045)]),0.033,dark)
		_box(root,"Slide",Vector3(0,0.052,-0.05),Vector3(0.038,0.036,0.181),steel)
		_box(root,"FrontSight",Vector3(0,0.075,-0.121),Vector3(0.007,0.011,0.009),dark)
		for x in [-0.012,0.012]:
			_box(root,"RearSight",Vector3(x,0.075,0.025),Vector3(0.008,0.010,0.012),dark)
		_box(root,"EjectionPort",Vector3(0.0195,0.055,-0.06),Vector3(0.002,0.019,0.037),dark)
		_cylinder(root,"Barrel",Vector3(0,0.055,-0.145),0.013,0.014,dark,Vector3(90,0,0))
		_cylinder(root,"Bore",Vector3(0,0.055,-0.153),0.0075,0.002,rubber,Vector3(90,0,0))
		for z in [-0.005,0.004,0.013,0.022]:
			_box(root,"SlideSerration",Vector3(0,0.054,z),Vector3(0.039,0.029,0.003),dark)
		_box(root,"MagazineBase",Vector3(0,-0.065,0.02),Vector3(0.037,0.009,0.043),rubber)
		for y in [-0.015,-0.027,-0.039,-0.051]:
			_box(root,"GripTexture",Vector3(0,y,0.02),Vector3(0.036,0.003,0.034),rubber)
		_trigger_guard(root,Vector3(0,-0.014,-0.047),dark)

static func _trigger_guard(root: Node3D, p: Vector3, mat: Material) -> void:
	_box(root,"GuardBottom",p+Vector3(0,-0.018,0),Vector3(0.015,0.008,0.057),mat)
	_box(root,"GuardFront",p+Vector3(0,-0.004,-0.027),Vector3(0.015,0.036,0.008),mat)
	_box(root,"Trigger",p+Vector3(0,0,0.006),Vector3(0.008,0.026,0.008),mat)

static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

static func _box(root: Node3D, label: String, p: Vector3, size: Vector3, mat: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = BoxMesh.new()
	part.mesh.size = size
	part.material_override = mat
	part.position = p
	root.add_child(part)

static func _cylinder(root: Node3D, label: String, p: Vector3, radius: float, length: float, mat: Material, angles: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	part.mesh = mesh
	part.position = p
	part.rotation_degrees = angles
	part.material_override = mat
	root.add_child(part)

static func _profile(root: Node3D, label: String, outline: PackedVector2Array, width: float, mat: Material) -> void:
	# Extruded Y/Z silhouette: shaped stocks and blades instead of rectangular bars.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0,1.0]:
		for t in range(0,indices.size(),3):
			for k in ([0,1,2] if side > 0 else [2,1,0]):
				var p := outline[indices[t+k]]
				surface.add_vertex(Vector3(side*width*0.5,p.y,p.x))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var vertices := [Vector3(-width*0.5,a.y,a.x),Vector3(width*0.5,a.y,a.x),Vector3(width*0.5,b.y,b.x),Vector3(-width*0.5,b.y,b.x)]
		for k in [0,1,2,0,2,3]: surface.add_vertex(vertices[k])
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = surface.commit()
	part.material_override = mat
	root.add_child(part)
