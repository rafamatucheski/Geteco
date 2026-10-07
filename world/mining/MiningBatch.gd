extends RefCounted
## Spatially bounded static batches. One material/primitive draw per chunk;
## explicit colliders remain independent from ornament and visual batching.
static var _meshes: Dictionary={}
static var _materials: Dictionary={}
var root: Node3D
var body: StaticBody3D
var groups: Dictionary={}
var piece_count := 0

func _init(parent: Node3D, label: String, at := Vector3.ZERO) -> void:
	root=Node3D.new()
	root.name=label
	root.position=at
	parent.add_child(root)
	body=StaticBody3D.new()
	body.name="MiningSolids"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface","hard")
	root.add_child(body)

func box(label: String, at: Vector3, size: Vector3, finish: String, solid := false, rotation := Vector3.ZERO) -> void:
	_add("box",finish,Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),at))
	if solid:
		var shape := BoxShape3D.new()
		shape.size=size
		_collision(label,at,rotation,shape)

func cylinder(label: String, at: Vector3, radius: float, height: float, finish: String, solid := false, rotation := Vector3.ZERO) -> void:
	_add("cylinder",finish,Transform3D(Basis.from_euler(rotation)*Basis.from_scale(Vector3(radius,height,radius)),at))
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius=radius
		shape.height=height
		_collision(label,at,rotation,shape)

func beam(label: String, start: Vector3, end: Vector3, width: float, finish: String, solid := false) -> void:
	var delta := end-start
	box(label,(start+end)*.5,Vector3(width,delta.length(),width),finish,solid,Basis(Quaternion(Vector3.UP,delta.normalized())).get_euler())

func rock(label: String, at: Vector3, size: Vector3, finish := "ore", solid := true, yaw := 0.0) -> void:
	_add("rock",finish,Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(size),at))
	if solid:
		var shape := ConvexPolygonShape3D.new()
		var vertices: PackedVector3Array=mesh("rock").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var points := PackedVector3Array()
		for vertex in vertices: points.append(vertex*size)
		shape.points=points
		_collision(label,at,Vector3(0,yaw,0),shape)

func _collision(label: String, at: Vector3, rotation: Vector3, shape: Shape3D) -> void:
	var node := CollisionShape3D.new()
	node.name=label
	node.position=at
	node.rotation=rotation
	node.shape=shape
	node.set_meta("mining_solid",label)
	body.add_child(node)

func _add(kind: String, finish: String, transform: Transform3D) -> void:
	var key := kind+":"+finish
	if not groups.has(key): groups[key]={"kind":kind,"finish":finish,"transforms":[]}
	groups[key].transforms.append(transform)
	piece_count+=1

func finish() -> Node3D:
	for key in groups:
		var group: Dictionary=groups[key]
		var batch := MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=mesh(group.kind)
		batch.instance_count=group.transforms.size()
		for i in group.transforms.size(): batch.set_instance_transform(i,group.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.name="MiningBatch_"+key.replace(":","_")
		visual.multimesh=batch
		if Engine.get_meta("geteco_live_preview_build",false): visual.set_meta("preview_instance_transforms",group.transforms)
		visual.material_override=material(group.finish)
		root.add_child(visual)
	if body.get_child_count()==0: body.free()
	root.set_meta("mining_static_pieces",piece_count)
	return root

static func material(id: String) -> StandardMaterial3D:
	if _materials.has(id): return _materials[id]
	var colors := {"steel":"515a5b","rust":"85533b","yellow":"b99a47","rubber":"262a29","concrete":"8a8879","timber":"776044","white":"d2c5a3","glass":"3c5354","red":"8e3b2b","ore":"746558","ore_dark":"514c48","ore_light":"9b8564","coal":"282d2d","trail":"6b6051","water":"515b58","cream":"bab295","cable":"313837","blue":"4b626c","lamp":"f9d49a"}
	var result := StandardMaterial3D.new()
	result.albedo_color=Color(colors.get(id,"8a7964"))
	result.roughness=.91
	if id in ["steel","glass","water"]: result.roughness=.56
	if id=="steel": result.metallic=.32
	if id=="recess":
		result.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		result.albedo_color=Color("080b0b")
	if id=="lamp":
		result.emission_enabled=true
		result.emission=Color("eac18d")
		result.emission_energy_multiplier=.65
	_materials[id]=result
	return result

static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var result: Mesh
	if kind=="rock":
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ring in 4:
			for index in 9:
				var a := _rock_vertex(ring,index)
				var b := _rock_vertex(ring,index+1)
				var c := _rock_vertex(ring+1,index+1)
				var d := _rock_vertex(ring+1,index)
				for vertex in [a,b,c,a,c,d]: builder.add_vertex(vertex)
		builder.generate_normals()
		result=builder.commit()
	elif kind=="cylinder":
		var geometry := CylinderMesh.new()
		geometry.top_radius=1
		geometry.bottom_radius=1
		geometry.height=1
		geometry.radial_segments=12
		result=geometry
	else:
		var geometry := BoxMesh.new()
		geometry.size=Vector3.ONE
		result=geometry
	_meshes[kind]=result
	return result

static func _rock_vertex(ring: int, index: int) -> Vector3:
	var angle := float(posmod(index,9))*TAU/9.0
	var radius: float=[.09,.83,1.0,.69,.06][ring]
	var height: float=[-.52,-.34,.02,.34,.54][ring]
	var variation := 1.0+sin(angle*3.0+float(ring)*1.9)*.13
	return Vector3(cos(angle)*radius*.5*variation,height,sin(angle)*radius*.5*variation)
