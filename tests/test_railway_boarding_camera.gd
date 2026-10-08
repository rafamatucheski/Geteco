extends SceneTree
const TRANSIT = preload("res://runtime/railway/RailwayTransit.gd")
class FakeFade extends Node:
	var alpha := 0.0
	func fade_to(value: float, _seconds: float) -> void:
		await get_tree().process_frame
		alpha = value
	func clear() -> void: alpha = 0.0
class FakeWorld extends Node:
	var player: Node3D
class FakeSession extends Node:
	var world: FakeWorld
	var door_transition: FakeFade
	var ready_for_play := false
class Probe extends TRANSIT:
	var updates := 0
	var last_alpha := -1.0
	var last_mode := -1
	func _update_camera(_interpolated := false) -> void:
		updates += 1
		last_alpha = session.door_transition.alpha
		last_mode = camera_mode
	func _update_train_pose() -> void: _update_camera()
	func _exit_tree() -> void: pass
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures += 1
func run() -> void:
	var session := FakeSession.new()
	root.add_child(session)
	session.world = FakeWorld.new()
	session.add_child(session.world)
	session.world.player = Node3D.new()
	session.world.add_child(session.world.player)
	session.door_transition = FakeFade.new()
	session.add_child(session.door_transition)
	var transit := Probe.new()
	session.add_child(transit)
	transit.session = session
	transit.train = Node3D.new()
	session.add_child(transit.train)
	transit.riding = true
	transit._boarding = true
	transit._generation = 1
	transit.set_camera_mode(1)
	check(transit.camera_mode == 1 and transit.updates == 0, "external selection while boarding never moves camera to remote train")
	transit.set_camera_mode("interior")
	transit.set_camera_mode("exterior")
	check(transit.camera_mode == 1 and transit.updates == 0, "latest named camera selection is retained without premature projection")
	await transit._board_with_fade(1)
	check(transit.updates == 1 and transit.last_alpha == 1.0, "boarding applies camera only after opaque fade")
	check(transit.last_mode == 1 and not transit._boarding and session.door_transition.alpha == 0.0, "chosen outside mode survives boarding and fade clears")
	transit.set_camera_mode(0)
	check(transit.updates == 2 and transit.last_mode == 0, "camera switches immediately after admission")
	print("RAILWAY_BOARDING_CAMERA_RESULT failures=", failures)
	session.free()
	quit(1 if failures else 0)
