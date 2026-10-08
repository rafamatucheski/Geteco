extends SceneTree
const SITE := preload("res://world/places/amusement_park/ParkLume.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const CLOWN := preload("res://activities/amusement_park/ParkClown.gd")
var checks := 0
var failures: Array[String] = []
var support_failures: Array = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("PARK_GROUND ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for index in polygon.size(): result += polygon[index].cross(polygon[(index+1)%polygon.size()])
	return absf(result)*.5

func inspect(park: Node3D) -> Dictionary:
	var planar_area := 0.0
	var samples := 0
	var fingerprint := 0
	var kinds: Array[String] = []
	for node in park.get_children():
		if not node is MeshInstance3D or not str(node.name).begins_with("ParkGround_"): continue
		kinds.append(node.name)
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		fingerprint = hash([fingerprint,vertices])
		for index in range(0,vertices.size(),3):
			var a: Vector3 = vertices[index]
			var b: Vector3 = vertices[index+1]
			var c: Vector3 = vertices[index+2]
			if node.name!="ParkGround_verge": planar_area += absf((b-a).cross(c-a).y)*.5
			var point: Vector3 = node.to_global((a+b+c)/3)
			var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.10,point-Vector3.UP*.10,1)
			var hit: Dictionary = park.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or absf(hit.position.y-point.y)>.003:
				support_failures.append({"kind":str(node.name),"point":str(point),"hit":str(hit.get("position",Vector3.INF))})
			samples += 1
	return {"area":planar_area,"samples":samples,"hash":fingerprint,"kinds":kinds}

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var park := SITE.new()
	stage.add_child(park)
	var player := ACTOR.new()
	player.is_player = true
	stage.add_child(player)
	player.set_physics_process(false)
	var clown := CLOWN.new()
	clown.configure({"id":"ground_fixture_clown","position":LAYOUT.ORIGIN+Vector3(0,.08,15),"worker_index":0})
	stage.add_child(clown)
	clown.set_physics_process(false)
	for frame in 4: await physics_frame
	var first := inspect(park)
	check(first.kinds.size()==5,"five static finishes replace complete authored ground")
	check(absf(first.area-area(LAYOUT.outline())-11*5.8)<.02,"composed horizontal finishes have no duplicated or missing area "+str(first.area))
	check(first.samples>250 and support_failures.is_empty(),"visible floor and sloped verge agree with real support at every triangle centroid "+str(first.samples))
	var clear_paths := [
		[Vector3(48,.08,16),Vector3(-3.5,.08,16)],
		[Vector3(20,.08,15),Vector3(20,.08,-2.2)],
		[Vector3(29,.08,15),Vector3(29,.08,20)],
		[Vector3(35,.08,34),Vector3(38,.08,34)],
		[Vector3(44,.08,12.45),Vector3(44,.08,14.0)],
		[Vector3(0,.08,-34),Vector3(0,.08,-28)]]
	for actor: CharacterBody3D in [player,clown]:
		actor.collision_mask = 1
		for segment in clear_paths:
			var pose := Transform3D(Basis.IDENTITY,park.to_global(segment[0]))
			check(not actor.test_move(pose,segment[1]-segment[0]),("Dante" if actor==player else "native clown")+" swept circulation "+str(segment[1]))
	var first_hash: int = first.hash
	park.free()
	await physics_frame
	park = SITE.new()
	stage.add_child(park)
	for frame in 3: await physics_frame
	var second := inspect(park)
	check(first_hash==second.hash and support_failures.is_empty(),"reentry reconstructs identical finish and physical support")
	stage.free()
	await process_frame
	print("PARK_GROUND_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"support_failures":support_failures,"first":first}))
	quit(0 if failures.is_empty() else 1)
