extends SceneTree

# Exercise real crime/death logic; omit only presentation and service dispatch.
class Civilian extends AnimatedPedestrian3D:
	var ambulance_calls := 0
	var coroner_calls := 0
	func _ready() -> void: set_physics_process(false)
	func panic() -> void: pass
	func _drop_cash_loot() -> void: pass
	func _create_3d_blood_puddle() -> void: pass
	func _start_decay() -> void: pass
	func _start_fall(_impact := Vector2.ZERO) -> void: pass
	func _play_audio(_s: AudioStream, _v: float = -6.0, _p: float = 1.0) -> void: pass
	func _dispatch_emergency_ambulance() -> void: ambulance_calls += 1
	func _dispatch_emergency_coroner() -> void: coroner_calls += 1

class Officer extends "res://police/PoliceOfficer.gd":
	func _ready() -> void: set_physics_process(false)
	func _drop_loot() -> void: pass
	func _create_3d_blood_puddle() -> void: pass
	func _spawn_blood_burst(_dir: Vector2) -> void: pass
	func _start_decay() -> void: pass
	func _start_fall(_impact := Vector2.ZERO) -> void: pass
	func _play_audio(_s: AudioStream, _v: float = -6.0, _p: float = 1.0) -> void: pass
	func _dispatch_emergency_coroner() -> void: pass

class FootPatrolProbe extends "res://world/harbor/HarborFootPatrol.gd":
	var shots := 0
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _fire_single_bullet(_point: Vector2, _damage: int, _speed: float, _spread: float) -> void: shots += 1
	func _play_audio(_stream: AudioStream, _volume: float = -6.0, _pitch: float = 1.0) -> void: pass

class DispatchProbe extends "res://police/WantedManager.gd":
	var dispatches := 0
	func _dispatch_police(): dispatches += 1

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("PASS " if ok else "FAIL ", message)

