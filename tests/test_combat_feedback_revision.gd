extends SceneTree
## Regression: a vehicle has no officer muzzle rig, but its passenger must still fire.
class FakeState extends RefCounted:
	func weapons_allowed() -> bool: return true
class Target extends CharacterBody3D:
	var half_width := 1.0
	func receive_damage(_amount: float, _source: Node = null) -> void: pass
class Combat extends "res://gameplay/Gameplay.gd":
	var surrender := false
	func _ready() -> void: set_process(false); set_physics_process(false)
	func police_force_authorized() -> bool: return true
	func police_surrendering() -> bool: return surrender
	func _play_stream(_stream: AudioStream, _point: Vector3, _volume: float = 0.0, _pitch: float = 1.0, _reach: float = 0.0) -> void: pass
class AirDirector extends Node3D:
	var gameplay: Node3D
	func exterior_active() -> bool: return true
	func point_on_screen(_point: Vector3, _padding: float) -> bool: return true
class Helicopter extends "res://gameplay/police_response/air_k9/PoliceHelicopter.gd":
	func _ready() -> void: set_physics_process(false)
class DrivingHarness extends "res://scripts/Driving.gd":
	func _ready() -> void: set_physics_process(false); set_process(false)
class Stage extends Node3D:
	var people: Array = []
class Bike extends CharacterBody3D:
	var archetype := "bike_urban"
	var traffic := true
	var speed := 10.0
	var throttle_input := 1.0
	var brake_input := false
	var _motorcycle_rider_parts: Array[Node3D] = []
	func driver_seat_anchor() -> Vector3: return global_position + Vector3.UP
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var combat := Combat.new()
	combat.state = FakeState.new()
	root.add_child(combat)
	var player := Target.new()
	combat.add_child(player)
	player.position = Vector3(10,0,-8)
	combat.player = player
	var car := Target.new()
	combat.add_child(car)
	await physics_frame
	check(combat.police_vehicle_shoot(car,8.0),"passenger fires without officer visual/muzzle_position")
	check(combat._police_rounds.size() == 1,"one physical round emitted")
	var shot: Dictionary = combat._police_rounds[0]
	check(shot.point.x > car.half_width and shot.source.get_ref() == car,"shot starts outside window and keeps vehicle authorship")
	combat.surrender = true
	check(not combat.police_vehicle_shoot(car,8.0) and combat._police_rounds.size() == 1,"surrender blocks vehicle fire")
	combat.confirm_player_hit(player,10.0)
	check(combat.hitmarker_active(),"confirmed damage activates hitmarker")
	combat._combat_clock += .2
	check(not combat.hitmarker_active(),"hitmarker expires")
	player.set_meta("invulnerable",true)
	combat.confirm_player_hit(player,10.0)
	check(not combat.hitmarker_active(),"protected garage characters never confirm damage")
	var air := AirDirector.new()
	combat.add_child(air)
	air.gameplay = combat
	var helicopter := Helicopter.new()
	air.add_child(helicopter)
	helicopter.position = Vector3(0,13,0)
	helicopter.director = air
	helicopter.spotlight = SpotLight3D.new()
	helicopter.add_child(helicopter.spotlight)
	helicopter._searchlight_ready = true
	helicopter.sees_player = true
	helicopter._update_searchlight(.2)
	check(helicopter.spotlight.visible and (-helicopter.spotlight.global_basis.z).dot(helicopter.spotlight.global_position.direction_to(player.global_position)) > .99,"searchlight tracks visible target")
	player.position = Vector3(-10,0,-8)
	helicopter._update_searchlight(.2)
	check((-helicopter.spotlight.global_basis.z).dot(helicopter.spotlight.global_position.direction_to(player.global_position)) > .99,"searchlight follows target movement")
	helicopter.dead = true
	helicopter._update_searchlight(.2)
	check(not helicopter.spotlight.visible,"destroyed helicopter disables searchlight")
	var setting_probe := preload("res://runtime/Settings.gd").new()
	check(not setting_probe.controller_aim_assist,"controller assistance defaults disabled")
	var settings: Node = root.get_node("V2Settings")
	var saved_assist: bool = settings.controller_aim_assist
	settings.controller_aim_assist = true
	var settings_path := "user://test-combat-assist-%d.cfg" % get_instance_id()
	check(settings.save_settings(settings_path) == OK and setting_probe.load_settings(settings_path) == OK and setting_probe.controller_aim_assist,"controller assistance persists to isolated settings file")
	settings.controller_aim_assist = saved_assist
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	setting_probe.free()
	combat.free()
	var stage := Stage.new()
	root.add_child(stage)
	var driving := DrivingHarness.new()
	driving.world = stage
	stage.add_child(driving)
	var bike := Bike.new()
	stage.add_child(bike)
	var visible_rider := Node3D.new()
	bike.add_child(visible_rider)
	bike._motorcycle_rider_parts.append(visible_rider)
	driving.motorcycle_crash(bike,Vector3(0,0,-10))
	check(not bike.traffic and bike.brake_input and not visible_rider.visible,"collision detaches traffic rider and stops autopilot")
	check(stage.people.size() == 1,"one real rider materialized")
	var rider: CharacterBody3D = stage.people[0]
	var flight: Node = rider.get_node_or_null("BodyFlight3D")
	check(flight != null and flight.ragdoll != null,"motorcycle rider uses pedestrian accident ragdoll")
	if flight != null and flight.ragdoll != null:
		var rigid: RigidBody3D = flight.ragdoll.parts[0].body
		check(not bike in rigid.get_collision_exceptions(),"impact vehicle remains solid to the ragdoll")
	var count := stage.people.size()
	driving.motorcycle_crash(bike,Vector3(0,0,-10))
	check(stage.people.size() == count,"one collision cannot duplicate the rider")
	stage.free()
	print("COMBAT_FEEDBACK_REVISION failures=",failures)
	quit(0 if failures == 0 else 1)
