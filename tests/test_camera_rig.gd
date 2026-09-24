extends SceneTree

const CAMERA := preload("res://scripts/CameraRig.gd")

class CameraTarget extends CharacterBody3D:
	var speed := 0.0
	var max_forward_speed := 15.0

class CameraGameplay extends Node:
	var active := false
	var aim_point := Vector3.ZERO
	func scope_active() -> bool: return active

class CameraWorld extends Node3D:
	var gameplay: Node
	var hud: Control

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool,message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func run() -> void:
	var stage := CameraWorld.new()
	root.add_child(stage)
	stage.gameplay = CameraGameplay.new()
	stage.add_child(stage.gameplay)
	stage.hud = Control.new()
	stage.add_child(stage.hud)
	var walker := CharacterBody3D.new()
	stage.add_child(walker)
	var camera = CAMERA.new()
	camera.target = walker
	stage.add_child(camera)
	await physics_frame
	camera._process(1.0/60.0)
	check(is_equal_approx(camera.target_size,CAMERA.WALK_SIZE_CLOSE),"Walking framing starts at the projected V1 scale")
	check(camera.focus.distance_to(walker.global_position)<.001,"Walking focus follows the interpolated actor without whole-target lag")
	stage.gameplay.aim_point = Vector3(30,0,0)
	stage.gameplay.active = true
	for frame in 180: camera._process(1.0/60.0)
	check(absf(camera.size-CAMERA.WALK_SIZE_CLOSE*CAMERA.SCOPE_SIZE_MULTIPLIER)<.01,"Scope preserves the V1 two-times zoom contract")
	check(camera.focus.x<=CAMERA.V1_SCOPE_LEAD+.01,"Scope anticipation remains capped at the V1 visible distance")
	check(is_instance_valid(camera.scope_reticle) and camera.scope_reticle.visible,"Camera keeps the existing scope presentation visible")
	stage.gameplay.active = false
	for frame in 180: camera._process(1.0/60.0)
	var shop_focus := Vector3(4, 1.2, -3)
	var exterior_focus: Vector3 = camera.focus
	var exterior_size: float = camera.size
	camera.focus_on_store(shop_focus, 8.0, 0.5)
	camera._process(0.25)
	check(camera.focus.distance_to(shop_focus) > 0.1 and camera.focus.distance_to(shop_focus) < exterior_focus.distance_to(shop_focus), "Shop camera starts an animated focus")
	check(camera.size < exterior_size and camera.size > 8.0, "Shop camera zooms during the approach")
	camera._process(0.25)
	check(camera.focus.distance_to(shop_focus) < 0.01 and absf(camera.size-8.0) < 0.01, "Shop facade reaches screen centre and final zoom")
	camera.clear_store_focus()
	camera._process(1.0/60.0)
	check(not camera._store_focus_active, "Shop focus releases normal camera control")
	var door_focus := Vector3(2, 1.2, -2)
	camera.focus_on_transition(door_focus, 9.0, CAMERA.STORE_FOCUS_OFFSET, 0.4)
	camera._process(0.4)
	check(camera.focus.distance_to(door_focus) < 0.01 and absf(camera.size-9.0) < 0.01, "Door approach reaches its authored focus and size")
	camera.clear_store_focus()
	camera.offset = CAMERA.EXTERIOR_OFFSET
	camera.heading = 0.0
	camera.reveal_exterior(walker.global_position, 9.0, exterior_size, 0.4)
	camera._process(0.2)
	check(camera.size > 9.0 and camera.size < exterior_size, "Exterior reveal zooms out gradually")
	camera._process(0.2)
	check(absf(camera.size-exterior_size) < 0.01, "Exterior reveal restores the saved framing")
	camera.clear_store_focus()

	var vehicle := CameraTarget.new()
	vehicle.position = Vector3(1,0,0)
	stage.add_child(vehicle)
	var previous_focus: Vector3 = camera.focus
	camera.target = vehicle
	camera._process(1.0/60.0)
	check(camera.focus.distance_to(previous_focus)<.1,"Nearby vehicle handoff preserves the visible centre")
	vehicle.speed = vehicle.max_forward_speed
	vehicle.velocity = Vector3(0,0,-vehicle.speed)
	for frame in 180: camera._process(1.0/60.0)
	check(absf(camera.target_size-CAMERA.size_for_v1_zoom(CAMERA.V1_DRIVE_ZOOM_FAR))<.01,"Driving reaches the V1 apparent far scale at authored top speed")
	check(camera.focus.z<vehicle.position.z-.25,"Driving adds forward anticipation")

	var room_anchor := Node3D.new()
	room_anchor.position = Vector3(0,.7,-2400)
	stage.add_child(room_anchor)
	camera.target = room_anchor
	camera.locked = true
	camera.offset = Vector3(0,18,15)
	camera.target_size = 13.12
	camera.initialized = false
	camera._process(1.0/60.0)
	check(camera.focus.distance_to(room_anchor.global_position)<.001,"Distant lodge entry snaps to the real anchor instead of interpolating across the world")
	check(absf(camera.size-13.12)<.001,"Lodge entry applies its authored framing in the first rendered frame")
	camera._process(1.0/60.0)
	check(camera.focus.distance_to(room_anchor.global_position)<.001,"Locked lodge framing remains stable after the transition frame")

	stage.free()
	print("CAMERA_RIG ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
