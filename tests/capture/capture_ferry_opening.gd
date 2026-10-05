extends SceneTree
## Offline movie writer or representative native 3D frames; never opens a user save.
var world
var director
var elapsed := 0.0
var recording := false
var output := "D:/geteco/artifacts/opening-ferry-20261003"
var frames := 0
var start_frame := 0
var movie_frames := 0
var previous_bones: Array[Quaternion] = []
var previous_phone := Vector3.ZERO
var max_bone_step := 0.0
var max_phone_step := 0.0
var max_background_drift := 0.0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	root.get_node("V2Launch").selected_path = "user://opening-authoring-isolated.json"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	assert(world.session != null and world.session.ready_for_play)
	world.player.teleport(Vector3(233,.56,188.2))
	world.production.region.set_focus(Vector3(233,0,183.5))
	for i in 120: await physics_frame
	director = preload("res://cutscenes/opening/ferry/FerryDirector.gd").new()
	world.add_child(director)
	director.configure(world)
	DirAccess.make_dir_recursive_absolute(output)
	if "--phone-poses" in OS.get_cmdline_user_args():
		var variants := [[-1.5,-.8],[0,.8],[1.5,.8],[3,.8]]
		for i in variants.size():
			director.sample(43.0,1.0/30.0)
			director.dante._apply_pose(director.dante._idle_pose)
			director.dante._apply_idle_breath()
			preload("res://cutscenes/opening/ferry/FerryPhonePose.gd").apply(director.dante,director.phone,1.0,variants[i][0],variants[i][1])
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/phone-%02d.png"%i)
		print("FERRY_PHONE_POSES_OK")
		await finish()
		return
	if "--layout" in OS.get_cmdline_user_args():
		director.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		director.camera.size = 225.0
		director.camera.global_position = Vector3(260,240,170)
		director.camera.look_at(Vector3(260,0,170),Vector3.FORWARD)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/layout.png")
		quit()
		return
	if "--stills" in OS.get_cmdline_user_args():
		for t in [3.0,9.0,13.0,17.0,26.0,32.0,43.0,58.0,63.0,70.0]:
			director.sample(t,1.0/30.0)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png(output+"/shot-%02d.png"%int(t))
			assert(result == OK)
		print("FERRY_STILLS_OK")
		world.queue_free()
		await process_frame
		quit()
	else:
		var matte := CanvasLayer.new()
		root.add_child(matte)
		for bottom in [false,true]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
			if bottom: bar.offset_top = -root.size.y*.125
			else: bar.offset_bottom = root.size.y*.125
			matte.add_child(bar)
		director.sample(0.0,1.0/30.0)
		start_frame = frames
		print("FERRY_MOVIE_START_FRAME ",start_frame)
		recording = true

func _process(delta: float) -> bool:
	frames += 1
	if not recording: return false
	elapsed = float(movie_frames)/30.0
	director.sample(elapsed,delta)
	_validate_motion()
	movie_frames += 1
	if movie_frames >= roundi(director.length*30.0):
		recording = false
		var file := FileAccess.open(output+"/render.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"start_frame":start_frame,"end_frame":frames,"duration":director.length,"fps":30,"size":str(root.size),"max_bone_step_degrees":rad_to_deg(max_bone_step),"max_phone_step_m":max_phone_step,"max_background_drift_m":max_background_drift,"directed_background_bodies":director.night_set.frozen_bodies.size()},"\t"))
		file.close()
		print("FERRY_MOVIE_FINISHED ",frames-start_frame," frames")
		finish.call_deferred()
	return false

func _validate_motion() -> void:
	# Detect the reported flips and circling across all 2,190 authored frames.
	var rotations: Array[Quaternion] = []
	for name in ["RightArm","RightForeArm","RightHand"]:
		var bone: int = director.dante.skeleton.find_bone(name)
		rotations.append(director.dante.skeleton.get_bone_pose_rotation(bone))
	var relative_phone: Vector3 = director.ferry.to_local(director.phone.global_position)
	if not previous_bones.is_empty():
		for i in rotations.size():
			max_bone_step = maxf(max_bone_step,previous_bones[i].angle_to(rotations[i]))
		max_phone_step = maxf(max_phone_step,relative_phone.distance_to(previous_phone))
	previous_bones = rotations
	previous_phone = relative_phone
	for body in director.night_set.frozen_bodies:
		if is_instance_valid(body.node):
			var drift: float = body.position.distance_to(body.node.global_position)
			if drift > .005:
				push_error("Cinematic mark moved: %s (%s), %.4f m"%[body.node.get_path(),body.node.get_script(),drift])
				recording = false
				quit(1)
				return
			max_background_drift = maxf(max_background_drift,drift)
	assert(max_bone_step < .1,"Sudden arm/wrist flip in the film")
	assert(max_phone_step < .04,"Phone jumps relative to the actor")
	assert(max_background_drift < .005,"Background extras left their cinematic marks")

func finish() -> void:
	world.queue_free()
	await process_frame
	await process_frame
	quit()
