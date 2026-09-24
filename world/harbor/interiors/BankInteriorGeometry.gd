extends RefCounted
## Classify the actual rendered furniture before projecting physical footprints.
const PROJECTION := preload("res://systems/interiors/InteriorSolidProjection.gd")
static func classify(model: Node3D, door: Node3D) -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("interior_surface"): continue
		var label := str(mesh.name)
		var center: Vector3 = model.to_local(mesh.to_global(mesh.mesh.get_aabb().get_center()))
		var id := ""
		if door.is_ancestor_of(mesh): id = "VaultDoor"
		elif label == "Floor" or label.begins_with("Tile_"):
			mesh.set_meta("interior_surface", "floor")
			continue
		elif label.begins_with("Cornice") or label == "VaultLintel" or label.begins_with("Lamp"):
			mesh.set_meta("interior_surface", "overhead")
			continue
		elif label.begins_with("Wall_") or label.begins_with("Baseboard_"):
			id = "WallLeft" if center.x < 0 else "WallRight"
		elif label == "BackWall": id = "BackWall"
		elif label.begins_with("VaultPartition") or label.begins_with("PartitionPanel"):
			id = "PartitionLeft" if center.x < 0 else "PartitionRight"
		elif label.begins_with("VaultFrame") or label.begins_with("Pilaster"): id = label
		elif label.begins_with("Counter") or label.begins_with("Panel") or label.begins_with("Monitor") or label.begins_with("Screen") or label.begins_with("Stand") or label.begins_with("Keyboard"):
			id = "CounterLeft" if center.x < 0 else "CounterRight"
		elif label.begins_with("Bench"):
			id = "BenchLeft" if center.x < 0 else "BenchRight"
		elif mesh.has_meta("interior_solid_id"):
			id = str(mesh.get_meta("interior_solid_id"))
		else:
			# Treasure is a collectible, handled by its interaction. Its low piles
			# remain reachable from the floor instead of trapping the pickup point.
			var ancestor: Node = mesh.get_parent()
			while ancestor != null and ancestor != model:
				if ancestor.has_meta("bank_collectible"):
					mesh.set_meta("interior_surface", "collectible")
					break
				ancestor = ancestor.get_parent()
			assert(mesh.has_meta("interior_surface"), "Unclassified bank mesh: " + str(mesh.get_path()))
			continue
		mesh.set_meta("interior_solid_id", StringName(id))
		mesh.set_meta("interior_surface", "solid")

static func build(room: Node2D, model: Node3D, door: Node3D) -> void:
	classify(model, door)
	var body := StaticBody2D.new()
	body.name = "BankVisualSolids"
	room.add_child(body)
	PROJECTION.build(model, body, room.project_floor)
	var moving := StaticBody2D.new()
	moving.name = "BankVaultSolid"
	room.add_child(moving)
	for shape in body.get_children():
		if shape.get_meta("interior_solid_id") == &"VaultDoor": shape.reparent(moving, false)
	room.vault_body = moving
	# The open front is a camera cutaway. Derive its world boundary from Floor.
	var floor_mesh := model.find_child("Floor", true, false) as MeshInstance3D
	if floor_mesh:
		var rect: AABB = floor_mesh.transform * floor_mesh.mesh.get_aabb()
		if room.get("inline_mode") == true:
			for edge in [Rect2(rect.position.x,rect.end.z,-1.55-rect.position.x,.12),Rect2(1.55,rect.end.z,rect.end.x-1.55,.12)]:
				var side: StaticBody2D = room._projected_solid(edge)
				side.name = "BankFloorBoundary"
		else:
			var front: StaticBody2D = room._projected_solid(Rect2(rect.position.x,rect.end.z,rect.size.x,.12))
			front.name = "BankFloorBoundary"
