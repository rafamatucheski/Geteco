extends SceneTree

const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
const ENGINE = preload("res://audio/VehicleEngineSound.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	var ids := ["bike_sport", "bike_cruiser", "bike_urban"]
	var audio_checksums := []
	for id in ids:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		check(spec.id == id and spec.colors.size() >= 5, id+" catalog/colors")
		check(ENGINE.family_for_vehicle(id) == id, id+" engine family")
		var path := Path2D.new()
		path.curve = Curve2D.new()
		path.curve.add_point(Vector2(50,100))
		path.curve.add_point(Vector2(450,100),Vector2(-100,0),Vector2(100,0))
		path.curve.add_point(Vector2(650,350),Vector2(0,-120))
		world.add_child(path)
		var bike = FACTORY.spawn_moving_vehicle(path,"TestBike",id,.2,90,0)
		bike.set_process(false)
		bike.set_physics_process(false)
		var pending_size: Vector2 = bike.collision.shape.size
		check(bike.body_model == null, id+" deferred model")
		check(pending_size.y < 20.0, id+" narrow collision")
		bike.ensure_presentation()
		check(bike.collision.shape.size == pending_size, id+" collision survives streaming")
		check(bike.body_model.rider.visible, id+" NPC visible")
		check(bike.wheels.size() == 2 and bike.spinners.size() == 2, id+" two animated wheels")
		var origin: Vector2 = bike.global_position
		for frame in 120: bike.advance_on_lane(1.0/60.0)
		check(bike.global_position.distance_to(origin) > 60.0, id+" advances on traffic route")
		bike.wheel_rig.update(1.0,5.0,0.0,.3)
		check(absf(bike.wheels[0].rotation.y) > .2 and is_zero_approx(bike.wheels[1].rotation.y), id+" front-only steering")
		bike.body_model.update_riding_pose(1.0,6.0,.25,true)
		check(absf(bike.body_model.lean) > .1, id+" leans in turns")
		bike.configure_as_parked()
		check(not bike.body_model.rider.visible and bike.body_model.stand.visible, id+" parked has no imaginary rider")
		bike.repaint_vehicle(Color.YELLOW)
		check(bike.body_model.paint.albedo_color == Color.YELLOW, id+" paint")
		check(bike.body_model.rider_jacket.albedo_color != Color.YELLOW, id+" material isolation")
		bike.body_model.apply_impact(Vector3(.2,.6,-.2),Vector3(-1,0,0),12.0)
		check(bike.body_model.impact_count == 1, id+" damage works")
		bike.body_model.repair()
		check(bike.body_model.impact_count == 0, id+" repair works")
		var actor = load("res://Player.gd").new()
		var actor_camera := Camera2D.new()
		actor_camera.name = "Camera"
		actor.add_child(actor_camera)
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.position = bike.global_position + Vector2(0,30)
		bike.enter_vehicle(actor)
		check(bike.is_driven_by_player and bike._boarding.active, id+" player mounts")
		check(not bike.body_model.rider.visible, id+" no duplicate during mount")
		while bike.has_meta("vehicle_boarding"): await process_frame
		check(not actor.visible and bike.body_model.rider.visible, id+" rider after mount")
		check(bike._side_doors.is_empty(), id+" no car doors")
		check(bike.radio_audio != null and bike.radio_audio.playing, id+" radio while riding")
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(700, 400)
		root.push_input(wheel)
		check(bike.radio_index == 1, id+" mouse wheel tunes radio")
		bike.exit_vehicle()
		while bike.has_meta("vehicle_boarding"): await process_frame
		check(actor.visible and actor.is_physics_processing() and not bike.body_model.rider.visible, id+" player dismounts")
		var layers := ENGINE.get_layer_streams(id,id)
		check(layers.size() == 3, id+" three engine layers")
		audio_checksums.append(hash(layers[0].data))
		var controller := ENGINE.new()
		var player := AudioStreamPlayer2D.new()
		world.add_child(player)
		controller.bind(player,id)
		for frame in 600: controller.update(player,float(frame)/600.0*300,300,1,1.0/60.0,id)
		check(controller.gear >= 4 and controller.engine_rpm > 1000, id+" gearbox/RPM")
		controller.stop()
		player.stop()
		actor.queue_free()
		bike.queue_free()
		path.queue_free()
		await process_frame
	check(audio_checksums[0] != audio_checksums[1] and audio_checksums[1] != audio_checksums[2],"distinct engine PCM")
	for id in ["union_sedan", "cargo_flatbed_truck"]:
		var vehicle = FACTORY.spawn_parked_vehicle(world, "RadioTest", Vector2(200, 200), 0, id, 0)
		vehicle.has_theft_alarm = false
		var actor = load("res://Player.gd").new()
		var actor_camera := Camera2D.new()
		actor_camera.name = "Camera"
		actor.add_child(actor_camera)
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.position = vehicle.global_position + Vector2(0, 30)
		vehicle.enter_vehicle(actor)
		while vehicle.has_meta("vehicle_boarding"): await process_frame
		check(vehicle.radio_audio != null and vehicle.radio_audio.playing, id+" radio on entry")
		var wheel := InputEventMouseButton.new()
		wheel.position = Vector2(700, 400)
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		root.push_input(wheel)
		check(vehicle.radio_index == 1, id+" wheel next")
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		root.push_input(wheel)
		check(vehicle.radio_index == 0, id+" wheel previous")
		vehicle.exit_vehicle()
		while vehicle.has_meta("vehicle_boarding"): await process_frame
		check(not vehicle.radio_audio.playing, id+" radio stops on exit")
		actor.queue_free()
		vehicle.queue_free()
		await process_frame
	var recycled = FACTORY.spawn_parked_vehicle(world,"Recycled",Vector2(100,100),0,"union_sedan",0)
	recycled.ensure_presentation()
	recycled.apply_archetype("bike_cruiser")
	check(recycled.body_model.style == "cruiser" and recycled.wheels.size() == 2,"car to bike rebuild")
	recycled.apply_archetype("bike_sport")
	check(recycled.body_model.style == "sport" and recycled.wheels.size() == 2,"bike class rebuild")
	recycled.apply_archetype("union_sedan")
	check(not recycled.is_motorcycle and recycled.wheels.size() == 4,"bike to car rebuild")
	world.queue_free()
	await process_frame
	print("MOTORCYCLES: %d failures" % failures)
	quit(1 if failures else 0)
