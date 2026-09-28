extends SceneTree
const VEHICLE = preload("res://scripts/Vehicle.gd")
const ACTOR = preload("res://scripts/Actor.gd")
const BAILOUT = preload("res://gameplay/VehicleBailout.gd")
class Driving extends "res://scripts/Driving.gd":
	func _ready() -> void:
		exit_capsule.radius = .32
		exit_capsule.height = 1.72
		set_process(false)
class Camera extends Camera3D:
	var locked := false
	var initialized := false
	var target: Node3D
class Damage extends Node:
	var health := 100.0
	var hits := 0
	var car_hits := 0
	func damage_player(amount: float) -> void:
		car_hits += 1
		print("BAILOUT_CAR_HIT amount=",amount," phase=",get_parent().driving.transition.phase if is_instance_valid(get_parent().driving.transition) else "done"," car=",get_parent().driving.car.position," actor=",get_parent().player.position)
	func damage_environment(amount: float) -> void:
		health -= amount
		hits += 1
class World extends Node3D:
	var player
	var driving
	var camera
	var gameplay
	var production: Node
	var session: Node
var world: World
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = size
	shape.shape = hull
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	body.add_child(mesh)
	body.position = point
	world.add_child(body)
	return body
func mount(speed: float) -> void:
	var car = world.driving.car
	car.place(Vector3(0,.04,0),0)
	car.stop_boarding_motion()
	car.speed = speed
	car.horizontal_velocity = Vector3(0,0,-speed)
	car.controlled = true
	car.input_locked = false
	world.driving.occupied = true
	world.player.input_locked = false
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	world.player.hide()
	world.gameplay.health = 100
	world.gameplay.hits = 0
	world.gameplay.car_hits = 0
func run() -> void:
	world = World.new()
	root.add_child(world)
	box(Vector3(0,-.1,0),Vector3(40,.2,40))
	world.camera = Camera.new()
	world.add_child(world.camera)
	world.camera.position = Vector3(-8,6,8)
	world.camera.look_at(Vector3(-1,0,-2))
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 11
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.shadow_enabled = true
	world.add_child(light)
	world.gameplay = Damage.new()
	world.add_child(world.gameplay)
	world.player = ACTOR.new()
	world.player.is_player = true
	world.player.controlled_automatically = true
	world.add_child(world.player)
	world.driving = Driving.new()
	world.driving.world = world
	world.add_child(world.driving)
	var car = VEHICLE.new()
	car.archetype = "sport_coupe"
	world.add_child(car)
	world.driving.car = car
	world.driving._watch_car(car)
	for frame in 3: await physics_frame
	for speed in [9.0,-6.0,22.0]:
		mount(speed)
		check(world.driving.leave(),"moving exit admitted at speed %s" % speed)
		check(not world.driving.occupied and world.player.visible and world.player.input_locked,"outside body visible and locked during fall")
		check(absf(car.speed)==absf(speed),"exit does not zero car momentum")
		check(not world.driving.interact(),"repeated input cannot remount during roll")
		var phases := {}
		var lowest := INF
		var start: Vector3 = world.player.position
		for frame in 180:
			await physics_frame
			for name in ["Head","LeftFoot","RightFoot","LeftHand","RightHand"]:
				var bone: int = world.player.skeleton.find_bone(name)
				lowest = minf(lowest,world.player.skeleton.to_global(world.player.skeleton.get_bone_global_pose(bone).origin).y)
			if is_instance_valid(world.driving.transition): phases[world.driving.transition.phase] = true
			if speed==9.0 and frame in [8,26,48,72,108] and "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://evidence/vehicle-bailout-20260928/roll-%03d.png" % frame)
			if not world.driving.is_body_transition_active(): break
		check(phases.has("roll") and phases.has("recover"),"fall rolls then gets up")
		check(lowest > -.05,"body extremities stay above ground: %s" % lowest)
		check(not world.driving.is_body_transition_active() and not world.player.input_locked and world.player.is_physics_processing(),"recovers walking control")
		check(world.player.position.distance_to(start)>.3,"momentum carries the body")
		check(world.gameplay.hits==1 and world.gameplay.health>=82 and world.gameplay.health<100,"single light damage on landing")
		check(world.gameplay.car_hits==0,"source car does not hit ejected player")
		check(world.player.visual.rotation.is_equal_approx(Vector3.ZERO),"restores upright visual")
		check(world.player.collision_mask==7 and world.player.collision_layer==2,"collision restored")
		check(world.camera.target==world.player,"camera follows ejected player")
	mount(9)
	var left := box(Vector3(-2.0,1,0),Vector3(1,2,8))
	var right := box(Vector3(2.0,1,0),Vector3(1,2,8))
	await physics_frame
	check(not world.driving.leave() and world.driving.occupied,"blocked doors reject exit without teleporting through walls")
	left.queue_free()
	right.queue_free()
	await physics_frame
	mount(9)
	var wall := box(Vector3(-2,1,-3),Vector3(4,2,.3))
	await physics_frame
	check(world.driving.leave(),"exit beside obstacle admitted")
	for frame in 160: await physics_frame
	check(world.player.position.z > -2.85,"rolling body cannot pass through wall")
	wall.queue_free()
	await physics_frame
	mount(9)
	check(world.driving.leave(),"exit before cancellation")
	await physics_frame
	var active_exit = world.driving.transition
	var paused_age: float = active_exit.age
	paused = true
	for frame in 5: await process_frame
	check(active_exit.age==paused_age,"pause freezes fall and damage timing")
	paused = false
	world.driving.cancel_transition("session_transition")
	check(not world.driving.is_body_transition_active() and world.player.visible and world.player.collision_mask==7,"cancellation restores body")
	check(not world.player.get_collision_exceptions().has(car) and not car.get_collision_exceptions().has(world.player),"cancellation removes temporary source exception")
	for child in world.player.get_children():
		if child is CollisionShape3D: check(is_equal_approx(child.shape.radius,.3),"restores normal walking hull")
	mount(.2)
	check(world.driving.leave() and not world.driving.transition is BAILOUT,"low speed retains normal boarding animation")
	world.driving.cancel_transition("test_done")
	mount(9)
	world.gameplay.health = 1
	check(world.driving.leave(),"critically injured player can attempt exit")
	for frame in 90: await physics_frame
	check(world.gameplay.health<=0 and not world.driving.is_body_transition_active() and world.player.input_locked and not world.player.is_physics_processing(),"fatal fall does not get up or regain controls")
	mount(9)
	check(world.driving.leave(),"moving exit before vehicle removal")
	world.driving._on_car_destroyed(car)
	check(world.driving.transition is BAILOUT,"source destruction does not kill detached occupant")
	car.queue_free()
	for frame in 180: await physics_frame
	check(not world.driving.is_body_transition_active() and not world.player.input_locked,"vehicle removal does not strand recovery")
	world.free()
	await process_frame
	print("VEHICLE_BAILOUT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
