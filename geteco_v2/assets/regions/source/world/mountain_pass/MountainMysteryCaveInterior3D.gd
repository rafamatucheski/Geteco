extends Node3D

const DETAIL := preload("res://assets/regions/source/world/mountain_pass/CaveDetailGeometry.gd")
const SECRET_POSITION := Vector3(3.1, 0.54, -0.6)
const FLOOR_OUTLINE: Array[Vector2] = [Vector2(-1,5.5),Vector2(-4.9,4.7),Vector2(-7.6,2.8),Vector2(-7.8,-1.9),Vector2(-5.5,-5.5),Vector2(-1.8,-6.2),Vector2(2.1,-5.8),Vector2(6.4,-4.4),Vector2(7.7,-1.1),Vector2(7.3,2.7),Vector2(4.6,4.7),Vector2(1,5.5)]

func _ready() -> void:
	_build_cave()
	_build_hideout_details()

func _build_cave() -> void:
	var stone := _mat(Color("343b3c"), 0.98)
	var dark := _mat(Color("171d1f"), 1.0)
	var dirt := _mat(Color("403a31"), 0.96)
	var canvas := _mat(Color("806a48"), 0.92)
	var steel := _mat(Color("68747a"), 0.42, 0.56)
	var amber := _mat(Color("c48a3d"), 0.62, 0.05, 1.4)
	var outline := PackedVector2Array(FLOOR_OUTLINE)
	var floor_surface := SurfaceTool.new()
	floor_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		for p in [Vector2.ZERO,outline[i],outline[(i+1)%outline.size()]]:
			floor_surface.add_vertex(Vector3(p.x,0,p.y))
	floor_surface.generate_normals()
	var floor_node := MeshInstance3D.new()
	floor_node.mesh=floor_surface.commit()
	var floor_material := ShaderMaterial.new()
	floor_material.shader = preload("res://assets/regions/source/world/mountain_pass/CaveFloor.gdshader")
	floor_node.material_override = floor_material
	add_child(floor_node)
	var rock := preload("res://assets/regions/source/world/mountain_pass/CaveRockGeometry.gd")
	for i in outline.size()-1:
		var a := outline[i]
		var b := outline[i+1]
		for j in 4:
			var p := a.lerp(b,float(j)/4.0)
			var height := 3.0 if p.y<1 else 0.8
			rock.rock(self,Vector3(p.x,height*0.5,p.y),Vector3(1.7,height,1.8),i*19+j,Color("394443"))
	var scatter := RandomNumberGenerator.new()
	scatter.seed=715
	for i in 75:
		var a := scatter.randf()*TAU
		var radius := sqrt(scatter.randf())*6.5
		rock.rock(self,Vector3(cos(a)*radius,0.08,sin(a)*radius*0.65),Vector3(scatter.randf_range(0.1,0.4),0.18,0.26),700+i,Color("505951"))
	for entry in [
		[Vector3(-5.7, 1.45, -3.7), Vector3(3.2, 3.0, 2.2)],
		[Vector3(5.9, 1.25, -3.9), Vector3(3.0, 2.7, 2.0)],
		[Vector3(-6.1, 1.1, 2.9), Vector3(2.5, 2.3, 2.2)],
		[Vector3(6.3, 1.0, 2.7), Vector3(2.1, 2.1, 2.2)],
		[Vector3(0.0, 1.7, -5.6), Vector3(3.4, 3.6, 1.2)],
	]:
		_sphere(entry[0], entry[1], stone)
	# Explorer camp, climbing hardware and the route that disappears deeper in.
	_box("CampBedroll", Vector3(-3.5, 0.13, -0.7), Vector3(2.4, 0.14, 1.0), canvas, Vector3(0, 0.24, 0))
	_box("SupplyCase", Vector3(-4.8, 0.42, 0.8), Vector3(1.1, 0.75, 0.8), dark)
	for i in 4:
		_cylinder("ClimbingPin", Vector3(3.7 + i * 0.38, 0.13, -1.0 + i * 0.16), 0.035, 0.62, steel, Vector3(0, 0, PI * 0.5))
	for point in [Vector3(-1.4, 0.9, -4.8), Vector3(1.2, 1.15, -4.8), Vector3(0, 1.65, -4.8)]:
		var scratch := _box("ClawMark", point, Vector3(0.055, 1.05, 0.04), _mat(Color("a8aaa0"), 0.86), Vector3(0, 0, -0.22 + point.x * 0.04))
		scratch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := _cylinder("CampLantern", Vector3(-2.0, 0.32, -0.2), 0.12, 0.36, amber)
	for y in [0.1,0.55]:
		_cylinder("LanternCap",Vector3(-2,y,-0.2),0.19,0.09,dark)
	for x in [-2.14,-1.86]:
		_cylinder("LanternFrame",Vector3(x,0.32,-0.2),0.018,0.45,steel)
	_cylinder("RolledBlanket",Vector3(-4.38,0.28,-0.48),0.24,0.95,canvas,Vector3(PI*0.5,0,0))
	for x in [-5.12,-4.48]:
		_box("CaseStrap",Vector3(x,0.81,0.8),Vector3(0.08,0.035,0.82),steel)
	var light := OmniLight3D.new()
	light.position = lamp.position + Vector3(0, 0.2, 0)
	light.light_color = Color("ffc274")
	light.light_energy = 2.2
	light.omni_range = 6.0
	add_child(light)

