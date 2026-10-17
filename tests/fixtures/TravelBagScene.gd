extends RefCounted
const MISSIONS = preload("res://data/campaign/HarborMissions.gd")

static func complete_through(session, last: String) -> bool:
	var data: Dictionary = session.state.campaign.snapshot()
	for id in MISSIONS.ORDER:
		if id not in data.completed:
			data.completed.append(id)
			data.pending_rewards[id] = MISSIONS.MISSIONS[id].reward
			for flag in MISSIONS.MISSIONS[id].sets_flags: data.flags[flag] = true
		if id == last: break
	return session.state.campaign.restore_snapshot(data)

static func park_monaliza(world):
	var session = world.session
	var initial = world.driving.car
	initial.collision_layer = 0; initial.collision_mask = 0
	initial.set_physics_process(false); initial.hide()
	var car = world.production.spawn_vehicle("monaliza", initial.position, initial.rotation.y)
	car.set_meta("garage_reward", true)
	car.vehicle_id = "personal_monaliza"
	session.garage_rewards.cars.personal_monaliza = car
	session.garage_rewards.data.vehicles.personal_monaliza = session.garage_rewards._initial_record("monaliza", car.position, car.rotation.y, "")
	return car

## Session readiness is published briefly during restore_location, before the
## streaming settle and loading-curtain fade finish. Fixtures must wait for play.
static func wait_for_startup(world, max_frames:=2400) -> bool:
	for i in max_frames:
		await world.get_tree().physics_frame
		if world.session==null or not world.session.ready_for_play: continue
		if preload("res://runtime/StartupCurtain.gd").existing(world.get_tree())!=null: continue
		if world.session.is_transition_blocked(): continue
		if vehicle_supported(world,world.driving.car): return true
	return false

static func vehicle_supported(world,car) -> bool:
	if not is_instance_valid(car) or car.has_meta("awaiting_ground"): return false
	var ray:=PhysicsRayQueryParameters3D.create(car.global_position+Vector3.UP*.6,car.global_position-Vector3.UP*.6,1)
	ray.exclude=[car.get_rid()]
	return not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

static func wait_for_vehicle_support(world,car,max_frames:=300) -> bool:
	for i in max_frames:
		await world.get_tree().physics_frame
		if vehicle_supported(world,car): return true
	return false
