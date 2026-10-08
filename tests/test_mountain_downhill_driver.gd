extends SceneTree
## Sensor regression uses actual physics obstacles; full driving is covered by
## test_mountain_downhill_runtime --drive in the production .NET session.
const DRIVER := preload("res://activities/mountain_downhill/MountainDownhillDriver.gd")
const COURSE := preload("res://activities/mountain_downhill/MountainDownhillCourse.gd")
class SensorCar extends CharacterBody3D:
	var max_forward_speed := 33.0
	var half_width := 1.0
	var half_length := 2.5
	var speed := 10.0
	var player_damage_attribution := false
	func set_external_driver(_active: bool) -> void: pass

var checks := 0
var failures := 0
var space: Node3D
var car: SensorCar
var course := COURSE.new()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("DOWNHILL_DRIVER ","PASS " if ok else "FAIL ",label)

func obstacle(point: Vector3, yaw: float, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = point
	body.rotation.y = yaw
	space.add_child(body)
	return body

func run() -> void:
	space = Node3D.new()
	root.add_child(space)
	car = SensorCar.new()
	space.add_child(car)
	var at := course.length-85.0
	var forward: Vector3 = course.direction(at)
	var right := forward.cross(Vector3.UP).normalized()
	var yaw := atan2(-forward.x,-forward.z)
	car.position = course.point(at)+right*1.8
	car.rotation.y = yaw
	var pilot := DRIVER.new()
	pilot.setup(car,course,1)
	check(pilot._passing_straight(at),"fixture has enough straight road for overtaking")
	var wall := obstacle(car.position+forward*8.0+Vector3.UP*.65,yaw,Vector3(2,.8,1))
	await physics_frame
	await physics_frame
	pilot._sense(at,8.0)
	check(is_finite(pilot.gap),"actual static obstacle is detected")
	check(pilot.desired_lane == 1.8,"static obstacle is not mistaken for a vehicle to overtake")
	wall.add_to_group("drivable")
	pilot._sense(at,8.0)
	check(pilot.desired_lane == -1.8,"clear straight allows a real detected vehicle to be passed")
	wall.queue_free()
	await physics_frame
	await physics_frame
	pilot.lane = -1.8
	car.position = course.point(at)+right*3.8
	var middle := course.point(at+4.0)+right*2.8+Vector3.UP*.65
	wall = obstacle(middle,yaw,Vector3(.4,.8,.4))
	await physics_frame
	await physics_frame
	check(not pilot._lane_clear(at,8.0,1.8),"displaced car cannot pass through obstacle on its actual merge corridor")
	wall.queue_free()
	await physics_frame
	await physics_frame
	car.position = course.point(at)-right*1.8
	wall = obstacle(course.point(at-8.0)+right*1.8+Vector3.UP*.65,yaw,Vector3(1.8,.8,4))
	await physics_frame
	await physics_frame
	check(not pilot._lane_clear(at,8.0,1.8),"vehicle approaching in destination lane prevents cutting across it")
	wall.queue_free()
	await physics_frame
	await physics_frame
	var has_bend := false
	for offset in range(20,int(course.length)-100,4):
		if not pilot._passing_straight(float(offset)):
			has_bend = true
			at = float(offset)
			break
	check(has_bend,"authored hairpins refuse a two-second lane change")
	forward = course.direction(at)
	right = forward.cross(Vector3.UP).normalized()
	yaw = atan2(-forward.x,-forward.z)
	car.position = course.point(at)-right*1.8
	car.rotation.y = yaw
	pilot = DRIVER.new()
	pilot.setup(car,course,0)
	await physics_frame
	await physics_frame
	pilot._sense(at,8.0)
	check(pilot.desired_lane==1.8,"clear corridor returns the driver right before an oncoming encounter exists")
	var rear_forward: Vector3 = course.direction(at-4.0)
	var rear_point: Vector3 = course.point(at-4.0)+rear_forward.cross(Vector3.UP).normalized()*1.8+Vector3.UP*.65
	obstacle(rear_point,atan2(-rear_forward.x,-rear_forward.z),Vector3(1.8,.8,4))
	await physics_frame
	await physics_frame
	pilot = DRIVER.new()
	pilot.setup(car,course,0)
	pilot._sense(at,8.0)
	check(pilot.desired_lane == -1.8,"preventive return cannot merge into an occupied right lane")
	print("DOWNHILL_DRIVER checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
