extends Node3D
## Geteco V2: original Maciota art in one native World3D.
const PROPS := preload("res://assets/maciota/WorkshopProps.gd")
const DETAILS := preload("res://assets/maciota/WorkshopDetails.gd")
const FACADE := preload("res://assets/maciota/GarageFacade.gd")
const MACIOTA := preload("res://assets/maciota/MaciotaModel.gd")
const MECHANIC := preload("res://assets/maciota/MechanicModel.gd")
var exterior_origin := Vector3(-21, 0, -21)
var interior_origin := Vector3(0, 0, -130)
var entry_position: Vector3:
	get: return to_global(exterior_origin + Vector3(-2.5, 0, 8.3))
var exterior_return: Vector3:
	get: return entry_position + Vector3(0, 0, 1)
var interior_spawn: Vector3:
	get: return to_global(interior_origin + Vector3(0, 0, 3.2))
var exit_position: Vector3:
	get: return to_global(interior_origin + Vector3(0, 0, 4.3))
var camera_target: Vector3:
	get: return to_global(interior_origin + Vector3(1.1, .55, .2))
var camera_size := 13.0
var camera_offset := Vector3(0,18,15)
var room_bounds := AABB(Vector3(-4.4, 0, -4.3), Vector3(11.2,3.8,9.2))
var exterior_bounds := AABB(Vector3(-6.4,0,1.56), Vector3(14.8,7.1,6.5))
var solid_bodies: Array[StaticBody3D] = []
var interaction_points: Dictionary = {}
var maciota: Node3D
var mechanic: Node3D
var room: Node3D
var facade: Node3D
var part_visual: Node3D
var interior_active := false

func _ready() -> void:
	facade = FACADE.new()
	facade.name = "MaciotaFacade"
	facade.position = exterior_origin + Vector3(-.5,0,0)
	add_child(facade)
	_build_mesh_solids(facade, "Facade")
	room = PROPS.new()
	room.name = "MaciotaInterior"
	room.position = interior_origin
	add_child(room)
	_retract_lift_arms()
	DETAILS.build(room)
	# Legacy external apron existed to fill a projected viewport. Native V2
	# keeps only the actual room footprint; collision remains independently intact.
	for detail in room.get_children():
		if detail is MeshInstance3D:
			if str(detail.name).begins_with("ApronJoint") or detail.name == "RearBuildingMass":
				detail.hide()
			elif detail.name == "BuildingFoundation":
				detail.mesh = detail.mesh.duplicate()
				detail.mesh.size = Vector3(11.3,.32,9.3)
				detail.position = Vector3(1.15,-.24,.25)
	# Bounds from original authoring plus tagged meshes cover furniture tops,
	# legs, lift arms and structural corners. Raised overhead details stay overhead.
	var index := 0
	for bounds: AABB in room.get_obstacle_bounds():
		_add_solid(room, "Furniture%d" % index, bounds)
		index += 1
	_build_mesh_solids(room, "Room")
	_add_solid(room, "Floor", AABB(Vector3(-24,-.32,-19),Vector3(50,.30,40)))
	# Original cutaway treatment: retain full physical walls, reveal actors.
	for child in room.get_children():
		if child is MeshInstance3D and child.position.z > 4.4 and child.position.y > 2.6:
			child.hide() # Roller cylinder as well as header: original open gate cutaway.
		if child is MeshInstance3D and child.mesh is BoxMesh:
			if child.position.z > 4.5 and child.mesh.size.y > 3.0:
				child.mesh = child.mesh.duplicate()
				child.mesh.size.y = .22
				child.position.y = .11
			elif child.position.y > 3.3 and child.mesh.size.z > 3.0:
				child.hide()
			elif child.position.z > 4.4 and child.position.y > 2.6:
				child.hide()
	maciota = _resident(MACIOTA, "Maciota", Vector3(3.35,0,-1.7))
	mechanic = _resident(MECHANIC, "Mechanic", Vector3(-2.9,0,-1.25))
	mechanic.rotation.y = PI
	interaction_points = {
		"maciota": to_global(interior_origin + Vector3(3.4,0,-.55)),
		"mechanic": to_global(interior_origin + Vector3(-2.9,0,-.15)),
		"workbench": to_global(interior_origin + Vector3(-.8,0,-2.65)),
		"part": to_global(interior_origin + Vector3(.75,0,-2.65)),
	}
	part_visual = Node3D.new()
	part_visual.name = "StarterPart"
	part_visual.position = Vector3(.75,.12,-2.65)
	room.add_child(part_visual)
	var metal := DETAILS.material("b9c4c9",.3,.7)
	DETAILS.box(part_visual,"PartCase",Vector3(0,.13,0),Vector3(.32,.26,.25),metal)
	DETAILS.box(part_visual,"PartHandle",Vector3(0,.3,0),Vector3(.15,.08,.055),DETAILS.material("daac52",.5))
	set_interior_active(false)

func _retract_lift_arms() -> void:
	# Park the original hinged arms parallel to their columns before deriving solids.
	# The authored service pose places the pads under a raised chassis, across the bay.
	for part in room.get_children():
		if not part is MeshInstance3D: continue
		var point: Vector3 = part.position
		if point.y < .19 or point.y > .3 or absf(point.x)<.95 or absf(point.x)>1.6 or absf(point.z)>1.2: continue
		if not (part.mesh is BoxMesh or part.mesh is CylinderMesh): continue
		part.position.x = signf(point.x)*2.05
		part.position.z = signf(point.z)*(.4 if part.mesh is BoxMesh else .85)
		part.rotation.y = 0

func _resident(model: Script, identity: String, point: Vector3) -> Node3D:
	var actor := model.new() as Node3D
	actor.name = identity
	actor.position = point
	actor.set_meta("invulnerable",true)
	actor.set_meta("persistent_id",identity.to_lower())
	room.add_child(actor)
	var body := StaticBody3D.new()
	body.name = "ResidentBody"
	body.collision_layer = 2
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.7
	shape.radius = .28
	collision.shape = shape
	collision.position.y = .85
	body.add_child(collision)
	actor.add_child(body)
	return actor

func _build_mesh_solids(parent: Node3D, prefix: String) -> void:
	var index := 0
	for node in parent.get_children():
		if not node is MeshInstance3D or not node.has_meta("interior_solid_id"): continue
		var bounds: AABB = node.transform * node.get_aabb()
		if bounds.position.y >= 2.1: continue
		# Full furniture footprint extends to floor; walking under desks is forbidden.
		bounds.size.y += maxf(bounds.position.y,0)
		bounds.position.y = minf(bounds.position.y,0)
		_add_solid(parent, "%s_%d" % [prefix,index], bounds)
		index += 1

func _add_solid(parent: Node3D, id: String, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.set_meta("interior_solid_id",id)
	body.set_meta("local_bounds",bounds)
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	collision.shape = shape
	collision.position = bounds.get_center()
	body.add_child(collision)
	parent.add_child(body)
	solid_bodies.append(body)

func set_interior_active(active: bool) -> void:
	interior_active = active
	if not is_instance_valid(room): return
	room.visible = active
	room.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func set_part_available(available: bool) -> void:
	if is_instance_valid(part_visual): part_visual.visible = available
