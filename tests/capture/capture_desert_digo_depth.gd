extends "res://tests/test_vertice_depth.gd"
## Native furniture, real player and supplied Digo mesh. Paired masks use
## unchanged camera/pose; hiding only the shop is the positive control.
const SHOP := preload("res://world/desert/drag_meet/DesertDigoWorkshop.gd")
const WORKER := preload("res://runtime/desert/DesertDigoWorker.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var destination := ""
var _started := 0
var _completed := false

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("DIGO_DEPTH requires actual rendered Mobile viewport")
		quit(2)
		return
	_started=Time.get_ticks_msec()
	destination="res://evidence/desert-digo-depth-%s-%d"%[Time.get_datetime_string_from_system().replace(":","-").replace("T","-"),_started]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): destination=arg.trim_prefix("--out-dir=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))!=OK:
		push_error("Cannot create Digo depth output")
		quit(2)
		return
	create_timer(150).timeout.connect(_timeout)
	viewport=SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	G.box(stage,"FixtureGround",Vector3(0,-.15,0),Vector3(50,.3,50),Color("ab9471"),true)
	var sky := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("a5b5c2")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("d4d7d9")
	settings.ambient_light_energy=.6
	sky.environment=settings
	stage.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-25,0)
	sun.light_energy=.85
	sun.light_color=Color("ffe7c9")
	sun.shadow_enabled=true
	stage.add_child(sun)
	var shop := SHOP.new()
	stage.add_child(shop)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=10
	camera.far=100
	stage.add_child(camera)
	camera.current=true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for who in ["player","digo"]:
		var actor: CharacterBody3D=ACTOR.new() if who=="player" else WORKER.new()
		if who=="player": actor.is_player=true; actor.controlled_automatically=true
		actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.position=WORKER.REPAIR_POINT
		actor.rotation.y=PI*.5
		for frame in 20: await process_frame
		# Natural work/wardrobe views keep their real materials before applying
		# the mask. This isolated capture is not a Main gameplay screenshot.
		for activity in ["repair","tools"]:
			actor.position=WORKER.REPAIR_POINT if activity=="repair" else WORKER.BENCH_POINT
			actor.rotation.y=PI*.5 if activity=="repair" else 0.0
			if who=="digo": actor.model.activity=activity
			await create_timer(.65).timeout
			for heading in [0,1,2]:
				_set_camera(camera,actor.position+Vector3.UP*.75,heading)
				var natural := await capture()
				var id: String="%s-%s-%s-natural"%[who,activity,["default","frontage","preview"][heading]]
				check(natural.save_png(destination.path_join(id+".png"))==OK,id+" image saved")
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		mask_meshes(actor,diagnostic)
		var cases := [
			{"id":"bench-front","point":Vector3(-4.5,.04,1.25),"expected":"clear"},
			{"id":"bench-behind","point":Vector3(-4.5,.04,3.55),"expected":"partial"},
			{"id":"bench-side","point":Vector3(-2.25,.04,2),"expected":"clear"},
			{"id":"car-front","point":Vector3(0,.04,-2.6),"expected":"clear"},
			{"id":"car-behind","point":Vector3(0,.04,2.3),"expected":"partial"},
			{"id":"car-side","point":Vector3(-1.5,.04,0),"expected":"clear"},
		]
		for setup in cases:
			actor.position=setup.point
			actor.rotation.y=PI
			actor.reset_physics_interpolation()
			_set_camera(camera,actor.position+Vector3.UP*.7,1)
			var id: String=str(who)+"-"+str(setup.id)
			check(not actor.test_move(actor.global_transform,Vector3.UP*.002),id+" whole capsule is outside furniture")
			await _depth_pair(shop,actor,camera,id,str(setup.expected),false)
		# Also test each actual routine point through the default camera. The
		# open bay must preserve the worker's head, including under the awning.
		for activity in ["repair","tools"]:
			actor.position=WORKER.REPAIR_POINT if activity=="repair" else WORKER.BENCH_POINT
			actor.rotation.y=PI*.5 if activity=="repair" else 0.0
			for heading in [0,2]:
				_set_camera(camera,actor.position+Vector3.UP*.7,heading)
				await _depth_pair(shop,actor,camera,str(who)+"-routine-"+str(activity)+("-preview" if heading==2 else ""),"readable",true)
		actor.free()
		await physics_frame
	_completed=true
	_save_report(false)
	print("DIGO_DEPTH checks=",checks," failures=",failures," output=",destination)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _set_camera(camera: Camera3D, target: Vector3, heading: int) -> void:
	var offset: Vector3=CAMERA.EXTERIOR_OFFSET
	if heading==1: offset=offset.rotated(Vector3.UP,PI)
	elif heading==2: offset=CAMERA.PREVIEW_OFFSET.rotated(Vector3.UP,CAMERA.PREVIEW_HEADING)
	camera.position=target+offset
	camera.look_at(target)

