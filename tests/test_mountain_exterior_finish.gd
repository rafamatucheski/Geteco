extends SceneTree
## Native physical geometry and real actor rigs. --render also proves depth with a visible control.
const REGION := preload("res://world/editing/EditableRegion.gd")
const EXIT := preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
var checks := 0
var failures: Array[String] = []
var region: Node3D
var entrance: Node3D
var actors: Array[CharacterBody3D] = []
var folder := "D:/geteco/artifacts/mountain-review-1001/exterior-contract"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("MOUNTAIN_EXTERIOR ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func support(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP,1)
	return region.get_world_3d().direct_space_state.intersect_ray(ray)
func ready_region(point: Vector3) -> void:
	region.set_focus(point)
	for i in 600:
		await process_frame
		if region.pending.is_empty() and region.build_jobs.is_empty(): break
	await frames(3)
func actor_free(actor: CharacterBody3D,point: Vector3) -> bool:
	var collision: CollisionShape3D = actor.get_child(0) as CollisionShape3D
	if collision == null:
		for child in actor.get_children():
			if child is CollisionShape3D: collision = child; break
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(Basis.IDENTITY,point+collision.position)
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return region.get_world_3d().direct_space_state.intersect_shape(query).is_empty()
func run() -> void:
	region = REGION.build_region("mountain",EXIT.WORLD_POSITION)
	root.add_child(region)
	await ready_region(EXIT.WORLD_POSITION)
	entrance = EXIT.new()
	root.add_child(entrance)
	entrance.configure(null)
	entrance.activate_now()
	entrance.set_process(false)
	var player := ACTOR.new()
	player.is_player = true
	root.add_child(player)
	player.set_physics_process(false)
	actors.append(player)
	var resident := RESIDENT.new()
	resident.configure({"id":"mountain_exterior_test_npc","stationary":true})
	root.add_child(resident)
	resident.set_physics_process(false)
	actors.append(resident)
	await frames(3)
	check(EXIT.WORLD_POSITION.distance_to(Vector3(731.25,0,-480.94))>30,"secret exit separated from resort by more than 30 m")
	for mesh in entrance.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("interior_solid_id","") != "":
			check(not mesh.find_children("*","StaticBody3D",true,false).is_empty(),"solid mesh carries its own collider")
	for actor in actors:
		var label := "player" if actor == player else "NPC"
		for other in actors:
			if other != actor: other.global_position = EXIT.WORLD_POSITION+Vector3(20,.04,10)
		actor.global_position = entrance.arrival_global()
		check(actor_free(actor,actor.global_position),label+" whole body fits arrival")
		check(actor_free(actor,entrance.interaction_global()),label+" whole body fits interaction")
		entrance.set_open(false,false)
		await frames(2)
		actor.global_position = entrance.interaction_global()
		var hit := actor.move_and_collide(Vector3(0,0,-6))
		check(hit != null and actor.global_position.z>entrance.global_position.z+.45,label+" closed slab blocks swept motion")
		entrance.set_open(true,false)
		await frames(2)
		actor.global_position = entrance.interaction_global()
		hit = actor.move_and_collide(Vector3(0,0,-2.9))
		check(hit == null and actor.global_position.z<entrance.global_position.z-.85,label+" opened slab leaves accessible throat")
		hit = actor.move_and_collide(Vector3(0,0,4.3))
		check(hit == null,label+" can leave the opened passage")
		actor.global_position = entrance.to_global(Vector3(-1.82,.04,1.9))
		hit = actor.move_and_collide(Vector3(0,0,-5))
		check(hit != null and actor.global_position.z>entrance.global_position.z-.15,label+" natural side rock blocks large swept step")
		actor.global_position = entrance.to_global(Vector3(-5,.04,-1.4))
		hit = actor.move_and_collide(Vector3(5,0,0))
		check(hit != null,label+" small outer rock remains physical")
		actor.global_position = entrance.arrival_global()
	var ground := support(entrance.arrival_global())
	check(not ground.is_empty() and absf(ground.position.y)<.1,"secret arrival has terrain support")
	for actor in actors: actor.global_position = EXIT.WORLD_POSITION+Vector3(20,.04,10)
	var pad_point := Vector3(655,0,-487)
	await ready_region(pad_point)
	var pads := region.find_children("MountainHelipad","Node3D",true,false)
	check(pads.size()==1,"one helipad instantiated at revised site")
	if not pads.is_empty():
		check(pads[0].global_position.distance_to(pad_point)<.01,"helipad model matches reserved world position")
		check(pads[0].find_children("Rail","MeshInstance3D",true,false).is_empty(),"landing disc has no raised perimeter barriers")
		for delta in [Vector3.ZERO,Vector3(2.5,0,0),Vector3(-2.5,0,0),Vector3(0,0,2.5),Vector3(0,0,-2.5)]:
			var contact := support(pad_point+delta)
			check(not contact.is_empty() and absf(contact.position.y)<.04,"pad physical contact agrees with thin deck")
		for actor in actors:
			actor.global_position = pad_point+Vector3(0,.05,3.8)
			var hit := actor.move_and_collide(Vector3(0,0,-6.0))
			check(hit == null,"actor crosses helipad through its clear path opening")
	var paths: Array = region.walkways.filter(func(path): return path.id == "helipad_walk")
	check(paths.size()==1,"saved map retains connected helipad path")
	if not paths.is_empty():
		check(paths[0].points[-1].distance_to(pad_point+Vector3(0,0,3.1))<.1,"path reaches new landing perimeter")
		check(paths[0].width<2.0,"pedestrian access retains its useful width")
	if "--render" in OS.get_cmdline_user_args():
		if DisplayServer.get_name()=="headless": check(false,"render requested with a real renderer")
		else: await depth_cases()
	else: print("MOUNTAIN_EXTERIOR rendered depth NOT_EXECUTED")
	print("MOUNTAIN_EXTERIOR checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures: push_error(failure)
	for actor in actors: actor.free()
	entrance.free()
	region.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func green_count(label: String) -> int:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(label+".png"))
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.g>.85 and color.r<.1 and color.b<.1: total += 1
	return total

func depth_cases() -> void:
	await ready_region(EXIT.WORLD_POSITION)
	root.size = Vector2i(960,640)
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	camera.global_position = EXIT.WORLD_POSITION+Vector3(0,7,15)
	camera.look_at(EXIT.WORLD_POSITION+Vector3(0,1,0))
	camera.make_current()
	var green := StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color = Color(0,1,0)
	for actor in actors:
		for mesh in actor.find_children("*","MeshInstance3D",true,false): mesh.material_override = green
		actor.visible = false
	entrance.set_open(false,false)
	for index in actors.size():
		var actor := actors[index]
		actor.visible = true
		actor.global_position = entrance.to_global(Vector3(0,.04,-.7))
		entrance.visible = false
		var control: int = await green_count("actor%d-behind-control"%index)
		check(control>100,"actor %d positive visible control"%index)
		entrance.visible = true
		var behind: int = await green_count("actor%d-behind"%index)
		check(behind<float(control)*.2,"actor %d occluded behind closed stone slab"%index)
		actor.global_position = entrance.arrival_global()
		var front: int = await green_count("actor%d-front"%index)
		check(front>float(control)*.75,"actor %d visible in front of formation"%index)
		actor.global_position = entrance.to_global(Vector3(-4.5,.04,0))
		var side: int = await green_count("actor%d-side"%index)
		check(side>float(control)*.75,"actor %d visible beside formation"%index)
		actor.visible = false
	camera.free()
