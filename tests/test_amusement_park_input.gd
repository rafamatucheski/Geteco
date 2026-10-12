extends SceneTree
const ANDROID := preload("res://ui/AndroidControls.gd")
var checks := 0
var failures := 0
var world
var park
var touch
var controls

class ParkInput extends "res://runtime/amusement_park/AmusementParkRuntime.gd":
	var departures := 0
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	# This fixture checks input delivery only; the real animated return is
	# exercised in test_coaster_session with Main and the actual station.
	func request_exit() -> void: leave()
	func leave() -> void:
		if active:
			active = false
			departures += 1
			world.player.input_locked = false
			if is_instance_valid(_ride_hint): _ride_hint.queue_free()
			_ride_hint = null

class Player extends Node3D:
	var input_locked := false

class State extends RefCounted:
	var region_id := "harbor"
	var place_id := "harbor_haunted_house"
	func weapons_allowed() -> bool: return true

class Session extends RefCounted:
	var world
	var state = State.new()
	var ready_for_play := true
	var modal := false
	var dialogue_open := false
	var passenger_transport = null
	var arrival = null
	var motocross = null
	var skate = null
	var fishing = null
	var port_container_loot = null
	var robberies = null
	var police_motor_pool = null
	func is_transition_blocked() -> bool: return false

class World extends Node3D:
	var session = Session.new()
	var driving := {"occupied":false, "car":null}
	var player = Player.new()

class InputRouter extends Node:
	var park
	var controls
	func _input(event: InputEvent) -> void:
		# Same ordering and handled-event contract as FullSession._input.
		controls.observe_event(event)
		if park.handle_input(event): get_viewport().set_input_as_handled()

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PARK_INPUT ", "PASS " if value else "FAIL ", label)
	if not value:
		failures += 1
		push_error(label)

