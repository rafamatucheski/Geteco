extends Node3D
## Authored public coastal overlook. Static batches, physical pedestrian access,
## no traffic edges, lights, frame callbacks or campaign shortcuts.
const ENTRANCE := Vector3(319.5, .055, -130.5)
const BASE_PLAZA := Vector3(303, 10.2, -198)
const BASE_CENTER := BASE_PLAZA
const LIGHTHOUSE := preload("res://world/places/coastal_lookout/LighthouseGeometry.gd")
const GALLERY_RADIUS := 6.5
const SUMMIT := Vector3(299.2, 24.2, -201.8)
const BINOCULAR := Vector3(300.15, 24.2, -203.35)
const DESERT_TARGET := Vector3(-180, 8, -900)
const RADIUS := 9.0
const PATH_HALF_WIDTH := 1.7
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const SURF := preload("res://world/places/coastal_lookout/coastal_surf.gdshader")
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _collision := PackedVector3Array()
var _head: Node3D
var _built := false
var _guard_post_phase := 0.0
var _lighthouse_sightline: Node

static func entrance_position() -> Vector3: return ENTRANCE
static func summit_position() -> Vector3: return SUMMIT
static func binocular_interaction_position() -> Vector3: return Vector3(300.65, 24.24, -202.55)
static func binocular_eye_position() -> Vector3:
	return BINOCULAR + Vector3.UP * 1.52 + (DESERT_TARGET-BINOCULAR).normalized() * .48
static func binocular_target_position() -> Vector3: return DESERT_TARGET
static func footprint() -> Rect2: return Rect2(275,-220,55,92)

static func route_points() -> PackedVector3Array:
	var path := promenade_route_points()
	path.append_array(lighthouse_route_points())
	return path

static func lighthouse_route_points() -> PackedVector3Array:
	return LIGHTHOUSE.route_points()

static func gallery_route_points() -> PackedVector3Array:
	return LIGHTHOUSE.gallery_route_points()

static func promenade_route_points() -> PackedVector3Array:
	# The first 17 m stay inside the 7 m gap between the two BridgeCourt houses.
	# The coast rail at z=-150 stays intact underneath the raised promenade.
	var controls := PackedVector3Array([ENTRANCE, Vector3(319.5,2.2,-147),
		Vector3(319.5,3.8,-159), Vector3(302,6.1,-171),
		Vector3(319,8.5,-183), Vector3(309,10.2,-192), BASE_PLAZA])
	var rounded := PackedVector3Array([controls[0]])
	for i in range(1,controls.size()-2):
		var a := controls[i].lerp(controls[i-1],.22)
		var b := controls[i].lerp(controls[i+1],.22)
		rounded.append(a)
		for k in range(1,9):
			var t := float(k)/8.0
			rounded.append(a.lerp(controls[i],t).lerp(controls[i].lerp(b,t),t))
	# The path meets the plaza tangentially; its end is inside the open SE arc.
	# Reach terrace height before its masonry perimeter to avoid a hidden lip.
	var plaza_landing := BASE_PLAZA + (controls[-2]-BASE_PLAZA).normalized()*10.25
	rounded.append(plaza_landing)
	var plaza_entry := BASE_PLAZA + (controls[-2]-BASE_PLAZA).normalized()*7.9
	if rounded[-1].distance_squared_to(plaza_entry)>.01: rounded.append(plaza_entry)
	return rounded

func _ready() -> void: build()

func build() -> void:
	if _built: return
	_built = true
	name = "CoastalLookout"
	_material("paving",Color("ada185"),"stone",.30)
	_material("wall",Color("968c77"),"stone",.40)
	_material("coping",Color("bbad90"),"concrete",.32)
	_material("rock",Color("535953"),"gravel",.36)
	_material("wet_rock",Color("323e3d"),"gravel",.48)
	_material("bronze",Color("655642"))
	_material("wood",Color("806b49"),"gravel",.30)
	_material("green",Color("697351"))
	_material("glass",Color("345a62"))
	_materials.bronze.metallic = .62
	_materials.bronze.roughness = .48
	_materials.glass.metallic = .45
	_materials.glass.roughness = .20
	_build_promontory()
	_build_walk()
	_build_plaza()
	LIGHTHOUSE.new().build(self)
	_build_binocular()
	_flush()
	set_meta("pedestrian_only",true)
	set_meta("desert_target",DESERT_TARGET)
	set_meta("entry",ENTRANCE)
	set_meta("static_collision_triangles",floori(float(_collision.size())/3.0))
	set_meta("lighthouse_gallery_height",24.2)

