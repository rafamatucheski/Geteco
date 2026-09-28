extends SceneTree
## Native room collision plus rendered depth with real player/NPC rigs.
## --geometry-only allows the physical subset headless; it never certifies depth.
const ROOM := preload("res://gameplay/urban_v1/VerticeUndercroft.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const OUTPUT := "res://evidence/port-logistics-20260928/undercroft-depth"
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var records: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("UNDERCROFT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for _i in count: await physics_frame
func sweep(actor: CharacterBody3D,start: Vector3,motion: Vector3) -> bool:
	return actor.test_move(Transform3D(Basis.IDENTITY,start),motion)

func run() -> void:
	var geometry_only := "--geometry-only" in OS.get_cmdline_user_args()
	if not geometry_only and DisplayServer.get_name()=="headless":
		push_error("Rendered depth needs GPU; use --geometry-only for the physical subset")
		quit(2)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(640,480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var room := ROOM.new()
	scene.add_child(room)
	await frames(3)
	check(room.solids.size()==12,"Complete inventory: four walls, seven furniture/ladder groups and a workbench")
	check(room.floor_body.has_meta("interior_floor") and room.floor_body not in room.solids,"Physical floor is separated from obstacles")
	for body in room.solids:
		check(body.has_meta("interior_solid_id") and body.get_meta("bounds") is AABB,"Identified physical volume "+body.name)
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		actor.position = Vector3(20,.04,20)
		scene.add_child(actor)
		actor.set_physics_process(false)
		await frames(2)
		var who := "player" if is_player else "npc"
		for spec in [
			[Vector3(0,.04,0),Vector3(-20,0,0),"west wall"],
			[Vector3(0,.04,3.9),Vector3(20,0,0),"east wall"],
			[Vector3(0,.04,0),Vector3(0,0,-20),"back wall"],
			[Vector3(2,.04,0),Vector3(0,0,20),"front wall despite cutaway"],
			[Vector3(-3,.04,-2.2),Vector3(-4,0,0),"workbench including space under top"],
			[Vector3(3.5,.04,-2.7),Vector3(0,0,-4),"armory cabinet"],
			[Vector3(3,.04,-2.6),Vector3(4,0,0),"ammo cases"],
			[Vector3(3,.04,1.9),Vector3(4,0,0),"cot"],
			[Vector3(3,.04,-.35),Vector3(4,0,0),"radio table"],
			[Vector3(-2,.04,3.3),Vector3(-4,0,0),"travel case"],
			[Vector3(-2,.04,1.07),Vector3(-4,0,0),"supply crates"],
			[Vector3(0,.04,3),Vector3(0,0,2),"exit ladder"],
			[Vector3(-3,.04,0),Vector3(-5,0,-5),"workbench corner with large displacement"]]:
			check(sweep(actor,spec[0],spec[1]),who+" blocked by "+spec[2])
		for spec in [
			[Vector3(0,.04,3),Vector3(0,0,-6),"spawn to weapon"],
			[Vector3(0,.04,3),Vector3(0,0,1),"spawn to exit"],
			[Vector3(0,.04,1),Vector3(3,0,0),"central aisle to cash"],
			[Vector3(0,.04,-2.2),Vector3(-3.9,0,0),"workbench approach"],
			[Vector3(0,.04,-3.3),Vector3(3.5,0,0),"armory approach"]]:
			check(not sweep(actor,spec[0],spec[1]),who+" clear "+spec[2])
		actor.position = Vector3(-3,.04,-2.2)
		var impact := actor.move_and_collide(Vector3(-8,0,0))
		check(impact!=null and actor.position.x>-4.1 and is_equal_approx(actor.position.y,.04),who+" actual movement stops at table without walking on it")
		actor.position = Vector3(20,.04,20)
		var capsule: CollisionShape3D
		for child in actor.get_children():
			if child is CollisionShape3D: capsule=child; break
		for point in [ROOM.SPAWN_POINT,ROOM.EXIT_POINT,ROOM.WEAPON_POINT,ROOM.CASH_POINT]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule.shape
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.04+capsule.position)
			query.collision_mask = 1
			query.exclude = [actor.get_rid()]
			check(scene.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),who+" full capsule fits functional point "+str(point))
		actor.free()
	room.set_active(false)
	check(not room.visible and room.floor_body.collision_layer==0 and room.solids.all(func(body): return body.collision_layer==0) and room.lights.all(func(light): return not light.visible),"Inactive room suspends rendering, lights and collision")
	room.set_active(true)
	check(room.visible and room.floor_body.collision_layer==1 and room.solids.all(func(body): return body.collision_layer==1),"Room reactivation restores floor and solids")
	if not geometry_only: await depth(scene,room)
	print("UNDERCROFT_RESULT checks=",checks," failures=",failures," depth_executed=",not geometry_only)
	scene.free()
	viewport.free()
	# Allow render resources and procedural texture jobs to retire before quit.
	for _i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func capture() -> Image:
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func mask_count(image: Image) -> int:
	var result := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r>.55 and color.b>.55 and color.g<.2: result+=1
	return result
func mask_meshes(node: Node,material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override=material
		node.material_overlay=null
	for child in node.get_children(): mask_meshes(child,material)

func depth(scene: Node3D,room: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("161f21")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b4bfba")
	settings.ambient_light_energy=.45
	environment.environment=settings
	scene.add_child(environment)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=13
	camera.position=Vector3(0,18,15)
	camera.far=70
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	var overview := await capture()
	check(overview.save_png(OUTPUT+"/room-natural.png")==OK,"Natural room overview saved")
	var mask := StandardMaterial3D.new()
	mask.albedo_color=Color(1,0,1)
	mask.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var setups := [
		# Front corner leaves the supply crates out of this object's sightline.
		{"id":"workbench","camera":Vector3(-3.2,3.6,2.5),"target":Vector3(-5.02,1,-2.2),"front":Vector3(-4.15,.04,.15),"behind":Vector3(-5.02,.04,-4.25),"side":Vector3(-3.8,.04,-2.2)},
		{"id":"cabinet","camera":Vector3(-3,2.4,-4.32),"target":Vector3(3.5,1,-4.32),"front":Vector3(1.7,.04,-4.32),"behind":Vector3(5.2,.04,-4.32),"side":Vector3(3.5,.04,-2.8)}]
	camera.size=5.8
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player=is_player
		actor.controlled_automatically=true
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		var who := "player" if is_player else "npc"
		actor.position=setups[0].front
		camera.position=setups[0].camera
		camera.look_at(setups[0].target)
		var natural := await capture()
		check(natural.save_png(OUTPUT+"/"+who+"-natural.png")==OK,who+" natural scale evidence saved")
		mask_meshes(actor.visual,mask)
		for setup in setups:
			camera.position=setup.camera
			camera.look_at(setup.target)
			for pose in ["front","behind","side"]:
				actor.position=setup[pose]
				room.show()
				var picture := await capture()
				var visible_pixels := mask_count(picture)
				var id: String = who+"-"+setup.id+"-"+pose
				check(picture.save_png(OUTPUT+"/"+id+".png")==OK,id+" evidence saved")
				room.hide()
				var control := await capture()
				var control_pixels := mask_count(control)
				check(control.save_png(OUTPUT+"/"+id+"-control.png")==OK,id+" control saved")
				check(control_pixels>150,id+" positive control contains visible actor")
				var ratio := float(visible_pixels)/maxf(1,float(control_pixels))
				if pose!="behind": check(ratio>.9,id+" actor is visible in front or beside furniture: "+str(ratio))
				elif setup.id=="cabinet": check(ratio<.2,id+" cabinet occludes actor: "+str(ratio))
				else: check(ratio>.05 and ratio<.9,id+" workbench occludes lower body: "+str(ratio))
				records.append({"actor":who,"prop":setup.id,"pose":pose,"visible_pixels":visible_pixels,"control_pixels":control_pixels,"ratio":ratio})
				room.show()
		actor.free()
	var report := FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE)
	check(report!=null,"Depth evidence report can be saved")
	if report: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"))
