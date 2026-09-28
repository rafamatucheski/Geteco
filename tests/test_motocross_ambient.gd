extends SceneTree
## Ambient riders use actual course collision and the controller's shared AI.
const AMBIENT := preload("res://activities/motocross/MotocrossAmbient.gd")
const CONTROLLER := preload("res://activities/motocross/Motocross.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
class FixtureWorld extends Node3D:
	var player: Node3D
class FixtureSession extends RefCounted:
	var world: Node3D
	var ready_for_play := true
	var modal := false
	var blocked := false
	var state := {"region_id": "harbor", "place_id": "", "wallet_untouched": 731}
	func is_transition_blocked() -> bool: return blocked
var checks := 0
var failures: Array[String] = []
var ambient := AMBIENT.new()

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_AMBIENT ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)
func step(count: int) -> void:
	for _i in count:
		ambient.update(1.0 / 60.0)
		await physics_frame

func run() -> void:
	var world := FixtureWorld.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.player.position = COURSE.ENTRY
	world.add_child(world.player)
	var session := FixtureSession.new()
	session.world = world
	var original_state := session.state.duplicate(true)
	var controller := CONTROLLER.new()
	controller.session = session
	world.add_child(controller)
	controller.set_physics_process(false)
	ambient.configure(controller)
	await step(40)
	check(ambient.rows.is_empty(), "no riders spawn before the physical course streams in")
	var course := COURSE.new()
	world.add_child(course)
	await step(120)
	check(ambient.rows.size() == 3, "nearby park activates at most three practice riders")
	var start: Vector3 = ambient.rows[0].bike.position
	await step(120)
	check(ambient.rows[0].bike.position.distance_to(start) > 4.0, "ambient riders physically drive using the shared controller AI")
	var all_ambient := true
	for row in ambient.rows:
		all_ambient = all_ambient and row.has("pace") and row.bike.get_meta("motocross_ambient", false) and not row.has("gate")
	check(all_ambient and session.state == original_state, "practice riders create no economic or race-checkpoint progress")
	session.modal = true
	ambient.update(1.0 / 60.0)
	var before_pause: Vector3 = ambient.rows[0].bike.position
	await step(40)
	check(ambient.rows[0].bike.position.is_equal_approx(before_pause), "modal suspends actual bike motion")
	session.modal = false
	await step(10)
	check(ambient.rows[0].bike.is_physics_processing(), "closing the modal resumes physics")
	var center2: Vector2 = COURSE.BOUNDS.get_center()
	world.player.position = Vector3(center2.x + 160.0, 0, center2.y)
	await step(40)
	check(ambient.rows.size() == 3, "150-to-180-metre hysteresis retains active riders")
	world.player.position.x = center2.x + 185.0
	await step(40)
	check(ambient.rows.is_empty(), "leaving the park unloads all ambient riders")
	world.player.position = COURSE.ENTRY
	await step(120)
	controller.active = true
	ambient.update(1.0 / 60.0)
	check(ambient.rows.is_empty(), "a paid race immediately removes decorative riders")
	controller.active = false
	await step(120)
	controller.mounted = true
	ambient.update(1.0 / 60.0)
	check(ambient.rows.is_empty(), "rental or player mounting immediately removes decorative riders")
	controller.mounted = false
	await step(120)
	session.blocked = true
	ambient.update(1.0 / 60.0)
	check(ambient.rows.is_empty(), "a world transition cleans up riders before terrain unload")
	session.blocked = false
	await step(120)
	var bike = ambient.rows[0].bike
	bike.position.y = -20
	await step(100)
	check(int(ambient.rows[0].respawns) > 0 and ambient.rows[0].bike.position.y > -5, "off-course falls recover onto a safe physical track point")
	course.free()
	ambient.update(1.0 / 60.0)
	check(ambient.rows.is_empty(), "streamed-out course leaves no riders running over missing terrain")
	ambient.clear()
	world.free()
	print("MOTOCROSS_AMBIENT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
