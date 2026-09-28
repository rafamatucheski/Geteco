extends Node3D
## Shaded spectator shore and one central floodlight tower, streamed with the park.
var course: Node3D
var _materials := {}
var _lights: Array[SpotLight3D] = []
var _lenses: Array[StandardMaterial3D] = []
var _solids: StaticBody3D
var tower_position := Vector3(-186,0,-111)

func _ready() -> void:
	name = "MotocrossScenery"
	add_to_group("motocross_scenery")
	_solids = StaticBody3D.new()
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)
	_trees()
	_tower()
	_spectator_shore()

func _mat(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .85
		_materials[color] = material
	return _materials[color]

func _box(p: Vector3, size: Vector3, color: Color, solid := false, parent: Node3D = null) -> MeshInstance3D:
	if parent == null: parent = self
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = p
	visual.material_override = _mat(color)
	parent.add_child(visual)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = parent.to_global(p)
		_solids.add_child(collision)
	return visual

func _beam(a: Vector3, b: Vector3, width: float, color: Color, parent: Node3D = null) -> void:
	if parent == null: parent = self
	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = (a+b)*.5
	visual.basis = Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	visual.material_override = _mat(color)
	parent.add_child(visual)

func _trees() -> void:
	for i in range(8,course.points.size()-1,25):
		var p: Vector3 = course.points[i]
		var tangent: Vector3 = course.points[i+1]-p
		var side := tangent.cross(Vector3.UP).normalized()
		for sign_value in [-1,1]:
			var at: Vector3 = p+side*10.0*sign_value
			if at.x > -91 or at.z > -44 or at.z < -154: continue
			if float(course.nearest(at).lateral) < 8.5: continue
			var point := Vector2(at.x,at.z)
			at.y = course.surface_height(point)-.08
			var tree := preload("res://world/regions/NativePine.gd").create(4,false)
			tree.name = "ShadeTree"
			tree.position = at
			tree.scale = Vector3.ONE*(1.6+float(i%3)*.16)
			add_child(tree)
			var collision := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = .48
			shape.height = 5.5
			collision.shape = shape
			collision.position = at+Vector3.UP*2.75
			_solids.add_child(collision)

func _tower() -> void:
	tower_position.y = course._height(Vector2(tower_position.x,tower_position.z))
	_box(tower_position+Vector3.UP*.3,Vector3(3,.6,3),Color("74776d"),true)
	var top := tower_position+Vector3.UP*23
	for side in [-1,1]:
		for end in [-1,1]:
			var foot := tower_position+Vector3(side*.7,.6,end*.7)
			_beam(foot,top+Vector3(side*.4,0,end*.4),.10,Color("525d5c"))
	for level in 7:
		var bottom := tower_position+Vector3.UP*(.6+float(level)*3.1)
		for side in [-1,1]:
			_beam(bottom+Vector3(-.65,0,side*.65),bottom+Vector3(.65,3.1,side*.65),.035,Color("89928c"))
	_box(tower_position+Vector3.UP*11.5,Vector3(1.4,23,1.4),Color(0,0,0,0),true).hide()
	_box(top,Vector3(5,.18,4),Color("455154"))
	for i in 4:
		var angle := float(i)*TAU/4
		var direction := Vector3(sin(angle),0,cos(angle))
		var light := SpotLight3D.new()
		light.name = "Floodlight%d"%i
		light.position = top+direction*1.5+Vector3.UP*.7
		add_child(light)
		light.look_at(tower_position+direction*48)
		light.light_color = Color("ffe8bf")
		light.light_energy = 10.0
		light.light_specular = .55
		light.spot_range = 125
		light.spot_angle = 62
		light.spot_attenuation = .6
		light.light_size = .8
		light.shadow_enabled = true
		light.distance_fade_enabled = true
		light.distance_fade_begin = 160
		light.distance_fade_length = 50
		light.visible = false
		_lights.append(light)
		var housing := _box(light.position,Vector3(1.5,.9,.30),Color("303b3d"))
		housing.basis = light.basis
		var lens := _box(light.position-light.basis.z*.17,Vector3(1.30,.72,.025),Color("e5e0cb"))
		lens.basis = light.basis
		var material := _mat(Color("e5e0cb")).duplicate() as StandardMaterial3D
		material.emission_enabled = true
		material.emission = Color("ffe4ad")
		material.emission_energy_multiplier = 0
		lens.material_override = material
		_lenses.append(material)

func set_lighting(night: float, viewer: Vector3) -> void:
	var nearby := viewer.distance_squared_to(tower_position) < 210*210
	for light in _lights:
		light.visible = night > .03 and nearby
		light.light_energy = 10.0*night
	for lens in _lenses: lens.emission_energy_multiplier = night*2.5

func _spectator_shore() -> void:
	# Moored in real water east of Harbor's rural shoreline (x = -80).
	for i in 3:
		var boat := Node3D.new()
		boat.name = "SpectatorBoat%d"%i
		boat.position = Vector3(-74,-.72,-113+float(i)*23)
		add_child(boat)
		_boat(boat,[Color("dbc9a8"),Color("497b89"),Color("914d34")][i])
		for j in 2: _spectator(boat,Vector3(float(j)*1.3-.65,.57,.6-float(j)*1.2),[Color("dd7637"),Color("497dae"),Color("d4bd51")][(i+j)%3])
		_beam(Vector3(-79,.5,boat.position.z-2),boat.position+Vector3(-1.3,.65,-2),.025,Color("b9aa80"))
		_beam(Vector3(-79,.5,boat.position.z+2),boat.position+Vector3(-1.3,.65,2),.025,Color("b9aa80"))

func _boat(boat: Node3D, color: Color) -> void:
	var outline := PackedVector2Array([Vector2(-1.55,3),Vector2(1.55,3),Vector2(1.55,-1.8),Vector2(.85,-3.1),Vector2(0,-3.8),Vector2(-.85,-3.1),Vector2(-1.55,-1.8)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var corners := [Vector3(a.x,.75,a.y),Vector3(b.x,.75,b.y),Vector3(a.x*.67,-.25,a.y*.88),Vector3(b.x*.67,-.25,b.y*.88)]
		for index in [0,2,1,1,2,3]: surface.add_vertex(corners[index])
	surface.generate_normals()
	var hull := MeshInstance3D.new()
	hull.mesh = surface.commit()
	var material := _mat(color).duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.material_override = material
	boat.add_child(hull)
	_box(Vector3(0,.48,.1),Vector3(2.65,.18,5.5),Color("b49c72"),true,boat)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		_beam(Vector3(a.x,.78,a.y),Vector3(b.x,.78,b.y),.09,Color("e2ddd0"),boat)
	for z in [-1.4,1.5]: _box(Vector3(0,.72,z),Vector3(2.7,.16,.6),Color("77583b"),true,boat)
	_box(Vector3(0,.4,3.1),Vector3(.65,.9,.6),Color("29373a"),true,boat)
	_beam(Vector3(.3,1,2.7),Vector3(.8,1.1,2.25),.05,Color("29373a"),boat)

func _spectator(parent: Node3D, at: Vector3, jersey: Color) -> void:
	var person := preload("res://activities/motocross/MotocrossSpectator.gd").new()
	person.configure({"identity":parent.get_child_count(),"jersey":jersey,"deck":parent,"bounds":Rect2(-1.325,-1.08,2.65,2.28),"flee_radius":1.0})
	person.position = at
	person.rotation.y = PI*.5
	parent.add_child(person)
