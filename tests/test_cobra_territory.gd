extends SceneTree

## Real physics ticks, collision LOS, actual resident damage and project bullets.
const TERRITORY := preload("res://district/harbor_preview/cobras/CobraTerritory.gd")
class Subject extends CharacterBody2D:
	var is_in_dialogue := false
	var is_control_disabled := false
	var is_dead := false
	var damage_received := 0
	func take_damage(amount: int, _player_attacker := false) -> void:
		damage_received += amount

class Reputation extends Node:
	var respect := 0
	func get_respect(_gang: String) -> int:
		return respect

class DrivenVehicle extends CharacterBody2D:
	var is_driven_by_player := true

var failures: Array[String] = []
var states: Array[String] = []
var messages: Array[String] = []
var scene: Node2D
var territory: Node2D
var subject: Subject
var reputation: Reputation

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	seed(7319)
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	subject = Subject.new()
	subject.name = "PlayerFixture"
	subject.position = Vector2(250, 200)
	subject.collision_layer = 2
	subject.collision_mask = 1
	subject.add_to_group("player")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	subject.add_child(shape)
	scene.add_child(subject)
	reputation = Reputation.new()
	reputation.add_to_group("gang_manager")
	scene.add_child(reputation)
	territory = TERRITORY.new()
	check(territory.notice_seconds >= 2.0 and territory.warning_seconds >= 5.0, "Production grace periods are long enough to read warnings")
	# Accelerate only the explicit grace-period exports, not AI or physics.
	territory.notice_seconds = 0.6
	territory.warning_seconds = 0.8
	territory.confrontation_seconds = 0.8
	territory.configure(Rect2(0, 0, 1000, 600), PackedVector2Array([Vector2(100, 200), Vector2(100, 280), Vector2(100, 360)]))
	territory.state_changed.connect(func(_previous: String, next: String): states.append(next))
	territory.warning_issued.connect(func(message: String): messages.append(message))
	scene.add_child(territory)
	await seconds(0.25)
	check(territory.state == "watch", "Brief peaceful passage is observation, not combat")
	check(subject.damage_received == 0, "No damage during peaceful passage")
	territory.guards[0].take_damage(1, false)
	check(territory.state != "combat", "Damage from another NPC is not blamed on player")
	await retreat()
	check(territory.state == "calm", "Leaving block resets exposure")
	states.clear()
	subject.position = Vector2(250, 200)
	await seconds(1.0)
	check(territory.state == "warning", "Lingering produces warning before confrontation")
	check(not messages.is_empty(), "Warning is communicated to player")
	check(subject.damage_received == 0, "Warning does not silently shoot")
	await retreat()
	check(territory.state == "calm", "Heeding warning de-escalates")
	states.clear()
	subject.position = Vector2(250, 200)
	await seconds(2.8)
	check(states == ["watch", "warning", "confrontation", "combat"], "Escalation order is visible and deterministic: %s" % [states])
	await seconds(1.2)
	check(subject.damage_received > 0, "Hostile guards fire real project bullets which reach subject")
	await retreat()
	var old_damage := subject.damage_received
	await seconds(0.8)
	check(subject.damage_received == old_damage, "Guards do not keep firing outside territory")

	# A real collision wall must suppress awareness; not a mocked visibility flag.
	var wall := StaticBody2D.new()
	wall.position = Vector2(210, 300)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30, 600)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	scene.add_child(wall)
	# Reset actual guard transforms after combat approach for deterministic wall sides.
	for index in territory.guards.size():
		territory.guards[index].position = Vector2(100, 200 + index * 80)
	subject.position = Vector2(280, 200)
	await seconds(2.8)
	check(territory.state == "calm", "Opaque wall prevents escalation")
	check(subject.damage_received == old_damage, "No shooting through wall")
	wall.queue_free()
	await retreat()

	reputation.respect = 25
	subject.position = Vector2(250, 200)
	await seconds(2.8)
	check(territory.state == "calm", "Earned respect permits lingering")
	check(subject.damage_received == old_damage, "Respected visitor is not attacked")
	# Use actual actor damage entry point; do not call report_aggression directly.
	territory.guards[0].take_damage(1, true)
	await seconds(0.3)
	check(territory.state == "combat", "Player aggression overrides friendship")
	await retreat()
	reputation.respect = 0
	subject.position = Vector2(250, 200)
	subject.is_in_dialogue = true
	await seconds(2.8)
	check(territory.state == "calm", "Dialogue freezes territorial escalation")
	subject.is_in_dialogue = false
	subject.is_control_disabled = true
	await seconds(2.8)
	check(territory.state == "calm", "Cutscene control lock freezes territorial escalation")
	subject.is_control_disabled = false
	paused = true
	for frame in 30:
		await physics_frame
	check(territory.state == "calm", "Game pause freezes territorial escalation")
	paused = false
	await seconds(0.25)
	check(territory.state == "watch", "Resume starts observation without accumulated hidden exposure")
	await retreat()

	# A hidden driver must be represented by the driven vehicle, not stale player coordinates.
	var vehicle := DrivenVehicle.new()
	vehicle.add_to_group("vehicle")
	vehicle.position = Vector2(250, 200)
	scene.add_child(vehicle)
	subject.hide()
	await seconds(1.0)
	check(territory.state == "warning", "Driven vehicle is observed while hidden player stays outside")
	vehicle.position = Vector2(1600, 200)
	await seconds(2.4)
	check(territory.state == "calm", "Driving away de-escalates")
	var resident = load("res://district/harbor_preview/cobras/CobraResident.gd").new()
	resident.patrol = PackedVector2Array([Vector2(10, 10), Vector2(10, 100), Vector2(100, 100)])
	var actual_targets: Array[Vector2] = []
	for step in 6:
		resident._pick_new_sidewalk_target()
		actual_targets.append(resident.walk_target)
	check(actual_targets == [Vector2(10, 10), Vector2(10, 100), Vector2(100, 100), Vector2(10, 100), Vector2(10, 10), Vector2(10, 100)], "Open pedestrian routes reverse instead of crossing courtyard diagonally")
	resident.free()
	print("COBRA_TERRITORY states_tested=5 guards=%d damage=%d failures=%d" % [territory.guards.size(), subject.damage_received, failures.size()])
	for failure in failures:
		push_error("COBRA_TERRITORY: " + failure)
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)

func retreat() -> void:
	subject.position = Vector2(1600, 200)
	await seconds(2.4)

func seconds(duration: float) -> void:
	for frame in ceili(duration * 60.0):
		await physics_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
