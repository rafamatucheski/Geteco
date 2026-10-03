extends SceneTree
## Directed functional flow: actual autonomous vehicles, no teleport after spawn,
## no manual callbacks, synthetic TTL, changed speed or bypassed junction rules.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const JUNCTIONS = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const FIRST := Vector3.ZERO
const SECOND := Vector3(0,0,-20)
var checks := 0
var failures: Array[String] = []
var world: Node3D
var samples: Array[Dictionary] = []
var output := "user://traffic-junction-autonomous.json"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func curve(points: Array[Vector3]) -> Curve3D:
	var result := Curve3D.new()
	for point in points: result.add_point(point)
	result.set_meta("traffic_open",true)
	return result

func held(center: Vector3, id: int) -> bool:
	return JUNCTIONS.owners.get(JUNCTIONS.key_of(center),{}).has(id)

func query(center: Vector3, width: float) -> PhysicsShapeQueryParameters3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,6,width)
	var result := PhysicsShapeQueryParameters3D.new()
	result.shape = shape
	result.transform.origin = center + Vector3.UP*3
	result.collision_mask = 4
	return result

func contains(probe: PhysicsShapeQueryParameters3D, id: int) -> bool:
	for hit in world.get_world_3d().direct_space_state.intersect_shape(probe):
		if hit.collider.get_instance_id() == id: return true
	return false

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--junction-autonomy-output="): output = argument.trim_prefix("--junction-autonomy-output=")
	if "--no-save" not in OS.get_cmdline_user_args() or not ClassDB.class_exists(&"CSharpScript"):
		push_error("Requires compiled Godot .NET and --no-save"); quit(2); return
	create_timer(65).timeout.connect(func(): push_error("Autonomous junction fixture timeout"); quit(3))
	JUNCTIONS.configure({"vertices":[FIRST,Vector3(50,0,0),Vector3(-50,0,0),Vector3(0,0,50),SECOND,
		Vector3(50,0,-20),Vector3(-50,0,-20),Vector3(0,0,-60)],
		"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}],4:[{"to":0},{"to":5},{"to":6},{"to":7}]}})
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(130,1,150)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var owner = VEHICLE.new()
	owner.archetype = "route_city"
	owner.position = Vector3(0,.1,23)
	owner.route = curve([Vector3(0,0,50),FIRST,SECOND,Vector3(0,0,-55)])
	owner.traffic = true
	world.add_child(owner)
	var crossing = VEHICLE.new()
	crossing.archetype = "union_sedan"
	crossing.position = Vector3(-35,.1,0)
	crossing.rotation.y = -PI*.5
	crossing.route = curve([Vector3(-50,0,0),FIRST,Vector3(55,0,0)])
	crossing.traffic = true
	world.add_child(crossing)
	check(owner.shape.shape is BoxShape3D and owner.half_length > 4.8,"autonomous owner has the actual 9.78m catalogue hull")
	var owner_id := owner.get_instance_id()
	var crossing_id := crossing.get_instance_id()
	var core := query(FIRST,8)
	# Independent physical oracle of the controller's existing protected volume.
	var first_protected := query(FIRST,14)
	var second_protected := query(SECOND,14)
	var saw_first := false
	var saw_second := false
	var saw_dual := false
	var saw_dual_physical := false
	var saw_perpendicular_wait := false
	var unsafe_cross_frames := 0
	var first_clear_held_frames := 0
	var second_clear_held_frames := 0
	var first_clear_held_max := 0
	var second_clear_held_max := 0
	var previous_owner: Vector3 = owner.global_position
	var previous_crossing: Vector3 = crossing.global_position
	var largest_step := 0.0
	var began := Time.get_ticks_usec()
	var next_sample := began
	var complete := false
	while Time.get_ticks_usec()-began < 45000000:
		await physics_frame
		await process_frame
		var now := Time.get_ticks_usec()
		var first := held(FIRST,owner_id)
		var second := held(SECOND,owner_id)
		var first_physical := contains(first_protected,owner_id)
		var second_physical := contains(second_protected,owner_id)
		var owner_in_core := contains(core,owner_id)
		saw_first = saw_first or first
		saw_second = saw_second or second
		saw_dual = saw_dual or (first and second)
		saw_dual_physical = saw_dual_physical or (first_physical and second_physical)
		if owner_in_core and crossing.junction_wait and not held(FIRST,crossing_id): saw_perpendicular_wait = true
		if owner_in_core and contains(core,crossing_id): unsafe_cross_frames += 1
		first_clear_held_frames = first_clear_held_frames+1 if saw_second and first and not first_physical else 0
		second_clear_held_frames = second_clear_held_frames+1 if second and not second_physical and owner.global_position.z < SECOND.z else 0
		first_clear_held_max = maxi(first_clear_held_max,first_clear_held_frames)
		second_clear_held_max = maxi(second_clear_held_max,second_clear_held_frames)
		largest_step = maxf(largest_step,owner.global_position.distance_to(previous_owner))
		largest_step = maxf(largest_step,crossing.global_position.distance_to(previous_crossing))
		previous_owner = owner.global_position
		previous_crossing = crossing.global_position
		if now >= next_sample:
			next_sample = now+1000000
			samples.append({"t":(now-began)/1000000.0,"owner_position":str(owner.global_position),"owner_speed":owner.speed,
				"owner_wait":owner.junction_wait,"owner_gap":owner.junction_gap,"owner_blocked":owner.blocked,"owner_backoff":owner.backoff_time,
				"owner_token":str(owner.get("_held_junction")),"owner_health":owner.health,
				"crossing_position":str(crossing.global_position),"crossing_speed":crossing.speed,"crossing_wait":crossing.junction_wait,
				"first_owner":first,"second_owner":second,"first_crossing":held(FIRST,crossing_id),"first_physical":first_physical,"second_physical":second_physical})
		if owner.global_position.z < -37 and crossing.global_position.x > 22:
			complete = true
			break
	check(saw_first and saw_second,"normal driver autonomously acquired both crossings")
	check(saw_dual,"normal movement held both reservations simultaneously")
	check(saw_dual_physical,"real moving hull occupied both protected volumes during handoff")
	check(saw_perpendicular_wait,"perpendicular autonomous car waited while the long hull occupied the first core")
	check(unsafe_cross_frames == 0,"two autonomous bodies never simultaneously entered the first physical core")
	check(complete,"both autonomous vehicles made forward progress and cleared their crossings within 45s")
	check(largest_step < 1.0,"recorded motion has no teleport-sized displacement")
	check(first_clear_held_max <= 2 and second_clear_held_max <= 2,"normal departure releases cleared reservations within two observed physics frames")
	check(not held(FIRST,owner_id) and not held(SECOND,owner_id) and not held(FIRST,crossing_id),"all autonomous reservations clear without TTL expiry or explicit reset")
	check(owner.health == owner.max_health and crossing.health == crossing.max_health,"directed passage caused no vehicle collision damage")
	world.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_id_valid(owner_id) and not is_instance_id_valid(crossing_id),"scene cleanup freed both actual vehicles")
	check(not held(FIRST,owner_id) and not held(SECOND,owner_id) and not held(FIRST,crossing_id),"scene cleanup leaves no reservation IDs")
	JUNCTIONS.configure(null)
	var report := {"checks":checks,"failures":failures,"seconds":(Time.get_ticks_usec()-began)/1000000.0,"largest_step":largest_step,
		"first_clear_held_max":first_clear_held_max,"second_clear_held_max":second_clear_held_max,"unsafe_cross_frames":unsafe_cross_frames,"samples":samples,
		"scope":"Directed real autonomous traffic on two synthetic flat crossings twenty metres apart; no post-spawn teleport, manual callback or registry admission. Does not certify throughput of the whole city."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Could not write autonomy evidence"); quit(4); return
	file.store_string(JSON.stringify(report,"\t"))
	print("TRAFFIC_JUNCTION_AUTONOMOUS checks=",checks," failures=",failures.size()," seconds=",report.seconds)
	quit(0 if failures.is_empty() else 1)
