extends "res://tests/measure_game_frame_stability.gd"
## Production downtown checkpoint. --chaos adds actual vehicle fires,
## casualties and police dispatch. Health is raised only in this diagnostic
## to keep the 30-second sample from turning into a death/loading screen.
var _subject: Node2D
var _tracking := false
var _chaos := false
var _incident_at := 0
var _incidents := 0
var _damaged_cars := 0
var _casualties := 0
var _bullets := 0
var _near_police_peak := 0
var _count_at := 0

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	if label == "warmup":
		car.global_position = Vector2(1325, 1080)
		car.rotation = PI * 0.5
		car.reset_physics_interpolation()
		current_scene.call("_walk")
		var deadline := Time.get_ticks_msec() + 8000
		while (car.get("is_driven_by_player") == true or (is_instance_valid(car.get("_boarding")) and car.get("_boarding").active)) and Time.get_ticks_msec() < deadline:
			await process_frame
		if car.get("is_driven_by_player") == true:
			push_error("Downtown checkpoint could not exit vehicle")
			quit(1)
			return
		_subject = current_scene.get_node("Player")
		_subject.global_position = Vector2(1325, 1250)
		_subject.reset_physics_interpolation()
		_subject.get_node("Camera").reset_smoothing()
		_subject.health = 100000
		node_added.connect(_count_bullet)
	else:
		Input.action_release("move_up")
		_tracking = true
		_chaos = OS.get_cmdline_user_args().has("--chaos") or label == "chaos"
		_incident_at = Time.get_ticks_msec() + 1000
	await super._sample(output, label, seconds, _subject)
	_tracking = false
	var path := output.path_join(label + ".json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["checkpoint"] = "downtown"
	data["diagnostic_player_health"] = 100000
	data["player_health_end"] = _subject.health
	data["player_position_end"] = str(_subject.global_position)
	data["vehicle_fires_triggered"] = _damaged_cars
	data["casualties_triggered"] = _casualties
	data["bullets_spawned"] = _bullets
	data["police_near_700_peak"] = _near_police_peak
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data, "\t"))
	if label != "warmup" and (_subject.get("is_dead") == true or paused):
		push_error("Downtown sample interrupted by death/pause")
		quit(1)

func _count_bullet(node: Node) -> void:
	if _tracking and node.get_script() == preload("res://guns/Bullet.gd"):
		_bullets += 1

func _report_render() -> void:
	super._report_render()
	if not _tracking: return
	var now := Time.get_ticks_msec()
	if now >= _count_at:
		_count_at = now + 250
		var nearby := 0
		for unit in get_nodes_in_group("emergency_vehicle"):
			if unit.visible and unit.type == 0 and unit.global_position.distance_to(_subject.global_position) < 700.0:
				nearby += 1
		_near_police_peak = maxi(_near_police_peak, nearby)
	if not _chaos or _incidents >= 3 or now < _incident_at: return
	_incident_at = now + 8000
	_incidents += 1
	for vehicle in get_nodes_in_group("modern_traffic"):
		var distance: float = vehicle.global_position.distance_to(_subject.global_position)
		if distance < 180 or distance > 700 or vehicle.is_broken: continue
		vehicle.take_damage(1000, true)
		_damaged_cars += 1
		break
	for person in get_nodes_in_group("pedestrian"):
		if not person.has_method("take_damage") or person.get_meta("matrix_casualty", false): continue
		if person.get("is_dead") == true or person.get("is_incapacitated") == true: continue
		if person.global_position.distance_to(_subject.global_position) > 600: continue
		person.set_meta("matrix_casualty", true)
		person.take_damage(95, true)
		_casualties += 1
		break
