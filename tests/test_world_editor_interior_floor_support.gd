extends SceneTree
const EDITS := preload("res://world/editing/WorldInteriorEdits.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
class Room:
	extends Node3D
	var definition := {"size":Vector2(8,8),"spawn":Vector3.ZERO,"exit":Vector3(0,0,2),"npcs":[{"id":"fixture_npc","local_position":Vector3(2,0,0)}]}
	var solid_bounds: Array = []
class Resident:
	extends CharacterBody3D
	var active := false
	func _physics_process(delta: float) -> void:
		if not active: return
		velocity.y -= 9.8*delta
		move_and_slide()
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func document(row: Dictionary, extra: Dictionary) -> Dictionary:
	var result := DATA.empty_document()
	var edit := {"id":row.id,"type":"piece","source_record":row.source_record,"position":row.position.duplicate(),"rotation":0.0}
	edit.merge(extra,true)
	result.interiors["floor_fixture"] = {row.id:edit}
	return result
func ground_ray() -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,0),Vector3(0,-.5,0),1))
func run() -> void:
	var official := DATA.disk_hash()
	var room := Room.new()
	root.add_child(room)
	var floor_body := StaticBody3D.new()
	floor_body.name = "OriginalFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.set_meta("interior_solid_id","Floor")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(8,.2,8)
	shape.position.y = -.1
	floor_body.add_child(shape)
	room.add_child(floor_body)
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	visual.mesh.size = Vector3(8,.2,8)
	visual.position.y = -.1
	visual.set_meta("interior_solid_id","Floor")
	room.add_child(visual)
	var actor := Resident.new()
	actor.position = Vector3(0,.09,0)
	actor.collision_layer = 2
	actor.collision_mask = 1
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	capsule.shape.radius = .32
	capsule.shape.height = 1.7
	capsule.position.y = .85
	actor.add_child(capsule)
	room.add_child(actor)
	var rows := EDITS.manifest(room,"floor_fixture")
	var floor_row := {}
	for row in rows:
		if row.label=="Floor" and "/solid/" in str(row.source_record): floor_row = row; break
	check(not floor_row.is_empty(),"Original physical floor is an editable inventory group")
	if floor_row.is_empty(): room.free(); quit(1); return
	var baseline := EDITS.prepare(room,"floor_fixture",DATA.empty_document())
	check(str(baseline.error).is_empty(),"Original supported room validates")
	var removed := document(floor_row,{"deleted":true})
	check(not str(EDITS.prepare(room,"floor_fixture",removed).error).is_empty(),"Removing the floor cannot approve unsupported spawn/exit/residents")
	await physics_frame
	await physics_frame
	check(ground_ray().is_empty(),"Physical control confirms that deleting the floor really removes its support")
	var moved := document(floor_row,{"position":[20,0]})
	check(not str(EDITS.prepare(room,"floor_fixture",moved).error).is_empty(),"Moving the floor away fails support validation immediately")
	var narrow := document(floor_row,{"stretch":[.4,1.0]})
	var narrow_error: String = EDITS.prepare(room,"floor_fixture",narrow).error
	check(not narrow_error.is_empty() and "posição de" in narrow_error,"Resizing beneath a resident is rejected even when spawn still has a floor")
	var short_floor := document(floor_row,{"stretch":[1.0,.2]})
	check("saída" in str(EDITS.prepare(room,"floor_fixture",short_floor).error),"The exit needs physical support as well as the spawn")
	var safe_scale := document(floor_row,{"stretch":[.98,.98],"rotation":2.0})
	check(str(EDITS.prepare(room,"floor_fixture",safe_scale).error).is_empty(),"A rotated and resized floor is accepted when its actual shape still supports every anchor")
	check(str(EDITS.prepare(room,"floor_fixture",DATA.empty_document()).error).is_empty(),"Undo restores original floor support and clears the validation error")
	await physics_frame
	await physics_frame
	check(not ground_ray().is_empty(),"Undo restores the real physics floor")
	var convex := ConvexPolygonShape3D.new()
	var corners := PackedVector3Array()
	var slab := AABB(Vector3(-4,-.2,-4),Vector3(8,.2,8))
	for corner in 8: corners.append(slab.get_endpoint(corner))
	convex.points = corners
	var convex_support: Variant = EDITS._support_height([EDITS._support_shape(convex,Transform3D.IDENTITY)],Vector3.ZERO,.12,-.18)
	check(convex_support!=null and absf(float(convex_support))<.0001,"A convex slab is checked against its real upper envelope")
	# A concave surface whose bounding box covers the room still has a real hole.
	var holed := StaticBody3D.new()
	holed.collision_layer = 1
	holed.collision_mask = 0
	var collider := CollisionShape3D.new()
	var triangles := PackedVector3Array()
	for span in [Vector2(-4,-.8),Vector2(.8,4)]:
		var a := Vector3(span.x,0,-4)
		var b := Vector3(span.y,0,-4)
		var c := Vector3(span.x,0,4)
		var d := Vector3(span.y,0,4)
		triangles.append_array(PackedVector3Array([a,b,c,b,d,c]))
	collider.shape = ConcavePolygonShape3D.new()
	collider.shape.set_faces(triangles)
	holed.add_child(collider)
	room.add_child(holed)
	check(not str(EDITS.prepare(room,"floor_fixture",removed).error).is_empty(),"A hole in real triangle geometry cannot pass as support through its bounding box")
	holed.free()
	var replacement := DATA.new_entity("ground",Vector2.ZERO)
	replacement.size = [8,8]
	replacement.surface = "concrete"
	removed.interiors.floor_fixture[replacement.id] = replacement
	check(str(EDITS.prepare(room,"floor_fixture",removed).error).is_empty(),"A newly authored physical floor can replace the original floor")
	actor.active = true
	for frame in 45: await physics_frame
	check(actor.is_on_floor() and actor.position.y>.04 and actor.position.y<.2,"A real character capsule remains standing on the replacement floor")
	check(not ground_ray().is_empty(),"The accepted replacement has real physical support")
	room.free()
	check(DATA.disk_hash()==official,"Floor validation never saves the official authored world")
	print("WORLD_EDITOR_INTERIOR_FLOOR_SUPPORT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
