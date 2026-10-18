extends SceneTree
## Sonda (18/10): o usuário vê a traseira do carro que dirige "meio transparente, meio
## amarela, piscando". Embarca de verdade, acelera e grava quadros seguidos recortados no
## carro: primeiro com a silhueta do CityLook, depois com ela zerada (tint alfa 0).
var world
var out := ""

func _initialize() -> void: run.call_deferred()

func run() -> void:
	out = ProjectSettings.globalize_path("res://evidence/vehicle-rear-overlay-20261018")
	DirAccess.make_dir_recursive_absolute(out)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if admitted(): break
	var car: CharacterBody3D = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var offset := route.get_closest_offset(car.position)
	var point := route.sample_baked(offset,true)
	var ahead := route.sample_baked(offset+1,true)-point
	car.place(point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
	for i in 3: await physics_frame
	var entered := false
	for side in [-1,1]:
		await physics_frame
		world.player.teleport(car.driver_door_anchor(side) + Vector3.UP*.04)
		world.camera.target = world.player
		await physics_frame
		var option: Dictionary = world.driving._entry_option()
		var door: Vector3 = car.driver_door_anchor(side)
		print("REAR_PROBE why locked=",world.player.input_locked," ext=",world.driving._external_transition_blocked()," air=",world.player.get_meta("player_air_busy",false)," vis=",car.is_visible_in_tree()," layer=",car.collision_layer," await=",car.has_meta("awaiting_ground")," hp=",car.health," speed=",car.speed," gap=",world.player.position.distance_to(door)," drivable=",car.is_in_group("drivable"))
		print("REAR_PROBE side=",side," option_car=",option.get("car")," same=",option.get("car")==car," archetype=",car.archetype,"")
		if world.driving._begin_entry(car, side): entered = true; break
	var until := Time.get_ticks_msec() + 15000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < until: await process_frame
	print("REAR_PROBE driving_car=",world.driving.car," transition=",world.driving.transition)
	print("REAR_PROBE entered=",entered," occupied=",world.driving.occupied," controlled=",car.controlled)
	Input.action_press("accelerate")
	await _hold(1.2)
	await _burst(car,"overlay")
	var overlays := {}
	for node in car.find_children("*","GeometryInstance3D",true,false):
		if node.material_overlay is ShaderMaterial: overlays[node.material_overlay] = true
	print("REAR_PROBE overlay_materials=",overlays.size())
	for material in overlays:
		material.set_shader_parameter("tint",Color(0,0,0,0))
		material.set_shader_parameter("readable_actor",false)
	await _burst(car,"no_overlay")
	Input.action_release("accelerate")
	world.queue_free()
	await process_frame
	quit(0)

func _hold(seconds: float) -> void:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < end: await process_frame

func _burst(car: Node3D, label: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(out+"/%s_%02d.png" % [label,i])
		await process_frame

func admitted() -> bool:
	return world.session != null and world.production != null and world.session.ready_for_play and world.production.ready_for_play and not world.player.input_locked and world.get_node_or_null("LoadingCurtain") == null and root.get_node_or_null("LoadingCurtain") == null
