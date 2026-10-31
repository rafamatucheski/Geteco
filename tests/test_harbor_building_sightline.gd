extends SceneTree
## Checagens finitas de geometria/ciclo de vida com renderizador real (o servidor dummy
## headless não guarda transformações de MultiMesh). As capturas do Main estabelecem
## à parte o resultado visual no bairro real.
const SIGHTLINE = preload("res://world/places/harbor_buildings/HarborBuildingSightline.gd")
class ChunkOwner:
	extends Node3D
	var chunks := {}
var checks := 0
var failures: Array[String] = []
var scene: Node3D
var railway: Node3D
var sightline: Node3D
var definition := {"id":"Fixture","source_id":"Fixture","floor_count":3,"storey_height":3.0,"size":Vector2(10,10),"exterior_position":Vector3.ZERO,"exterior_rotation":0.0}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("BUILDING_SIGHTLINE ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)

func batch_at(point: Vector3) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(30,1,3)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 3
	multi.set_instance_transform(0,Transform3D(Basis.IDENTITY,point))
	multi.set_instance_transform(1,Transform3D(Basis.IDENTITY,point+Vector3.RIGHT*80))
	multi.set_instance_transform(2,Transform3D(Basis.IDENTITY,point+Vector3(0,0,-8.8)))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multi
	railway.add_child(batch)
	return batch

func visible_hit(from: Vector3, to: Vector3) -> bool:
	for node: Node in railway.find_children("*","MultiMeshInstance3D",true,false):
		if not node.is_visible_in_tree() or node.is_queued_for_deletion(): continue
		var multi: MultiMesh = node.multimesh
		if multi==null or multi.mesh==null: continue
		var faces: PackedVector3Array = multi.mesh.get_faces()
		for index: int in multi.instance_count:
			var transform: Transform3D = node.global_transform*multi.get_instance_transform(index)
			if absf(transform.basis.determinant())<.000001: continue
			for face: int in range(0,faces.size(),3):
				if Geometry3D.segment_intersects_triangle(from,to,transform*faces[face],transform*faces[face+1],transform*faces[face+2])!=null: return true
	return false

func physical_hit(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from,to,1)
	return not scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func street_tree(chunk: Node3D, point: Vector3) -> HarborProp3D:
	var tree := HarborProp3D.new()
	tree.configure({"kind":"tree","source_id":"Fixture","point":Vector2.ZERO,"style":1,"scale_factor":1.0,"color":"426451"})
	tree.position = point
	chunk.add_child(tree)
	return tree

func tree_snapshot(tree: HarborProp3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in tree.get_children():
		if node is MeshInstance3D: result.append({"node":node,"mesh":node.mesh,"visible":node.visible})
	return result

func tree_matches(snapshot: Array[Dictionary]) -> bool:
	for item: Dictionary in snapshot:
		if item.node.mesh!=item.mesh or item.node.visible!=item.visible: return false
	return true

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("BUILDING_SIGHTLINE requires a real renderer: headless MultiMesh transforms are unavailable")
		quit(2)
		return
	create_timer(30).timeout.connect(func(): push_error("BUILDING_SIGHTLINE timeout"); quit(3))
	scene = Node3D.new()
	root.add_child(scene)
	railway = Node3D.new()
	railway.add_to_group("railway_geometry")
	scene.add_child(railway)
	var batch := batch_at(Vector3(0,6,8))
	var original: MultiMesh = batch.multimesh
	var far_transform: Transform3D = original.get_instance_transform(1)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30,1,3)
	collider.shape = shape
	collider.position = Vector3(0,6,8)
	body.add_child(collider)
	railway.add_child(body)
	sightline = SIGHTLINE.new()
	scene.add_child(sightline)
	await physics_frame
	await physics_frame
	var target := Vector3(0,0,3)
	var from := target+Vector3(0,18,15)
	var outside_target := Vector3(10,0,3)
	var outside_from := outside_target+Vector3(0,18,15)
	var rear_head := Vector3(0,1.8,-4.4)
	var rear_from := rear_head+Vector3(0,18,15)
	print("BUILDING_SIGHTLINE_SOURCE ",original.get_aabb()," transform=",original.get_instance_transform(0)," faces=",original.mesh.get_faces().size()," batches=",railway.find_children("*","MultiMeshInstance3D",true,false).size())
	check(visible_hit(from,target),"control: railway actually covers the room before cut")
	check(visible_hit(rear_from,rear_head),"control: railway also covers a standing head at the rear wall")
	check(physical_hit(from,target),"control: railway solid intersects the same ray")
	sightline.configure(definition,0)
	check(sightline.debug_snapshot().batches==1,"only intersecting railway batch is adapted")
	check(not visible_hit(from,target),"room sightline passes through the removed visual portion")
	check(not visible_hit(rear_from,rear_head),"standing actors remain visible at the rear edge of the room")
	check(visible_hit(outside_from,outside_target),"railway outside room projection remains visible")
	check(physical_hit(from,target),"physical railway support remains intact after visual cut")
	check(original.get_instance_transform(1)==far_transform and batch.multimesh.get_instance_transform(1)==far_transform,"untouched distant instance and original resource are preserved")
	sightline.configure(definition,3,true)
	check(batch.multimesh==original and visible_hit(from,target),"rooftop restores original railway resource and sightline")
	check(not sightline.debug_snapshot().active,"rooftop releases sightline ownership")
	sightline.configure(definition,1)
	check(batch.multimesh!=original,"another inhabited floor reapplies local adaptation")
	sightline.clear()
	check(batch.multimesh==original and visible_hit(from,target),"exit/reset restore the exact original batch")
	check(physical_hit(from,target),"physical support survives multiple floor and exit cycles")
	sightline.configure(definition,0)
	var late := batch_at(Vector3(0,9,10.5))
	var late_original: MultiMesh = late.multimesh
	await process_frame
	await process_frame
	check(late.multimesh!=late_original,"new railway streaming batch receives the active floor cut")
	sightline.clear()
	check(late.multimesh==late_original,"exit restores batches that streamed during the visit")
	sightline.configure(definition,0)
	var interrupted := batch_at(Vector3(0,12,13))
	var interrupted_original: MultiMesh = interrupted.multimesh
	sightline.clear()
	await process_frame
	check(interrupted.multimesh==interrupted_original,"clear cancels queued streaming work from an old generation")
	var region := ChunkOwner.new()
	scene.add_child(region)
	var chunk := Node3D.new()
	region.add_child(chunk)
	region.chunks[Vector2i.ZERO] = chunk
	var facade := Node3D.new()
	chunk.add_child(facade)
	var access := preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").new()
	access.definition = definition
	access.facade = facade
	facade.add_child(access)
	access.add_to_group("harbor_building_facade")
	var tree := street_tree(chunk,Vector3(0,0,5))
	var outside_tree := street_tree(chunk,Vector3(50,0,5))
	var foliage_original := tree_snapshot(tree)
	var outside_original := tree_snapshot(outside_tree)
	var wood: MeshInstance3D = tree.get_node("TreeTrunk")
	var original_wood: Mesh = wood.mesh
	await physics_frame
	await physics_frame
	check(physical_hit(Vector3(0,4,5),Vector3(0,.3,5)),"control: real street-tree trunk is physically solid")
	sightline.configure(definition,0)
	check(not tree_matches(foliage_original) and sightline.debug_snapshot().canopies>0,"only projected street-tree crowns receive local visual cut")
	check(wood.mesh==original_wood and wood.visible and physical_hit(Vector3(0,4,5),Vector3(0,.3,5)),"tree wood and trunk collision remain unchanged")
	check(tree_matches(outside_original),"distant tree crown and trunk remain fully intact")
	var previous: Dictionary = sightline.debug_snapshot()
	var transient_batch := batch_at(Vector3(0,9,10.5))
	var transient_tree := street_tree(chunk,Vector3(1,0,5))
	transient_batch.free()
	transient_tree.free()
	await process_frame
	await process_frame
	check(sightline.debug_snapshot().batches==previous.batches and sightline.debug_snapshot().canopies==previous.canopies,"rapid railway/tree streaming deletion drops stale weak callbacks")
	sightline.clear()
	check(tree_matches(foliage_original),"exit restores every original canopy mesh and visibility")
	sightline.configure(definition,0)
	sightline.queue_free()
	await process_frame
	await process_frame
	check(batch.multimesh==original and late.multimesh==late_original,"owner deletion restores surviving railway batches")
	check(tree_matches(foliage_original),"owner deletion restores the original tree crowns")
	print("BUILDING_SIGHTLINE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
