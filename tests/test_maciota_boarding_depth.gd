extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func magenta_pixels(frame: Image) -> int:
	var count := 0
	for y in frame.get_height():
		for x in frame.get_width():
			var color := frame.get_pixel(x,y)
			if color.r > .8 and color.b > .8 and color.g < .2 and color.a > .8: count += 1
	return count
func snapshot(car: Node) -> Image:
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	return car.body_viewport.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(35).timeout.connect(func(): quit(2))
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var car := preload("res://world/harbor/campaign/MaciotaTourCar.gd").new()
	stage.add_child(car)
	car.set_physics_process(false)
	var marker := StandardMaterial3D.new()
	marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.albedo_color = Color.MAGENTA
	for index in 2:
		var actor: CharacterBody2D
		if index == 0:
			actor = preload("res://characters/Player.gd").new()
			var camera := Camera2D.new()
			camera.name = "Camera"
			actor.add_child(camera)
		else: actor = preload("res://characters/JagerNPC.gd").new()
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.global_position = car.seat(1-index)
		# Camera projection matrices are finalized by rendering, as they are
		# before an actual player walks up to the production car.
		for frame in 3: await process_frame
		for mesh in actor.model_root.find_children("*","MeshInstance3D",true,false): mesh.material_override = marker
		var original_parent: Node = actor.model_root.get_parent()
		var original_update: int = actor.viewport_3d.render_target_update_mode
		var view := preload("res://world/harbor/campaign/TourActorPresentation.gd").new()
		stage.add_child(view)
		view.configure(actor,car,1.0 if index == 0 else -1.0)
		var pose: RefCounted = preload("res://scripts/player/VehicleBoardingPose.gd").new() if index == 0 else preload("res://world/harbor/campaign/MaciotaBoardingPose.gd").new()
		pose.setup(actor)
		car.model.door(1-index,true)
		var visible_control := false
		var occluded := false
		for progress in [0.0,.45,.7,1.0]:
			if index == 0: pose.apply(actor,"car",1.0,progress,car.heading)
			else: pose.apply(progress,car.heading)
			view.entry = progress
			view.sync()
			var composed := magenta_pixels(await snapshot(car))
			car.model.hide()
			var isolated := magenta_pixels(await snapshot(car))
			car.model.show()
			if is_zero_approx(progress): visible_control = composed > 10
			occluded = occluded or isolated > composed+5
			print("DEPTH actor=",index," progress=",progress," visible=",composed," without_car=",isolated)
		check(visible_control,"actor remains visible beside the car (positive control)")
		check(occluded,"real bodywork occludes actor pixels during seat entry")
		check(not actor.sprite_3d_display.visible and actor.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED,"individual actor pass is suspended during shared depth")
		pose.restore()
		view.restore()
		check(actor.model_root.get_parent() == original_parent and actor.sprite_3d_display.visible and actor.viewport_3d.render_target_update_mode == original_update,"exit restores the original rig and rendering state")
		view.queue_free()
		actor.queue_free()
		car.model.door(1-index,false)
		await process_frame
	print("MACIOTA_BOARDING_DEPTH failures=",failures)
	quit(1 if failures else 0)
