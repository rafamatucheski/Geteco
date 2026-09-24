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
	var player: CharacterBody2D = scene.player_instance
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
	var outdoor_residents := get_nodes_in_group("winter_resident").filter(func(n): return n.get_parent().name in [&"MountainSettlement", &"MountainExpedition"])
	check(outdoor_residents.size() == 25, "twenty-five residents across valley and snow stops")
	for resident in get_nodes_in_group("winter_resident"):
		check(resident.is_in_group("damageable"), "resident participates in combat: " + String(resident.name))
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
	var entrance := _find_door(scene, &"mountain_cabin")
	var cabin_outside := entrance.global_position + Vector2(0, 18)
	player.global_position = cabin_outside
	for i in 4: await physics_frame
	check(await _walk(player, cabin.to_global(cabin.project_floor(Vector2(0, .5)))), "real cabin door opens while walking")
	for pickup_name in ["LegendaryRifleStation","HuntingKnifeStation","WoodAxeStation"]:
		var pickup: Node2D = cabin.get_node(pickup_name)
		check(pickup.model is Node3D and pickup.model.get_node("FloorWeapon").get_child_count() >= (3 if pickup.weapon_id == "axe" else 5), "physical modeled weapon: "+pickup_name)
		var rotation_before: float = pickup.model.rotation.y
		await create_timer(0.15).timeout
		check(pickup.model.rotation.y == rotation_before,"cabin pickup rests on the floor")
		player.global_position = pickup.global_position
		for i in 5: await physics_frame
		check(pickup.collected and not pickup.model.visible, "proximity collects without E: "+pickup_name)
		check(player.world_pickups_collected.has(pickup.pickup_id) and player.weapon_inventory.get(pickup.weapon_id,false), "weapon and pickup ID granted once")
		var saved: Dictionary = player.serialize()
		player.restore(JSON.parse_string(JSON.stringify(saved)))
		check(player.world_pickups_collected.has(pickup.pickup_id),"pickup persists through JSON save")
	var saved_world: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(not saved_world.has("interior"),"save keeps cabin world coordinates")
	check(cabin.spawn_point.position.distance_to(cabin.project_floor(Vector2(0,1.38))) < 0.1, "cabin spawn remains aligned after camera interpolation")
	var bed_polygon: PackedVector2Array = cabin.walls_body.get_node("Bed").polygon
	check(Geometry2D.is_point_in_polygon(cabin.project_floor(Vector2(-1.16,-.54)), bed_polygon), "bed collision covers the displayed bed")
	player.global_position = cabin.to_global(cabin.project_floor(Vector2(0,1)))
	check(await _walk(player,cabin_outside), "cabin exit walks back to exterior")
	var shelter_door := _find_door(scene, &"lumberjack_shelter")
	var shelter_outside := shelter_door.global_position + Vector2(0,18)
	player.global_position = shelter_outside
	for i in 4: await physics_frame
	check(await _walk(player, manager.lumberjack_interior.to_global(manager.lumberjack_interior.project_floor(Vector2(0,.5)))), "logger shelter entered on foot")
	var shelter_axe: Node2D = manager.lumberjack_interior.get_node("WoodAxeStation")
	player.global_position = shelter_axe.global_position
	for i in 5: await physics_frame
	check(shelter_axe.collected and not shelter_axe.model.visible, "lumberjack shelter axe collects by physical proximity")
	player.global_position = manager.lumberjack_interior.to_global(manager.lumberjack_interior.project_floor(Vector2(0,1)))
	check(await _walk(player,shelter_outside), "logger exit walks back to exterior")
	check(not player.get_meta("mountain_interior", false), "logger exterior restored")
	var traffic: Node = scene.get_node("MountainTraffic") if scene.has_node("MountainTraffic") else null
	check(traffic != null and traffic.vehicles.size()==8,"mountain traffic fleet present")
	print("MOUNTAIN LIFE FAILURES: ", failures)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)

func _find_door(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var found := _find_door(child,id)
		if found != null: return found
	return null

func _walk(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 300:
		var motion := target - actor.global_position
		if motion.length() < 2: return true
		if actor.move_and_collide(motion.limit_length(2.5)) != null: return false
		await physics_frame
	return false
