extends RefCounted
const SURFACE := preload("res://world/desert/desert_surface.gdshader")
static var materials: Dictionary = {}

static func material(color: Color, ground := false, asphalt := false) -> Material:
	var key := str(color)+str(ground)+str(asphalt)
	if materials.has(key): return materials[key]
	var mat: Material
	if ground or asphalt:
		var shader := ShaderMaterial.new()
		shader.shader = SURFACE
		shader.set_shader_parameter("base_color",color)
		shader.set_shader_parameter("asphalt",asphalt)
		mat=shader
	else:
		var standard := StandardMaterial3D.new()
		standard.albedo_color=color
		standard.roughness=.88
		mat=standard
	materials[key]=mat
	return mat

static func box(parent: Node3D, id: String, at: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=id
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.position=at
	node.material_override=material(color)
	parent.add_child(node)
	if solid: collision(node,size)
	return node

static func collision(node: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	node.add_child(body)

static func cylinder(parent: Node3D, id: String, at: Vector3, radius: float, height: float, color: Color, solid := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=id
	node.position=at
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=10
	node.mesh=mesh
	node.material_override=material(color)
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer=1
		body.collision_mask=0
		var collider := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius=radius
		shape.height=height
		collider.shape=shape
		body.add_child(collider)
		node.add_child(body)
	return node

static func sign_name(parent: Node3D, text: String, at: Vector3, size := 50) -> void:
	if text.is_empty(): return
	var sign := Label3D.new()
	sign.text=text
	sign.position=at
	sign.font_size=size
	sign.pixel_size=.018
	sign.modulate=Color("eee2c6")
	sign.outline_size=0
	parent.add_child(sign)

static func room_box(parent: Node3D, id: String, at: Vector3, size: Vector3, color: Color, solid := true) -> MeshInstance3D:
	var node := box(parent,id,at,size,color)
	if solid: node.set_meta("interior_solid_id",id)
	return node

static func quad(parent: Node3D, id: String, points: PackedVector3Array, mat: Material, solid := false) -> MeshInstance3D:
	var vertices := PackedVector3Array([points[0],points[1],points[2],points[0],points[2],points[3]])
	var normals := PackedVector3Array()
	for i in 6: normals.append(Vector3.UP)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name=id
	node.mesh=mesh
	node.material_override=mat
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer=1
		body.collision_mask=0
		var collision_shape := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(vertices)
		collision_shape.shape=shape
		body.add_child(collision_shape)
		node.add_child(body)
	return node

static func batch_repeated_meshes(parent: Node3D) -> void:
	# Repeated parked-truck ribs/wheels are static. One draw per geometry/material,
	# while solid volumes and unique interactive pieces retain their normal nodes.
	var groups: Dictionary={}
	for child in parent.get_children():
		if not child is MeshInstance3D or child.get_child_count()>0: continue
		var geometry: Mesh=child.mesh
		var shape_key := ""
		if geometry is BoxMesh: shape_key="box:"+str(geometry.size)
		elif geometry is CylinderMesh: shape_key="cylinder:%s:%s:%s:%s"%[geometry.top_radius,geometry.bottom_radius,geometry.height,geometry.radial_segments]
		else: continue
		var key := shape_key+":"+str(child.material_override.get_rid())
		if not groups.has(key): groups[key]=[]
		groups[key].append(child)
	for key in groups:
		var items: Array=groups[key]
		if items.size()<3: continue
		var first: MeshInstance3D=items[0]
		var batch := MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=first.mesh
		batch.instance_count=items.size()
		for i in items.size(): batch.set_instance_transform(i,items[i].transform)
		var node := MultiMeshInstance3D.new()
		node.name="Batched"+str(first.name)
		node.multimesh=batch
		node.material_override=first.material_override
		parent.add_child(node)
		for item in items: item.free()
