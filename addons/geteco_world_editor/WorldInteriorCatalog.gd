@tool
extends RefCounted
const PLACES := preload("res://world/places/PlaceCatalog.gd")

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = PLACES.definitions()
	result.append({"id":"maciota","original_name":"Garagem do Maciota","region":"harbor","size":Vector2(11.2,9.2),"camera_target":Vector3(1.1,.55,.2),"camera_size":13.0,"spawn":Vector3(0,0,3.2)})
	return result

static func definition(id: String) -> Dictionary:
	for row in definitions():
		if str(row.id) == id: return row
	return {}

static func build_preview(parent: Node3D, id: String, floor_index := 0) -> Dictionary:
	var row := definition(id)
	if row.is_empty(): return {"error":"Interior desconhecido: "+id}
	var place: Node3D
	if id == "maciota":
		place = preload("res://world/maciota/MaciotaPlace.gd").new()
		place.interior_origin = Vector3.ZERO
	else:
		place = PLACES.create_place(id)
		if place == null: return {"error":"Não foi possível preparar o interior: "+id}
		if "floor_index" in place:
			place.floor_index = clampi(floor_index,0,int(row.get("floor_count",0)))
	# Builders run once, without a game session, residents, rewards or save lifecycle.
	place.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(place)
	var room: Node3D = place.room if id == "maciota" else (place.floor_room if place.get("floor_room") is Node3D else place)
	if id == "maciota":
		room.show()
		place.facade.hide()
	_finish(room)
	return {"error":"","place":place,"root":room,"definition":row}

static func strip_actors(room: Node3D) -> void:
	_remove_actors(room)

static func _finish(node: Node) -> void:
	if node.has_method("finish_build"): node.call("finish_build")
	for child in node.get_children(): _finish(child)

static func _remove_actors(node: Node) -> void:
	for child in node.get_children():
		if child is CharacterBody3D or child is RigidBody3D or child.has_meta("invulnerable") or child.has_meta("persistent_id"):
			child.free()
		else: _remove_actors(child)