func configure_lighthouse_player(player: CharacterBody3D) -> void:
	if not is_instance_valid(_lighthouse_sightline):
		_lighthouse_sightline = preload("res://world/places/coastal_lookout/LighthouseSightline.gd").new()
		add_child(_lighthouse_sightline)
	_lighthouse_sightline.configure(player)

func _material(id: String, color: Color, texture := "", scale_value := .4) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .91
	material.metallic_specular = .18
	if not texture.is_empty():
		GROUND.bind(material, texture)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE * scale_value
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[id] = material

func _build_walk() -> void:
	var path := promenade_route_points()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in path.size():
		var tangent := path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]
		var side := Vector3(-tangent.z,0,tangent.x).normalized()*PATH_HALF_WIDTH
		left.append(path[i]-side)
		right.append(path[i]+side)
	for i in range(path.size()-1):
		if path[i].distance_squared_to(path[i+1])<.0001: continue
		_quad("paving",left[i],right[i],right[i+1],left[i+1],Vector3.UP,true)
		# The retaining masonry is a real volume down into the rock, never a floating slab.
		for edge in [[left[i],left[i+1]],[right[i],right[i+1]]]:
			var a: Vector3 = edge[0]
			var b: Vector3 = edge[1]
			var bottom_a := Vector3(a.x,-3.2,a.z)
			var bottom_b := Vector3(b.x,-3.2,b.z)
			var outward := ((a+b)*.5-(path[i]+path[i+1])*.5).normalized()
			_quad("wall",a,b,bottom_b,bottom_a,outward,true)
			_guard(a,b)
	# A flush threshold and three permanent bollards admit people, never cars.
	for x in [-1.36,0.0,1.36]:
		var p := ENTRANCE+Vector3(x,0,-1.1)
		_cylinder("bronze",p+Vector3.UP*.50,.16,1.0,true)
		_cylinder("coping",p+Vector3.UP*.10,.23,.20,true)
		_cylinder("bronze",p+Vector3.UP*1.01,.20,.10)

func _guard(a: Vector3, b: Vector3, prefix := "") -> void:
	_beam(prefix+"coping",a+Vector3.UP*.12,b+Vector3.UP*.12,.34,.24,true)
	_beam(prefix+"bronze",a+Vector3.UP*1.14,b+Vector3.UP*1.14,.075,.075)
	_beam(prefix+"bronze",a+Vector3.UP*.43,b+Vector3.UP*.43,.05,.05)
	# Invisible panel matches the visible railing; do not allow slipping between rods.
	_collision_box((a+b)*.5+Vector3.UP*.65,Vector3(.13,1.16,a.distance_to(b)+.025),_beam_basis(a,b))
	var count := maxi(1,ceili(a.distance_to(b)/.55))
	for i in count:
		var at := a.lerp(b,float(i)/count)
		_beam(prefix+"bronze",at+Vector3.UP*.24,at+Vector3.UP*1.12,.038,.038)
		_guard_post_phase += a.distance_to(b)/count
		if _guard_post_phase>=2.8:
			_guard_post_phase -= 2.8
			_box(prefix+"coping",at+Vector3.UP*.36,Vector3(.33,.72,.33))
			_box(prefix+"coping",at+Vector3.UP*.75,Vector3(.40,.09,.40))

func _build_plaza() -> void:
	var count := 64
	var opening_center := (Vector3(309,10.2,-192)-BASE_PLAZA).normalized()
	for i in count:
		var a := BASE_PLAZA+Vector3(cos(TAU*i/count),0,sin(TAU*i/count))*RADIUS
		var b := BASE_PLAZA+Vector3(cos(TAU*(i+1)/count),0,sin(TAU*(i+1)/count))*RADIUS
		_triangle("paving",BASE_PLAZA,a,b,Vector3.UP,true)
		var outward := ((a+b)*.5-BASE_PLAZA).normalized()
		_quad("wall",a,b,b-Vector3.UP*2.9,a-Vector3.UP*2.9,outward,true)
		# The swept walk enters from southeast; this arc is the sole railing opening.
		if outward.dot(opening_center)<.94: _guard(a,b)
		# Pale radial border is a solid stone inlay, offset only 4mm above paving.
		var inner_a := BASE_PLAZA+(a-BASE_PLAZA)*.925+Vector3.UP*.004
		var inner_b := BASE_PLAZA+(b-BASE_PLAZA)*.925+Vector3.UP*.004
		_quad("coping",inner_a,inner_b,b+Vector3.UP*.004,a+Vector3.UP*.004,Vector3.UP)
	# Two inward-facing benches sit against the sides; circulation stays clear.
	_bench(BASE_PLAZA+Vector3(-6.4,0,1.2),PI*.5)
	_bench(BASE_PLAZA+Vector3(4.2,0,-4.7),-PI*.25)

