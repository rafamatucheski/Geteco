extends SceneTree
## Short rendered integration check. It records no benchmark and requires no-save.

var world: Node3D
var failures: Array[String] = []
var peak_sfx_db := -200.0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		push_error("VEHICLE_AUDIO_VALIDATION requires a rendered display")
		quit(2)
		return
	if "--no-save" not in arguments or "--skip-arrival" not in arguments:
		push_error("VEHICLE_AUDIO_VALIDATION requires --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play \
			and is_instance_valid(world.production.world_audio) and world.production.vehicles.size() >= 8:
			break
	_check(world.session != null and world.session.ready_for_play, "production world reaches playable state")
	if not world.session.ready_for_play:
		await _finish()
		return
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	var audio: Node = world.production.world_audio
	var mixer: Node = audio.vehicle_ambience
	_check(is_instance_valid(mixer), "WorldAudio installs nearby vehicle mixer")
	# Arrival can put Dante beyond the 45 m mixer radius of all traffic cars.
	# Sample actual moving production cars with a dedicated nearby listener.
	var nearby_listener := Node3D.new()
	world.add_child(nearby_listener)
	for candidate in world.production.vehicles:
		if is_instance_valid(candidate) and candidate.traffic and candidate.health > 0:
			nearby_listener.global_position = candidate.global_position + Vector3(4.0, 0.04, 0.0)
			break
	mixer.configure(world, nearby_listener)
	await _sample_frames(180)
	var on_foot: Dictionary = mixer.snapshot()
	_check(on_foot.audible > 0 and on_foot.audible <= 6, "nearby production traffic is spatially audible on foot")
	_check(on_foot.playing_voices > 0 and on_foot.playing_voices <= 12, "production voice ceiling")
	_check(_players_match_budget(mixer), "production voices use 45 m range, 8 m unit size and traffic level")

	var target := _vehicle_by_id(int(on_foot.audible_ids[0]) if not on_foot.audible_ids.is_empty() else 0)
	if is_instance_valid(target):
		var states: Dictionary = mixer.get("_states")
		var original_speed := float(target.speed)
		var original_traffic := bool(target.traffic)
		var original_controlled := bool(target.controlled)
		var original_external := bool(target.external_input)
		target.traffic = false
		target.controlled = true
		target.external_input = true
		for frame in 24:
			target.speed = 0.0
			target.throttle_input = 0.0
			await process_frame
		var idle_rpm := float(states[target.get_instance_id()].rpm) if states.has(target.get_instance_id()) else 0.0
		var accelerated_rpm := idle_rpm
		for frame in 45:
			target.speed = maxf(4.0, float(target.max_forward_speed) * 0.75)
			target.throttle_input = 1.0
			await process_frame
			if states.has(target.get_instance_id()):
				accelerated_rpm = maxf(accelerated_rpm, float(states[target.get_instance_id()].rpm))
		_check(accelerated_rpm > idle_rpm + 0.2, "nearby engine mix follows acceleration/speed")
		target.engine_disabled = true
		await _sample_frames(12)
		_check(target.get_instance_id() not in mixer.snapshot().audible_ids, "disabled nearby engine stops")
		target.engine_disabled = false
		target.speed = original_speed
		target.traffic = original_traffic
		target.controlled = original_controlled
		target.external_input = original_external
	else:
		_check(false, "selected production vehicle remains available")
	mixer.configure(world, world.player)

	var first_car: CharacterBody3D = world.driving.car
	var entered := await _enter_starting_car(first_car)
	_check(entered, "real Driving contract enters starting vehicle")
	if entered:
		for frame in 120:
			if first_car.controlled and not world.driving.is_body_transition_active(): break
			await process_frame
		_check(first_car.controlled, "boarding transition completes before acceleration")
		var entry_position: Vector3 = first_car.global_position
		var entry_yaw: float = first_car.rotation.y
		await _sample_frames(15)
		_check(first_car.get_instance_id() not in mixer.snapshot().audible_ids, "occupied car leaves nearby pool")
		var foreground_voices := _foreground_voice_count(audio)
		_check(foreground_voices > 0 and foreground_voices <= 2, "occupied car uses a bounded foreground engine")
		for layer in audio.layers:
			_check(layer is AudioStreamPlayer and layer.bus == &"SFX", "foreground engine uses the SFX bus without camera attenuation")
		var original_radio := int(audio.radio_index)
		audio._cycle_radio(1)
		var next_radio := int(audio.radio_index)
		audio._cycle_radio(-1)
		_check(next_radio != original_radio and int(audio.radio_index) == original_radio, "radio next/previous retain the off slot")
		first_car.external_input = true
		var peak_speed := 0.0
		for frame in 90:
			first_car.throttle_input = 1.0
			first_car.brake_input = false
			await physics_frame
			peak_speed = maxf(peak_speed, absf(float(first_car.speed)))
			_sample_peak()
		_check(peak_speed > 0.5, "foreground motor validated while accelerating")
		_check(float(audio.engine_rpm) > 0.15, "V1 foreground RPM follows the driven car")
		_check(audio.road_audio.playing and audio.road_audio.stream.loop_end == 22050,
			"V1 road noise follows speed and loops without guard samples")
		first_car.engine_disabled = true
		await _sample_frames(4)
		_check(_foreground_voice_count(audio) == 0, "disabled occupied engine is silent")
		first_car.engine_disabled = false
		first_car.speed = 0.0
		first_car.throttle_input = 0.0
		first_car.brake_input = true
		first_car.external_input = false
		first_car.place(entry_position, entry_yaw)
		await _sample_frames(4)
		var left: bool = world.driving.leave()
		_check(left, "real Driving contract exits stopped vehicle")
		if left:
			for frame in 120:
				if not world.driving.occupied and not world.driving.is_body_transition_active(): break
				await process_frame
			var second_car: CharacterBody3D
			for candidate in world.production.vehicles:
				if is_instance_valid(candidate) and candidate != first_car and candidate.health > 0:
					second_car = candidate
					break
			_check(is_instance_valid(second_car), "second production vehicle exists for bank switch")
			if is_instance_valid(second_car):
				# Exercise the sound ownership change directly. Boarding itself was
				# verified above; a second physical entry is unrelated to audio.
				world.driving.car = second_car
				world.driving.occupied = true
				second_car.controlled = true
				second_car.traffic = false
				await _sample_frames(12)
				_check(audio.engine_car == second_car and audio.engine_archetype == str(second_car.archetype),
					"foreground bank follows the new vehicle family")
				_check(second_car.get_instance_id() not in mixer.snapshot().audible_ids,
					"newly occupied vehicle is not duplicated")
				# Exercise the V1 one-shot routes with imported samples. Traffic and
				# the foreground engine are already covered in the real drive above.
				audio.family = "bus"
				audio.engine_gear = 2
				audio.engine_load = 0.8
				audio.engine_rpm = 0.6
				audio.engine_fx_cooldown = 0.0
				audio._update_vehicle_foley(second_car, {}, 0.6, 0.8, 1)
				_check(audio.shift_audio.playing and "turbo_shift" in audio.shift_audio.stream.resource_path,
					"V1 heavy turbo shift plays")
				audio.engine_was_moving_fast = true
				second_car.speed = 0.0
				audio._update_vehicle_foley(second_car, {}, 0.0, 0.0, 2)
				_check(audio.air_brake_audio.playing, "V1 air brake plays after heavy vehicle stops")
				audio.family = "sport"
				audio.engine_gear = 1
				audio.engine_turbo_pressure = 0.8
				audio.engine_last_throttle = 0.9
				audio.engine_fx_cooldown = 0.0
				audio._update_vehicle_foley(second_car, {"turbo_audio": true}, 0.6, 0.0, 1)
				_check(audio.shift_audio.playing and "sport_blowoff" in audio.shift_audio.stream.resource_path,
					"V1 sport turbo release plays")
	print("VEHICLE_AUDIO_RENDERED snapshot=", on_foot, " peak_sfx_db=", peak_sfx_db)
	await _finish()


func _players_match_budget(mixer: Node) -> bool:
	var found := false
	for slot in mixer.get("_slots"):
		for player in slot.players:
			if not player.playing:
				continue
			found = true
			if not is_equal_approx(player.max_distance, 45.0) or not is_equal_approx(player.unit_size, 8.0):
				return false
			if player.volume_db > -23.9:
				return false
	return found


func _foreground_voice_count(audio: Node) -> int:
	var count := 0
	for player in audio.layers:
		if player.playing:
			count += 1
	return count


func _vehicle_by_id(id: int) -> CharacterBody3D:
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and vehicle.get_instance_id() == id:
			return vehicle
	if is_instance_valid(world.dispatch):
		for unit in world.dispatch.units:
			if is_instance_valid(unit.vehicle) and unit.vehicle.get_instance_id() == id:
				return unit.vehicle
	return null


func _enter_starting_car(car: CharacterBody3D) -> bool:
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	if route == null:
		return false
	var distance := route.get_closest_offset(car.position)
	for attempt in 16:
		var probe := fposmod(distance + attempt * 6.0, route.get_baked_length())
		var point := route.sample_baked(probe, true)
		var direction := route.sample_baked(minf(probe + 1.0, route.get_baked_length()), true) - point
		var yaw := atan2(-direction.x, -direction.z)
		if not world.production.vehicle_position_clear(car, point + Vector3.UP * 0.12, yaw):
			continue
		car.traffic = false
		car.place(point + Vector3.UP * 0.12, yaw)
		for side in [-1, 1]:
			var approach := car.to_global(Vector3(side * (car.half_width + 0.65), 0.04, 0.15))
			if not world.session.position_clear(approach):
				continue
			world.player.teleport(approach)
			await physics_frame
			if world.driving.interact():
				return true
	return false


func _sample_frames(count: int) -> void:
	for frame in count:
		await process_frame
		_sample_peak()


func _sample_peak() -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0:
		bus = 0
	peak_sfx_db = maxf(peak_sfx_db, AudioServer.get_bus_peak_volume_left_db(bus, 0))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _finish() -> void:
	if is_instance_valid(world):
		world.queue_free()
		for frame in 12:
			await process_frame
	if failures.is_empty():
		print("VEHICLE_AUDIO_RENDERED: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("VEHICLE_AUDIO_RENDERED failures: ", failures)
		quit(1)
