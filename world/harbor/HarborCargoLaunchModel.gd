extends Node3D
const PART = preload("res://characters/pedestrians/CitizenDetails.gd")
var crates: Array[Node3D] = []
func _ready() -> void:
	PART.piece(self,Vector3(4.2,.65,10),Vector3(0,.1,0),Color("344e59"))
	PART.piece(self,Vector3(3.8,.12,9.6),Vector3(0,.48,0),Color("a39170"))
	for x in [-2.0,2.0]:
		PART.piece(self,Vector3(.18,.8,10),Vector3(x,.75,0),Color("d0c8ad"))
	PART.piece(self,Vector3(4.1,.8,.18),Vector3(0,.75,5),Color("d0c8ad"))
	_build_bow()
	for x in [-2.15,2.15]:
		for z in [-3.5,0,3.5]: PART.piece(self,Vector3(.4,.6,.65),Vector3(x,.55,z),Color("242c30"),true)
	PART.piece(self,Vector3(2.9,1.7,2),Vector3(0,1.35,3.6),Color("ded5b8"))
	PART.piece(self,Vector3(2.5,.7,.04),Vector3(0,1.65,2.57),Color("365965"))
	PART.piece(self,Vector3(3.2,.15,2.3),Vector3(0,2.25,3.6),Color("eeead8"))
	PART.piece(self,Vector3(.09,1.5,.09),Vector3(0,3,3.9),Color("69777a"))
	PART.piece(self,Vector3(.7,.08,.1),Vector3(0,3.65,3.9),Color("e7ded0"))
	for n in 30:
		var box := Node3D.new()
		box.name = "Cargo%02d" % n
		box.position = Vector3((n%3-1)*.95,.93+float(n/15)*.78,-3.6+float((n%15)/3)*1.02)
		add_child(box)
		PART.piece(box,Vector3(.85,.75,.85),Vector3.ZERO,Color("ab7c49"))
		for x in [-.3,.3]: PART.piece(box,Vector3(.09,.78,.89),Vector3(x,0,0),Color("d0a66b"))
		box.hide()
		crates.append(box)
func set_load(count: int) -> void:
	for i in crates.size(): crates[i].visible = i < count
func _build_bow() -> void:
	var ring := [Vector3(-2,.43,-5),Vector3(0,.43,-6.8),Vector3(2,.43,-5)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [ring[0],ring[2],ring[1]]: surface.add_vertex(v)
	for i in 3:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i+1)%3]
		var c := b-Vector3(0,.65,0)
		var d := a-Vector3(0,.65,0)
		for v in [a,b,c,a,c,d]: surface.add_vertex(v)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("344e59")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)
