extends RefCounted
## Chapas e arremates externos; não cria luzes, colisões ou acesso ao telhado.
static var materials: Dictionary = {}
static func material(color: String) -> StandardMaterial3D:
	if not materials.has(color):
		var result:=StandardMaterial3D.new()
		result.albedo_color=Color(color)
		result.roughness=.88
		materials[color]=result
	return materials[color]
static func box(parent: Node3D, name: String, point: Vector3, size: Vector3, color: String) -> void:
	var instance:=MeshInstance3D.new()
	instance.name=name
	var mesh:=BoxMesh.new()
	mesh.size=size
	instance.mesh=mesh
	instance.material_override=material(color)
	instance.position=point
	parent.add_child(instance)
static func build(roof: Node3D) -> void:
	var root:=Node3D.new()
	root.name="BoothRoofDetails"
	roof.add_child(root)
	for side in [-1,1]:
		box(root,"FlashingSide",Vector3(side*3.25,.12,0),Vector3(.09,.16,6.6),"53636a")
		box(root,"FlashingEnd",Vector3(0,.12,side*3.25),Vector3(6.6,.16,.09),"53636a")
	var seams:=MultiMeshInstance3D.new()
	seams.name="StandingSeams"
	var multi:=MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	var rib:=BoxMesh.new()
	rib.size=Vector3(.07,.045,6.32)
	multi.mesh=rib
	multi.instance_count=13
	for i in 13: multi.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(-2.88+i*.48,.1325,0)))
	seams.multimesh=multi
	seams.material_override=material("53636a")
	# Chapas quase coplanares: o contraste da junta evita sombra fina instável.
	seams.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(seams)
	box(root,"VentBase",Vector3(1.5,.17,1.25),Vector3(1.35,.12,1.1),"28373e")
	box(root,"VentHousing",Vector3(1.5,.39,1.25),Vector3(1.05,.4,.8),"64737a")
	box(root,"VentCap",Vector3(1.5,.63,1.25),Vector3(1.25,.10,1.0),"53636a")
	for i in 4: box(root,"VentLouver",Vector3(1.5,.27+i*.075,.83),Vector3(.82,.025,.025),"28373e")