func _bench(point: Vector3, yaw: float) -> void:
	var bench_basis := Basis(Vector3.UP,yaw)
	for x in [-1.0,1.0]:
		_box("bronze",point+bench_basis*Vector3(x,.26,0),Vector3(.12,.52,.55),true,bench_basis)
	for z in [-.22,0,.22]: _box("wood",point+bench_basis*Vector3(0,.53,z),Vector3(2.5,.085,.18),true,bench_basis)
	for y in [.83,1.05]: _box("wood",point+bench_basis*Vector3(0,y,.28),Vector3(2.5,.16,.08),true,bench_basis)
	for x in [-1.1,1.1]: _box("bronze",point+bench_basis*Vector3(x,.83,.27),Vector3(.07,.68,.07),false,bench_basis)

func _build_promontory() -> void:
	# Authored principal rock masses give the overlook a geological foundation.
	_rock(Vector3(303,1.6,-198),Vector3(13.8,7.3,12.5),31)
	_rock(Vector3(313,.8,-181),Vector3(11.2,5.5,13.0),47)
	_rock(Vector3(311,-.5,-162),Vector3(9.2,3.2,10.0),71)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7102026
	for i in 27:
		var angle := TAU*float(i)/27.0
		var center := Vector3(304+cos(angle)*rng.randf_range(13.0,23),-.8,-190+sin(angle)*rng.randf_range(18.0,28))
		if center.z>-153: continue
		var size := Vector3(rng.randf_range(2.1,4.6),rng.randf_range(1.4,4.0),rng.randf_range(2.4,5.0))
		_rock(center,size,200+i)
		if i%2==0: _surf(center,size.x*.86,size.z*.86,angle)
	# Small planted pockets sit outside the walk, on broad stone shoulders.
	for p: Vector3 in [Vector3(294,6.7,-198),Vector3(309,7.8,-207),Vector3(309,4.0,-177)]:
		for i in 5:
			var angle := TAU*i/5.0
			var base := p+Vector3(cos(angle),0,sin(angle))*.28
			var tip := base+Vector3(cos(angle)*.55,.95,sin(angle)*.55)
			_triangle("green",base+Vector3(.08,0,.08),base-Vector3(.08,0,.08),tip,Vector3.UP)

