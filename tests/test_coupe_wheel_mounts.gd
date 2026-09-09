extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var scene = load("res://district/harbor_preview/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 5: await physics_frame
	var car = scene.get_node("PlayerCar")
	car.set_physics_process(false)
	for i in car.spinners.size():
		var tires := 0
		for part in car.spinners[i].get_children():
			if part is MeshInstance3D and part.material_override == car.body_model.materials["rubber"]:
				tires += 1
				print("WHEEL_CENTER index=%d local=%s" % [i, part.position])
				check(part.position.length() < 0.001, "Tire center must coincide with wheel axle")
		check(tires == 1, "Each spinning assembly requires one tire")
		var calipers := 0
		for part in car.wheels[i].get_children():
			if part is MeshInstance3D and part.material_override == car.body_model.materials["brake"]:
				calipers += 1
				var before: Transform3D = part.transform
				car.spinners[i].rotation.x += PI / 2
				check(part.transform.is_equal_approx(before), "Caliper must not spin with the tire")
		check(calipers == 1, "Caliper must be mounted outside the spinning assembly")
	var wheel_positions: Array[Vector3] = []
	for wheel in car.wheels: wheel_positions.append(wheel.position)
	car.body_model.apply_impact(Vector3(0.7,0.81,-1.8),Vector3(0,0,1),12.0)
	check(car.body_model.max_deformation() > 0, "Impact must still deform bodywork")
	for i in car.wheels.size():
		check(car.wheels[i].position.is_equal_approx(wheel_positions[i]), "Body damage must preserve axle mounts")
	car.body_model.repair()
	check(is_zero_approx(car.body_model.max_deformation()), "Repair must restore bodywork")
	if "capture" in OS.get_cmdline_user_args():
		for i in 4:
			car.body_model.rotation.y = -PI / 2
			for spin in car.spinners: spin.rotation.x = i * PI / 2
			car.request_appearance_update()
			await RenderingServer.frame_post_draw
			car.body_viewport.get_texture().get_image().save_png("D:/geteco/coupe-wheel-%d.png" % i)
	scene.queue_free()
	await process_frame
	print("COUPE_WHEEL_MOUNTS failures=%d" % failures)
	quit(0 if failures == 0 else 1)
