extends RefCounted
## Geometria de arma compartilhada, em escala humana. A origem é a mão que atira, a boca do cano olha para -Z.
## As mesmas malhas aparecem equipadas e como loot no chão, preservando a silhueta.

static func build(root: Node3D, id: String) -> void:
	var steel := _mat(Color("697782"), 0.60, 0.40)
	var dark := _mat(Color("222b30"), 0.45, 0.46)
	var rubber := _mat(Color("252629"), 0.0, 0.86)
	var wood := _mat(Color("714331"), 0.0, 0.62)
	var brass := _mat(Color("b7955b"), 0.65, 0.38)
	if id == "axe":
		var trail := preload("res://gameplay/AxeSwingTrail.gd").new()
		trail.name = "AxeSwingTrail"
		root.add_child(trail)
		# Cabo de freixo torneado: fino no meio e alargando num talão no fim, como um cabo de verdade.
		_lathe(root,"AshHandle",PackedVector2Array([Vector2(-0.495,0.0155),Vector2(-0.30,0.0150),Vector2(-0.10,0.0158),Vector2(0.03,0.0172),Vector2(0.10,0.0200),Vector2(0.145,0.0245),Vector2(0.162,0.0225),Vector2(0.165,0.0)]),wood)
		_cylinder(root,"GripWrap",Vector3(0,0,0.065),0.020,0.10,rubber,Vector3(90,0,0))
		# A cabeça fica deitada aqui (gume para +X); o rig a gira 90° na pegada (WeaponRigPose).
		var head := Node3D.new()
		head.name = "ForgedHead"
		head.rotation.z = -PI * 0.5
		root.add_child(head)
		# Cunha de verdade: a espessura cai de forma contínua do olho até o gume (linhas: reach, z_tras, z_frente, meia-espessura).
		_loft(head,"ForgedBlade",[[-0.058,-0.492,-0.398,0.025],[0.062,-0.492,-0.398,0.025],[0.078,-0.497,-0.393,0.019],[0.118,-0.516,-0.384,0.0085],[0.150,-0.523,-0.372,0.0035],[0.170,-0.522,-0.367,0.0022],[0.184,-0.508,-0.378,0.0016],[0.192,-0.478,-0.402,0.0008]],dark)
		_loft(head,"CuttingEdge",[[0.158,-0.524,-0.369,0.0030],[0.170,-0.523,-0.368,0.0026],[0.184,-0.509,-0.379,0.0020],[0.192,-0.478,-0.402,0.0011]],_mat(Color("aeb8bf"),0.9,0.22))
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
		# Os dedos entram pelos anéis na vertical; a face de golpe aponta para -Z.
		for i in range(4):
			var x_off := -0.033 + i * 0.022
			var ring := MeshInstance3D.new()
			ring.name = "FingerRing_%d" % i
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.0085
			mesh.outer_radius = 0.0135
			mesh.rings = 16
			mesh.ring_segments = 8
			ring.mesh = mesh
			ring.position = Vector3(x_off, 0, -0.012)
			ring.material_override = gold_brass
			root.add_child(ring)
			_box(root, "KnucklePyramid_%d" % i, Vector3(x_off, 0, -0.030), Vector3(0.013, 0.013, 0.012), steel)
		_box(root, "StrikingRidge", Vector3(0, 0, -0.0225), Vector3(0.094, 0.011, 0.012), gold_brass)
		_cylinder(root, "PalmBar", Vector3(0, 0, 0.034), 0.0085, 0.100, gold_brass, Vector3(0, 0, 90))
		for x in [-0.047, 0.047]:
			_box(root, "PalmSupport", Vector3(x, 0, 0.011), Vector3(0.011, 0.015, 0.050), gold_brass)
	elif id in ["bat", "taco", "baseball"]:
		var bat_trail := preload("res://gameplay/AxeSwingTrail.gd").new()
		bat_trail.name = "AxeSwingTrail"
		bat_trail.inner = Vector3(0, 0, -0.24)
		bat_trail.outer = Vector3(0, 0, -0.49)
		bat_trail.opacity = 0.12
		root.add_child(bat_trail)
		# Perfil torneado: o corpo afina de forma contínua até o cabo, como um taco de verdade.
		_lathe(root, "BatBarrel", PackedVector2Array([Vector2(-0.490,0.0),Vector2(-0.484,0.019),Vector2(-0.468,0.029),Vector2(-0.430,0.0340),Vector2(-0.340,0.0355),Vector2(-0.250,0.0330),Vector2(-0.160,0.0260),Vector2(-0.080,0.0200),Vector2(-0.010,0.0172),Vector2(0.150,0.0172)]), wood)
		_cylinder(root, "BatGrip", Vector3(0, 0, 0.075), 0.0185, 0.15, rubber, Vector3(90, 0, 0))
		_lathe(root, "BatPommel", PackedVector2Array([Vector2(0.150,0.0185),Vector2(0.160,0.0235),Vector2(0.178,0.0262),Vector2(0.194,0.0215),Vector2(0.199,0.0)]), wood)
	elif id == "hunting_rifle":
		_stock_profile(root,"WalnutStock",PackedVector2Array([Vector2(0.18,-0.085),Vector2(0.175,0.042),Vector2(0.13,0.037),Vector2(0.085,0.045),Vector2(-0.25,0.018),Vector2(-0.25,-0.017),Vector2(-0.065,-0.025),Vector2(-0.012,-0.035),Vector2(0.035,-0.07),Vector2(0.065,-0.052),Vector2(0.10,-0.014),Vector2(0.14,-0.052)]),0.046,wood)
		_box(root,"ButtPad",Vector3(0,-0.02,0.182),Vector3(0.050,0.135,0.015),rubber)
		_section_box(root,"Receiver",Vector3(0,0.04,-0.055),Vector3(0.041,0.035,0.19),dark,0.006)
		_cylinder(root,"Barrel",Vector3(0,0.055,-0.375),0.012,0.43,steel,Vector3(90,0,0))
		_cylinder(root,"Bore",Vector3(0,0.055,-0.591),0.007,0.003,rubber,Vector3(90,0,0))
		_cylinder(root,"Bolt",Vector3(0.023,0.053,-0.021),0.008,0.042,steel,Vector3(0,0,90))
		_cylinder(root,"BoltLever",Vector3(0.046,0.035,-0.021),0.006,0.039,steel,Vector3(0,0,-25))
		_section_box(root,"BoltKnob",Vector3(0.052,0.015,-0.021),Vector3(0.020,0.019,0.020),dark,0.004)
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
		_profile(root,"Frame",PackedVector2Array([Vector2(0.035,0.033),Vector2(-0.132,0.033),Vector2(-0.140,0.024),Vector2(-0.132,0.015),Vector2(-0.052,0.010),Vector2(-0.025,0.003),Vector2(-0.004,-0.057),Vector2(0.005,-0.066),Vector2(0.032,-0.066),Vector2(0.042,-0.045)]),0.033,dark)
		_section_box(root,"Slide",Vector3(0,0.052,-0.05),Vector3(0.038,0.036,0.181),steel,0.0045)
		_box(root,"FrontSight",Vector3(0,0.075,-0.121),Vector3(0.007,0.011,0.009),dark)
		for x in [-0.012,0.012]:
			_box(root,"RearSightLeft" if x < 0.0 else "RearSightRight",Vector3(x,0.075,0.025),Vector3(0.008,0.010,0.012),dark)
		_box(root,"EjectionPort",Vector3(0.0195,0.055,-0.06),Vector3(0.002,0.019,0.037),dark)
		_cylinder(root,"Barrel",Vector3(0,0.055,-0.145),0.013,0.014,dark,Vector3(90,0,0))
		_cylinder(root,"Bore",Vector3(0,0.055,-0.153),0.0075,0.002,rubber,Vector3(90,0,0))
		for z in [-0.005,0.004,0.013,0.022]:
			_box(root,"SlideSerration_%s" % str(z),Vector3(0,0.054,z),Vector3(0.039,0.029,0.003),dark)
		_box(root,"MagazineBase",Vector3(0,-0.065,0.02),Vector3(0.037,0.009,0.043),rubber)
		for y in [-0.015,-0.027,-0.039,-0.051]:
			_box(root,"GripTexture",Vector3(0,y,0.02),Vector3(0.036,0.003,0.034),rubber)
		_trigger_guard(root,Vector3(0,-0.014,-0.047),dark)
		# Esses detalhes pertencem ao ferrolho e precisam acompanhá-lo no recuo
		# e na recarga. Mantém o cano e a empunhadura presos à armação parada.
		var slide := root.get_node("Slide") as Node3D
		for child in root.get_children():
			if child.name == "FrontSight" or String(child.name).begins_with("RearSight") or String(child.name).begins_with("SlideSerration") or child.name == "EjectionPort":
				var detail := child as Node3D
				var local := detail.transform
				root.remove_child(detail)
				slide.add_child(detail)
				detail.transform = slide.transform.affine_inverse() * local