func finger(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame

func drag(index: int, point: Vector2, movement: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = movement
	root.push_input(event,true)
	await process_frame

func action(id: String) -> void:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = InputEventAction.new()
	event.action = id
	event.pressed = false
	root.push_input(event,true)
	await process_frame

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	controls = root.get_node("GameInput")
	world = World.new()
	world.session.world = world
	root.add_child(world)
	current_scene = world
	world.add_child(world.player)
	park = ParkInput.new()
	park.configure(world.session)
	world.add_child(park)
	park.house_view = true
	touch = ANDROID.new()
	touch.world = world
	world.add_child(touch)
	await process_frame
	touch._refresh()
	# Added last so the park adapter receives raw events before AndroidControls.
	var router := InputRouter.new()
	router.park = park
	router.controls = controls
	router.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(router)
	check(touch.playable and not Input.emulate_mouse_from_touch, "real Android overlay owns gameplay touches without mouse emulation")
	await finger(1,touch.move_center+Vector2(touch.radius*.45,0),true)
	var initial_yaw: float = park.yaw
	await drag(1,touch.move_center+Vector2(touch.radius,0),Vector2(45,0))
	check(controls.touch_move.x > .9 and controls.touch_sprint, "left finger drag reaches real movement joystick")
	check(is_equal_approx(park.yaw,initial_yaw), "left joystick never rotates attraction camera")
	await finger(2,touch.aim_center+Vector2(0,-touch.radius*.6),true)
	await drag(2,touch.aim_center+Vector2(touch.radius*.8,0),Vector2(35,20))
	check(controls.touch_aim.x > .7 and controls.touch_move.x > .9, "right joystick and movement remain independent")
	park._gamepad_look(.1)
	check(park.yaw < initial_yaw and controls.touch_move.x > .9, "right touch joystick rotates camera while movement remains held")
	var after_stick: float = park.yaw
	await finger(3,Vector2(600,260),true)
	await drag(3,Vector2(630,275),Vector2(30,15))
	check(park.yaw < after_stick and park.pitch < 0 and controls.touch_move.x > .9, "free finger drag looks around without stealing movement")
	await finger(3,Vector2(630,275),false)
	await finger(2,Vector2.ZERO,false)
	await finger(1,Vector2.ZERO,false)
	check(touch.fingers.is_empty() and controls.touch_move.is_zero_approx() and controls.touch_aim.is_zero_approx(), "releasing fingers clears both real touch joysticks")
	world.session.modal = true
	touch._refresh()
	var modal_yaw: float = park.yaw
	await drag(4,Vector2(610,270),Vector2(80,0))
	controls.touch_aim = Vector2.RIGHT
	park._gamepad_look(.2)
	check(is_equal_approx(park.yaw,modal_yaw), "modal menu blocks free drag and continuous joystick look")
	controls.touch_aim = Vector2.ZERO
	world.session.modal = false
	paused = true
	touch._refresh()
	await drag(4,Vector2(620,270),Vector2(80,0))
	controls.touch_aim = Vector2.RIGHT
	park._gamepad_look(.2)
	check(is_equal_approx(park.yaw,modal_yaw), "pause blocks both camera input paths")
	controls.touch_aim = Vector2.ZERO
	paused = false
	touch._refresh()
	# GameInput caches synthetic axis values for its no-device fallback.
	controls.using_gamepad = true
	controls.active_joypad = -1
	controls._aim_stick = Vector2(.1,.1)
	park._gamepad_look(.2)
	check(is_equal_approx(park.yaw,modal_yaw), "gamepad radial deadzone prevents camera drift")
	controls._aim_stick = Vector2(.8,0)
	park._gamepad_look(.2)
	check(park.yaw < modal_yaw, "right gamepad stick above deadzone rotates camera")
	controls._aim_stick = Vector2.ZERO
	controls.using_gamepad = false
	park.house_view = false
	park.active = true
	world.player.input_locked = true
	park._make_hint()
	await process_frame
	var exit_button := park._ride_hint.get_node("RideExitButton") as Button
	check(not touch.playable and Input.emulate_mouse_from_touch, "coaster hint immediately releases overlay controls and enables native GUI touch")
	var exit_point: Vector2 = exit_button.get_global_rect().get_center()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await mouse_button(exit_point,true)
	await mouse_button(exit_point,false)
	check(not park.active and park.departures == 1, "real ride Button responds to viewport mouse press and release")
	park.active = true
	world.player.input_locked = true
	park._make_hint()
	await process_frame
	exit_button = park._ride_hint.get_node("RideExitButton") as Button
	exit_point = exit_button.get_global_rect().get_center()
	var button_yaw: float = park.yaw
	await finger(7,exit_point,true)
	await drag(7,exit_point+Vector2(5,0),Vector2(5,0))
	check(is_equal_approx(park.yaw,button_yaw), "finger beginning on exit button cannot rotate camera")
	await finger(7,exit_point+Vector2(5,0),false)
	check(not park.active and park.departures == 2, "real ride Button responds to native viewport touch press and release")
	# Desktop offers the actual active bindings, with no button behind capture.
	controls.remove_meta("touch_controls_active")
	park.active = true
	park._make_hint()
	await process_frame
	check(park._ride_hint.has_node("RideExitHint") and not park._ride_hint.has_node("RideExitButton") and controls.prompt("interact") in park._ride_hint.get_node("RideExitHint").text, "desktop hint uses configured return binding and no unreachable button")
	park.leave()
	controls.set_meta("touch_controls_active",true)
	park.active = true
	await action("exit_vehicle")
	check(not park.active and park.departures == 4, "exit action requests one coaster cancellation")
	park.active = true
	await action("pause_game")
	check(not park.active and park.departures == 5, "pause requests coaster cancellation and remains available to pause UI")
	park.house_view = false
	world.free()
	await process_frame
	check(not controls.has_meta("touch_controls_active") and Input.emulate_mouse_from_touch, "teardown restores ordinary menu touch handling")
	print("%s amusement park input: %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
