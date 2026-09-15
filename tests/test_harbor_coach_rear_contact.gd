extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var service := preload("res://world/harbor/terminal/HarborTerminalCoachService.gd").new()
	service.operations = world
	service.platform_index = 1
	service.position = Vector2(1700,1060)
	world.add_child(service)
	service.set_physics_process(false)
	for person in service.passenger_service.people: person.set_physics_process(false)
	service.state = "arriving"
	service._set_route(service._arrival_route())
	service.coach.position = Vector2(-263.9473,168)
	service.route_progress = service.route.get_closest_offset(service.coach.position)
	service.heading = Vector2.RIGHT
	service.coach_shape.shape = service._shape_for_heading(Vector2.RIGHT)
	var car := preload("res://emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world,"RearContact",Vector2(1341.673,1202.239),0.9297818,"route_city",20)
	car.set_process(false)
	car.set_physics_process(false)
	await physics_frame
	await physics_frame
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = service.coach_shape.shape
	query.transform = service.coach.global_transform
	query.collision_mask = 2
	query.exclude = [service.coach.get_rid()]
	print("COACH_REAR_INITIAL carshape=",car.collision.shape.get_rect()," overlaps=",world.get_world_2d().direct_space_state.intersect_shape(query))
	var origin := service.coach.position
	var max_step := 0.0
	for frame in 120:
		var before := service.coach.position
		service._advance(1.0/60.0)
		max_step = maxf(max_step,before.distance_to(service.coach.position))
		await physics_frame
	print("COACH_REAR_CONTACT moved=",service.coach.position-origin," max_step=",max_step," blocked=",service.blocked," progress=",service.route_progress," pos=",service.coach.position)
	var passed := service.coach.position.x > origin.x + 20 and max_step < 0.6
	passed = passed and absf(service.route_progress - service.route.get_closest_offset(service.coach.position)) < 0.01
	for placement in [Vector2(80,0), Vector2(0,-20)]:
		service.coach.position = origin
		service.route_progress = service.route.get_closest_offset(origin)
		service.current_speed = 0.0
		service.blocked = false
		car.global_rotation = 0.0
		car.global_position = service.coach.global_position + placement
		await physics_frame
		await physics_frame
		for frame in 12:
			service._advance(1.0/60.0)
			await physics_frame
		var stayed := service.coach.position.distance_to(origin) < 0.01
		print("COACH_CONTACT_GUARD placement=",placement," stayed=",stayed," blocked=",service.blocked)
		passed = passed and stayed and service.blocked
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)