static func _trigger_guard(root: Node3D, p: Vector3, mat: Material) -> void:
	_box(root,"GuardBottom",p+Vector3(0,-0.018,0),Vector3(0.015,0.008,0.057),mat)
	_box(root,"GuardFront",p+Vector3(0,-0.004,-0.027),Vector3(0.015,0.036,0.008),mat)
	_box(root,"Trigger",p+Vector3(0,0,0.006),Vector3(0.008,0.026,0.008),mat)

static var _materials: Dictionary = {}
static var _section_meshes: Dictionary = {}
const MATERIAL_CACHE_LIMIT := 128
const SECTION_CACHE_LIMIT := 64

static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "%s:%.4f:%.4f" % [color.to_html(true), metallic, roughness]
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if _materials.size() < MATERIAL_CACHE_LIMIT: _materials[key] = mat
	return mat

## A seção octogonal pega luz em chanfros largos e deliberados. Os
## limites da caixa original e a origem do nó ficam exatos para empunhaduras e animação.
static func _section_box(root: Node3D, label: String, p: Vector3, size: Vector3, mat: Material, bevel: float) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = section_mesh(size, bevel)
	part.material_override = mat
	part.position = p
	root.add_child(part)

static func section_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	var key := Vector4(size.x, size.y, size.z, bevel)
	if _section_meshes.has(key): return _section_meshes[key]
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, half.y) * 0.7)
	var outline := PackedVector2Array([
		Vector2(-half.x+b,-half.y), Vector2(half.x-b,-half.y),
		Vector2(half.x,-half.y+b), Vector2(half.x,half.y-b),
		Vector2(half.x-b,half.y), Vector2(-half.x+b,half.y),
		Vector2(-half.x,half.y-b), Vector2(-half.x,-half.y+b)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0,1.0]:
		st.set_normal(Vector3(0,0,side))
		for t in range(0,indices.size(),3):
			for k in ([2,1,0] if side > 0.0 else [0,1,2]):
				var point := outline[indices[t+k]]
				st.add_vertex(Vector3(point.x,point.y,side*half.z))
	for i in outline.size():
		var a := outline[i]
		var c := outline[(i+1)%outline.size()]
		st.set_normal(Vector3(c.y-a.y,a.x-c.x,0).normalized())
		var points := [Vector3(a.x,a.y,-half.z),Vector3(a.x,a.y,half.z),Vector3(c.x,c.y,half.z),Vector3(c.x,c.y,-half.z)]
		for k in [0,1,2,0,2,3]: st.add_vertex(points[k])
	var mesh := st.commit()
	if _section_meshes.size() < SECTION_CACHE_LIMIT: _section_meshes[key] = mesh
	return mesh

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

## Sólido por fatias ao longo de Y: cada linha é [y, z_min, z_max, meia_largura_em_x]. Serve para
## cunhas (cabeça de machado) onde a espessura varia com a distância, sem degraus.
static func _loft(root: Node3D, label: String, rows: Array, mat: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for row in rows:
		rings.append([Vector3(-row[3], row[0], row[1]), Vector3(row[3], row[0], row[1]), Vector3(row[3], row[0], row[2]), Vector3(-row[3], row[0], row[2])])
	for i in rings.size() - 1:
		for e in 4:
			var q := [rings[i][e], rings[i][(e + 1) % 4], rings[i + 1][(e + 1) % 4], rings[i + 1][e]]
			for k in [0, 2, 1, 0, 3, 2]: surface.add_vertex(q[k])
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		for k in ([0, 1, 2, 0, 2, 3] if end == 0 else [0, 2, 1, 0, 3, 2]): surface.add_vertex(r[k])
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = surface.commit()
	part.material_override = mat
	root.add_child(part)

## Corpo de granada "abacaxi": esfera de `lat` x `lon` gomos, cada um uma pirâmide baixa de faces
## planas (centro em `radius`, juntas a 94 %). Eixo vertical em Y.
static func _pineapple(root: Node3D, label: String, center: Vector3, radius: float, mat: Material, lat := 6, lon := 10) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in lat:
		for j in lon:
			var corners: Array[Vector3] = []
			# Ordem a, d, c, b = face voltada para fora (mesmo giro do `_lathe`).
			for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				corners.append(_sphere_point(k[0] / float(lat), k[1] / float(lon), radius * 0.94))
			var mid := _sphere_point((i + 0.5) / lat, (j + 0.5) / lon, radius)
			for k in 4:
				var p: Vector3 = corners[k]
				var q: Vector3 = corners[(k + 1) % 4]
				if p.distance_squared_to(q) < 1e-8: continue
				for v in [p, q, mid]: surface.add_vertex(v)
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = surface.commit()
	part.material_override = mat
	part.position = center
	root.add_child(part)

static func _sphere_point(u: float, v: float, r: float) -> Vector3:
	var theta := PI * u
	var phi := TAU * v
	return Vector3(sin(theta) * cos(phi) * r, cos(theta) * r, sin(theta) * sin(phi) * r)

## Sólido de revolução em torno do eixo Z; o perfil é (z, raio), da ponta (-Z) para trás.
static func _lathe(root: Node3D, label: String, profile: PackedVector2Array, mat: Material, segments := 20) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for i in profile.size() - 1:
		for j in segments:
			var a0 := TAU * j / segments
			var a1 := TAU * (j + 1) / segments
			var p00 := Vector3(cos(a0) * profile[i].y, sin(a0) * profile[i].y, profile[i].x)
			var p01 := Vector3(cos(a1) * profile[i].y, sin(a1) * profile[i].y, profile[i].x)
			var p10 := Vector3(cos(a0) * profile[i+1].y, sin(a0) * profile[i+1].y, profile[i+1].x)
			var p11 := Vector3(cos(a1) * profile[i+1].y, sin(a1) * profile[i+1].y, profile[i+1].x)
			for v in [p00, p11, p10, p00, p01, p11]: surface.add_vertex(v)
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = surface.commit()
	part.material_override = mat
	root.add_child(part)

## Uma coronha de madeira moldada afina no guarda-mão e no punho. O contorno Y/Z
## definido e as posições de contato da soleira e da empunhadura ficam intactos.
static func _stock_profile(root: Node3D, label: String, outline: PackedVector2Array, width: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(outline)
	var min_z := outline[0].x
	var max_z := outline[0].x
	for point in outline:
		min_z = minf(min_z,point.x)
		max_z = maxf(max_z,point.x)
	var sides: Array[PackedVector3Array] = []
	for sign_value in [-1.0,1.0]:
		var points := PackedVector3Array()
		for point in outline:
			var portion := inverse_lerp(min_z,max_z,point.x)
			var cheek_width := width * lerpf(.72,1.0,smoothstep(.25,.8,portion))
			points.append(Vector3(sign_value*cheek_width*.5,point.y,point.x))
		sides.append(points)
		for t in range(0,indices.size(),3):
			for k in ([0,1,2] if sign_value > 0.0 else [2,1,0]): st.add_vertex(points[indices[t+k]])
	for i in outline.size():
		var next := (i+1)%outline.size()
		var points := [sides[0][i],sides[1][i],sides[1][next],sides[0][next]]
		for k in [0,1,2,0,2,3]: st.add_vertex(points[k])
	st.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = st.commit()
	part.material_override = mat
	root.add_child(part)

static func _profile(root: Node3D, label: String, outline: PackedVector2Array, width: float, mat: Material) -> void:
	# Silhueta Y/Z extrudada: coronhas e lâminas moldadas em vez de barras retangulares.
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
