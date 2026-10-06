extends SceneTree
## Physical/visual seams of the permanent bridge banks, without treating
## ordinary unloaded terrain neighbours as coast or filling the bridge void.
const REGION := preload("res://world/regions/NativeRegion.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const SHORE := preload("res://world/regions/MountainBridgeShore.gd")
var checks := 0
var failures: Array[String] = []
var terrain: RefCounted
var owners: Node3D
var chunks: Dictionary = {}
var edges: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))

func build(key: Vector2i) -> MeshInstance3D:
	var chunk := Node3D.new()
	chunk.name = "ShoreChunk_%s_%s" % [key.x,key.y]
	root.add_child(chunk)
	chunks[key] = chunk
	terrain.build_chunk(chunk,Rect2(Vector2(key)*64.0,Vector2.ONE*64.0),edges[key])
	return chunk.get_node("MountainBridgeShore") as MeshInstance3D

func run() -> void:
	owners = REGION.new()
	terrain = TERRAIN.new()
	# Same physical pass width and axis as the authored connection. The separate
	# bridge_approach_terrain test checks the production road catalogue/ownership.
	terrain.configure([{"id":"mountain_pass","points":PackedVector3Array([Vector3(448,0,-285),Vector3(650,0,-285)]),"width":8.75,"surface":"asphalt"}],[],[])
	var expected := {Vector2i(7,-6):Vector2.DOWN,Vector2i(8,-6):Vector2.DOWN,Vector2i(9,-5):Vector2.LEFT,Vector2i(7,-4):Vector2.UP,Vector2i(8,-4):Vector2.UP}
	for x in range(4,11):
		for z in range(-7,-2):
			var key := Vector2i(x,z)
			var found := SHORE.frontiers(key,REGION.MOUNTAIN_BRIDGE_VOID_CELLS,owners._mountain_owns_terrain)
			check(found.size()==(1 if expected.has(key) else 0),"only an owned permanent VOID frontier is closed: %s" % key)
			if not expected.has(key): continue
			check(found[0].outward==expected[key],"bank faces its explicit VOID neighbour: %s" % key)
			edges[key] = found
	var ordinary := Node3D.new()
	root.add_child(ordinary)
	terrain.build_chunk(ordinary,Rect2(640,-448,64,64))
	check(ordinary.find_children("MountainBridgeShore","MeshInstance3D",true,false).is_empty(),"default terrain build has no artificial streaming-edge bank")
	ordinary.free()
	for key in edges: build(key)
	await physics_frame
	await physics_frame
	var all_triangles := {}
	for key in edges:
		var mesh := chunks[key].get_node("MountainBridgeShore") as MeshInstance3D
		var faces := mesh.mesh.get_faces()
		check(mesh.get_child_count()==1 and mesh.get_child(0).get_child_count()==1,"one physical surface per bank chunk: %s" % key)
		check(mesh.material_override is StandardMaterial3D and mesh.material_override.uv1_world_triplanar,"rock uses world projection without vertical texture stretch: %s" % key)
		for index in range(0,faces.size(),3):
			var a := faces[index]
			var b := faces[index+1]
			var c := faces[index+2]
			check((b-a).cross(c-a).length_squared()>.00000001,"bank triangle has physical area: %s/%s" % [key,index])
			var signature := [str(a.snapped(Vector3.ONE*.0001)),str(b.snapped(Vector3.ONE*.0001)),str(c.snapped(Vector3.ONE*.0001))]
			signature.sort()
			var triangle_key := "|".join(signature)
			check(not all_triangles.has(triangle_key),"no duplicate physical/visual bank triangle: %s/%s" % [key,index])
			all_triangles[triangle_key] = true
		for edge in edges[key]:
			for step in 17:
				var point: Vector3 = SHORE.point_at(terrain,edge,float(step)*4.0,0.0)
				check(is_equal_approx(point.y,float(terrain.height_at(Vector2(point.x,point.z)))),"bank welds every original 4m grid vertex: %s/%s" % [key,step])
			for step in [1,7,14]:
				for ring in 3:
					var a: Vector3 = SHORE.point_at(terrain,edge,float(step)*4.0,SHORE.RINGS[ring])
					var b: Vector3 = SHORE.point_at(terrain,edge,float(step+1)*4.0,SHORE.RINGS[ring])
					var c: Vector3 = SHORE.point_at(terrain,edge,float(step+1)*4.0,SHORE.RINGS[ring+1])
					var center := (a+b+c)/3.0
					var normal := (b-a).cross(c-a).normalized()
					if normal.dot(Vector3(edge.outward.x,1,edge.outward.y))<0.0: normal = -normal
					var hit := ray(center+normal*.5,center-normal*.5)
					check(not hit.is_empty() and hit.position.distance_to(center)<.012 and str(hit.collider.name)=="MountainBridgeShoreSolid","visible rock and collision coincide: %s/%s/%s" % [key,step,ring])
				var toe: Vector3 = SHORE.point_at(terrain,edge,float(step)*4.0,1.0)
				check(toe.y<=-5.5,"bank reaches below the lowest bridge water: %s/%s" % [key,step])
	# Shared straight boundary at x=512; shared miters at both eastern corners.
	for pair in [[Vector2i(7,-6),64.0,Vector2i(8,-6),0.0],[Vector2i(7,-4),64.0,Vector2i(8,-4),0.0],[Vector2i(8,-6),64.0,Vector2i(9,-5),0.0],[Vector2i(8,-4),64.0,Vector2i(9,-5),64.0]]:
		for fraction in SHORE.RINGS:
			var first: Vector3 = SHORE.point_at(terrain,edges[pair[0]][0],pair[1],fraction)
			var second: Vector3 = SHORE.point_at(terrain,edges[pair[2]][0],pair[3],fraction)
			check(first.distance_to(second)<.0001,"neighbour banks share all seam/corner rings: %s/%s" % [pair,fraction])
			var a: Vector3 = SHORE._normal(terrain,edges[pair[0]][0],pair[1],fraction)
			var b: Vector3 = SHORE._normal(terrain,edges[pair[2]][0],pair[3],fraction)
			check(a.distance_to(b)<.001,"seam/corner shading normals agree: %s/%s" % [pair,fraction])
	# Keep the ocean span empty under the road; its original deck is independent.
	for x in [396.0,430.0,470.0,520.0,550.0]:
		for z in [-290.0,-285.0,-280.0]:
			check(ray(Vector3(x,2,z),Vector3(x,-8,z)).is_empty(),"shore never fills bridge water/deck corridor: %s/%s" % [x,z])
	var capsule := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .35
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = .91
	capsule.add_child(collision)
	capsule.collision_mask = 1
	root.add_child(capsule)
	await physics_frame
	capsule.position = Vector3(570,.015,-285)
	check(not capsule.test_move(capsule.transform,Vector3(12,0,0)),"bank closure cannot block entry across the east abutment")
	capsule.free()
	var key := Vector2i(7,-6)
	var before: PackedVector3Array = chunks[key].get_node("MountainBridgeShore").mesh.get_faces()
	var sample: Vector3 = SHORE.point_at(terrain,edges[key][0],32,.48)
	chunks[key].free()
	await physics_frame
	check(ray(sample+Vector3.UP*5,sample-Vector3.UP*5).is_empty(),"unloading removes the old shore collider")
	var rebuilt := build(key)
	await physics_frame
	check(before==rebuilt.mesh.get_faces(),"reloaded bank geometry is deterministic")
	check(not ray(sample+Vector3.UP*5,sample-Vector3.UP*5).is_empty(),"reload restores physical bank support")
	for chunk in chunks.values(): chunk.free()
	owners.free()
	print("MOUNTAIN_BRIDGE_SHORE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
