extends SceneTree
const APPROACH = preload("res://world/shared/emergency/AmbulanceApproach.gd")
class Unit extends CharacterBody2D:
	var current_speed := 0.0
	var stuck_despawn_timer := 0.0
	var is_reversing := false
	var responded := false
	var is_returning_to_base := false
	func _begin_response() -> void: responded = true
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(-500,0))
	lane.curve.add_point(Vector2(800,0))
	world.add_child(lane)
	lane.add_to_group("unified_traffic_lane")
	var unit := Unit.new()
	unit.collision_layer = 2
	unit.collision_mask = 7
	var hull := CollisionShape2D.new()
	hull.name = "CollisionShape2D"
	hull.shape = RectangleShape2D.new()
	hull.shape.size = Vector2(100,46)
	unit.add_child(hull)
	world.add_child(unit)
	unit.position = Vector2(-350,0)
	var patient := Node2D.new()
	patient.position = Vector2(200,100)
	world.add_child(patient)
	var planner := APPROACH.new()
	await physics_frame
	check(planner.service_clear(unit,patient,Transform2D(0,Vector2(280,0))),"Open lane has full unloading and walking clearance")
	var pole := preload("res://geodata/roads/traffic/FixedTrafficSignal.gd").new()
	pole.position = Vector2(202,0)
	world.add_child(pole)
	await physics_frame
	check(not planner.service_clear(unit,patient,Transform2D(0,Vector2(280,0))),"Actual fixed signal blocks rear cot extraction even when hull fits")
	pole.position = Vector2(288,45)
	await physics_frame
	check(not planner.service_clear(unit,patient,Transform2D(0,Vector2(280,0))),"Actual fixed signal blocks door and side walkway")
	pole.position = Vector2(200,0)
	await physics_frame
	var previous := unit.position
	var heading := unit.rotation
	var coherent := true
	for frame in 1600:
		planner.tick(unit,patient,1.0/60)
		var motion := unit.position-previous
		var turn := angle_difference(heading,unit.rotation)
		coherent = coherent and absf(turn) <= motion.length()/65+.002
		coherent = coherent and absf(motion.dot(Vector2.from_angle(heading+turn*.5).orthogonal())) < .05
		previous = unit.position
		heading = unit.rotation
		if unit.responded: break
		await physics_frame
	check(unit.responded,"Blocked ideal point selects an alternative and arrives")
	check(unit.position.x+60 < pole.position.x or unit.position.x-118 > pole.position.x,"Alternative preserves front or rear service envelope around obstruction")
	check(coherent,"Translation and yaw stay coherent throughout maneuver")
	check(planner.service_clear(unit,patient,unit.global_transform),"Final pose has viable cot route to patient")
	# A swept curve must not skip a narrow obstacle between endpoint queries.
	unit.position = Vector2(-350,0)
	unit.rotation = 0
	pole.position = Vector2(-100,0)
	await physics_frame
	check(not planner._build_trajectory(unit,Transform2D(0,Vector2(280,0))),"Continuous hull sweep rejects a pole along the maneuver")
	check(not planner._build_trajectory(unit,Transform2D(PI,Vector2(-330,0))),"A tight turn cannot become an in-place rotation")
	pole.position = Vector2(900,900)
	unit.position = Vector2(-350,0)
	unit.rotation = 0
	await physics_frame
	# Pavement is generated from the same polylines used to draw this L road.
	planner.road_surfaces.assign(Geometry2D.offset_polyline(PackedVector2Array([Vector2(-500,0),Vector2(0,0)]),60))
	planner.road_surfaces.append_array(Geometry2D.offset_polyline(PackedVector2Array([Vector2(0,0),Vector2(0,400)]),60))
	check(not planner._build_trajectory_with_lead(unit,Transform2D(PI*.5,Vector2(0,240)),0),"Long direct curve correctly rejects cutting outside an L junction")
	check(planner._build_trajectory(unit,Transform2D(PI*.5,Vector2(0,240))),"Approach remains on the entry street before turning through the junction")
	var priority := preload("res://world/shared/emergency/AmbulanceManeuverReservation.gd").new()
	world.add_child(priority)
	priority.configure(unit)
	priority.follow(planner.trajectory,planner.headings,1)
	var traffic := CharacterBody2D.new()
	world.add_child(traffic)
	var ahead := Transform2D(planner.headings[15],planner.trajectory[15])
	check(preload("res://world/shared/emergency/MedicalRescueWorkZone.gd").blocks_hull(traffic,hull.shape,ahead),"Crossing traffic sees the reserved upcoming maneuver before entering it")
	priority.cancel()
	check(not preload("res://world/shared/emergency/MedicalRescueWorkZone.gd").blocks_hull(traffic,hull.shape,ahead),"Cancelling a maneuver releases its traffic reservation immediately")
	var hospital_priority := preload("res://world/shared/emergency/AmbulanceManeuverReservation.gd").new()
	world.add_child(hospital_priority)
	hospital_priority.allow_hospital_return = true
	hospital_priority.configure(unit)
	hospital_priority.follow(planner.trajectory,planner.headings,1)
	unit.is_returning_to_base = true
	hospital_priority._physics_process(0)
	check(hospital_priority.active,"Hospital return keeps its maneuver reserved against crossing traffic")
	unit.set_meta("hospital_available",true)
	hospital_priority._physics_process(0)
	check(not hospital_priority.active,"Completed hospital parking releases maneuver priority")
	unit.remove_meta("hospital_available")
	unit.position = Vector2(-350,0)
	unit.rotation = 0
	var arrival := preload("res://world/shared/emergency/HospitalArrival.gd").new()
	arrival.tick(unit,Vector2(-100,0),0,1.0/60)
	var pedestrian := StaticBody2D.new()
	pedestrian.collision_layer = 4
	pedestrian.position = unit.position+Vector2(64,0)
	var pedestrian_shape := CollisionShape2D.new()
	pedestrian_shape.shape = CircleShape2D.new()
	pedestrian_shape.shape.radius = 7
	pedestrian.add_child(pedestrian_shape)
	world.add_child(pedestrian)
	await physics_frame
	for i in 150:
		arrival.tick(unit,Vector2(-100,0),0,1.0/60)
		await physics_frame
	check(not arrival.path.is_empty() and arrival.search==null and absf(unit.rotation)<.001,"Pedestrian crossing preserves the planned hospital maneuver without a pivot or replan")
	var waiting_position := unit.position
	pedestrian.queue_free()
	await physics_frame
	for i in 60:
		arrival.tick(unit,Vector2(-100,0),0,1.0/60)
		await physics_frame
	check(unit.position.x>waiting_position.x+20,"Hospital maneuver resumes when the pedestrian clears")
	arrival.reset()
	print("AMBULANCE_PARKING_CONTRACT failures=",failures)
	quit(0 if failures.is_empty() else 1)
