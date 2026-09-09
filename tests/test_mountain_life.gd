extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	for i in 10: await physics_frame
	var scene := current_scene
	var player: Node2D = scene.player_instance
	player.set_physics_process(false)
	var weather: Node = scene.storm_manager
	weather.dynamic_weather = false
	weather.weather_clock = 0
	weather.advance_weather(0)
	check(weather.storm_intensity == 0, "clear interval between snow fronts")
	weather.advance_weather(110)
	check(weather.storm_intensity > 0.7, "front builds into heavy weather")
	weather.set_sheltered(true)
	weather.advance_weather(30)
	check(not weather.hail_particles.emitting and not weather.snow_blizzard_particles.emitting and not weather.visible, "changing front cannot emit inside shelter")
	weather.advance_weather(100)
	check(weather.storm_intensity == 0, "front fades back to calm")
	check(get_nodes_in_group("winter_resident").size() == 5, "five winter residents present")
	check(get_nodes_in_group("mountain_wildlife").size() == 4, "two adults and two cubs in remote forest")
	var bear: Node2D = get_nodes_in_group("mountain_wildlife")[0]
	player.global_position = bear.global_position + Vector2(20,0)
	var hp: int = player.health
	bear._physics_process(0.1)
	check(player.health < hp, "bear attack damages real player")
	var after_bite: int = player.health
	bear._physics_process(0.1)
	check(player.health == after_bite, "bite cooldown prevents per-frame damage")
	player.global_position = bear.home+Vector2(500,0)
	bear._physics_process(0.1)
	check(bear.velocity.length() <= 32, "bear stops chasing outside forest territory")
	var manager: Node = scene.interior_manager
	var cabin: Node2D = manager.cabin_interior
	var entrance: BuildingEntrance
	for door in manager._exterior_doors:
		if manager._exterior_doors[door].interior_id == &"mountain_cabin": entrance = door; break
	player.global_position = entrance.global_position+Vector2(0,24)
	for i in 4: await physics_frame
	check(entrance.request_interaction(player), "real cabin door opens")
	await create_timer(0.4).timeout
	for pickup_name in ["LegendaryRifleStation","HuntingKnifeStation"]:
		var pickup: Node2D = cabin.get_node(pickup_name)
		check(pickup.model is Node3D and pickup.model.get_node("FloorWeapon").get_child_count() >= 5, "physical modeled weapon: "+pickup_name)
		var rotation_before: float = pickup.model.rotation.y
		await create_timer(0.15).timeout
		check(pickup.model.rotation.y != rotation_before,"pickup rotates in occupied room")
		player.global_position = pickup.global_position
		for i in 5: await physics_frame
		check(pickup.collected and not pickup.model.visible, "proximity collects without E: "+pickup_name)
		check(player.world_pickups_collected.has(pickup.pickup_id) and player.weapon_inventory.get(pickup.weapon_id,false), "weapon and pickup ID granted once")
		var saved: Dictionary = player.serialize()
		player.restore(JSON.parse_string(JSON.stringify(saved)))
		check(player.world_pickups_collected.has(pickup.pickup_id),"pickup persists through JSON save")
	var saved_world: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(saved_world.get("interior","")=="mountain_cabin","save includes occupied room")
	var traffic: Node = scene.get_node("MountainTraffic") if scene.has_node("MountainTraffic") else null
	check(traffic != null and traffic.vehicles.size()==8,"mountain traffic fleet present")
	print("MOUNTAIN LIFE FAILURES: ", failures)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
