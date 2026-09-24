extends SceneTree
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
var camera: Camera3D
var actor: CharacterBody3D
var reports: Array = []
func _initialize() -> void: call_deferred("run")
func capture(path: String) -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if not path.is_empty(): picture.save_png(path)
	return picture
func pixels(a: Image,b: Image) -> int:
	var feet := camera.unproject_position(actor.position)
	var head := camera.unproject_position(actor.position+Vector3.UP*1.9)
	var count := 0
	for y in range(maxi(0,int(head.y)-8),mini(a.get_height(),int(feet.y)+8)):
		for x in range(maxi(0,int(feet.x)-30),mini(a.get_width(),int(feet.x)+30)):
			var ac := a.get_pixel(x,y)
			var bc := b.get_pixel(x,y)
			if absf(ac.r-bc.r)+absf(ac.g-bc.g)+absf(ac.b-bc.b)>.08: count+=1
	return count
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute("res://evidence/interiors")
	var fixture := Node3D.new()
	root.add_child(fixture)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("829da6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c4d4de")
	env.environment.ambient_light_energy = .65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	fixture.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	fixture.add_child(sun)
	actor = preload("res://scripts/Actor.gd").new()
	actor.is_player = true
	fixture.add_child(actor)
	actor._physics_process(.016)
	actor.set_physics_process(false)
	camera = preload("res://scripts/CameraRig.gd").new()
	fixture.add_child(camera)
	camera.set_process(false)
	actor.camera = camera
	var populated := "--populated" in OS.get_cmdline_user_args()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	for definition in CATALOG.definitions():
		if not only.is_empty() and not definition.id in only.split(","): continue
		var room = CATALOG.create_place(definition.id)
		fixture.add_child(room)
		if populated:
			for npc in definition.get("npcs",[]):
				var resident = preload("res://world/places/OriginalResidents.gd").create_model(npc)
				room.add_child(resident)
				resident.position = npc.local_position
			for stock in definition.get("vehicles",[]):
				var vehicle = load(stock.model).instantiate()
				room.add_child(vehicle)
				vehicle.position = stock.local_position
				vehicle.rotation.y = stock.yaw
		camera.size = room.camera_size
		camera.position = room.camera_target+Vector3(0,18,15)
		camera.look_at(room.camera_target)
		actor.position = room.spawn_position+Vector3.UP*.04
		actor.reset_physics_interpolation()
		var prefix: String = "res://evidence/interiors/"+definition.id
		if populated:
			await capture(prefix+"-populated.png")
			print("POPULATED_CAPTURE ",prefix+"-populated.png")
			room.free()
			continue
		await capture(prefix+"-entry.png")
		var candidates: Array = []
		for i in room.solid_bounds.size():
			var bounds: AABB = room.solid_bounds[i]
			if bounds.size.x > 5 or bounds.size.z > 4 or bounds.size.x < .5 or bounds.size.z < .35 or bounds.size.y > 2.3: continue
			var point := Vector3(bounds.get_center().x,.04,bounds.position.z-.44)
			if not room.is_floor_clear(point,.32): continue
			if absf(point.x)>definition.size.x*.5-.5 or absf(point.z)>definition.size.y*.5-.5: continue
			candidates.append({"position":point,"solid":str(room.solid_bodies[i].name),"distance":Vector2(point.x,point.z).length()})
		candidates.sort_custom(func(a,b): return a.distance < b.distance)
		var directed := {"lumberjack_shelter":Vector3(-3.75,.04,1.96),"cemetery_keeper":Vector3(-3.75,.04,-1.31),"harbor_sewer":Vector3(7.4,.04,-3.99)}
		if directed.has(definition.id): candidates.push_front({"position":directed[definition.id],"solid":"OriginalStoveOrPump","distance":0})
		var report := {"id":definition.id,"entry":ProjectSettings.globalize_path(prefix+"-entry.png"),"candidate_count":candidates.size(),"camera_size":camera.size}
		if not candidates.is_empty():
			actor.position = room.to_global(candidates[0].position)
			actor.reset_physics_interpolation()
			var physical := actor.move_and_collide(Vector3.UP*.001,true)
			report["physical_clear"] = physical == null
			report["solid"] = candidates[0].solid
			report["position"] = actor.position
			actor.visual.show()
			var shown := await capture(prefix+"-behind.png")
			actor.visual.hide()
			var absent := await capture("")
			var visible_count := pixels(shown,absent)
			room.hide()
			actor.visual.show()
			var isolated := await capture("")
			actor.visual.hide()
			var background := await capture("")
			var isolated_count := pixels(isolated,background)
			visible_count = 0
			isolated_count = 0
			var feet := camera.unproject_position(actor.position)
			var head := camera.unproject_position(actor.position+Vector3.UP*1.9)
			for y in range(maxi(0,int(head.y)-8),mini(shown.get_height(),int(feet.y)+8)):
				for x in range(maxi(0,int(feet.x)-30),mini(shown.get_width(),int(feet.x)+30)):
					var a := isolated.get_pixel(x,y)
					var b := background.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)<.08: continue
					isolated_count+=1
					a = shown.get_pixel(x,y)
					b = absent.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.08: visible_count+=1
			report["visible_pixels"] = visible_count
			report["isolated_pixels"] = isolated_count
			report["visible_ratio"] = float(visible_count)/maxi(1,isolated_count)
			report["behind"] = ProjectSettings.globalize_path(prefix+"-behind.png")
			actor.visual.show()
		else: report["depth_pending"] = "No furniture candidate with a physically clear rear point"
		reports.append(report)
		print("VISUAL_ROOM ",JSON.stringify(report))
		room.free()
		await physics_frame
	if populated:
		quit(0)
		return
	if not only.is_empty():
		var old: Array = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/interiors/report.json"))
		for previous in old:
			if not previous.id in only.split(","): reports.append(previous)
	var file := FileAccess.open("res://evidence/interiors/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"  "))
	fixture.free()
	quit()