func _depth_pair(shop: Node3D, actor: CharacterBody3D, camera: Camera3D, id: String, expected: String, inspect_head: bool) -> void:
	shop.show()
	var actual := await capture()
	var visible := mask_count(actual)
	shop.hide()
	var control := await capture()
	var unobstructed := mask_count(control)
	shop.show()
	check(actual.save_png(destination.path_join(id+".png"))==OK,id+" depth image saved")
	check(control.save_png(destination.path_join(id+"-control.png"))==OK,id+" positive control saved")
	check(unobstructed>150,id+" positive control contains the real rig")
	var ratio := float(visible)/maxf(1.0,float(unobstructed))
	if expected=="clear": check(ratio>.90,id+" front/side preserves visible actor ratio="+str(ratio))
	elif expected=="partial": check(ratio>.05 and ratio<.90,id+" prop actually occludes lower body ratio="+str(ratio))
	else: check(ratio>.55,id+" actual routine keeps actor readable ratio="+str(ratio))
	var head_ratio := -1.0
	if inspect_head:
		var projected := camera.unproject_position(actor.global_position+Vector3.UP*1.57)
		var extent := Vector2(24,22)
		var area := Rect2i(Vector2i(projected-extent),Vector2i(extent*2))
		var head_visible := _count_area(actual,area)
		var head_control := _count_area(control,area)
		head_ratio=float(head_visible)/maxf(1.0,float(head_control))
		check(head_control>20,id+" head has positive control pixels")
		check(head_ratio>.65,id+" canopy does not conceal worker head ratio="+str(head_ratio))
	records.append({"id":id,"position":str(actor.position),"camera":str(camera.position),"expected":expected,
		"visible_pixels":visible,"control_pixels":unobstructed,"visible_ratio":ratio,"head_ratio":head_ratio})

func _count_area(image: Image, area: Rect2i) -> int:
	var count := 0
	area=area.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var color := image.get_pixel(x,y)
			if color.r>.55 and color.b>.55 and color.g<.2: count+=1
	return count

func _timeout() -> void:
	if _completed: return
	failures.append("150s bounded capture timed out")
	_save_report(true)
	quit(3)

func _save_report(timed_out: bool) -> void:
	var report := FileAccess.open(destination.path_join("results.json"),FileAccess.WRITE)
	if report==null: push_error("Digo depth report unavailable"); return
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"timed_out":timed_out,
		"seconds":float(Time.get_ticks_msec()-_started)/1000.0,"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":[1280,720],"camera_offset":str(CAMERA.EXTERIOR_OFFSET),"records":records,
		"limitations":["Native scene fixture; full Main lifecycle and FPS require separate evidence.",
			"Natural materials use a stable fixture sun/ambient light, not the active Main weather.",
			"Front/side/behind probes use production exterior inclination with heading180; actual routine points use both default and production preview cameras."]},"\t"))
