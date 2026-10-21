extends "res://tests/test_harbor_service_roofs.gd"
## Focused integrated review: the original roof runner owns isolated persistence;
## this adds Vance's real service before returning through the authored aisle.
func recovery_scenarios(_target: Dictionary) -> void:
	# Peaceful shops correctly reject the runner's environmental lethal hit.
	# Takeshi's house exercises the same runtime under its real damage policy.
	await super.recovery_scenarios(CATALOG.find("cobra_leader_house"))

func normal_jump(_target: Dictionary) -> void:
	# This inherited scenario expects survival. Takeshi's 9.2 m roof produces
	# a lethal fall; the low shop roof exercises the intended nonlethal case.
	await super.normal_jump(CATALOG.find("harbor_ammunation"))

func approach_owner(target: Dictionary) -> bool:
	if not await super.approach_owner(target): return false
	if str(target.id)!="harbor_ammunation": return true
	var runtime = world.session.service_roofs
	# The real player must contact the ladder itself before the masonry behind
	# it. A wall alone would not prove the visible ladder has physical coverage.
	world.player.automatic_direction = runtime.access_frame*Vector3.BACK
	for frame in 30: await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var ladder_contact := false
	for index in world.player.get_slide_collision_count():
		var collider = world.player.get_slide_collision(index).get_collider()
		if collider is Node and runtime.access_visual.is_ancestor_of(collider): ladder_contact = true
	check(ladder_contact,"real player sweep is blocked by the wall ladder's own collider")
	if not check(await walk(runtime.access_point),"player can retreat from the solid ladder"): return false
	var reverse: Array[Vector3] = runtime.access_route.duplicate()
	reverse.reverse()
	for waypoint: Vector3 in reverse:
		if not check(await walk(waypoint),"Vance approach follows physical side aisle"): return false
	var service_point: Vector3 = world.session.room.interaction_points.service
	if not check(await walk(service_point),"walks to Vance service across clear customer floor"): return false
	var action: Dictionary = world.session.nearest()
	if not check(action.get("id","")=="service" and action.get("label","")=="Falar com Vance","Vance interaction remains discoverable"): return false
	if not check(await world.session.interact(),"Vance real service interaction succeeds"): return false
	check(world.session.storefronts.is_open() and is_instance_valid(world.session.storefronts.ammunation),"real Ammu-Nation catalog opens")
	await photo("harbor_ammunation-catalog")
	world.session.close_menu()
	check(not world.session.modal and not world.session.storefronts.is_open() and not world.player.input_locked,"closing catalog returns movement control")
	for waypoint: Vector3 in runtime.access_route:
		if not check(await walk(waypoint),"catalog departure follows physical side aisle"): return false
	if not check(await walk(runtime.access_point),"catalog departure returns to roof access"): return false
	return check(runtime.nearest_action().get("id","")=="service_roof_stairs","roof access remains usable after catalog")
