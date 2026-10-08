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
