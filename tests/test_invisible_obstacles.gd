extends SceneTree
## Regressões de física real para props removidos, chunks em streaming e rochas do motocross.
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("INVISIBLE_OBSTACLE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var chunk := Node3D.new()
	root.add_child(chunk)
	var prop := MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	chunk.add_child(prop)
	FRAGILE.register_node("desert_rock",prop,chunk)
	check(FRAGILE.query(Vector3.ZERO,1).size()==1,"visible prop remains hittable")
	prop.hide()
	check(FRAGILE.query(Vector3.ZERO,1).is_empty(),"hidden prop causes no synthetic impact")
	prop.show()
	check(FRAGILE.query(Vector3.ZERO,1).size()==1,"showing prop restores impact registration")
	prop.free()
	check(FRAGILE.query(Vector3.ZERO,1).is_empty(),"deleted prop leaves no phantom impact")
	FRAGILE.cells.clear()
	var next := MeshInstance3D.new()
	next.mesh = BoxMesh.new()
	chunk.add_child(next)
	FRAGILE.register_node("desert_rock",next,chunk)
	chunk.hide()
	check(FRAGILE.query(Vector3.ZERO,1).is_empty(),"hidden chunk has no synthetic impacts")
	chunk.show()
	var body := StaticBody3D.new()
	body.collision_layer=1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(2,2,2)
	collision.shape=box
	body.add_child(collision)
	chunk.add_child(body)
	for i in 3: await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(-3,0,0),Vector3(3,0,0),1)
	check(not chunk.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"live solid blocks movement")
	var owner := REGION.new()
	owner._retire_chunk(chunk)
	for i in 3: await physics_frame
	check(chunk.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"retirement removes collision before incremental disposal")
	check(FRAGILE.query(Vector3.ZERO,1).is_empty(),"retirement removes synthetic impacts")
	owner.free()
	if is_instance_valid(chunk): chunk.free()
	FRAGILE.cells.clear()
	# Varre toda categoria de prop compartilhada, incluindo os caminhos por nó e em lote.
	for kind in FRAGILE.KINDS:
		var holder := Node3D.new()
		root.add_child(holder)
		var object := MeshInstance3D.new()
		object.mesh=BoxMesh.new()
		holder.add_child(object)
		FRAGILE.register_node(kind,object,holder)
		check(FRAGILE.query(Vector3.ZERO,1).size()==1,kind+": visible node hittable")
		holder.remove_child(object)
		check(FRAGILE.query(Vector3.ZERO,1).is_empty(),kind+": cached detached node has no impact")
		holder.add_child(object)
		check(FRAGILE.query(Vector3.ZERO,1).size()==1,kind+": cached node resumes on return")
		object.free()
		check(FRAGILE.query(Vector3.ZERO,1).is_empty(),kind+": removed node leaves no impact")
		var visual := MultiMeshInstance3D.new()
		var batch := MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=BoxMesh.new()
		batch.instance_count=1
		batch.set_instance_transform(0,Transform3D.IDENTITY)
		visual.multimesh=batch
		holder.add_child(visual)
		FRAGILE.register_instance(kind,batch,0,holder,[],[],visual)
		check(FRAGILE.query(Vector3.ZERO,1).size()==1,kind+": visible batch hittable")
		visual.hide()
		check(FRAGILE.query(Vector3.ZERO,1).is_empty(),kind+": hidden batch has no impact")
		visual.show()
		batch.visible_instance_count=0
		check(FRAGILE.query(Vector3.ZERO,1).is_empty(),kind+": hidden instance has no impact")
		batch.visible_instance_count=-1
		check(FRAGILE.query(Vector3.ZERO,1).size()==1,kind+": restored batch hittable")
		visual.free()
		check(FRAGILE.query(Vector3.ZERO,1).is_empty(),kind+": removed batch leaves no impact")
		holder.free()
	FRAGILE.cells.clear()
	var course := COURSE.new()
	root.add_child(course)
	course.finish_build()
	for i in 3: await physics_frame
	# As rochas visíveis da pedreira são elipsoides achatados: um colisor esférico fica
	# acima do topo e além dos lados delas. Toda rocha precisa usar o próprio casco de malha.
	var rock_shapes := 0
	var oversized := 0
	for shape in course.find_children("*","CollisionShape3D",true,false):
		if shape.shape is SphereShape3D: oversized += 1
		if shape.shape is ConvexPolygonShape3D: rock_shapes += 1
	check(oversized==0 and rock_shapes>20,"all quarry rock colliders follow flattened mesh instead of oversized spheres")
	var rocks: MultiMeshInstance3D = course.get_node("QuarryRocks")
	var solids: StaticBody3D = course.get_node("QuarryRockSolids")
	var poses: Array = rocks.get_meta("preview_instance_transforms")
	var air_clear := 0
	var supported := 0
	for pose: Transform3D in poses:
		var top := -INF
		for vertex in rocks.multimesh.mesh.get_faces(): top=maxf(top,(pose*vertex).y)
		var at := Vector3(pose.origin.x,top,pose.origin.z)
		var empty_ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.025,at+Vector3.UP*.005,1)
		var hit: Dictionary = course.get_world_3d().direct_space_state.intersect_ray(empty_ray)
		if hit.is_empty() or hit.collider!=solids: air_clear+=1
		var support_ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.025,at-Vector3.UP*.025,1)
		hit=course.get_world_3d().direct_space_state.intersect_ray(support_ray)
		if not hit.is_empty() and hit.collider==solids and absf(hit.position.y-top)<.002: supported+=1
	check(air_clear==poses.size(),"air above every visible rock is free of rock collisions")
	check(supported==poses.size(),"every visible rock top has physical support at its exact height")
	course.free()
	print("INVISIBLE_OBSTACLE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