func _build_hideout_details() -> void:
	var stone := _mat(Color("58625a"), 0.96)
	var damp := _mat(Color("283e39"), 0.24)
	var wood := _mat(Color("66513a"), 0.88)
	var steel := _mat(Color("657170"), 0.36, 0.65)
	var olive := _mat(Color("485038"), 0.76)
	var foam := _mat(Color("172222"), 0.98)
	var rope_mat := _mat(Color("a58e63"), 0.95)
	var mineral := _mat(Color("738c7b"), 0.7)
	# Broad wet patches break up the bare floor; the central route stays dry.
	for patch in [[Vector2(-5.0,-2.4),Vector2(1.6,0.65)],[Vector2(5.4,2.0),Vector2(1.4,0.55)],[Vector2(-1.8,-4.2),Vector2(1.8,0.65)]]:
		DETAIL.floor_patch(self,"WetRockPool",DETAIL.ellipse(patch[0],patch[1]),0.018,damp)
	for i in 12:
		var side := -1.0 if i%2 == 0 else 1.0
		var p := Vector3(side*(5.8+float(i%3)*0.32),0,-3.5+float(i/2)*0.95)
		var height := 0.45+float(i%4)*0.30
		var stalagmite := DETAIL.cylinder(self,"Stalagmite",p+Vector3.UP*height*0.5,0.24,0.035,height,stone)
		stalagmite.set_meta("interior_solid_id",StringName("Stalagmite%d" % i))
		if i < 6:
			DETAIL.cylinder(self,"Stalactite",Vector3(p.x,2.5,p.z),0.02,0.28,1.1,stone)
	# Layered mineral seams and fallen slabs around the rear wall.
	for i in 8:
		var p := Vector3(-5.8+i*1.6,1.1+sin(i)*0.4,-4.9)
		_box("MineralSeam",p,Vector3(0.9,0.10,0.15),mineral,Vector3(0,0,0.22*sin(i)))
		if i%2 == 0: _sphere(Vector3(p.x,0.18,-3.8),Vector3(1.3,0.32,0.75),stone)
	# Expedition supplies: timber supports, metal tins, rope, tools and a map board.
	for z in [-0.9,-0.3]:
		_box("CotRail",Vector3(-3.5,0.14,z),Vector3(2.5,0.12,0.10),wood)
	for x in [-4.5,-2.5]:
		for z in [-0.9,-0.3]: _box("CotFoot",Vector3(x,0.06,z),Vector3(0.12,0.2,0.12),wood)
	_box("SuppliesLid",Vector3(-4.8,0.83,0.41),Vector3(1.18,0.12,0.85),olive,Vector3(-0.55,0,0))
	for i in 5:
		_cylinder("FoodTin",Vector3(-5.1+float(i%3)*0.22,0.10,1.55+float(i/3)*0.24),0.085,0.2,steel)
	for i in 4:
		var coil := MeshInstance3D.new()
		coil.name = "ClimbingRope"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.23+float(i)*0.035
		ring.outer_radius = ring.inner_radius+0.025
		ring.rings = 20
		ring.ring_segments = 5
		coil.mesh = ring
		coil.material_override = rope_mat
		coil.position = Vector3(-3.9,0.06+float(i)*0.025,1.55)
		add_child(coil)
	_box("MapBoard",Vector3(-3.1,0.06,2.05),Vector3(1.25,0.08,0.75),wood,Vector3(0,-0.25,0))
	_box("MapSheet",Vector3(-3.1,0.108,2.05),Vector3(1.05,0.012,0.60),_mat(Color("b6a57b"),0.95),Vector3(0,-0.25,0))
	_box("PickaxeHandle",Vector3(-5.6,0.48,0.6),Vector3(0.07,1.0,0.07),wood,Vector3(0,0,-0.45))
	_box("PickaxeHead",Vector3(-5.4,0.93,0.6),Vector3(0.55,0.09,0.09),steel)
	# The secret reward is deliberately readable from the entrance.
	_box("SecretWeaponCase",Vector3(3.1,0.22,-0.6),Vector3(2.35,0.44,1.15),olive)
	_box("WeaponCaseFoam",Vector3(3.1,0.455,-0.6),Vector3(2.18,0.055,0.95),_mat(Color("b29b65"),0.98))
	_box("OpenWeaponCaseLid",Vector3(3.1,0.92,-1.24),Vector3(2.38,1.02,0.12),olive,Vector3(-0.24,0,0))
	_box("LidFoam",Vector3(3.1,0.92,-1.16),Vector3(2.15,0.84,0.04),foam,Vector3(-0.24,0,0))
	for x in [2.25,3.95]:
		_box("CaseLatch",Vector3(x,0.40,0.0),Vector3(0.14,0.18,0.08),steel)
	for i in 3:
		DETAIL.cylinder(self,"SpareRocket",Vector3(4.70+i*0.20,0.10,-0.15),0.07,0.035,0.72,olive,Vector3(PI*0.5,0,0))
	# Warm lighting around the cache, cool damp stone at the back.
	var amber := _mat(Color("ffb95d"),0.45,0.0,1.2)
	_cylinder("CacheLantern",Vector3(1.6,0.28,-1.1),0.13,0.36,amber)
	for y in [0.08,0.50]: _cylinder("CacheLanternCap",Vector3(1.6,y,-1.1),0.17,0.08,steel)
	var cache_light := OmniLight3D.new()
	cache_light.name = "CacheWarmLight"
	cache_light.position = Vector3(2.5,1.7,-0.4)
	cache_light.light_color = Color("ffc77c")
	cache_light.light_energy = 2.0
	cache_light.omni_range = 4.8
	cache_light.shadow_enabled = false
	add_child(cache_light)
	# Footprints guide the eye from the entrance to the open case.
	for i in 9:
		var t := float(i)/8.0
		var p := Vector3(0,0.023,3.6).lerp(Vector3(3.1,0.023,0.65),t)
		p.x += -0.11 if i%2 == 0 else 0.11
		_box("Bootprint",p,Vector3(0.12,0.008,0.27),damp,Vector3(0,-0.75,0))

