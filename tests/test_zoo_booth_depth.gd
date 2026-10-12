extends "res://tests/test_vertice_depth.gd"
const BOOTH = preload("res://world/mountain_detail/zoo/ZooTicketBooth.gd")
const DEPTH_OUTPUT := "res://evidence/zoo-refresh-20261010/depth"

func _upper_mask(image: Image, top: int, bottom: int) -> int:
	var count := 0
	for y in range(top, bottom):
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r > .55 and color.b > .55 and color.g < .2: count += 1
	return count

func _mask_bounds(image: Image) -> Vector2i:
	var top := image.get_height()
	var bottom := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r > .55 and color.b > .55 and color.g < .2:
				top = mini(top,y); bottom = maxi(bottom,y)
	return Vector2i(top,bottom)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEPTH_OUTPUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var architecture := Node3D.new()
	stage.add_child(architecture)
	BOOTH.build(architecture)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("99aeb4")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .8
	stage.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	stage.add_child(camera)
	camera.make_current()
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1,0,1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rows: Array[Dictionary] = []
	for is_player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.identity = 624
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		# Freeze presentation for matching masks without removing body from physics.
		actor.visual.process_mode = Node.PROCESS_MODE_DISABLED
		actor.visual.rotation.y = PI
		var who := "player" if is_player else "npc"
		await physics_frame
		for collision in [
			{"id":"front", "at":Vector3(-3.2,.06,24.5), "move":Vector3(0,0,-4), "blocked":true},
			{"id":"behind", "at":Vector3(-3.2,.06,21.1), "move":Vector3(0,0,4), "blocked":true},
			{"id":"side", "at":Vector3(-5.2,.06,22.5), "move":Vector3(4,0,0), "blocked":true},
			{"id":"clear_side", "at":Vector3(-5.2,.06,24.5), "move":Vector3(0,0,-3), "blocked":false}]:
			actor.position = collision.at
			check(actor.test_move(actor.global_transform,collision.move) == collision.blocked, who+" physical sweep "+collision.id)
		actor.position = Vector3(-3.2,.06,21.1)
		check(not actor.test_move(actor.global_transform,Vector3(.02,0,0),null,.001,true), who+" service spawn is clear of solids")
		var focus := Vector3(-3.2,.8,22.3)
		camera.position = focus + preload("res://scripts/CameraRig.gd").EXTERIOR_OFFSET
		camera.look_at(focus)
		var natural := await capture()
		natural.save_png(DEPTH_OUTPUT+"/"+who+"-cashier-natural.png")
		mask_meshes(actor.visual,diagnostic)
		for pose in [
			{"id":"front", "at":Vector3(-3.2,.06,24.5)},
			{"id":"behind", "at":Vector3(-3.2,.06,21.1)},
			{"id":"side", "at":Vector3(-5.2,.06,22.5)}]:
			actor.position = pose.at
			architecture.show()
			var shown := await capture()
			architecture.hide()
			var control := await capture()
			var pixels := mask_count(control)
			var visible := mask_count(shown)
			var ratio := float(visible)/maxf(pixels,1)
			var bounds := _mask_bounds(control)
			var head_bottom := bounds.x + int((bounds.y-bounds.x)*.3)+1
			var head_control := _upper_mask(control,bounds.x,head_bottom)
			var head_shown := _upper_mask(shown,bounds.x,head_bottom)
			var head_ratio := float(head_shown)/maxf(head_control,1)
			check(pixels>150 and head_control>30,who+" positive visible control "+pose.id)
			if pose.id == "behind":
				check(ratio>.05 and ratio<.95,who+" counter occludes lower body but keeps cashier readable")
				check(head_ratio>.5,who+" cashier head remains readable from gameplay camera")
			else: check(ratio>.9,who+" remains unobstructed "+pose.id)
			shown.save_png(DEPTH_OUTPUT+"/"+who+"-"+pose.id+".png")
			control.save_png(DEPTH_OUTPUT+"/"+who+"-"+pose.id+"-control.png")
			rows.append({"actor":who,"pose":pose.id,"visible_ratio":ratio,"head_visible_ratio":head_ratio,"visible_pixels":visible,"control_pixels":pixels})
			architecture.show()
		actor.free()
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"camera":"CameraRig.EXTERIOR_OFFSET 45 degrees","rows":rows}
	FileAccess.open(DEPTH_OUTPUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ZOO_BOOTH_DEPTH ",JSON.stringify(report))
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
