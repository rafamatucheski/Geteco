extends RefCounted
## Shared low-poly primitives, grouped by shape/material into MultiMeshes.
var groups: Dictionary = {}
static var meshes: Dictionary = {}
static var materials: Dictionary = {}
func part(kind: String, at: Vector3, size: Vector3, color: String, rotation := Vector3.ZERO) -> void:
	var patterned := color in ["d8b56a","e4dfcf","9e937a","8d8a5a","ae9870"]
	var key := kind+":"+(color if patterned else "vertex")
	if not groups.has(key): groups[key]=[]
	groups[key].append([Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),at),Color.WHITE if patterned else Color(color)])
func flush(parent: Node3D) -> void:
	for key: String in groups:
		var bits:=key.split(":")
		if not meshes.has(bits[0]):
			var mesh: PrimitiveMesh
			if bits[0]=="box": mesh=BoxMesh.new()
			elif bits[0]=="round":
				mesh=SphereMesh.new()
				mesh.radius=.5; mesh.height=1; mesh.radial_segments=20; mesh.rings=10
			else:
				mesh=CylinderMesh.new()
				mesh.top_radius=.5; mesh.bottom_radius=.5; mesh.height=1; mesh.radial_segments=8
			meshes[bits[0]]=mesh
		if not materials.has(bits[1]):
			var mat:=StandardMaterial3D.new()
			mat.albedo_color=Color.WHITE if bits[1]=="vertex" else Color(bits[1]); mat.roughness=.92
			mat.vertex_color_use_as_albedo=bits[1]=="vertex"
			mat.vertex_color_is_srgb=true
			# Cor lisa lia como plano chapado: relevo em espaço de mundo; a textura
			# multiplica a cor da instância/vértice, então o tom autorado se mantém.
			var tint:=mat.albedo_color
			preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(mat,"plaster",2.0,.7)
			mat.albedo_color=Color(minf(tint.r*mat.albedo_color.r,1.0),minf(tint.g*mat.albedo_color.g,1.0),minf(tint.b*mat.albedo_color.b,1.0))
			mat.roughness=1.0
			materials[bits[1]]=mat
			if bits[1] in ["d8b56a","e4dfcf"]:
				var coat:=ShaderMaterial.new()
				coat.shader=preload("res://world/mountain_detail/zoo/animal_coat.gdshader")
				coat.set_shader_parameter("base_color",Color(bits[1]))
				coat.set_shader_parameter("marking",Color("795131") if bits[1]=="d8b56a" else Color("242725"))
				coat.set_shader_parameter("pattern",1 if bits[1]=="d8b56a" else 2)
				materials[bits[1]]=coat
			if bits[1] in ["9e937a","8d8a5a","ae9870"]:
				var ground:=ShaderMaterial.new()
				ground.shader=preload("res://world/mountain_detail/zoo/zoo_ground.gdshader")
				ground.set_shader_parameter("soil",Color(bits[1]))
				materials[bits[1]]=ground
		var mm:=MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.use_colors=true
		mm.mesh=meshes[bits[0]]
		mm.instance_count=groups[key].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i,groups[key][i][0])
			mm.set_instance_color(i,groups[key][i][1])
		var instance:=MultiMeshInstance3D.new()
		instance.multimesh=mm
		if Engine.get_meta("geteco_live_preview_build",false):
			var transforms: Array = []
			var colors: Array = []
			for item in groups[key]:
				transforms.append(item[0])
				colors.append(item[1])
			instance.set_meta("preview_instance_transforms",transforms)
			instance.set_meta("preview_instance_colors",colors)
		instance.material_override=materials[bits[1]]
		parent.add_child(instance)
	groups.clear()
static func solid(parent: Node3D, id: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=id
	body.collision_layer=1; body.collision_mask=0
	body.position=at
	var shape:=BoxShape3D.new()
	shape.size=size
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	parent.add_child(body)
	return body
static func polygon(parent: Node3D, outline: PackedVector2Array, y: float, color: Color) -> MeshInstance3D:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices:=Geometry2D.triangulate_polygon(outline)
	for i in range(0,indices.size(),3):
		for j in [0,1,2]:
			var point:=outline[indices[i+j]]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x,y,point.y))
	var node:=MeshInstance3D.new(); node.mesh=surface.commit()
	var mat:=ShaderMaterial.new(); mat.shader=preload("res://world/mountain_detail/zoo/zoo_ground.gdshader")
	mat.set_shader_parameter("soil",color); node.material_override=mat
	parent.add_child(node)
	node.create_trimesh_collision()
	for body in node.get_children():
		if body is StaticBody3D: body.collision_layer=1; body.collision_mask=0
	return node
func fence_segment(parent: Node3D, a: Vector2, b: Vector2, height: float, id: String="HabitatFence") -> void:
	var gap:=b-a; var length:=gap.length(); var yaw:=atan2(gap.x,gap.y)
	var midpoint:=(a+b)*.5
	var at:=Vector3(midpoint.x,0,midpoint.y)
	var body:=solid(parent,id,at+Vector3.UP*height*.5,Vector3(.16,height,length+.06))
	body.rotation.y=yaw
	for y in [.12,height*.52,height]: part("box",at+Vector3.UP*y,Vector3(.13,.10,length+.04),"48584d",Vector3(0,yaw,0))
	part("box",at+Vector3.UP*.10,Vector3(.24,.20,length+.06),"827f6c",Vector3(0,yaw,0))
	var count:=ceili(length/.55)
	for i in count:
		var p:=a.lerp(b,float(i)/count)
		part("pole",Vector3(p.x,height*.5,p.y),Vector3(.055,height,.055),"48584d")
