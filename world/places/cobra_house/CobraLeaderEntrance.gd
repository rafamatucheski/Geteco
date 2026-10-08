extends Node3D
## The leader keeps a physical locked door until the won race admits Dante.
## Geometry is adapted once during streaming, with the original wood/stone finish.
var open_amount := 0.0
var hinge: Node3D
var canopy_center: MeshInstance3D

static func install(art: Node3D, front_z: float) -> Node3D:
	var adapter = load("res://world/places/cobra_house/CobraLeaderEntrance.gd").new()
	adapter.name = "LeaderWalkupDoor"
	art.visuals_root.add_child(adapter)
	adapter.set_meta("place_id","cobra_leader_house")
	adapter.add_to_group("v2_walkin_facade")
	adapter._build(art,front_z)
	return adapter

func set_open_amount(value: float) -> void:
	open_amount = clampf(value,0,1)
	hinge.rotation.y = open_amount*PI*.5
	if is_instance_valid(canopy_center): canopy_center.visible = open_amount<.5

func _build(art: Node3D, front_z: float) -> void:
	var source: MeshInstance3D = art.visuals_root.get_node("HouseBody")
	art.collision_root.get_node("HouseBodySolid").free()
	_cut(source,1.16,2.65,front_z-1.5)
	_cut(art.visuals_root.get_node("FrontDoorFrame"),.98,2.48,front_z-.1)
	hinge = Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-.475,0,front_z+.04)
	add_child(hinge)
	for key in ["FrontDoor","FrontDoorknob"]:
		var part: Node3D = art.visuals_root.get_node(key)
		part.reparent(hinge,true)
	_box(hinge,"DoorSolid",Vector3(.475,1.4,0),Vector3(.95,2.1,.10))
	var porch: Node3D = art.visuals_root.get_node("FrontPorch")
	# Only the doorway's canopy panel cuts away on approach. The porch roof
	# keeps its exterior silhouette and the threshold becomes readable.
	canopy_center = porch.get_node("PorchRoof")
	var canopy_size: Vector3 = canopy_center.mesh.size
	var side_width := (canopy_size.x-2.2)*.5
	for side in [-1.0,1.0]:
		var panel := canopy_center.duplicate() as MeshInstance3D
		panel.name = "CanopySide"
		panel.mesh = canopy_center.mesh.duplicate()
		panel.mesh.size.x = side_width
		panel.position.x = float(side)*(1.1+side_width*.5)
		porch.add_child(panel)
	canopy_center.mesh = canopy_center.mesh.duplicate()
	canopy_center.mesh.size.x = 2.2
	for part in porch.get_children():
		if not part is MeshInstance3D or not part.mesh is BoxMesh: continue
		if str(part.name)=="PorchDeck" or str(part.name).begins_with("PorchStep_"):
			var body := _box(part,"WalkablePorch",Vector3.ZERO,part.mesh.size)
			body.set_meta("pedestrian_step",true)
			body.set_meta("pedestrian_step_top",part.mesh.size.y*.5)
		elif str(part.name).begins_with("PorchPost_") or str(part.name).begins_with("PorchRail"):
			_box(part,"PorchSolid",Vector3.ZERO,part.mesh.size)
	set_open_amount(0)

func _cut(source: MeshInstance3D, width: float, ceiling: float, rear: float) -> void:
	var low: Vector3 = source.position-source.mesh.size*.5
	var high: Vector3 = source.position+source.mesh.size*.5
	_piece(source,low,Vector3(-width*.5,high.y,high.z))
	_piece(source,Vector3(width*.5,low.y,low.z),high)
	if rear>low.z: _piece(source,Vector3(-width*.5,low.y,low.z),Vector3(width*.5,high.y,rear))
	_piece(source,Vector3(-width*.5,ceiling,maxf(rear,low.z)),Vector3(width*.5,high.y,high.z))
	source.free()

func _piece(source: MeshInstance3D, low: Vector3, high: Vector3) -> void:
	var size := high-low
	if minf(size.x,minf(size.y,size.z))<=.001: return
	var mesh := MeshInstance3D.new()
	mesh.name = str(source.name)+"Passage"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.material_override = source.material_override
	mesh.position = (low+high)*.5
	source.get_parent().add_child(mesh)
	_box(mesh,"WallSolid",Vector3.ZERO,size)

func _box(parent: Node3D, id: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	return body
