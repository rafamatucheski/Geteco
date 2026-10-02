extends SceneTree
## Physical agreement for both accessible terminal slabs and their walkup ramps.
const LIFT := preload("res://world/environmental_parity/MountainChairliftParity3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const DEPTH_OUTPUT := "D:/geteco/artifacts/mountain-review-1001/station-depth"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func floor_at(point: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*2,1))

func actor(player: bool) -> CharacterBody3D:
	var body := ACTOR.new()
	body.is_player = player
	body.controlled_automatically = true
	body.automatic_direction = Vector3.FORWARD
	body.speed = 2.0
	body.set_meta("region_id","mountain")
	return body

func terminal(station: Node3D) -> void:
	var label := str(station.name)
	for offset in [Vector3.ZERO,Vector3(2,0,1),Vector3(-2,0,-1)]:
		var hit := floor_at(station.global_position+offset)
		check(not hit.is_empty(),label+": raised platform has physical support")
		if not hit.is_empty():
			check(absf(float(hit.position.y)-.36)<.01 and hit.normal.y>.99,label+": visual slab and collision agree")
	for z in [3.2,3.9,4.6]:
		var hit := floor_at(station.global_position+Vector3(0,0,z))
		var expected: float = .36*(4.8-float(z))/1.8
		check(not hit.is_empty() and absf(float(hit.position.y)-expected)<.01,label+": ramp supports its rendered slope")
	for player in [true,false]:
		var who := "player" if player else "NPC"
		var person := actor(player)
		person.position = station.global_position+Vector3(0,.02,5.5)
		root.add_child(person)
		for frame in 150: await physics_frame
		person.set_physics_process(false)
		check(person.global_position.z < station.global_position.z+1.4,label+": "+who+" walks up ramp into terminal")
		check(absf(person.global_position.y-.36)<.03 and person.is_on_floor(),label+": "+who+" feet remain on raised platform")
		person.global_position = station.global_position+Vector3(1.5,.37,0)
		await physics_frame
		var collision := person.move_and_collide(Vector3(2.0,0,0),true)
		check(collision != null,label+": terminal post blocks swept "+who)
		person.free()

func run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(260,.2,260)
	shape.shape = box
	shape.position.y = -.1
	ground.add_child(shape)
	root.add_child(ground)
	var lift := LIFT.new()
	lift.set_animation_active(false)
	root.add_child(lift)
	await physics_frame
	await physics_frame
	for name in ["SummitLiftStation","BaseLiftStation"]:
		await terminal(lift.get_node(name))
	if "--render" in OS.get_cmdline_user_args():
		if DisplayServer.get_name()=="headless": check(false,"depth validation requires a real renderer")
		else: await depth_cases(lift)
	else: print("MOUNTAIN_LIFT_STATIONS rendered depth NOT_EXECUTED")
	lift.free()
	ground.free()
	for failure in failures: push_error(failure)
	print("MOUNTAIN_LIFT_STATIONS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func green_pixels(label: String) -> int:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := root.get_texture().get_image()
	snapshot.save_png(DEPTH_OUTPUT.path_join(label+".png"))
	var pixels := 0
	for y in snapshot.get_height():
		for x in snapshot.get_width():
			var color := snapshot.get_pixel(x,y)
			if color.g>.85 and color.r<.1 and color.b<.1: pixels += 1
	return pixels

func depth_cases(lift: Node3D) -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(DEPTH_OUTPUT)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("6b7f86")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 1.0
	environment.environment = settings
	root.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA.WALK_SIZE_CLOSE
	root.add_child(camera)
	camera.make_current()
	var green := StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.albedo_color = Color(0,1,0)
	var records: Array[Dictionary] = []
	for name in ["SummitLiftStation","BaseLiftStation"]:
		var station: Node3D = lift.get_node(name)
		camera.global_position = station.global_position+CAMERA.EXTERIOR_OFFSET
		camera.look_at(station.global_position)
		for player in [true,false]:
			var who := "player" if player else "NPC"
			var label := str(name)+"-"+who
			var person := actor(player)
			root.add_child(person)
			person.set_physics_process(false)
			for node in person.find_children("*","Node3D",true,false): node.set_process(false)
			for mesh in person.find_children("*","MeshInstance3D",true,false): mesh.material_override = green
			# Match the real orthographic gameplay angle. The roof projects over
			# the ground behind the station, while the front platform stays visible.
			person.global_position = station.global_position+Vector3(0,.02,-6.0)
			lift.hide()
			var control: int = await green_pixels(label+"-behind-control")
			check(control>100,label+": positive visible control contains the real rig")
			lift.show()
			var behind: int = await green_pixels(label+"-behind-roof")
			check(behind<float(control)*.2,label+": shelter roof occludes actor behind it")
			var row := {"station":name,"actor":who,"control_pixels":control,"behind_pixels":behind}
			var positions := {"front":Vector3(0,.02,6),"side":Vector3(6,.02,0),"platform":Vector3(0,.37,0)}
			for pose in positions:
				person.global_position = station.global_position+positions[pose]
				var visible: int = await green_pixels(label+"-"+pose)
				check(visible>float(control)*.75,label+": actor remains visible "+pose)
				row[pose+"_pixels"] = visible
			records.append(row)
			person.free()
	var file := FileAccess.open(DEPTH_OUTPUT.path_join("report.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"camera_size":camera.size,"camera_offset":str(CAMERA.EXTERIOR_OFFSET),"records":records},"\t"))
	camera.free()
	environment.free()