func _rock(center: Vector3, size: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rows: Array[PackedVector3Array] = []
	for row in 4:
		var ring := PackedVector3Array()
		var y := [-1.0,-.35,.43,1.0][row] as float
		var radius := [.76,1.0,.78,.26][row] as float
		for i in 11:
			var angle := TAU*i/11.0
			var radial := radius*rng.randf_range(.81,1.18)
			ring.append(center+Vector3(cos(angle)*size.x*radial,size.y*(y+rng.randf_range(-.10,.1)),sin(angle)*size.z*radial))
		rows.append(ring)
	for row in 3:
		for i in 11:
			var j := (i+1)%11
			var a: Vector3 = rows[row][i]
			var b: Vector3 = rows[row][j]
			var c: Vector3 = rows[row+1][j]
			var d: Vector3 = rows[row+1][i]
			var normal := ((a+b+c+d)*.25-center).normalized()
			_quad("wet_rock" if row==0 else "rock",a,b,c,d,normal,true)
	var peak := center+Vector3.UP*size.y*.99
	for i in 11: _triangle("rock",peak,rows[3][i],rows[3][(i+1)%11],Vector3.UP,true)

func _surf(center: Vector3, radius_x: float, radius_z: float, phase: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a := TAU*i/24.0
		var b := TAU*(i+1)/24.0
		# Start under the submerged rock footprint. Noise removes the exposed
		# outer edge; the apron cannot appear as a detached ring round the rock.
		var points := [Vector3(cos(a)*radius_x*.58,0,sin(a)*radius_z*.58),Vector3(cos(b)*radius_x*.58,0,sin(b)*radius_z*.58),Vector3(cos(b)*(radius_x+3.0),0,sin(b)*(radius_z+3.0)),Vector3(cos(a)*(radius_x+3.0),0,sin(a)*(radius_z+3.0))]
		var uvs := [Vector2(a*radius_x+phase,0),Vector2(b*radius_x+phase,0),Vector2(b*radius_x+phase,1),Vector2(a*radius_x+phase,1)]
		for index in [0,2,1,0,3,2]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[index])
			st.add_vertex(points[index])
	var mesh := MeshInstance3D.new()
	mesh.name = "RockBreakers"
	mesh.mesh = st.commit()
	mesh.position = Vector3(center.x,-.88,center.z)
	var material := ShaderMaterial.new()
	material.shader = SURF
	material.set_shader_parameter("rock_radius",Vector2(radius_x,radius_z))
	material.set_shader_parameter("wave_phase",center.z*.19+phase)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = 160
	add_child(mesh)

func _build_binocular() -> void:
	_cylinder("coping",BINOCULAR+Vector3.UP*.07,.55,.14,true)
	_cylinder("bronze",BINOCULAR+Vector3.UP*.66,.13,1.25,true)
	_cylinder("bronze",BINOCULAR+Vector3.UP*.20,.25,.12)
	_cylinder("bronze",BINOCULAR+Vector3.UP*1.25,.23,.19)
	_head = Node3D.new()
	_head.name = "BinocularHead"
	_head.position = BINOCULAR+Vector3.UP*1.52
	add_child(_head)
	for x in [-.135,.135]:
		for part in [{"r":.12,"h":.42,"z":-.05,"m":"bronze"},{"r":.095,"h":.025,"z":-.275,"m":"glass"},{"r":.075,"h":.11,"z":.22,"m":"bronze"}]:
			var node := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = float(part.r)
			mesh.bottom_radius = float(part.r)
			mesh.height = float(part.h)
			mesh.radial_segments = 20
			node.mesh = mesh
			node.position = Vector3(x,0,float(part.z))
			node.rotation.x = PI*.5
			node.material_override = _materials[part.m]
			_head.add_child(node)
	set_binocular_angles(0,0)

func set_binocular_angles(yaw: float, pitch: float) -> void:
	if not is_instance_valid(_head): return
	var target := DESERT_TARGET-BINOCULAR
	_head.rotation = Vector3(pitch,atan2(-target.x,-target.z)+yaw,0)

func _triangle(id: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, solid := false) -> void:
	if not _batches.has(id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[id] = st
	var normal := (c-a).cross(b-a).normalized()
	if normal.dot(outward)<0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	for p in [a,b,c]:
		_batches[id].set_normal(normal)
		_batches[id].set_uv(Vector2(p.x,p.z))
		_batches[id].add_vertex(p)
		if solid: _collision.append(p)

func _quad(id: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, solid := false) -> void:
	_triangle(id,a,b,c,outward,solid)
	_triangle(id,a,c,d,outward,solid)

func _box(id: String, point: Vector3, size: Vector3, solid := false, box_basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_mesh(id,mesh,Transform3D(box_basis,point),solid)

func _cylinder(id: String, point: Vector3, radius: float, height: float, solid := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	_append_mesh(id,mesh,Transform3D(Basis.IDENTITY,point),solid)

func _beam_basis(a: Vector3, b: Vector3) -> Basis:
	var forward := (b-a).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	if right.length_squared()<.1: right = Vector3.RIGHT
	return Basis(right,forward.cross(right).normalized(),forward)

func _beam(id: String, a: Vector3, b: Vector3, width: float, height: float, solid := false) -> void:
	_box(id,(a+b)*.5,Vector3(width,height,a.distance_to(b)),solid,_beam_basis(a,b))

func _append_mesh(id: String, mesh: Mesh, mesh_transform: Transform3D, solid: bool) -> void:
	if not _batches.has(id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[id] = st
	# All batches are non-indexed triangles. append_from() on an indexed Box/
	# Cylinder creates an index buffer referring only to primitive vertices;
	# manually emitted ring/quad vertices then disappear from that same batch.
	# Expand source indices here, preserving each primitive's normals and UVs.
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var normal_basis := mesh_transform.basis.inverse().transposed()
	for i in count:
		var index := indices[i] if not indices.is_empty() else i
		var point := mesh_transform*vertices[index]
		_batches[id].set_normal((normal_basis*normals[index]).normalized())
		_batches[id].set_uv(uvs[index] if index<uvs.size() else Vector2.ZERO)
		_batches[id].add_vertex(point)
		if solid: _collision.append(point)

func _collision_box(point: Vector3, size: Vector3, box_basis: Basis) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box_transform := Transform3D(box_basis,point)
	for p in mesh.get_faces(): _collision.append(box_transform*p)

func _flush() -> void:
	for id in _batches:
		var node := MeshInstance3D.new()
		node.name = "Lighthouse_"+str(id) if str(id).begins_with("lighthouse_") else "Lookout_"+str(id)
		node.mesh = _batches[id].commit()
		node.material_override = _materials[id]
		if id in ["lighthouse_glass","lighthouse_lens","lighthouse_lens_edges"]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batches.clear()
	var body := StaticBody3D.new()
	body.name = "LookoutSolids"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_collision)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
