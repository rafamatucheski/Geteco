extends Node3D
var lid: Node3D
var kind := "backpack"
var pose_tween: Tween
var carry_space: Node3D
var actor_space: Node3D
var straps: Node3D
var hand_skeleton: Skeleton3D
var hand_bone := -1
var opened := false
const BACKPACK_COLOR := Color("6d4d37")

static func pickup_size(bag_kind: String) -> Vector3:
	return Vector3(.34,.44,.26) if bag_kind=="backpack" else Vector3(.66,.63,.34)

func rest_position() -> Vector3:
	return Vector3(0,.98,.22) if kind=="backpack" else Vector3(.46,.20,0)

# Alça da mala fica ~.03 acima da tampa (y=.625 no espaço da mala); a mão a segura ali.
const HANDLE_HEIGHT := .60
const HAND_OUTWARD := .11

func _process(_delta: float) -> void:
	# A mala pende da mão a cada quadro; o carry de 4 Hz do inventário não basta e a
	# deixava parada num ponto fixo ao lado do corpo enquanto o boneco andava.
	if kind!="handbag" or opened or hand_bone<0: return
	if pose_tween!=null and pose_tween.is_running(): return
	var hang:=_hand_hang()
	position=hang[0]; rotation=Vector3(0,hang[1],0)

func _hand_hang() -> Array:
	# [posição local, yaw]: a mala desce reta da palma, com a face lisa junto à perna
	# e o lado dos bolsos para fora, seja qual for o braço animado.
	var pose:=hand_skeleton.get_bone_global_pose(hand_bone)
	var palm:Vector3=actor_space.to_local(hand_skeleton.to_global(pose*Vector3(0,.065,0)))
	var side:=1.0 if palm.x>=0 else -1.0
	return [Vector3(palm.x+side*HAND_OUTWARD,palm.y-HANDLE_HEIGHT,palm.z),-side*PI*.5]

func _ready() -> void:
	if kind=="backpack":
		_build_backpack()
		return
	var fabric := Color("826044")
	var width := .62
	_box(Vector3(width,.48,.25),Vector3(0,.26,0),fabric)
	_box(Vector3(width*.85,.22,.065),Vector3(0,.20,-.15),fabric.darkened(.18))
	for side in [-1,1]:
		_box(Vector3(.036,.47,.028),Vector3(side*width*.28,.27,-.14),Color("383f36"))
		_box(Vector3(.06,.047,.032),Vector3(side*width*.28,.34,-.16),Color("b3a584"))
		_box(Vector3(.034,.11,.03),Vector3(side*.07,.57,0),Color("373c35"))
	_box(Vector3(.17,.032,.03),Vector3(0,.625,0),Color("4e5144"))
	lid=Node3D.new(); lid.position=Vector3(0,.51,.11); add_child(lid)
	_box(Vector3(width,.055,.27),Vector3(0,0,-.11),fabric.lightened(.12),lid)

func _build_backpack() -> void:
	# Compact canvas bag: softened silhouette, shallow pocket and quiet hardware.
	_soft_box(Vector3(.32,.36,.17),Vector3(0,.18,0),BACKPACK_COLOR)
	_soft_box(Vector3(.24,.14,.038),Vector3(0,.12,-.096),BACKPACK_COLOR.darkened(.13))
	straps=Node3D.new(); add_child(straps); straps.scale.z=.35
	for side in [-1,1]:
		_strap(float(side))
		_box(Vector3(.014,.027,.012),Vector3(side*.09,.15,-.123),Color("a08b66"))
		_box(Vector3(.016,.045,.02),Vector3(side*.048,.392,0),Color("493626"))
	_soft_box(Vector3(.11,.019,.026),Vector3(0,.417,0),Color("493626"))
	lid=Node3D.new(); lid.position=Vector3(0,.355,.078); add_child(lid)
	_soft_box(Vector3(.325,.028,.19),Vector3(0,0,-.078),BACKPACK_COLOR.lightened(.07),lid)

func _strap(side: float) -> void:
	# Short shoulder sections meet the shirt; folded flat when placed on the floor.
	var path: Array[Vector3]=[Vector3(side*.10,.33,.09),Vector3(side*.12,.40,.15),Vector3(side*.13,.42,.21),Vector3(side*.13,.36,.26)]
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge:=Vector3(.015,0,0)
	for i in path.size()-1:
		for vertex in [path[i]-edge,path[i]+edge,path[i+1]+edge,path[i]-edge,path[i+1]+edge,path[i+1]-edge]: surface.add_vertex(vertex)
	surface.generate_normals()
	var material:=StandardMaterial3D.new(); material.albedo_color=Color("493626"); material.roughness=1; material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var mesh:=MeshInstance3D.new(); mesh.mesh=surface.commit(); mesh.material_override=material; straps.add_child(mesh)

func set_worn(worn: bool) -> void:
	if is_instance_valid(straps): straps.scale.z=1.0 if worn else .35

func _soft_box(size: Vector3, at: Vector3, color: Color, parent: Node3D = self) -> void:
	# Four bevelled rings; no subdivision, shader animation or extra frame loop.
	var vertices: Array[Vector3]=[]
	for ring in [Vector2(-.5,.78),Vector2(-.34,1),Vector2(.34,1),Vector2(.5,.78)]:
		for corner in [Vector2(-.36,-.5),Vector2(.36,-.5),Vector2(.5,-.36),Vector2(.5,.36),Vector2(.36,.5),Vector2(-.36,.5),Vector2(-.5,.36),Vector2(-.5,-.36)]:
			vertices.append(Vector3(corner.x*size.x*ring.y,ring.x*size.y,corner.y*size.z*ring.y))
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 3:
		for side in 8:
			var a:=ring*8+side; var b:=ring*8+(side+1)%8; var c:=b+8; var d:=a+8
			for index in [a,b,c,a,c,d]: surface.add_vertex(vertices[index])
	for side in range(1,7):
		for index in [0,side+1,side,24,24+side,25+side]: surface.add_vertex(vertices[index])
	surface.generate_normals()
	var mesh:=MeshInstance3D.new(); mesh.mesh=surface.commit(); mesh.position=at
	var material:=StandardMaterial3D.new(); material.albedo_color=color; material.roughness=.95
	mesh.material_override=material; parent.add_child(mesh)

func _box(dimensions: Vector3, at: Vector3, color: Color, parent: Node3D = self) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size=dimensions; mesh.mesh=box
	var mat := StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=.95; mesh.material_override=mat
	mesh.position=at; parent.add_child(mesh)

func set_open(open: bool, carried := true) -> void:
	opened=open
	set_worn(carried and not open)
	if pose_tween!=null: pose_tween.kill()
	pose_tween=create_tween().set_parallel(true)
	pose_tween.tween_property(lid,"rotation:x",-1.4 if open else 0.0,.22)
	if carried:
		if kind=="backpack" and is_instance_valid(carry_space):
			# Opening leaves the bone socket; closing returns to its animated space.
			reparent(actor_space if open else carry_space,true)
		var rest_at:=rest_position()
		var rest_rotation:=Vector3(0,PI,0) if kind=="backpack" else Vector3.ZERO
		if kind=="handbag" and hand_bone>=0:
			var hang:=_hand_hang()
			rest_at=hang[0]; rest_rotation=Vector3(0,hang[1],0)
		pose_tween.tween_property(self,"position",Vector3(0,.55,-.55) if open else rest_at,.25).set_trans(Tween.TRANS_QUAD)
		pose_tween.tween_property(self,"rotation",Vector3(-.18,0,0) if open else rest_rotation,.25)
