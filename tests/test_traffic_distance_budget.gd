extends SceneTree

class TestWorld extends Node3D:
	var player: Node3D

class TrafficCar extends "res://scripts/Vehicle.gd":
	func _ready() -> void:
		set_physics_process(false)

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var car := TrafficCar.new()
	world.add_child(car)
	car.traffic = true
	car.position = Vector3(80, 0, -10)
	check(car._lod_stride() == 4, "Distant off-screen traffic uses four-step cadence")
	car.position = Vector3(0, 0, -80)
	check(car._lod_stride() == 2, "Visible traffic retains its existing cadence")
	car.position = Vector3(0, 0, -30)
	check(car._lod_stride() == 1, "Nearby traffic remains full rate")
	car.position = Vector3(80, 0, -10)
	world.player.position = car.position
	check(car._lod_stride() == 2, "Player proximity prevents the new off-screen reduction")
	world.player.position = Vector3.ZERO

	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 1, 200)
	floor_shape.shape = floor_box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var body_shape := CollisionShape3D.new()
	body_shape.shape = BoxShape3D.new()
	car.add_child(body_shape)
	car.position = Vector3(0, 0.5, -30)
	await physics_frame
	car.velocity = Vector3.DOWN
	car.move_and_slide()
	check(car.is_on_floor(), "Native collision establishes ground support")
	car._lod_pending = 2.0 / 60.0
	check(is_equal_approx(car._lod_gate(1.0 / 60.0), 3.0), "Near reentry preserves skipped simulation time")
	check(car._lod_pending == 0.0, "Consumed elapsed time is cleared once")
	car._lod_pending = 2.0 / 60.0
	car.controlled = true
	check(car._lod_gate(1.0 / 60.0) == 1.0 and car._lod_pending == 0.0, "Taking control discards ambient backlog")
	car.controlled = false
	car._lod_pending = 2.0 / 60.0
	car.set_meta("crash_stun", 1.0)
	check(car._lod_gate(1.0 / 60.0) == 1.0 and car._lod_pending == 0.0, "Crash response resumes immediately without backlog")
	world.free()
	print("TRAFFIC_DISTANCE_BUDGET checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
