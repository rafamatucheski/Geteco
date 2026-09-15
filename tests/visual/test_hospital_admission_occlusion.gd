extends SceneTree
const OUT := "D:/geteco/artifacts/life-refinement-0911/"
var failures: Array[String] = []
var world: Node2D
var hospital: Node2D
var camera: Camera2D
var cot: CharacterBody2D
var patient: CharacterBody2D
var crew: Array[CharacterBody2D] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _settle() -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw

func _capture(file: String, center: Vector2, zoom: float) -> void:
	camera.position = center
	camera.zoom = Vector2.ONE * zoom
	await _settle()
	root.get_texture().get_image().save_png(OUT + file + ".png")

func _overlay_alpha(point: Vector2) -> float:
	var sprite: Sprite2D = hospital.overhead_sprite
	var texture: Image = hospital.overhead_viewport.get_texture().get_image()
	var pixel := Vector2i(sprite.to_local(hospital.to_global(point)) + Vector2(texture.get_size()) * .5)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= texture.get_width() or pixel.y >= texture.get_height(): return 0
	return texture.get_pixelv(pixel).a

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This fixture requires rendering for alpha/composition checks")
		quit(2)
		return
	root.size = Vector2i(1100, 850)
	RenderingServer.set_default_clear_color(Color("9ba49b"))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	hospital = preload("res://world/harbor/hospital/HarborHospital.gd").new()
	world.add_child(hospital)
	hospital.set_emergency_door_open(true)
	hospital.emergency_door_amount = 1.0
	hospital._process(0.0)
	camera = Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	patient = preload("res://AnimatedPedestrian3D.gd").new()
	world.add_child(patient)
	patient.set_physics_process(false)
	patient.set_process(false)
	patient.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	patient.is_gangster = false
	cot = preload("res://world/shared/emergency/MedicalStretcher.gd").new()
	world.add_child(cot)
	cot.z_index = 6
	cot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cot.heading = 0.0
	cot.orient(Vector2.RIGHT)
	for i in 2:
		var medic := load("res://Paramedic.tscn").instantiate() as CharacterBody2D
		world.add_child(medic)
		medic.set_physics_process(false)
		medic.set_process(false)
		medic.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		medic.z_index = 7
		medic.left_upper_arm.rotation.x = -.8
		medic.right_upper_arm.rotation.x = -.8
		medic.model_root.rotation.y = PI * .5 if i == 0 else -PI * .5
		crew.append(medic)
	var outside := preload("res://AnimatedPedestrian3D.gd").new()
	outside.position = Vector2(-55, 145)
	world.add_child(outside)
	outside.set_physics_process(false)
	outside.set_process(false)
	outside.is_gangster = false
	await _settle()
	cot.load_patient(patient)
	for x in [117.0, 102.0, 74.0]:
		cot.position = Vector2(x, 40)
		for i in 2: crew[i].position = cot.position + Vector2(25 if i == 0 else -25, 0)
		cot.update_patient(1.0)
		await _capture("hospital-occlusion-full-%d" % x, Vector2(10, -5), 1.75)
		await _capture("hospital-occlusion-entry-%d" % x, Vector2(111, 26), 5.0)
		check(cot.patient_model == patient.model_root, "Original patient model retained at admission x=%d" % x)
	var roof_alpha := _overlay_alpha(Vector2(74, 43))
	var canopy_alpha := _overlay_alpha(Vector2(130, 20))
	var floor_alpha := _overlay_alpha(Vector2(120, 90))
	var outside_alpha := _overlay_alpha(Vector2(-55, 132))
	check(roof_alpha > .95, "Opaque white roof covers crew/cot behind it (alpha %.3f)" % roof_alpha)
	check(canopy_alpha > .1 and canopy_alpha < .9, "Glass canopy composes translucently over the real team (alpha %.3f)" % canopy_alpha)
	check(floor_alpha < .01, "Walking floor is absent from the overhead render")
	check(outside_alpha < .01, "A person outside the south frontage is not covered by the overhead pass")
	var overhead_camera: Camera3D = hospital.overhead_viewport.get_camera_3d()
	var lit := false
	for child in hospital.hospital_view.viewport_3d.get_children():
		if child is DirectionalLight3D:
			lit = lit or (child.layers & overhead_camera.cull_mask) != 0
	check(lit, "The overhead camera includes the actual directional light as well as its light mask")
	# Compare the same frozen crew with the upper architecture hidden. The
	# difference is compositing, not movement or a replacement character model.
	hospital.overhead_sprite.hide()
	await _capture("hospital-occlusion-before-comparison", Vector2(111, 26), 5.0)
	hospital.overhead_sprite.show()
	cot.release_patient()
	patient.hide()
	cot.position = Vector2(102, 40)
	for i in 2: crew[i].position = cot.position + Vector2(25 if i == 0 else -25, 0)
	await _capture("hospital-occlusion-empty-cot", Vector2(111, 26), 5.0)
	print("HOSPITAL_ADMISSION_OCCLUSION failures=", failures)
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
