extends SceneTree
const IDS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife", "bat", "axe", "knuckles"]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="): label = arg.trim_prefix("label=")
	var view := SubViewport.new()
	view.size = Vector2i(480,300)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("26313d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bac8db")
	env.environment.ambient_light_energy = 0.65
	view.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 1.6
	view.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25,140,0)
	fill.light_energy = 0.8
	view.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.05
	view.add_child(cam)
	cam.position = Vector3(1.2,0.55,-0.65)
	cam.look_at(Vector3(0,0,-0.08))
	var title := Label.new()
	title.position = Vector2(16,14)
	title.add_theme_font_size_override("font_size",20)
	view.add_child(title)
	var atlas := Image.create(2400,900,false,Image.FORMAT_RGBA8)
	var report := {}
	for i in IDS.size():
		var holder := Node3D.new()
		view.add_child(holder)
		var muzzle: Vector3 = preload("res://scripts/player/ArsenalWeapon3D.gd").build(holder,IDS[i])
		title.text = IDS[i].replace("_"," ").to_upper()
		cam.size = 0.48 if IDS[i] in ["pistol","magnum","grenade","knife","knuckles"] else 1.05
		var vertices := 0
		var surfaces := 0
		for part in holder.find_children("*","MeshInstance3D",true,false):
			for s in part.mesh.get_surface_count():
				surfaces += 1
				var a: Array = part.mesh.surface_get_arrays(s)
				vertices += a[Mesh.ARRAY_VERTEX].size()
		report[IDS[i]] = {"vertices":vertices,"surfaces":surfaces,"muzzle":str(muzzle)}
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		frame.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(frame,Rect2i(0,0,480,300),Vector2i(i%5,i/5)*Vector2i(480,300))
		holder.queue_free()
		await process_frame
	var output := "D:/geteco/artifacts/arsenal-quality-0914/models-"+label
	atlas.save_png(output+".png")
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARSENAL_MODELS_CAPTURED ",IDS.size())
	quit()
