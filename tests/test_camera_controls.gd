extends SceneTree

const CAMERA := preload("res://scripts/CameraRig.gd")

class CameraGameplay extends Node:
	var attacks_allowed := true
	var aim_point := Vector3.ZERO
	func attack_allowed() -> bool: return attacks_allowed
	func scope_active() -> bool: return false

class CameraSession extends Node:
	var modal := false
	var ready_for_play := true
	var transition_blocked := false
	func is_transition_blocked() -> bool: return transition_blocked

class CameraWorld extends Node3D:
	var gameplay: Node
	var session: Node
	var hud: Control

class CameraVehicle extends CharacterBody3D:
	var max_forward_speed := 15.0
	var archetype := "sport_coupe"

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures.append(message)

func action_event(action: StringName, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event

func axis_event(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 7
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	var stage := CameraWorld.new()
	root.add_child(stage)
	stage.gameplay = CameraGameplay.new()
	stage.session = CameraSession.new()
	stage.hud = Control.new()
	stage.add_child(stage.gameplay)
	stage.add_child(stage.session)
	stage.add_child(stage.hud)
	var walker := CharacterBody3D.new()
	stage.add_child(walker)
	var camera = CAMERA.new()
	camera.target = walker
	stage.add_child(camera)
	camera.set_process(false)
	await process_frame

	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = true
	camera._unhandled_input(key)
	check(is_equal_approx(camera.heading, PI / 4), "Z rotates the exterior by 45 degrees")
	key.echo = true
	camera._unhandled_input(key)
	key.echo = false
	key.pressed = false
	camera._unhandled_input(key)
	check(is_equal_approx(camera.heading, PI / 4), "Key repeat and release do not add a rotation")
	key.physical_keycode = KEY_C
	key.pressed = true
	camera._unhandled_input(key)
	check(is_zero_approx(camera.heading), "C rotates back by 45 degrees")

	camera._unhandled_input(action_event("camera_left"))
	check(is_equal_approx(camera.heading, PI / 4), "Touch camera actions reach the same camera command")
	camera._unhandled_input(action_event("camera_left", false))
	check(is_equal_approx(camera.heading, PI / 4), "Touch release does not repeat the turn")
	camera._unhandled_input(action_event("camera_right"))
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_RIGHT
	button.pressed = true
	var rebound: Dictionary = controls.rebind_gamepad("camera_right", button)
	check(rebound.ok, "A camera direction can be remapped to a gamepad button")
	camera._unhandled_input(button)
	check(is_equal_approx(camera.heading, -PI / 4), "Remapped gamepad button rotates by 45 degrees")
	button.pressed = false
	camera._unhandled_input(button)
	check(is_equal_approx(camera.heading, -PI / 4), "Gamepad release does not repeat the turn")
	controls.reset_bindings()

	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_X
	motion.axis_value = 1.0
	camera.heading = 0.0
	camera._unhandled_input(motion)
	check(is_zero_approx(camera.heading), "Analog events do not also trigger discrete camera steps")

	camera.locked = true
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Authored interior camera ignores rotation")
	camera.locked = false
	paused = true
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Pause ignores camera commands")
	paused = false
	controls.remapping = true
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Remapping does not move the camera")
	controls.remapping = false
	stage.session.modal = true
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Modal interaction ignores camera commands")
	stage.session.modal = false
	stage.session.ready_for_play = false
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Loading ignores camera commands")
	stage.session.ready_for_play = true
	stage.session.transition_blocked = true
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Session transitions ignore camera commands")
	stage.session.transition_blocked = false
	camera.focus_on_store(Vector3.ZERO, 8.0, 0.5)
	camera._unhandled_input(action_event("camera_left"))
	check(is_zero_approx(camera.heading), "Door focus animation ignores rotation")
	camera.clear_store_focus()
	camera._unhandled_input(action_event("camera_left"))
	check(is_equal_approx(camera.heading, PI / 4), "Exterior rotation returns after input is unlocked")

	camera.heading = 0.0
	await axis_event(0.1)
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Right-stick deadzone prevents camera drift")
	await axis_event(1.0)
	camera._process(0.25)
	var full_turn: float = camera.heading
	check(full_turn < -0.3 and full_turn > -0.7, "Holding the right stick rotates continuously at a usable speed")
	camera.heading = 0.0
	await axis_event(0.5)
	camera._process(0.25)
	check(camera.heading < 0.0 and absf(camera.heading) < absf(full_turn), "Partial stick travel turns the camera more slowly")
	await axis_event(0.0)
	var released_heading: float = camera.heading
	camera._process(0.25)
	check(is_equal_approx(camera.heading, released_heading), "Returning the stick to neutral stops orbiting")
	camera.heading = 0.0
	await axis_event(-1.0)
	camera._process(0.25)
	check(is_equal_approx(camera.heading, -full_turn), "Left and right stick directions turn symmetrically")

	camera.heading = 0.0
	await axis_event(1.0)
	Input.action_press("aim")
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Aiming on foot reserves the right stick for aim")
	Input.action_release("aim")
	Input.action_press("fire")
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Firing on foot keeps the camera fixed for aim")
	stage.gameplay.attacks_allowed = false
	camera._process(0.25)
	check(camera.heading < 0.0, "Activities that disable combat can look around with a trigger held")
	Input.action_release("fire")

	var vehicle := CameraVehicle.new()
	stage.add_child(vehicle)
	camera.target = vehicle
	camera.heading = 0.0
	Input.action_press("accelerate")
	camera._process(0.25)
	check(camera.heading < 0.0, "Ordinary driving allows camera orbit while accelerating")
	Input.action_release("accelerate")
	vehicle.archetype = "army_tank"
	camera.heading = 0.0
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "The tank reserves the right stick for its cannon")
	camera.target = walker
	stage.gameplay.attacks_allowed = true

	camera.locked = true
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Analog orbit preserves authored interior framing")
	camera.locked = false
	paused = true
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Held stick cannot rotate during pause")
	paused = false
	stage.session.modal = true
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Held stick cannot rotate behind modal interactions")
	stage.session.modal = false
	stage.session.transition_blocked = true
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Held stick cannot rotate during session transitions")
	stage.session.transition_blocked = false
	controls.remapping = true
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Analog remapping keeps the camera stationary")
	controls.remapping = false

	button.pressed = true
	controls.rebind_gamepad("camera_right", button)
	await axis_event(1.0)
	camera._process(0.25)
	check(is_zero_approx(camera.heading), "Replacing the camera axis removes its continuous input")
	camera._unhandled_input(button)
	var button_heading: float = camera.heading
	camera._process(0.25)
	check(is_equal_approx(button_heading, -PI / 4) and is_equal_approx(camera.heading, button_heading), "Remapped button does not also trigger continuous orbit")
	await axis_event(0.0)
	controls.reset_bindings()

	stage.free()
	print("CAMERA_CONTROLS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
