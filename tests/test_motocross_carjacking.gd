extends SceneTree
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const ACTOR := preload("res://scripts/Actor.gd")
class TheftController extends "res://activities/motocross/Motocross.gd":
	func _claim_bike(bike: CharacterBody3D) -> bool:
		mounted = true
		player_bike = bike
		return true
class Gameplay extends RefCounted:
	var health := 100.0
	var reports := 0
	func report_observed_crime(_amount, _point, _kind, _source) -> void: reports += 1
class World extends Node3D:
	var player: CharacterBody3D
	var gameplay := Gameplay.new()
	var production: Node
class Session extends RefCounted:
	var world: Node3D
	var modal := false
	var blocked := false
	func is_transition_blocked() -> bool: return blocked
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures.append(title); push_error(title)
func run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	var world := World.new()
	root.add_child(world)
	world.player = ACTOR.new()
	world.player.is_player = true
	world.add_child(world.player)
	world.player.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,.2,80)
	floor_shape.shape = box
	floor_body.position.y = -.1
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var session := Session.new()
	session.world = world
	var controller := TheftController.new()
	controller.session = session
	world.add_child(controller)
	controller.set_physics_process(false)
	for aborting in [false,true]:
		controller.mounted = false
		var bike := BIKE.new()
		bike.set_meta("motocross_ambient",true)
		world.add_child(bike)
		bike.set_physics_process(false)
		world.player.teleport(Vector3(-1.05,.04,0))
		await physics_frame
		var original_model: Node3D = bike._rider_visual
		check(controller.steal_bike(bike),"occupied motocross starts a staged theft")
		check(controller.stealing and not controller.mounted and world.player.input_locked,"controls stay reserved before the punch finishes")
		check(not controller.steal_bike(bike),"duplicate theft is rejected during removal")
		if aborting: session.blocked = true
		var deadline := Time.get_ticks_msec() + 5000
		while controller.stealing and Time.get_ticks_msec() < deadline: await process_frame
		check(not controller.stealing,"finite theft sequence releases its busy state")
		check(is_instance_valid(original_model) and original_model != bike._rider_visual,"same displaced model survives separately from Dante's new rider")
		check(world.player.collision_layer == 2 and world.player.collision_mask == 7,"both completion and interruption restore player collision")
		check(controller.mounted != aborting,"world transition cancels takeover; ordinary completion mounts afterward")
		session.blocked = false
		bike.queue_free()
		await process_frame
	world.free()
	await process_frame
	print("MOTOCROSS_CARJACKING checks=",checks," failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
