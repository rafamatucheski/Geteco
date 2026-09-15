extends SceneTree
const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
const OUTPUT := "D:/geteco/artifacts/vehicle-exit-0914/"
var failures: Array[String] = []
var render := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(900, 600)
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-2000,-2000), Vector2(2000,-2000), Vector2(2000,2000), Vector2(-2000,2000)])
	ground.color = Color("78817e")
	world.add_child(ground)
	var actor = load("res://Player.gd").new()
	var actor_cam := Camera2D.new()
	actor_cam.name = "Camera"
	actor.add_child(actor_cam)
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	actor.add_child(shape)
	world.add_child(actor)
	actor.set_physics_process(false)
	var review := Camera2D.new()
	review.zoom = Vector2.ONE * 4.5
	world.add_child(review)
	var caption := Label.new()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	layer.add_child(caption)
	caption.position = Vector2(24,24)
	caption.add_theme_font_size_override("font_size", 24)
	var ids := ["monaliza", "sport_coupe", "summit_suv", "ranch_single", "courier_van", "boxrunner", "towmaster", "port_forklift", "beach_cabriolet", "bike_sport", "bike_cruiser", "bike_urban"]
	if "--open-focus" in OS.get_cmdline_user_args(): ids = ["port_forklift", "beach_cabriolet"]
	if "--cabin-focus" in OS.get_cmdline_user_args(): ids = ["monaliza"]
	if "--truck-focus" in OS.get_cmdline_user_args(): ids = ["towmaster"]
	for id in ids:
		var car: CharacterBody2D
		if id == "monaliza":
			car = load("res://world/harbor/monaliza/MonalizaCar.gd").new()
			world.add_child(car)
			car.unlocked = true
		else:
			car = FACTORY.spawn_parked_vehicle(world,"BoardingCase",Vector2.ZERO,0,id,0,Color("28609a"))
			car.ensure_presentation()
		for side in [-1.0, 1.0]:
			actor.set_physics_process(false)
			car.global_position = Vector2.ZERO
			car.global_rotation = -0.35 if side < 0 else 0.75
			actor.global_position = car.to_global(Vector2(-8, side * 43))
			actor.global_rotation = 0
			actor.model_root.rotation = Vector3(0,0.3,0)
			actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			var rest: Transform3D = actor.left_upper_leg.transform
			var approach: Vector2 = actor.global_position
			car.enter_vehicle(actor)
			var boarding: Node = car._boarding
			var label := "%s side %s" % [id,side]
			check(boarding.side == side and actor.global_position.distance_to(approach) < 0.01, label + " starts at approached side")
			check(is_zero_approx(actor.global_rotation), label + " upright sprite on entry")
			check(not actor.weapon_mount_node.visible, label + " frees hands")
			check(actor.is_control_disabled and not actor.is_physics_processing(), label + " controls locked")
			if not id.begins_with("bike"):
				check(is_instance_valid(boarding.cabin_occupant) and boarding.cabin_occupant.get_parent() == car.body_model, label + " actor shares vehicle depth buffer")
				check(not actor.sprite_3d_display.visible, label + " no foreground actor sprite")
				check(boarding.cabin_occupant.start.is_finite() and is_finite(boarding.cabin_occupant.actor_scale), label + " finite 3D placement")
			car.camera.enabled = false
			review.make_current()
			Input.action_press("move_up")
			var parked: Vector2 = car.global_position
			var capture_case: bool = render and id in ["monaliza", "boxrunner", "towmaster", "bike_urban", "port_forklift", "beach_cabriolet"]
			for t in [0.25, 0.49, 0.70]:
				if capture_case:
					while is_instance_valid(boarding) and boarding.progress < t: await process_frame
				else:
					boarding.motion.pause()
					boarding.progress = t
					boarding._process(0)
				check(is_zero_approx(actor.global_rotation) and actor.model_root.basis.y.dot(Vector3.UP) > 0.999, label + " upright throughout")
				check(actor.modulate.a > 0.99, label + " visible through articulation")
				check(actor.head_node.position.distance_to(actor.torso_node.transform * Vector3(0,0.36,0)) < 0.001, label + " connected head")
				check(actor.left_lower_leg.transform.is_finite() and actor.right_lower_leg.transform.is_finite(), label + " finite joints")
				if is_instance_valid(boarding.cabin_occupant):
					for pair in boarding.cabin_occupant._pairs:
						check(pair.copy.global_transform.is_finite(), label + " finite copied " + String(pair.copy.name))
				if t > 0.45:
					check(actor.left_lower_leg.quaternion.get_angle() + actor.right_lower_leg.quaternion.get_angle() > 0.35, label + " knees articulate")
				if capture_case:
					caption.text = "%s | %s | %s" % [id, "esquerda" if side < 0 else "direita", boarding.phase]
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT + "%s_%s_%s.png" % [id, "L" if side < 0 else "R", int(t*100)])
			check(car.global_position.distance_to(parked) < 1.0, label + " cannot drive during entry")
			if capture_case:
				while car.has_meta("vehicle_boarding"): await process_frame
			else:
				boarding._finish()
			check(not actor.visible and not actor.is_control_disabled, label + " seated state")
			if not id.begins_with("bike"):
				var occupant: Node3D = car.body_model.get_node("DanteCabinOccupant")
				check(occupant.seated and (is_zero_approx(occupant.position.x) if id == "port_forklift" else occupant.position.x < 0), label + " occupant stays in driver seat")
				check(absf(occupant.position.x) < absf(car._door_3d.hinge.position.x) - 0.25, label + " occupant inside body sides")
				var head: Node3D = occupant.rig.get_node("HeadNode")
				check(occupant.position.y + (head.position.y + occupant.head_clearance) * occupant.actor_scale <= occupant.ceiling + 0.001, label + " head fits below cabin roof")
				if capture_case:
					car.set_physics_process(false)
					car.set_process(false)
					caption.text = "%s | %s | dentro da cabine" % [id, "esquerda" if side < 0 else "direita"]
					for frame in 3: await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT + "%s_%s_seated.png" % [id, "L" if side < 0 else "R"])
					await check_occlusion(car, occupant, label, id in ["port_forklift", "beach_cabriolet"])
					car.set_physics_process(true)
					car.set_process(true)
			check(actor.left_upper_leg.transform.is_equal_approx(rest), label + " restores rig")
			check(actor.weapon_mount_node.visible, label + " restores weapon")
			check(actor.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, label + " restores original interpolation")
			check(actor.z_index == 10, label + " restores pedestrian drawing layer")
			check(not car._drive_input_armed, label + " held throttle needs release")
			if id.begins_with("bike"):
				check(car.body_model.rider.visible, label + " rider handoff")
			Input.action_release("move_up")
			var blocker := StaticBody2D.new()
			if side > 0:
				var blocked_shape := CollisionShape2D.new()
				blocked_shape.shape = CircleShape2D.new()
				blocked_shape.shape.radius = 12
				blocker.add_child(blocked_shape)
				world.add_child(blocker)
				blocker.global_position = car.to_global(Vector2(0,-45))
				await physics_frame
			if id.begins_with("bike"):
				check(is_instance_valid(car.body_model.dante_rider), label + " seated rider exists without helmet controller")
				if is_instance_valid(car.body_model.dante_rider): car.body_model.dante_rider.free()
				car.body_model.dante_rider = null
			car.exit_vehicle()
			if id.begins_with("bike"):
				check(is_instance_valid(car.body_model.dante_rider), label + " exit rebuilds missing rider")
				check(not car._boarding.cabin_occupant._rider_pose.is_empty(), label + " exit captures seated pose")
			var leaving: Node = car._boarding
			var door_origin: Vector2 = leaving._project_anchor(leaving.cabin_occupant.doorway)
			check(absf(leaving._start.x - door_origin.x) < 0.01, label + " landing stays at door, never vehicle centre")
			check(leaving._start.distance_to(door_origin) <= 24.01, label + " only body clearance beyond doorway")
			var landing: Vector2 = car.to_global(leaving._start)
			check(leaving.exiting and leaving.active and car.is_driven_by_player, label + " exit remains a controlled transition")
			check(leaving.side == side, label + " safe exit chooses available side")
			check(not actor.is_physics_processing() and actor.is_control_disabled, label + " exit locks controls until feet reach ground")
			car.exit_vehicle()
			check(car._boarding == leaving, label + " repeated exit preserves animation")
			car.camera.enabled = false
			review.make_current()
			for t in [0.95, 0.70, 0.49, 0.25, 0.01]:
				if capture_case:
					while is_instance_valid(leaving) and leaving.progress > t: await process_frame
				else:
					leaving.motion.pause()
					leaving.progress = t
					leaving._process(0)
				check(actor.global_position.is_finite() and not actor.is_physics_processing(), label + " exit has finite placement and locked physics")
				if t < 0.18:
					check(actor.sprite_3d_display.visible and not leaving.cabin_occupant.visible, label + " full body leaves vehicle viewport without clipping")
				if capture_case:
					caption.text = "%s | saida %s | %d%%" % [id, "esquerda" if side < 0 else "direita", int((1-t)*100)]
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT + "%s_%s_exit_%s.png" % [id,"L" if side < 0 else "R",int((1-t)*100)])
			if capture_case:
				while car.has_meta("vehicle_boarding"): await process_frame
			else: leaving._finish_exit()
			if blocker.is_inside_tree(): blocker.queue_free()
			else: blocker.free()
			check(actor.visible and actor.is_physics_processing() and not actor.is_control_disabled, label + " can move after exit")
			check(actor.sprite_3d_display.visible and car.body_model.get_node_or_null("DanteCabinOccupant") == null, label + " no duplicate after exit")
			check(actor.global_position.distance_to(landing) < 0.01, label + " completion preserves landing")
			await physics_frame
			await physics_frame
			await process_frame
			check(actor.global_position.distance_to(landing) < 0.5, label + " idle physics does not push pedestrian away")
			actor.set_physics_process(false)
			# Interrupt after articulation, then let every stale tween expire.
			actor.global_position = car.to_global(Vector2(-8, side * 43))
			var before_interrupt: Transform3D = actor.left_upper_leg.transform
			car.enter_vehicle(actor)
			car._boarding.motion.pause()
			car._boarding.progress = 0.6
			car._boarding._process(0)
			if id == "monaliza" and side > 0:
				car._boarding.cabin_occupant.free()
			car.exit_vehicle()
			check(is_equal_approx(car._boarding.progress, 0.6), label + " interrupted entry reverses current pose")
			car._boarding._finish_exit()
			actor.set_physics_process(false)
			check(actor.left_upper_leg.transform.is_equal_approx(before_interrupt) and actor.modulate.a == 1, label + " cancellation restores rig and opacity")
			check(actor.sprite_3d_display.visible, label + " sprite restored even if cabin presentation was removed")
			if id == "monaliza" and side < 0:
				car.enter_vehicle(actor)
				car._boarding._finish()
				await process_frame
				car.exit_vehicle()
				var live_exit: Node = car._boarding
				var previous: Vector2 = actor.global_position
				var saw_close := false
				while is_instance_valid(live_exit) and live_exit.active:
					await process_frame
					if not is_instance_valid(live_exit): break
					check(actor.global_position.distance_to(previous) < 12, "Exit never jumps away from the door")
					previous = actor.global_position
					if live_exit.phase == "close_outside":
						saw_close = true
						check(actor.is_control_disabled and not actor.is_physics_processing(), "Closing door keeps pedestrian beside car")
				check(saw_close, "Exit includes a visible closing beat outside")
				check(absf(car._door_3d.hinge.rotation.y) < .001, "Door is closed before walking resumes")
				actor.set_physics_process(false)
			await process_frame
			if capture_case: await create_timer(1.1).timeout
		print("CHECKED ", id, " both sides")
		car.queue_free()
		await process_frame
	await create_timer(2.6).timeout
	check(actor.visible and not actor.is_control_disabled, "cancelled callbacks cannot hide or lock actor")
	world.queue_free()
	await process_frame
	print("BOARDING ANIMATION: ", failures.size(), " failures ", failures)
	quit(0 if failures.is_empty() else 1)

func check_occlusion(car: Node, occupant: Node3D, label: String, open_cabin := false) -> void:
	# False color detects actual exposed body pixels without confusing opaque
	# coplanar vehicle seams (whose sorting can change) with actor protrusion.
	var marker := StandardMaterial3D.new()
	marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.albedo_color = Color.MAGENTA
	var saved: Array[Dictionary] = []
	for mesh in occupant.find_children("*", "MeshInstance3D", true, false):
		saved.append({"mesh":mesh, "material":mesh.material_override})
		mesh.material_override = marker
	occupant._refresh()
	for frame in 3: await RenderingServer.frame_post_draw
	var rendered: Image = car.body_viewport.get_texture().get_image()
	var exposed := 0
	for y in rendered.get_height():
		for x in rendered.get_width():
			var pixel := rendered.get_pixel(x,y)
			if pixel.r > 0.85 and pixel.g < 0.1 and pixel.b > 0.85 and pixel.a > 0.5: exposed += 1
	if open_cabin:
		check(exposed > 5, label + " seated driver visible in open cabin (%d)" % exposed)
	else:
		check(exposed == 0, label + " no body pixels outside the closed cabin (%d)" % exposed)
	for item in saved: item.mesh.material_override = item.material
	occupant._refresh()