func run() -> void:
	create_timer(45.0).timeout.connect(func(): printerr("POLICE_SENSITIVITY TIMEOUT"); quit(2))
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	var probe := DispatchProbe.new()
	root.add_child(probe)
	probe.set_process(false)
	probe.report_crime(6)
	probe._process(11.9)
	check(probe.current_stars == 0 and probe.dispatches == 0, "One minor incident causes no pursuit")
	probe._process(0.2)
	check(probe.crime_points == 0, "Minor incident expires after 12 seconds")
	probe.report_crime(6)
	probe.report_crime(6)
	check(probe.current_stars == 1, "Repeated minor incidents earn one star")
	probe._process(5.9)
	check(probe.dispatches == 0, "First response waits six seconds")
	probe._process(0.2)
	check(probe.dispatches == 1, "First response arrives after the delay")
	probe._process(9.9)
	check(probe.dispatches == 1, "Low-level reinforcements are spaced out")
	probe._process(0.2)
	check(probe.dispatches == 2, "Reinforcements still arrive during pursuit")
	probe.reset_crime()
	probe.report_crime(20)
	check(probe.current_stars == 1, "Civilian fatality or reported car theft starts at one star")
	probe.report_crime(20)
	check(probe.current_stars == 2, "Repeated serious crimes escalate")
	probe.ensure_minimum_wanted_level(4)
	check(probe.current_stars == 4, "Mission minimum wanted level survives rebalance")
	probe.decrease_stars(2)
	probe.report_crime(1)
	check(probe.current_stars == 2, "A minor incident cannot immediately restore lost stars")
	probe.reset_crime()
	probe.report_crime(-20)
	check(probe.crime_points == 0, "Invalid negative severity is ignored")
	probe.restore({"current_stars": 2, "crime_points": 18})
	check(probe.current_stars == 2 and probe.crime_points >= 30 and probe.police_spawn_timer > 0, "Old save retains stars and receives response delay")
	probe.restore({"current_stars": 0, "crime_points": 200})
	probe._process(12.1)
	check(probe.current_stars == 0 and probe.crime_points == 0, "Stale saved score cannot restart a cleared pursuit")
	for player_caused in [false, true]:
		for fatal in [false, true]:
			wanted.reset_crime()
			var civilian := Civilian.new()
			root.add_child(civilian)
			civilian.get_run_over(Vector2(300 if fatal else 120, 0), player_caused)
			check(wanted.crime_points == ((20 if fatal else 6) if player_caused else 0), "Vehicle casualty attribution: player=%s fatal=%s" % [player_caused, fatal])
			check(civilian.coroner_calls == int(fatal) and civilian.ambulance_calls == int(not fatal), "Medical response still matches casualty severity")
			civilian.get_run_over(Vector2(300, 0), true)
			check(wanted.crime_points == ((20 if fatal else 6) if player_caused else 0), "Same casualty is not counted twice")
			civilian.free()
		wanted.reset_crime()
		var victim := Civilian.new()
		root.add_child(victim)
		victim.take_damage(1000, player_caused)
		check(wanted.crime_points == (20 if player_caused else 0), "Civilian gunfire death attribution: player=%s" % player_caused)
		victim.free()
		for vehicle_hit in [false, true]:
			wanted.reset_crime()
			var officer := Officer.new()
			root.add_child(officer)
			if vehicle_hit: officer.get_run_over(Vector2(300, 0), player_caused)
			else: officer.take_damage(1000, player_caused)
			check(wanted.crime_points == (60 if player_caused else 0), "Officer casualty attribution: player=%s vehicle=%s" % [player_caused, vehicle_hit])
			officer.free()
	wanted.reset_crime()
	var actor := CharacterBody2D.new()
	actor.add_to_group("player")
	actor.position = Vector2(40, 0)
	root.add_child(actor)
	var patrol = load("res://world/harbor/HarborFootPatrol.gd").new()
	root.add_child(patrol)
	patrol.set_physics_process(false)
	await physics_frame
	wanted.report_crime(6)
	check(not patrol.alerted, "Nearby foot patrol ignores a single minor incident")
	wanted.report_crime(6)
	check(patrol.alerted, "Nearby foot patrol responds to repeated incidents in sight")
	patrol.free()
	wanted.reset_crime()
	actor.position = Vector2(600, 0)
	var street_patrol := FootPatrolProbe.new()
	root.add_child(street_patrol)
	street_patrol.set_physics_process(false)
	await physics_frame
	wanted.ensure_minimum_wanted_level(2)
	check(not street_patrol.alerted, "Street patrol does not detect a wanted suspect outside sight range")
	actor.position = Vector2(400, 0)
	street_patrol._physics_process(0.26)
	check(street_patrol.alerted and street_patrol.target == actor, "Street patrol joins an existing pursuit when the wanted suspect enters sight")
	actor.position = Vector2(180, 0)
	street_patrol._physics_process(0.7)
	check(street_patrol.shots > 0, "Street patrol uses armed response against a visible two-star suspect")
	street_patrol.free()
	actor.free()
	for scene_path in ["res://characters/PlayerCar.gd", "res://cars/traffic/TrafficVehicle.tscn", "res://emergency/EmergencyVehicle.tscn"]:
		for player_caused in [false, true]:
			wanted.reset_crime()
			var car: Node2D
			if scene_path.ends_with(".gd"):
				car = load(scene_path).new()
				var camera := Camera2D.new()
				camera.name = "Camera"
				car.add_child(camera)
				var interact := Area2D.new()
				interact.name = "InteractArea"
				car.add_child(interact)
			else:
				car = load(scene_path).instantiate()
			root.add_child(car)
			car.set_physics_process(false)
			var victim := Civilian.new()
			victim.add_to_group("damageable")
			root.add_child(victim)
			victim.position = car.position + Vector2(40, 0)
			victim.health = 50 # Preserve homicide-attribution coverage after the vehicle-blast damage reduction.
			car.take_damage(1000, player_caused)
			car._explode()
			check(victim.is_dead and wanted.crime_points == (20 if player_caused else 0), "Vehicle explosion preserves attribution: %s player=%s" % [scene_path, player_caused])
			victim.free()
			car.free()
	wanted.reset_crime()
	probe.free()
	print("POLICE_SENSITIVITY ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
