extends RefCounted
## Lotes estáticos limitados no espaço. Um draw de material/primitiva por chunk;
## colisores explícitos ficam independentes do ornamento e do lote visual.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
static var _meshes: Dictionary={}
static var _late_body := OS.get_environment("GETECO_MINING_BODY_LATE") != "0"
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
	# Corpo entra na árvore só no finish(), já com todas as formas (22/10): cada CollisionShape3D somada a
	# um corpo que já está no espaço refaz a forma composta dele; a mina (centenas de rochas, cercas e
	# cabos sólidos) custava 22–24 ms num quadro (stream.desert.mining). GETECO_MINING_BODY_LATE=0 volta.
	if not _late_body: root.add_child(body)

func box(label: String, at: Vector3, size: Vector3, material_key: String, solid := false, rotation := Vector3.ZERO) -> void:
	_add("box",material_key,Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),at))
	if solid:
		var shape := BoxShape3D.new()
		shape.size=size
		_collision(label,at,rotation,shape)

func cylinder(label: String, at: Vector3, radius: float, height: float, material_key: String, solid := false, rotation := Vector3.ZERO) -> void:
	_add("cylinder",material_key,Transform3D(Basis.from_euler(rotation)*Basis.from_scale(Vector3(radius,height,radius)),at))
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius=radius
		shape.height=height
		_collision(label,at,rotation,shape)

func beam(label: String, start: Vector3, end: Vector3, width: float, material_key: String, solid := false) -> void:
	var delta := end-start
	box(label,(start+end)*.5,Vector3(width,delta.length(),width),material_key,solid,Basis(Quaternion(Vector3.UP,delta.normalized())).get_euler())

func rock(label: String, at: Vector3, size: Vector3, material_key := "ore", solid := true, yaw := 0.0) -> void:
	_add("rock",material_key,Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(size),at))
	if solid:
		var shape := ConvexPolygonShape3D.new()
		# Malha da rocha é única e fixa: vértices pela cópia na CPU (22/10). A leitura da GPU por rocha sólida
		# fazia a etapa da mina custar 22 ms num quadro (stream.desert.mining, estresse do deserto).
		var vertices: PackedVector3Array=(MESH_ARRAYS.arrays_of(mesh("rock"),0) if MESH_ARRAYS.scaled_enabled else mesh("rock").surface_get_arrays(0))[Mesh.ARRAY_VERTEX]
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

func _add(kind: String, material_key: String, transform: Transform3D) -> void:
	var key := kind+":"+material_key
	if not groups.has(key): groups[key]={"kind":kind,"finish":material_key,"transforms":[]}
	groups[key].transforms.append(transform)
	piece_count+=1

func finish() -> Node3D:
	# Spans (27/10): a etapa inteira custava 17–20 ms num quadro no estresse do deserto; separa a montagem das
	# MultiMesh da entrada do corpo com todas as formas no espaço físico.
	var span := STALL_WORK.begin()
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
		if group.kind == "rock": visual.material_override = mineral_material(group.finish)
		root.add_child(visual)
	STALL_WORK.finish_slow("mining.batch.multimesh", span, 1000)
	span = STALL_WORK.begin()
	if body.get_child_count()==0: body.free()
	elif body.get_parent()==null: root.add_child(body)
	STALL_WORK.finish_slow("mining.batch.body", span, 1000)
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

## Sob a cortina (27/10): o primeiro ShaderMaterial com mineral_surface.gdshader custava 15 ms para criar (medido
## com janela; os seguintes, 0,01 ms) e caía no quadro em que a mina entra no streaming (mining.batch.multimesh
## 16,5 ms, estresse do deserto). Cria as rochas minerais de todas as cores e uma peça escondida de cada, para a
## pipeline também ficar pronta. Os materiais ficam retidos no cache estático.
const MINERAL_KEYS := ["ore", "ore_dark", "ore_light", "coal"]
static func prewarm_minerals(host: Node3D) -> void:
	for id: String in MINERAL_KEYS:
		var piece := MeshInstance3D.new()
		piece.mesh = mesh("rock")
		piece.material_override = mineral_material(id)
		piece.position = Vector3(0, -500, 0)
		host.add_child(piece)
		piece.queue_free()

static func mineral_material(id: String) -> ShaderMaterial:
	var key := "mineral_"+id
	if _materials.has(key): return _materials[key] as ShaderMaterial
	var result := ShaderMaterial.new()
	result.shader = preload("res://world/mining/mineral_surface.gdshader")
	result.set_shader_parameter("base_color", material(id).albedo_color)
	result.set_shader_parameter("world_origin", Vector3(-180,0,-1080))
	_materials[key] = result
	return result

static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var result: Mesh
	if kind=="rock":
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Bloco pentagonal fraturado, não uma superfície de revolução. Largas
		# faces partidas, uma coroa inclinada e cantos assimétricos substituem as pedrinhas antigas.
		# Todo vértice fica dentro do envelope anterior de colisão/posicionamento.
		var vertices := PackedVector3Array([
			Vector3(-.38,-.5,-.33), Vector3(.31,-.46,-.43), Vector3(.5,-.42,-.08),
			Vector3(.27,-.48,.43), Vector3(-.47,-.41,.31),
			Vector3(-.27,.25,-.32), Vector3(.16,.5,-.31), Vector3(.41,.33,-.03),
			Vector3(.18,.41,.32), Vector3(-.4,.24,.16)])
		var indices: Array[int] = [0,2,1,0,3,2,0,4,3,5,6,7,5,7,8,5,8,9]
		for index in 5:
			var next := (index + 1) % 5
			indices.append_array([index,next,next+5,index,next+5,index+5])
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index+1]]
			var c := vertices[indices[index+2]]
			var normal := (b-a).cross(c-a).normalized()
			# O Godot usa frentes horárias; orienta cada face para fora do bloco.
			if normal.dot((a+b+c)/3.0) > 0:
				var swap := b
				b = c
				c = swap
				normal = -normal
			for vertex in [a,b,c]:
				builder.set_normal(-normal)
				builder.add_vertex(vertex)
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
