extends Node3D
## Native reconstruction of MountainSceneryBuilder.build_detailed_bunker exterior2D.
## The helipad itself reuses its original native3D model.
const S := 1.0/16.0
var materials: Dictionary = {}
func _ready() -> void:
	_box("OriginalBunkerBody",Vector3(0,1.5,-12.5*S),Vector3(250*S,3,115*S),Color("3d444d"),true)
	_box("ConcreteRoof",Vector3(0,3.05,-12.5*S),Vector3(250*S,.1,115*S),Color("6b747a"))
	for x in [-70,0,70]:
		_box("OriginalSlit",Vector3(x*S,1.8,45*S+.02),Vector3(32*S,.6,.05),Color("0f172a"))
	_box("BunkerDoor",Vector3(0,.95,45*S+.05),Vector3(1.35,1.9,.06),Color("263a3f"))
	_box("OriginalGenerator",Vector3(105*S,.8,130*S),Vector3(40*S,1.6,40*S),Color("2c3e50"),true)
	var mast := Vector3(85*S,3,-60*S)
	for side in [-1,1]: _beam(mast+Vector3(side*14*S,0,0),mast+Vector3(0,4.8,0),.14,Color("e74c3c"))
	_box("OriginalBeacon",mast+Vector3(0,4.9,0),Vector3(.23,.23,.23),Color("ff4133"))
	var radar := Vector3(-75*S,3,-20*S)
	_beam(radar,radar+Vector3(0,1.1,0),.15,Color("c4cdcc"))
	_beam(radar+Vector3(-24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	_beam(radar+Vector3(24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	var helipad = preload("res://assets/regions/source/world/mountain_pass/MountainHelipad3D.gd").new()
	helipad.name = "MountainHelipad"
	# Separate landing clearance from the bunker entrance and road turnaround.
	helipad.position = Vector3(-20,0,3.625)
	add_child(helipad)
	for mesh in helipad.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("interior_solid_id","") != "": mesh.create_trimesh_collision()
	# The region's connected footpath owns the approach. No slabs across the road.
func _beam(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	var beam := _box("OriginalAntenna",(a+b)*.5,Vector3(width,a.distance_to(b),width),color)
	beam.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
func _box(id: String,at: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	if not materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		materials[color] = mat
	mesh.material_override = materials[color]
	add_child(mesh)
	if solid: mesh.create_trimesh_collision()
	return mesh
