extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var travel := root.get_node("RegionTravel")
	for bad in [[INF,0], [NAN,0], [987654321.0,-900], [null,10], ["100",200], [1]]:
		check(not travel.valid_saved_point(bad), "reject " + str(bad))
		var state := {"world": {"region":"harbor", "vehicle":{"x":bad[0],"y":900}}, "player":{"position":bad,"money":3200,"personal_car_state":{"position":bad,"paint":"ff9922","health":73}}}
		var original := state.duplicate(true)
		var copy := state.duplicate(true)
		check(not travel.sanitize_saved_coordinates(copy).is_empty(), "recovery reported")
		check(copy.player.position == [1700.0,1130.0], "Harbor authored arrival")
		check(copy.player.money == 3200 and copy.player.personal_car_state.health == 73 and copy.player.personal_car_state.paint == "ff9922", "progress retained")
		check(not copy.player.personal_car_state.has("position"), "owned car delegates to garage bay")
		check(state.player.has("position") and state.player.personal_car_state.has("position"), "original data retained")
	for version in [1,2]:
		var state := {"world":{"region":"mountain","coordinates_version":version,"interior":"cabin","exterior_return":[NAN,4]},"player":{"position":[INF,0]}}
		travel.sanitize_saved_coordinates(state)
		check(state.player.position == ([3240.0,430.0] if version == 1 else [7540.0,-4530.0]), "regional coordinate version respected")
		check(not state.world.has("interior"), "no stale interior at outdoor recovery")
	for point in [[30000.0,30000.0],[-22000.0,32000.0],[7540.0,-4530.0]]:
		var state := {"world":{"region":"mountain","coordinates_version":2,"interior":"cabin","exterior_return":[8000,-3000]},"player":{"position":point,"personal_car_state":{"position":point}}}
		var before := state.duplicate(true)
		check(travel.sanitize_saved_coordinates(state).is_empty() and state == before,"legitimate interior/world coordinates untouched")
	for migrated in [
		{"old":[20000.0,20000.0],"safe":[777.0,1594.258]},
		{"old":[21400.0,20000.0],"safe":[1080.0,2053.672]},
		{"old":[22800.0,20000.0],"safe":[1800.0,1622.293]},
		{"old":[25800.0,20000.0],"safe":[5905.0,-1296.218]},
		{"old":[30600.0,20000.0],"safe":[5479.0,5870.0]},
		{"old":[42000.0,20000.0],"safe":[650.0,190.0]},
		{"old":[48000.0,20000.0],"safe":[2460.0,195.0]},
		{"old":[30000.0,20000.0],"safe":[1890.0,200.0]},
	]:
		var state := {"world":{"region":"harbor","interior":"old_room","exterior_return":[1200.0,500.0]},"player":{"position":migrated.old,"money":731}}
		check(not travel.sanitize_saved_coordinates(state).is_empty(),"old off-map room migration reported")
		var restored_position := Vector2(float(state.player.position[0]), float(state.player.position[1]))
		var expected_position := Vector2(float(migrated.safe[0]), float(migrated.safe[1]))
		check(restored_position.distance_to(expected_position) < 0.01 and state.player.money == 731,"old room save returns to physical aisle without losing progress")
		check(not state.world.has("interior") and not state.world.has("exterior_return"),"old room return route removed")
	var invalid_vehicle := {"world":{"region":"mountain","coordinates_version":2,"interior":"cabin","exterior_return":[INF,3],"vehicle":{"x":1e30,"y":0}},"player":{"position":[30000,30000]}}
	travel.sanitize_saved_coordinates(invalid_vehicle)
	check(not invalid_vehicle.world.has("vehicle"),"invalid driven vehicle not instantiated")
	check(invalid_vehicle.world.exterior_return == [7540.0,-4530.0] and invalid_vehicle.world.interior == "cabin", "valid interior keeps regional safe exit")
	var legacy := {"player":{"position":[1e20,0],"money":99}}
	travel.sanitize_saved_coordinates(legacy)
	check(not legacy.player.has("position") and legacy.player.money == 99,"unknown scene uses existing spawn")
	# Exercise load_game on an isolated real file; never write a player-owned slot.
	var saves := root.get_node("SaveManager")
	var old_dir: String = saves._save_dir
	saves._save_dir = OS.get_temp_dir().path_join("geteco_coord_recovery_%s" % Time.get_ticks_usec()) + "/"
	saves._save_directory_ready = false
	var path: String = saves.get_slot_path("legacy")
	var original := JSON.stringify({"save_version":1,"world":{"region":"harbor"},"player":{"position":[9e25,0],"money":777}})
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var result: Dictionary = saves.load_game("legacy")
	check(result.success and result.data.player.position == [1700.0,1130.0] and result.data.player.money == 777,"real load migrated in memory")
	check(FileAccess.get_file_as_string(path) == original,"real file byte for byte retained")
	saves.clear_pending_save()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(saves._save_dir)
	saves._save_dir = old_dir
	saves._save_directory_ready = false
	print("SAVED_COORDINATE_RECOVERY failures=",failures)
	quit(0 if failures.is_empty() else 1)
