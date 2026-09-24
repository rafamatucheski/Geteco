extends SceneTree
## Paired no-save render of the same native road maneuver with effects disabled/enabled.

var world: Node3D
var effects_enabled := true
var label := "vehicle-effects-after"

func _initialize() -> void:
	call_deferred("run")

func hide_other_vehicles(car: CharacterBody3D) -> void:
	for candidate in world.find_children("*","CharacterBody3D",true,false):
		if candidate==car or str(candidate.get_meta("gameplay_role",""))!="vehicle": continue
		candidate.set_physics_process(false)
		candidate.collision_layer=0
		candidate.collision_mask=0
		candidate.hide()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Vehicle effect capture requires rendered output")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg=="--effects-off": effects_enabled=false; label="vehicle-effects-before"
		if arg.begins_with("--label="): label=arg.split("=")[1]
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch",true)
	world.set_meta("skip_traffic_yield",true)
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1200:
		await physics_frame
		if world.production!=null and world.production.ready_for_play: break
	if world.production==null or not world.production.ready_for_play:
		push_error("Native world did not become ready")
		quit(1)
		return
	world.set_population(0)
	world.hud.hide()
	world.diagnostic_label.hide()
	world.session.set_process_input(false)
	world.camera.set_process_unhandled_input(false)
	if world.session.weather!=null:
		world.session.weather.weather_state=0
		world.session.weather._update()
	var car: CharacterBody3D = world.driving.car
	car.paint_color=Color("d5a544")
	for other in get_nodes_in_group("drivable"):
		if other==car: continue
		if not other is CollisionObject3D: continue
		other.set_physics_process(false)
		other.collision_layer=0
		other.collision_mask=0
		other.hide()
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var distance := route.get_closest_offset(car.position)
	var point := route.sample_baked(distance,true)
	var direction := route.sample_baked(minf(distance+1,route.get_baked_length()),true)-point
	for attempt in 16:
		var probe := fposmod(distance+attempt*7,route.get_baked_length())
		point = route.sample_baked(probe,true)
		direction = route.sample_baked(minf(probe+1,route.get_baked_length()),true)-point
		if world.production.vehicle_position_clear(car,point+Vector3.UP*.12,atan2(-direction.x,-direction.z)): break
	car.place(point+Vector3.UP*.12,atan2(-direction.x,-direction.z))
	car.set_physics_process(false)
	car.repair()
	car.controlled = true
	car.external_input = true
	car.effects.presentation_enabled = effects_enabled
	if not effects_enabled: car.effects.clear_all()
	world.player.hide()
	world.player.set_physics_process(false)
	world.player.collision_layer=0
	world.player.collision_mask=0
	world.camera.target=car
	world.camera.heading=-PI/5
	world.camera.target_size=10
	world.camera.initialized=false
	for frame in 72:
		hide_other_vehicles(car)
		car.health=car.max_health
		car.speed=10
		car.throttle_input=0
		car.brake_input=true
		car.steer_input=.72
		car.horizontal_velocity=-car.global_basis.z*8.2+car.global_basis.x*6.0
		car.global_position += -car.global_basis.z*.075
		car.rotation.y += .006
		car.effects.physics_tick(1.0/60.0,car.horizontal_velocity)
		await physics_frame
	hide_other_vehicles(car)
	car.health=car.max_health
	car.effects.powertrain_effects.physics_tick(effects_enabled)
	await RenderingServer.frame_post_draw
	var path := "res://evidence/"+label+".png"
	var saved := root.get_texture().get_image().save_png(path)
	var tire = car.effects.tire_effects
	var particle_names: Array = car.find_children("*","GPUParticles3D",true,false).map(func(node: Node): return node.name)
	var report := {"label":label,"effects_enabled":effects_enabled,"save_error":saved,"car_position":str(car.position),"speed":car.speed,"health":car.health,"marks":tire.marks.size(),"modes":tire.last_modes,"emitters":particle_names}
	var file := FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("VEHICLE_EFFECT_CAPTURE ",JSON.stringify(report))
	car.effects.clear_all()
	await create_timer(.65).timeout
	world.free()
	await process_frame
	await process_frame
	quit(0 if saved==OK else 1)