func _mat(color: Color, roughness: float, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _box(node_name: String, point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation = rotation
	var groups := {
		"CampBedroll":"ExpeditionCot", "CotRail":"ExpeditionCot", "CotFoot":"ExpeditionCot",
		"SupplyCase":"SupplyCase", "SuppliesLid":"SupplyCase", "CaseStrap":"SupplyCase",
		"SecretWeaponCase":"SecretWeaponCase", "WeaponCaseFoam":"SecretWeaponCase",
		"OpenWeaponCaseLid":"SecretWeaponCase", "LidFoam":"SecretWeaponCase", "CaseLatch":"SecretWeaponCase",
		"PickaxeHandle":"CampPickaxe", "PickaxeHead":"CampPickaxe"
	}
	node.set_meta("interior_solid_id",StringName(groups.get(node_name,"")))
	add_child(node)
	return node

func _sphere(point: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var rock := preload("res://assets/regions/source/world/mountain_pass/CaveRockGeometry.gd").rock(self,point,scale_value,get_child_count()*13,material.albedo_color)
	rock.set_meta("interior_solid_id",StringName("CaveRock%d" % get_child_count()))
	return rock

func _cylinder(node_name: String, point: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation = rotation
	var groups := {"CampLantern":"CampLantern", "LanternCap":"CampLantern", "LanternFrame":"CampLantern", "CacheLantern":"CacheLantern", "CacheLanternCap":"CacheLantern", "RolledBlanket":"ExpeditionCot", "FoodTin":"FoodTins"}
	node.set_meta("interior_solid_id",StringName(groups.get(node_name,"")))
	add_child(node)
	return node
