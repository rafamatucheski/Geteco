extends SceneTree
## Straight traffic has no rotation sweep to validate. Every real turn still
## requests collision clearance, and a denied turn must keep its prior heading.

class QueryProbe extends "res://scripts/Vehicle.gd":
	var rotation_queries := 0
	var queried_yaw := NAN
	var rotation_clear := true

	func _ready() -> void:
		set_physics_process(false)

	func can_rotate(yaw: float) -> bool:
		rotation_queries += 1
		queried_yaw = yaw
		return rotation_clear

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func route_to(destination: Vector3) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(destination)
	curve.set_meta("traffic_open", true)
	return curve

func prepare(car: QueryProbe, curve: Curve3D, speed_value := 3.0) -> void:
	car.route = curve
	car.traffic = true
	car.position = Vector3.ZERO
	car.rotation.y = 0.0
	car.speed = speed_value
	car.blocked = false
	car.junction_wait = false
	# Isolate the heading decision between the ordinary 10 Hz obstacle scans.
	car.sensor_clock = 1.0
	car.rotation_queries = 0
	car.queried_yaw = NAN

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var car := QueryProbe.new()
	scene.add_child(car)
	var straight := route_to(Vector3(0, 0, -100))
	prepare(car, straight)
	for step in 4:
		car._drive_traffic(1.0 / 60.0)
	check(car.rotation.y == 0.0, "Straight traffic keeps its exact heading")
	check(car.rotation_queries == 0, "Unchanged heading performs no rotation collision query")

	var turn := route_to(Vector3(25, 0, -80))
	prepare(car, turn)
	car.rotation_clear = false
	car._drive_traffic(1.0 / 60.0)
	check(car.rotation_queries == 1 and car.queried_yaw != 0.0, "A real turn requests collision clearance")
	check(car.rotation.y == 0.0, "Denied clearance prevents turning into an obstruction")

	prepare(car, turn)
	car.rotation_clear = true
	car._drive_traffic(1.0 / 60.0)
	check(car.rotation_queries == 1 and is_equal_approx(car.rotation.y, car.queried_yaw), "A clear turn applies its validated heading")

	prepare(car, route_to(Vector3(0.0001, 0, -100)))
	car._drive_traffic(1.0 / 60.0)
	check(car.rotation_queries == 1 and car.rotation.y != 0.0, "Tiny real heading changes retain collision clearance")

	prepare(car, turn, 0.0)
	car.blocked = true
	car._drive_traffic(1.0 / 60.0)
	check(car.rotation_queries == 0 and car.rotation.y == 0.0, "Stopped traffic keeps the existing no-turn behavior")

	scene.free()
	print("TRAFFIC_ROTATION_QUERY_BUDGET checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
