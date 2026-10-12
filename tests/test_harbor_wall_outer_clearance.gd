extends SceneTree
## Local geometry contract; temporal stability and real admission need Main.
const INTERIOR := preload("res://world/places/harbor_buildings/HarborBuildingInterior.gd")
const NATIVE := preload("res://world/places/NativePlace.gd")
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func close(a: float, b: float) -> bool: return absf(a-b) < .00001

func bounds(node: MeshInstance3D) -> AABB: return node.transform*node.get_aabb()

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("WALL_CLEARANCE timeout"); quit(3))
	for spec in [Vector4(30,13.75,0,0),Vector4(8,6,-.5,0),Vector4(18,9,3.0,0),Vector4(18,9,0,1)]:
		check_shell(spec)
	# Exercise the actual floor-adapter collider instead of copying its formula
	# into a fake shape. Its footprint stays full beneath the recessed finish.
	var room := NATIVE.new()
	room.definition = CATALOG.find("harbor_building_market_hall").duplicate(true)
	root.add_child(room)
	var floor_body: StaticBody3D
	for body in room.solid_bodies:
		if str(body.name) == "Floor": floor_body = body
	check(floor_body != null, "Actual room retains floor collider")
	if floor_body != null:
		var collision := floor_body.get_child(0) as CollisionShape3D
		var shape := collision.shape as BoxShape3D
		var size: Vector2 = room.definition.size
		var box := collision.transform*AABB(-shape.size*.5,shape.size)
		check(box.position.is_equal_approx(Vector3(-size.x*.5,-.22,-size.y*.5)), "Floor collider origin unchanged")
		check(box.size.is_equal_approx(Vector3(size.x,.2,size.y)), "Floor collider footprint and thickness unchanged")
		check(close(box.end.y,-.02), "Floor collider top remains aligned to finish")
	room.queue_free()
	await process_frame
	print(JSON.stringify({"test":"harbor_wall_outer_clearance","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func check_shell(spec: Vector4) -> void:
	var room := INTERIOR.new()
	room.width = spec.x
	room.depth = spec.y
	room.floor_index = int(spec.w)
	room.definition = {"id":"wall_clearance_fixture","entrance_local":Vector3(spec.z,0,0)}
	# Detached _shell construction isolates the changed geometry from dressing.
	room._shell()
	var walls := {}
	for node in room.get_children():
		if node is MeshInstance3D and node.has_meta("interior_solid_id"):
			walls[str(node.get_meta("interior_solid_id"))] = bounds(node)
	var prefix := str(spec)+": "
	check(walls.size()==5, prefix+"all five solid walls remain")
	var back: AABB = walls.BackWall
	check(close(back.position.z,-spec.y*.5+.02) and close(back.end.z,-spec.y*.5+.24), prefix+"back outer face recessed, inner face unchanged")
	check(close(back.position.x,-spec.x*.5+.02) and close(back.end.x,spec.x*.5-.02), prefix+"back end caps recessed")
	check(close(back.position.y,0) and close(back.end.y,2.7), prefix+"back height unchanged")
	for side in [-1,1]:
		var wall: AABB = walls["SideWall%d"%side]
		var front: AABB = walls["FrontWall%d"%side]
		check(close(wall.position.x, -spec.x*.5+.02 if side<0 else spec.x*.5-.24) and close(wall.end.x, -spec.x*.5+.24 if side<0 else spec.x*.5-.02), prefix+"side %d inner face preserved and outer recessed"%side)
		check(close(wall.position.z,-spec.y*.5+.02) and close(wall.end.z,spec.y*.5-.02), prefix+"side %d end caps recessed"%side)
		check(close(wall.position.y,0) and close(wall.end.y,1.1), prefix+"side height unchanged")
		check(close(front.position.z,spec.y*.5-.24) and close(front.end.z,spec.y*.5-.02), prefix+"front inner face preserved and outer recessed")
		check(close(front.position.y,0) and close(front.end.y,1.04), prefix+"front height unchanged")
		var doorway_edge := spec.z+float(side)*1.2 if int(spec.w)==0 else 0.0
		check(close(front.end.x if side<0 else front.position.x,doorway_edge), prefix+"door jamb/upper seam unchanged")
		check(close(front.position.x if side<0 else front.end.x,float(side)*(spec.x*.5-.02)), prefix+"front outer end cap recessed")
		check(back.intersects(wall) and front.intersects(wall), prefix+"corners retain overlapping wall volumes")
	var floor_box := bounds(room.get_child(0) as MeshInstance3D)
	check(close(floor_box.position.x,-spec.x*.5+.02) and close(floor_box.end.x,spec.x*.5-.02) and close(floor_box.position.z,-spec.y*.5+.02) and close(floor_box.end.z,spec.y*.5-.02), prefix+"floor visual edges tucked under walls")
	check(close(floor_box.position.y,-.07) and close(floor_box.end.y,-.02), prefix+"floor finish elevation/thickness unchanged")
	room.free()
