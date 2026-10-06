extends RefCounted
## Scene-free timer with ordered, forward physical gate crossings.
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
var active := false
var finished := false
var settled := false
var failure := ""
var countdown := 3.0
var elapsed := 0.0
var gate := 0
var outside := 0.0
var vehicle_token := 0
var previous := Vector3.ZERO
var staging := Vector3.ZERO
var gates: Array[Dictionary] = []

func begin(token: int, archetype: String, point: Vector3) -> bool:
	if active or token == 0 or archetype != COURSE.VEHICLE or not point.is_finite(): return false
	if point.distance_to(COURSE.start()) > 4.0: return false
	active=true; finished=false; settled=false; failure=""; countdown=3.0; elapsed=0.0; gate=0; outside=0.0
	vehicle_token=token; previous=point; staging=point; gates=COURSE.checkpoints()
	return true

func cancel(reason := "cancelled") -> void:
	active=false
	failure=reason

func tick(delta: float, point: Vector3, token: int, valid_driver: bool) -> void:
	if not active: return
	if not valid_driver or token != vehicle_token:
		cancel("driver_left"); return
	if not is_finite(delta) or delta <= 0.0 or delta > .5 or not point.is_finite():
		cancel("interrupted"); return
	if previous.distance_to(point) > maxf(2.5,45.0*delta):
		cancel("teleport"); return
	if countdown > 0.0:
		if point.distance_to(staging)>1.0: cancel("false_start"); return
		countdown=maxf(0.0,countdown-delta); previous=point; return
	elapsed += delta
	if elapsed > COURSE.TIME_LIMIT: cancel("timeout"); return
	outside=outside+delta if COURSE.corridor_distance(point)>COURSE.WIDTH*.5+2.0 else 0.0
	if outside>2.0: cancel("off_course"); return
	var target: Dictionary = gates[gate]
	var center: Vector3 = target.position
	var forward: Vector3 = target.forward
	var before := (previous-center).dot(forward)
	var after := (point-center).dot(forward)
	if before<=0.0 and after>0.0:
		var crossing := previous.lerp(point,-before/(after-before))
		var lateral := Vector3(forward.z,0,-forward.x)
		if absf((crossing-center).dot(lateral)) <= COURSE.WIDTH*.5 and absf(crossing.y-center.y) < 2.0:
			gate+=1
			if gate==gates.size(): active=false; finished=true
	previous=point

func target_position() -> Vector3:
	if not active: return Vector3.INF
	return staging if countdown>0.0 else Vector3(gates[gate].position)
