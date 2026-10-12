extends "res://tests/measure/measure_performance_plan.gd"
## Rendered Main: normal city30s, weapon input/police response30s, recovery30s.
## Native presentation, full NPC admission and raw frame gates apply.
## Natural traffic mode records live counts without certifying the traffic cap.
const PHASE_USEC := 30000000
var _phases: Array[Dictionary] = []
var _phase: Dictionary = {}
var _phase_frames: Array[float] = []
var _previous := 0
var _next_snapshot := 0
var _next_aim := 0
var _finished := false
var _invalid: Array[String] = []
var _actions: Array[Dictionary] = []
var _shots_at_open := 0
var _weapon := ""
var _natural_traffic_diagnostic := false

func run() -> void:
	# Fixed-population runs require --no-density. The explicit area-policy
	# comparison opts into authored density and records the resulting live caps.
	if not "--no-density" in OS.get_cmdline_user_args() and not "--area-density-comparison" in OS.get_cmdline_user_args():
		push_error("HEART_MEASURE_REQUIRES_NO_DENSITY: preserve the full population and traffic targets")
		quit(2)
		return
	if "--profile" in OS.get_cmdline_user_args():
		quit(7)
		return
	seconds = 92.0
	_natural_traffic_diagnostic = "--natural-traffic-diagnostic" in OS.get_cmdline_user_args()
	await super.run()
	_close_input()
	var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join(label+".json")))
	if not str(parent.get("invalid", "")).is_empty(): _invalid.append(str(parent.invalid))
	if _phases.size() != 3: _invalid.append("three_complete_phases_required")
	FileAccess.open(output.path_join(label+"-chaos.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"invalid":_invalid,"phases":_phases,"actions":_actions,
		"configuration":parent.get("configuration",{}),"native_presentation":parent.get("native_presentation",{}),
		"natural_traffic_diagnostic":_natural_traffic_diagnostic,
		"population_policy":"authored_area_and_emergency" if "--area-density-comparison" in OS.get_cmdline_user_args() else "fixed_full_targets",
		"full_traffic_capacity_certified":not _natural_traffic_diagnostic,
		"scope":"Normal rendered Main with live production and unchanged population/traffic targets. Full NPC admission is required; natural traffic mode records actual admitted counts and does not certify traffic-cap replenishment. Scene placement is a setup fixture; measured combat uses the normal fire input, ammo, reload, projectiles, damage, wanted, police and emergency systems. Setup grants weapons and invulnerability; this is a performance diagnostic, not acceptance of normal survival. Targets are existing vehicles/people; none are spawned, frozen, healed or removed by the runner. First attack and weapon switches remain in combat statistics. Recovery releases fire and preserves wanted/cleanup. No highway driving/collision route or other map is certified. Phases contain disjoint complete frame intervals, including phase-boundary observer costs; snapshots every5s."},"\t"))
	print("HEART_CHAOS ",JSON.stringify({"invalid":_invalid,"phases":_phases.size(),"shots":shots}))
	if not _invalid.is_empty(): quit(7)

func settle_load() -> bool:
	scenario = "idle"
	# Explicit separate diagnostic of the naturally admitted traffic. This does
	# not change targets or freeze/remove cars, and does not certify the traffic
	# target's replenishment. Full NPC admission and native FPS gates still apply.
	var settled: bool = await _settle_natural_traffic() if _natural_traffic_diagnostic else await super.settle_load()
	if not settled: return false
	world.gameplay.toggle_god_mode()
	world.gameplay.activate_arsenal_cheat()
	world.gameplay.weapon_fired.connect(func(_id: String,_point: Vector3): shots += 1)
	return true

func _settle_natural_traffic() -> bool:
	var began := Time.get_ticks_usec()
	var next_probe := began
	while Time.get_ticks_usec()-began < 90000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now < next_probe: continue
		next_probe = now+1000000
		var row := state()
		row["settling_t"] = float(now-began)/1000000.0
		settling_states.append(row)
		if now-began >= 40000000 and row.people >= row.population_cap and row.ambient_traffic > 0 and row.streaming_idle:
			settling_seconds = float(now-began)/1000000.0
			settled_state = row
			return true
	settling_seconds = float(Time.get_ticks_usec()-began)/1000000.0
	return false

func apply_load(now: int) -> void:
	if _finished: return
	if _phase.is_empty():
		if frames.is_empty(): return
		_open_phase(now)
	else:
		_phase_frames.append(float(now-_previous)/1000.0)
		_previous = now
		if not DisplayServer.window_is_focused(): _invalid.append("focus_lost")
		if now-int(_phase.start_usec) >= PHASE_USEC:
			_close_phase(now)
			if _phases.size() == 3:
				_finished = true
				_close_input()
				return
			_open_phase(now)
		elif now >= _next_snapshot:
			_next_snapshot = now+5000000
			_phase.snapshots.append({"engine_usec":now,"state":state()})
	if _phase.name != "combat": return
	var elapsed := now-int(_phase.start_usec)
	var desired := "ak47" if elapsed < 12000000 or elapsed >= 22000000 else "rpg"
	if _weapon != desired:
		_weapon = desired
		world.session.state.equip_weapon(desired)
		_actions.append({"engine_usec":now,"frame":Engine.get_process_frames(),"action":"equip","weapon":desired})
	if now >= _next_aim:
		_next_aim = now+200000
		_aim_at_existing_target()
	Input.action_press("fire")

func _aim_at_existing_target() -> void:
	var origin: Vector3 = world.player.global_position
	var target := origin+Vector3(8,0,-2)
	var distance := 45.0*45.0
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle) or vehicle == world.driving.car or vehicle.health <= 0: continue
		var gap: float = origin.distance_squared_to(vehicle.global_position)
		if gap < distance:
			distance = gap
			target = vehicle.global_position
	for person in world.people:
		if not is_instance_valid(person) or person.dead: continue
		var gap: float = origin.distance_squared_to(person.global_position)
		if gap < distance:
			distance = gap
			target = person.global_position
	var direction := target-origin
	direction.y = 0.0
	if direction.length_squared() < .001: return
	direction = direction.normalized()
	var right: Vector3 = world.camera.global_basis.x
	var back: Vector3 = world.camera.global_basis.z
	right.y = 0.0
	back.y = 0.0
	root.get_node("GameInput").touch_aim = Vector2(direction.dot(right.normalized()),direction.dot(back.normalized()))

func _open_phase(now: int) -> void:
	_phase = {"name":["normal","combat","recovery"][_phases.size()],"start_usec":now,
		"state_start":state(),"physics_start":Engine.get_physics_frames(),"snapshots":[]}
	_shots_at_open = shots
	_previous = now
	_next_snapshot = now+5000000
	_phase_frames.clear()
	if _phase.name == "recovery": _close_input()

func _close_phase(now: int) -> void:
	_phase["end_usec"] = now
	_phase["frames_ms"] = _phase_frames.duplicate()
	_phase["summary"] = super.stats(_phase_frames)
	_phase["state_end"] = state()
	_phase["shots"] = shots-_shots_at_open
	_phase["physics_ticks"] = Engine.get_physics_frames()-int(_phase.physics_start)
	_phases.append(_phase)
	_phase = {}

func _close_input() -> void:
	Input.action_release("fire")

func _finalize() -> void:
	_close_input()
