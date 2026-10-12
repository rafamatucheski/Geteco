extends SceneTree
## Mouse camera contracts: no feedback drift, continuous orbit and interruption recovery.
const CAMERA := preload("res://scripts/CameraRig.gd")
var failures: Array[String] = []
var checks := 0

class Session extends Node:
	var modal := false
	var ready_for_play := true
	func is_transition_blocked() -> bool: return false

class Combat extends Node:
	var aim_point := Vector3.ZERO
	func scope_active() -> bool: return false
	func attack_allowed() -> bool: return true

class World extends Node3D:
	var session: Node
	var gameplay: Node
	var hud: Control

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func drag_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event

func run() -> void:
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	var world := World.new()
	root.add_child(world)
	current_scene = world
	world.session = Session.new()
	world.gameplay = Combat.new()
	world.hud = Control.new()
	world.add_child(world.session)
	world.add_child(world.gameplay)
	world.add_child(world.hud)
	var player := CharacterBody3D.new()
	world.add_child(player)
	var camera = CAMERA.new()
	camera.target = player
	world.add_child(camera)
	camera.set_process(false)
	camera._process(1.0 / 60.0)
	var viewport_size := root.get_visible_rect().size
	var screen := viewport_size * Vector2(0.72, 0.4)
	var first: Vector3 = camera.mouse_aim_lead(player.position, true, screen)
	check(first.length() > 0.2, "Scope responds to cursor away from centre")
	camera.position += Vector3(4, 0, -3)
	var translated: Vector3 = camera.mouse_aim_lead(player.position, true, screen)
	check(first.distance_to(translated) < 0.001, "Camera translation cannot feed back into mouse lead")
	check(camera.mouse_aim_lead(player.position, true, viewport_size * 0.5).length() < 0.001, "Centred cursor returns scope to player")
	check(camera.mouse_aim_lead(player.position, false, screen).length() < first.length(), "Ordinary aim has less anticipation than scope")
	check(camera.mouse_aim_lead(player.position, true, viewport_size * 20).length() <= CAMERA.V1_SCOPE_LEAD + 0.001, "Out-of-window coordinates cannot run camera away")
	for angle in [0.0, PI / 2, PI, -PI / 2]:
		camera.heading = angle
		camera.initialized = false
		camera._process(1.0 / 60.0)
		var lead: Vector3 = camera.mouse_aim_lead(player.position, true, viewport_size * Vector2(0.75, 0.5))
		check(lead.dot(camera.global_basis.x) > 0.0, "Mouse anticipation respects orbit %s" % angle)
	camera.heading = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	camera._unhandled_input(drag_event(true))
	check(camera.mouse_orbit_active(), "Middle button begins continuous orbit")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80, 0)
	motion.screen_relative = motion.relative
	camera._unhandled_input(motion)
	check(camera.heading < -0.1, "Held mouse drag rotates without discrete steps")
	var heading: float = camera.heading
	camera._input(drag_event(false))
	camera._unhandled_input(motion)
	check(not camera.mouse_orbit_active() and is_equal_approx(camera.heading, heading), "Release stops orbit even before GUI handling")
	camera._unhandled_input(drag_event(true))
	world.session.modal = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera._process(0.0)
	check(not camera.mouse_orbit_active() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Opening menu cancels capture and preserves menu cursor")
	world.session.modal = false
	camera._unhandled_input(drag_event(true))
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not camera.mouse_orbit_active(), "Focus loss cancels orbit")
	camera.locked = true
	camera._unhandled_input(drag_event(true))
	check(not camera.mouse_orbit_active(), "Authored interior camera rejects mouse orbit")
	camera.locked = false
	camera._unhandled_input(drag_event(true))
	paused = true
	camera._process(0.0)
	check(not camera.mouse_orbit_active(), "Pause cancels orbit")
	paused = false
	camera._unhandled_input(drag_event(true))
	check(camera.mouse_orbit_active(), "Fresh press recovers after pause")
	camera._input(drag_event(false))
	var aim_button := InputEventMouseButton.new()
	aim_button.button_index = MOUSE_BUTTON_RIGHT
	aim_button.pressed = true
	aim_button.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(aim_button)
	Input.flush_buffered_events()
	var pad_motion := InputEventJoypadMotion.new()
	pad_motion.device = 7
	pad_motion.axis = JOY_AXIS_RIGHT_X
	pad_motion.axis_value = 0.5
	controls.observe_event(pad_motion)
	check(not controls.using_gamepad, "Controller motion cannot steal a held mouse aim gesture")
	aim_button = aim_button.duplicate()
	aim_button.pressed = false
	aim_button.button_mask = 0
	Input.parse_input_event(aim_button)
	Input.flush_buffered_events()
	controls.observe_event(pad_motion)
	check(controls.using_gamepad, "Controller remains available after mouse release")
	world.free()
	print("MOUSE_CAMERA_RESPONSE checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
