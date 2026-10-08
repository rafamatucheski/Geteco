extends SceneTree
const REGION := preload("res://world/editing/EditableRegion.gd")
const PILOT := preload("res://world/regions/MountainTerrain3DPilot.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(ClassDB.can_instantiate("Terrain3D"), "Installed Terrain3D extension loads")
	var definition = REGION.new()
	definition.region_id = "mountain"
	definition.prepare_data()
	var chunk := Node3D.new()
	root.add_child(chunk)
	var rect := Rect2(PILOT.ORIGIN,Vector2.ONE*64)
	var native: MeshInstance3D = definition.terrain.build_chunk(chunk,rect)
	check(native.get_meta("terrain3d_baked_pilot",false), "Production hook loads exported Terrain3D tile")
	check(native.mesh.get_meta("generator","").begins_with("Terrain3D 1.0.2"), "Mesh records Terrain3D export provenance")
	check(chunk.find_children("*","Terrain3D",true,false).is_empty(), "No unstable native Terrain3D nodes during gameplay")
	var faces := native.mesh.get_faces()
	var vertex_error := 0.0
	var face_error := 0.0
	var outside := 0
	for i in range(0,faces.size(),3):
		var center := Vector3.ZERO
		for j in 3:
			var v: Vector3 = faces[i+j]
			center += v/3.0
			vertex_error = maxf(vertex_error,absf(v.y-definition.terrain.surface_height_at(Vector2(v.x,v.z))))
			if v.x<704 or v.x>768 or v.z < -448 or v.z > -384: outside+=1
		face_error = maxf(face_error,absf(center.y-definition.terrain.surface_height_at(Vector2(center.x,center.z))))
	check(vertex_error<.005,"All exported vertices match native floor: %s" % vertex_error)
	check(face_error<.02,"All exported triangle centres within 2 cm of collider: %s" % face_error)
	check(outside==0,"Export stays within the single tile")
	await physics_frame
	await physics_frame
	for offset in [Vector2(1,1),Vector2(63,1),Vector2(1,63),Vector2(63,63),Vector2(32,32)]:
		var p: Vector2 = PILOT.ORIGIN + offset
		var expected: float = definition.terrain.surface_height_at(p)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x,expected+3,p.y),Vector3(p.x,expected-3,p.y),1)
		var hit := chunk.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-expected)<.005,"Native collision at %s" % p)
	var neighbour: MeshInstance3D = definition.terrain.build_chunk(chunk,Rect2(PILOT.ORIGIN+Vector2(64,0),Vector2.ONE*64))
	check(not neighbour.get_meta("terrain3d_baked_pilot",false),"Neighbour remains native")
	var old_id := native.get_instance_id()
	native.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_id_valid(old_id),"Unloading releases pilot surface")
	native = definition.terrain.build_chunk(chunk,rect)
	check(native.get_meta("terrain3d_baked_pilot",false),"Return rebuilds pilot")
	definition.terrain.build_chunk(chunk,Rect2(PILOT.ORIGIN-Vector2(64,0),Vector2.ONE*64))
	for player_mode in [true,false]:
		var actor = preload("res://scripts/Actor.gd").new()
		actor.is_player = player_mode
		actor.controlled_automatically = true
		actor.speed = 8.0
		actor.position = Vector3(700,definition.terrain.surface_height_at(Vector2(700,-444))+.08,-444)
		chunk.add_child(actor)
		actor.automatic_direction = Vector3.RIGHT
		var floor_error := 0.0
		for frame in 720:
			await physics_frame
			if actor.position.x>=772: break
			if frame>12:
				var ground: float = definition.terrain.surface_height_at(Vector2(actor.position.x,actor.position.z))
				floor_error=maxf(floor_error,absf(actor.position.y-ground))
		check(actor.position.x>=772 and floor_error<.2,"Player=%s crosses both seams; x=%s floor_error=%s" % [player_mode,actor.position.x,floor_error])
		actor.free()
	chunk.free()
	definition.free()
	for failure in failures: push_error(failure)
	print("TERRAIN3D_PILOT checks=",checks," failures=",failures.size()," vertex_error=",vertex_error," face_error=",face_error)
	quit(0 if failures.is_empty() else 1)
