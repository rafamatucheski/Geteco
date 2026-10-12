extends SceneTree
const BOARD = preload("res://activities/skate/SkateBody.gd")
const STREET = preload("res://gameplay/street_physics/StreetPhysics.gd")

class TestCar extends CharacterBody3D:
	var controlled := false
	var half_length := 1.0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var car := TestCar.new()
	car.collision_layer = 4
	car.collision_mask = 7
	var hull := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 1, 2)
	hull.shape = shape
	hull.position.y = .6
	car.add_child(hull)
	stage.add_child(car)
	var board := BOARD.new()
	board.position = Vector3(0, 0, -1.5)
	stage.add_child(board)
	board.set_physics_process(false)
	board.riding = true
	board.collision_layer = 4
	board.collision_mask = 7
	var street := STREET.new()
	street._people_cache = [board]
	await physics_frame
	await physics_frame
	var motion := Vector3(0, 0, -2)
	var blocked_before := car.test_move(car.global_transform, motion)
	street._hit_people(car, Vector3(0, 0, -8), motion)
	var clear_after := not car.test_move(car.global_transform, motion)
	var ok := blocked_before and clear_after and not board.riding and board.speed > 0 and board.collision_layer == 0
	print("SKATE_VEHICLE_CONTACT blocked_before=", blocked_before, " clear_after=", clear_after, " riding=", board.riding, " board_speed=", board.speed)
	street.free()
	stage.free()
	quit(0 if ok else 1)
