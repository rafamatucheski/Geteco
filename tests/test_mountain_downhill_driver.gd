extends SceneTree
## A regressão de sensores usa obstáculos de física reais; a direção completa é coberta por
## test_mountain_downhill_runtime --drive na sessão .NET de produção.
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

## Impasse de 07/10: rival na faixa da esquerda com um carro contrário parado a ~8 m e o pelotão na direita.
func oncoming_encounter() -> void:
	for child in space.get_children():
		if child is StaticBody3D: child.free()
	var at := course.length-85.0
	var forward: Vector3 = course.direction(at)
	var right := forward.cross(Vector3.UP).normalized()
	var yaw := atan2(-forward.x,-forward.z)
	car.position = course.point(at)-right*1.8
	car.rotation.y = yaw
	car.speed = 1.0
	var pilot := DRIVER.new()
	pilot.setup(car,course,0)
	pilot.lane = -1.8
	pilot.desired_lane = -1.8
	pilot.pass_cooldown = 5.0
	# Contrário: um "carro" virado para nós na mesma faixa.
	var van := obstacle(course.point(at+8.5)-right*1.8+Vector3.UP*.65,yaw+PI,Vector3(2,.8,4.6))
	van.add_to_group("drivable")
	var blocker := obstacle(course.point(at+1.0)+right*1.8+Vector3.UP*.65,yaw,Vector3(2,.8,4.6))
	blocker.add_to_group("drivable")
	await physics_frame
	await physics_frame
	pilot._sense(at,8.0)
	check(pilot.merge_request and pilot.desired_lane == -1.8,"oncoming car with a rival alongside asks for room instead of cutting in")
	check(is_equal_approx(pilot.stop_gap,6.5),"oncoming car makes the driver stop with room left to swerve")
	# O rival que estava ao lado seguiu; o que vem atrás parou com folga: sobra o desvio curto.
	blocker.position = course.point(at-10.0)+course.direction(at-10.0).cross(Vector3.UP).normalized()*1.8+Vector3.UP*.65
	await physics_frame
	await physics_frame
	check(not pilot._lane_clear(at,8.0,1.8),"the long two-second merge is still blocked by the oncoming car itself")
	pilot._sense(at,8.0)
	check(pilot.desired_lane == 1.8 and pilot.lane_rate > 1.8,"short low-speed swerve takes the gap the rival behind left")
	# Quem está na direita atrás de um pedido para antes dele; quem está à frente segue.
	var follower := DRIVER.new()
	var follower_car := SensorCar.new()
	follower_car.position = course.point(at-30.0)+right*1.8
	space.add_child(follower_car)
	follower.setup(follower_car,course,1)
	follower.lane = 1.8
	pilot.merge_request = true
	pilot.course_offset = at
	follower.peers = [pilot,follower]
	check(follower._yield_speed(at-14.0) < 5.0,"right-lane rival behind the request slows to open the gap")
	check(follower._yield_speed(at-8.0) == 0.0,"right-lane rival stops with room for the swerve")
	check(follower._yield_speed(at+3.0) == INF,"right-lane rival ahead keeps going so the gap opens behind it")
	follower.car.free()
	van.free()
	blocker.free()

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
	# Fila de 28/10: colado no carro lento (2–4 m) o corredor da troca tocava nele e ninguém ultrapassava.
	wall.position = car.position+forward*5.8+Vector3.UP*.65
	pilot.desired_lane = 1.8
	pilot.pass_cooldown = 0.0
	await physics_frame
	await physics_frame
	pilot._sense(at,8.0)
	check(pilot.gap < 4.0 and pilot.desired_lane == -1.8,"a slow car right ahead does not block its own overtaking corridor")
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
	await oncoming_encounter()
	print("DOWNHILL_DRIVER checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
