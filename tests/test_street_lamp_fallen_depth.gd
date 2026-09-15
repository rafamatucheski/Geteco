extends SceneTree

const OUT := "D:/geteco/artifacts/lamp-fall-0914/"
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _picture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("PASS " if ok else "FAIL ", message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	create_timer(30).timeout.connect(func(): quit(2))
	root.size = Vector2i(640,480)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("667078"))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car = load("res://cars/traffic/SavedPlayerCar.tscn").instantiate()
	car.set_script(load("res://prototypes/living_cast/HarborCoupe.gd"))
	world.add_child(car)
	car.set_physics_process(false)
	# Leave the foot exposed so visibility has a positive control as well.
	car.position = Vector2(55,-5)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE*4
	camera.position = Vector2(25,-10)
	camera.make_current()
	var lamp = load("res://StreetLamp.gd").new()
	var baseline := "before" in OS.get_cmdline_user_args()
	if baseline:
		lamp.free()
		var original := GDScript.new()
		original.source_code = FileAccess.get_file_as_string(OUT+"StreetLamp-before.gd").replace("class_name StreetLamp", "")
		assert(original.reload()==OK)
		lamp = original.new()
	# Deliberately add the lamp after the car: identical z=8 must not make
	# ground debris cover a vehicle just because it streamed in later.
	world.add_child(lamp)
	lamp.receive_vehicle_impact(100,Vector2.RIGHT)
	await create_timer(1).timeout
	for side in [-5,12]:
		car.position.y=side
		car.reset_physics_interpolation()
		car.show()
		lamp.show()
		await physics_frame
		await physics_frame
		var combined := await _picture()
		lamp.hide()
		var actor_only := await _picture()
		car.hide()
		var empty := await _picture()
		lamp.show()
		var pole_only := await _picture()
		var overlap := 0
		var correct := 0
		var visible_pole := 0
		for y in combined.get_height():
			for x in combined.get_width():
				var a := actor_only.get_pixel(x,y)
				var p := pole_only.get_pixel(x,y)
				var bg := empty.get_pixel(x,y)
				if _difference(p,bg)<.15: continue
				if _difference(a,bg)<.05:
					if _difference(combined.get_pixel(x,y),p)<.08: visible_pole+=1
				elif _difference(a,p)>.15:
					overlap+=1
					if _difference(combined.get_pixel(x,y),a)<.08: correct+=1
		_check(overlap>12,"Actual car/pole pixel overlap side=%d pixels=%d"%[side,overlap])
		_check(correct>overlap*.9,"Car covers fallen pole side=%d pixels=%d/%d"%[side,correct,overlap])
		_check(visible_pole>12,"Uncovered debris remains visible side=%d pixels=%d"%[side,visible_pole])
		combined.save_png(OUT+("before" if baseline else "after")+"-side%d.png"%side)
	print("FALLEN_LAMP_DEPTH failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _difference(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
