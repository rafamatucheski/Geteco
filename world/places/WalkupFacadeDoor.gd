extends Node3D
## Adapts the authored exterior once at chunk construction; no per-frame scans.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var open_amount := 0.0
var hinge: Node3D

static func install(art: Node3D, data: Dictionary) -> Node3D:
	var family := CATALOG.walkup_family(str(data.id))
	if family.is_empty() or art.has_node("WalkupDoor"): return null
	var adapter = load("res://world/places/WalkupFacadeDoor.gd").new()
	adapter.name = "WalkupDoor"
	art.add_child(adapter)
	adapter.set_meta("place_id", data.get("access_id", data.id))
	adapter.add_to_group("v2_walkin_facade")
	adapter._build(art, family)
	return adapter

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount, 0.0, 1.0)
	if is_instance_valid(hinge): hinge.rotation.y = open_amount * PI * .5

func _build(art: Node3D, family: String) -> void:
	var z: float = CATALOG.walkup_door_z(family)
	var width := .92
	var height := 2.0
	var bottom := .14
	var leaves: Array[Node3D] = []
	match family:
		"cabin":
			# The source's unnamed meshes are identified by its authored door bounds.
			for node in art.get_children():
				if node is MeshInstance3D and absf(node.position.x) < .45 and node.position.z >= 1.87 and node.position.z <= 1.98 and node.position.y > .3 and node.position.y < 2.0:
					leaves.append(node)
			for node in art.get_children():
				if node is MeshInstance3D and node.mesh is BoxMesh and not node in leaves:
					var size: Vector3 = node.mesh.size
					if size.y > 2.0: _solid(node)
					elif size.y < .2 and size.x > 1.0 and absf(node.position.x) < .1 and node.position.y < .2:
						_cut_box(node, 1.02, 2.3, .3, true)
		"shop":
			width = 1.1; height = 2.2; bottom = .08
			leaves = _named_parts(art, ["Door", "DoorGlass", "Handle"])
			_cut_named(art, ["Foundation", "Threshold"], 1.2, 2.4, .2, true)
		"residence":
			width = 1.12; height = 2.16; bottom = .14
			leaves = _named_parts(art, ["FrontDoor", "DoorPanel", "DoorHandle"])
			_cut_named(art, ["Walls", "StonePlinth", "DoorFrame"], 1.14, 2.34, 1.35)
			_cut_named(art, ["Foundation", "PorchStep"], 1.14, 2.34, 1.35, true)
		"keeper":
			width = 1.08; height = 2.06; bottom = .18
			_cut_named(art, ["LimewashedCottage", "DoorRecess"], 1.12, 2.28, 1.0)
			_cut_named(art, ["StoneFoundation", "StoneStep"], 1.12, 2.28, 1.0, true)
			var original: Node3D = art.get_node("HingedDoor")
			original.rotation.y = 0.0
			# Leave its empty source pivot alive so an existing factory tween remains harmless.
			for node in original.get_children():
				if node is Node3D: leaves.append(node)
		"bunker":
			width = 1.35; height = 1.9; bottom = 0.0
			leaves = _named_parts(art, ["BunkerDoor"])
			_cut_named(art, ["OriginalBunkerBody"], 1.4, 2.02, 1.05)
			for node in art.get_children():
				if node is MeshInstance3D and absf(node.position.x) < .01 and is_equal_approx(node.position.y, 1.8): node.position.y = 2.4
		"lodge":
			width = 1.45; height = 2.35; bottom = .075
			for node in art.get_children():
				if node is MeshInstance3D and absf(node.position.x) < .01 and node.position.z > 3.95 and node.position.z < 4.1 and node.position.y < 2.0: leaves.append(node)
			_cut_named(art, ["MainHall"], 1.55, 2.5, 2.2)
			_cut_named(art, ["Foundation", "Porch"], 1.55, 2.5, 2.2, true)
	# Fresh structural solids also cover cabin/lodge models that had no native collider.
	for node in art.find_children("*", "MeshInstance3D", true, false):
		if node.get_meta("interior_solid_id", "") != "" and not node in leaves: _solid(node)
	hinge = Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-width * .5, 0, z)
	add_child(hinge)
	for leaf in leaves:
		leaf.reparent(hinge, true)
		for child in leaf.find_children("*", "StaticBody3D", true, false): child.free()
	var body := StaticBody3D.new()
	body.name = "DoorSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	hinge.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, .12)
	collision.shape = shape
	collision.position = Vector3(width * .5, bottom + height * .5, 0)
	body.add_child(collision)
	set_open_amount(0.0)

func _named_parts(art: Node3D, names: Array) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for node in art.get_children():
		if node is MeshInstance3D:
			# Repeated generated names are auto-renamed by Godot; position covers panels.
			if str(node.name) in names or ("DoorPanel" in names and node.mesh is BoxMesh and node.mesh.size.is_equal_approx(Vector3(.84, .64, .04))): parts.append(node)
	return parts

func _cut_named(art: Node3D, names: Array, width: float, ceiling: float, rear_z: float, floor_strip := false) -> void:
	for node in art.get_children():
		if not node is MeshInstance3D or not node.mesh is BoxMesh: continue
		if str(node.name) in names or ("Porch" in names and node.mesh.size.is_equal_approx(Vector3(4.3, .18, 1.45))):
			if node.position.z + node.mesh.size.z * .5 > rear_z:
				_cut_box(node, width, ceiling, rear_z, floor_strip)

func _cut_box(source: MeshInstance3D, width: float, ceiling: float, rear_z: float, floor_strip := false) -> void:
	# Partition the original solid, retaining its exact material and exterior silhouette.
	var size: Vector3 = source.mesh.size
	var low := source.position - size * .5
	var high := source.position + size * .5
	var left := maxf(low.x, -width * .5)
	var right := minf(high.x, width * .5)
	var rear := clampf(rear_z, low.z, high.z)
	_piece(source, Vector3(low.x, low.y, low.z), Vector3(left, high.y, high.z))
	_piece(source, Vector3(right, low.y, low.z), high)
	_piece(source, Vector3(left, low.y, low.z), Vector3(right, high.y, rear))
	_piece(source, Vector3(left, maxf(low.y, ceiling), rear), Vector3(right, high.y, high.z))
	if floor_strip: _piece(source, Vector3(left, -.025, rear), Vector3(right, .005, high.z))
	source.free()

func _piece(source: MeshInstance3D, low: Vector3, high: Vector3) -> void:
	var size := high - low
	if size.x <= .001 or size.y <= .001 or size.z <= .001: return
	var piece := MeshInstance3D.new()
	piece.name = str(source.name) + "Passage"
	var box := source.mesh.duplicate() as BoxMesh
	box.size = size
	piece.mesh = box
	piece.material_override = source.material_override
	piece.layers = source.layers
	piece.position = (low + high) * .5
	source.get_parent().add_child(piece)
	_solid(piece)

func _solid(mesh: MeshInstance3D) -> void:
	for child in mesh.get_children():
		if child is StaticBody3D: return
	mesh.create_trimesh_collision()
	for child in mesh.get_children():
		if child is StaticBody3D:
			child.collision_layer = 1
			child.collision_mask = 0
