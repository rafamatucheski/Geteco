extends SceneTree

class Suspect extends CharacterBody2D:
	var fire_cooldown := 0.0
	var is_dead := false
	var is_control_disabled := false
	var arrests := 0
	var health := 80
	func arrest_and_respawn() -> void: arrests += 1
	func take_damage(amount: int, _player_attacker := false) -> void: health -= amount

class EscapeCar extends CharacterBody2D:
	var is_driven_by_player := true

class Depot extends Node2D:
	var dispatches := 0
	func request_dispatch(_kind: String, _target: Node2D, _urgent: bool) -> Node2D:
		dispatches += 1
		var unit := Node2D.new()
		add_child(unit)
		return unit

class ArmedOfficer extends "res://PoliceOfficer.gd":
	func _ready() -> void: set_physics_process(false)

class Officer extends "res://PoliceOfficer.gd":
	var shots := 0
	func _ready() -> void:
		add_to_group("police_officer")
		set_physics_process(false)
	func _fire_single_bullet(_point: Vector2, _damage: int, _speed: float, _spread: float) -> void: shots += 1
	func _play_audio(_stream: AudioStream, _volume: float = -6.0, _pitch: float = 1.0) -> void: pass
	func _drop_loot() -> void: pass
	func _start_fall(_impact := Vector2.ZERO) -> void: pass
	func _create_3d_blood_puddle() -> void: pass
	func _dispatch_emergency_coroner() -> void: pass
	func _start_decay() -> void: pass

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func run() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("POLICE_ESCALATION_SEARCH TIMEOUT"); quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	var suspect := Suspect.new()
	suspect.add_to_group("player")
	suspect.position = Vector2(180, 0)
	scene.add_child(suspect)
	var officer := Officer.new()
	scene.add_child(officer)
	officer.target = suspect
	await physics_frame
	wanted.ensure_minimum_wanted_level(1)
	check(wanted.get_max_active_units() == 2, "One star allows two units")
	officer._physics_process(0.7)
	check(officer.shots == 0 and officer.arrest_warning_given, "One star gives surrender warning before force")
	suspect.velocity = Vector2(100, 0)
	for index in 7: officer._physics_process(1.0)
	check(wanted.current_stars == 2, "Prolonged visible flight after warning escalates to two stars")
	check(officer.shots > 0, "Two stars actively engages an unarmed fleeing suspect")
	check(not officer._can_arrest_target(), "Combat response does not arrest while firing")
	var before := officer.shots
	officer.fire_cooldown = 0.0
	officer.burst_pause = 2.0
	officer._physics_process(0.1)
	check(officer.shots == before, "Burst pause provides a retaliation and escape window")
	var car := EscapeCar.new()
	car.add_to_group("vehicle")
	car.position = Vector2(160, 0)
	car.velocity = Vector2(80, 0)
	scene.add_child(car)
	officer.fire_cooldown = 0.0
	officer.burst_pause = 0.0
	officer._physics_process(0.7)
	check(officer.target == car and officer.shots > before, "Armed response shoots a moving escape car in sight")
	car.free()
	officer.position = Vector2.ZERO
	suspect.position = Vector2(180, 0)
	wanted.report_visual_contact(officer)
	var known: Vector2 = suspect.position
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 400)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(90, 0)
	scene.add_child(wall)
	await physics_frame
	check(not wanted.report_visual_contact(officer), "Solid wall blocks reacquisition")
	suspect.position = Vector2(220, 60)
	wanted.police_spawn_timer = 100.0
	wanted._process(1.2)
	check(wanted.is_searching() and wanted.get_pursuit_target().global_position == known, "Search freezes at last witnessed position behind cover")
	before = officer.shots
	officer._physics_process(1.0)
	check(officer.shots == before, "No shooting at a search marker through walls")
	wanted.time_hidden = wanted.get_escape_duration() - 0.1
	wanted._process(0.2)
	check(wanted.current_stars == 0, "Sustained loss of contact clears pursuit")
	wall.free()
	wanted.reset_crime()
	officer.take_damage(1000, false)
	check(wanted.current_stars == 0, "Non-player officer death does not implicate player")
	var victim := Officer.new()
	scene.add_child(victim)
	victim.take_damage(1000, true)
	check(wanted.current_stars == 3, "Killing a police officer immediately sets minimum three stars")
	wanted.ensure_minimum_wanted_level(5)
	check(wanted.get_max_active_units() == 5, "Five stars escalates to the five-vehicle maximum")
	wanted.reset_crime()
	var depot := Depot.new()
	depot.add_to_group("emergency_depot_director")
	scene.add_child(depot)
	wanted.ensure_minimum_wanted_level(1)
	for index in 12: wanted._dispatch_police()
	check(depot.dispatches == 4 and wanted.deployed_this_pursuit == 4, "Defeating units cannot cause unlimited reinforcements in one pursuit")
	wanted.ensure_minimum_wanted_level(3)
	check(wanted.can_request_reinforcements() and wanted.deployed_this_pursuit == 4, "Escalation expands the budget without erasing previous deployments")
	var saved: Dictionary = wanted.serialize()
	wanted.restore(saved)
	check(wanted.deployed_this_pursuit == 4, "Save and reload preserves spent reinforcements")
	wanted.reset_crime()
	wanted.ensure_minimum_wanted_level(1)
	wanted._dispatch_police()
	check(wanted.deployed_this_pursuit == 1 and depot.dispatches == 5, "A new pursuit receives a fresh finite budget")
	wanted.reset_crime()
	wanted.ensure_minimum_wanted_level(3)
	wanted._dispatch_police()
	check(depot.dispatches == 6, "Initial response still leaves the precinct")
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(-1600, 0))
	lane.curve.add_point(Vector2(1600, 0))
	lane.add_to_group("unified_traffic_lane")
	scene.add_child(lane)
	wanted._dispatch_police()
	check(depot.dispatches == 6 and wanted.deployed_this_pursuit == 2, "Higher-level reinforcements use a nearby regional patrol before a distant precinct")
	var regional: Node2D
	for unit in get_nodes_in_group("emergency_vehicle"):
		if unit.visible and unit.get_meta("police_player_pursuit", false): regional = unit
	check(regional != null and absf(regional.position.y) < 1.0 and regional.position.distance_to(suspect.position) >= 520.0, "Regional patrol appears on a safe road at least 520 units away")
	if regional: regional._deactivate()
	lane.free()
	wanted._dispatch_police()
	check(depot.dispatches == 7, "Without a safe regional lane reinforcements fall back to precinct dispatch")
	wanted.reset_crime()
	# Exercise the actual Bullet scene and collision path, in addition to AI decisions.
	var gunner := ArmedOfficer.new()
	scene.add_child(gunner)
	suspect.position = Vector2(180, 0)
	suspect.velocity = Vector2.ZERO
	var suspect_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	suspect_shape.shape = circle
	suspect.add_child(suspect_shape)
	await physics_frame
	gunner._fire_single_bullet(suspect.position, 8, 1200.0, 0.0)
	for frame in 20: await physics_frame
	check(suspect.health == 72, "Real police projectile reaches and damages a visible suspect")
	var cover := StaticBody2D.new()
	var cover_shape := CollisionShape2D.new()
	cover_shape.shape = shape
	cover.add_child(cover_shape)
	cover.position = Vector2(90, 0)
	scene.add_child(cover)
	await physics_frame
	gunner._fire_single_bullet(suspect.position, 8, 1200.0, 0.0)
	for frame in 20: await physics_frame
	check(suspect.health == 72, "Real police projectile collides with cover before the suspect")
	scene.queue_free()
	await process_frame
	print("POLICE_ESCALATION_SEARCH ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
