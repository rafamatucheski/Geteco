extends CharacterBody2D
## Physical passenger tour. Every step is swept; route progress stops on obstacles.
signal arrived
signal obstructed
const MODEL := preload("res://world/harbor/campaign/MaciotaM8SedanModel.gd")
var model: Node3D
var heading := PI/2
var route := PackedVector2Array()
var cursor := 1
var driving := false
var speed := 0.0
var travelled := 0.0
var blocked_time := 0.0
var shape: CollisionShape2D
var last_obstacle := ""
var engine := preload("res://audio/VehicleEngineSound.gd").new()
var engine_audio: AudioStreamPlayer2D
var lamps: Array[PointLight2D] = []
var avoidance_wait := 0.0
var pass_attempts := 0
var obstacle_id := 0
var obstacle_anchor := Vector2.ZERO
var stationary_time := 0.0
var _rotation_obstacle: Node2D
var pass_reason := ""
var throttle := 0.0
var _previous_speed := 0.0
var _steering := 0.0
var sprite: Sprite2D
var body_viewport: SubViewport
var pass_plan: RefCounted
var pass_lane: Path2D
var pass_join := 0
var pass_side := 0
# The sedan is wider than the previous coupe. Keep the first sidewalk option
# inside the authored pavement while leaving larger offsets for open shoulders.
const PASS_OFFSETS := [44.0, -40.0, 72.0, -72.0, 100.0, -100.0]
const MANEUVER := preload("res://cars/traffic/EmergencyRoadManeuver.gd")
const SEAT_OFFSET := 35.0

func _ready() -> void:
	name = "MaciotaM8Sedan"
	z_index = 5
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	shape = CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(67,29)
	shape.shape = rectangle
	add_child(shape)
	var view := SubViewport.new()
	body_viewport = view
	view.size = Vector2i(384,384)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(view)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .8
	view.find_world_3d().environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = 1.8
	view.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.position = Vector3(0,9,6)
	view.add_child(camera)
	camera.look_at(Vector3.ZERO)
	model = MODEL.new()
	view.add_child(model)
	# The rendered closed body, including bumpers and mirrors, defines the
	# physical footprint. Local -Z is the car's forward axis.
	var half_extent := Vector2.ZERO
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = mesh.get_aabb()
		var relative: Transform3D = model.global_transform.affine_inverse()*mesh.global_transform
		for corner in 8:
			var point: Vector3 = relative*bounds.get_endpoint(corner)
			half_extent = half_extent.max(Vector2(absf(point.z),absf(point.x)))
	rectangle.size = half_extent*2.0*16.6
	sprite = Sprite2D.new()
	sprite.texture = view.get_texture()
	sprite.scale = Vector2.ONE*(10.0*16.6/384.0)
	add_child(sprite)
	engine_audio = AudioStreamPlayer2D.new()
	engine_audio.bus = "SFX"
	engine_audio.volume_db = -28.0
	engine_audio.max_distance = 1000
	add_child(engine_audio)
	engine.bind(engine_audio,"maciota_m8")
	for side in [-1,1]:
		var light_2d := PointLight2D.new()
		light_2d.texture = preload("res://legacy/city_demo/scripts/HeadlightTextureGenerator.gd").get_conical_headlight_texture()
		light_2d.offset = Vector2(100,0)
		light_2d.texture_scale = .55
		light_2d.energy = .8
		add_child(light_2d)
		lamps.append(light_2d)
	pose()

func pose() -> void:
	global_rotation = heading
	shape.rotation = 0
	sprite.rotation = -heading
	model.rotation.y = -heading-PI/2
	for i in lamps.size():
		lamps[i].position = Vector2(32,-10 if i == 0 else 10)
		lamps[i].rotation = 0
		lamps[i].visible = driving

func seat(index: int) -> Vector2:
	# The M8's wider shoulders need a little more lateral clearance so the
	# whole actor body can leave without touching the sill or the car hull.
	return global_position + Vector2.from_angle(heading+PI/2)*( -SEAT_OFFSET if index == 0 else SEAT_OFFSET)

func start(points: PackedVector2Array) -> void:
	route = points
	cursor = 1
	speed = 0
	travelled = 0
	blocked_time = 0
	avoidance_wait = 0
	pass_attempts = 0
	obstacle_id = 0
	stationary_time = 0
	last_obstacle = ""
	pass_reason = ""
	_previous_speed = 0
	throttle = 0
	pass_plan = null
	driving = route.size()>1
	if driving:
		engine.bind(engine_audio,"maciota_m8")
		engine.update(engine_audio,0.0,220.0,0.0,1.0/60.0,"maciota_m8")

func _physics_process(delta: float) -> void:
	if not driving:
		if engine_audio.playing:
			engine.stop()
			engine_audio.stop()
		return
	var acceleration := (speed-_previous_speed)/maxf(delta,.001)
	_previous_speed = speed
	throttle = move_toward(throttle, .6 if acceleration > 2 else (.18 if acceleration >= -2 and speed > 1 else 0.0), delta*1.2)
	engine.update(engine_audio,speed,220.0,throttle,delta,"maciota_m8")
	if pass_plan != null:
		_advance_pass(delta)
		return
	var offset := route[cursor]-global_position
	while offset.length()<4 or (cursor < route.size()-1 and offset.dot(route[cursor]-route[cursor-1]) < 0 and offset.length()<35):
		cursor += 1
		if cursor >= route.size():
			driving = false
			speed = 0
			velocity = Vector2.ZERO
			pose()
			arrived.emit()
			return
		offset = route[cursor]-global_position
	var aim := _lookahead(maxf(12.0,speed*.24))
	var desired := (aim-global_position).angle()
	var turn := absf(angle_difference(heading,desired))
	var remaining := global_position.distance_to(route[-1]) if cursor >= route.size()-5 else INF
	var parking := cursor >= route.size()/2 and global_position.distance_to(route[-1]) < 180
	var limit := 95.0 if turn < .20 else 38.0
	if parking: limit = minf(limit,22.0)
	limit = minf(limit,sqrt(maxf(0,remaining-1.0)*70.0))
	speed = move_toward(speed,limit,(30.0 if speed < limit else 65.0)*delta)
	var old_heading := heading
	heading = rotate_toward(heading,desired,maxf(.20,speed/30.0)*delta)
	if not _rotation_clear(old_heading,heading):
		pass_reason = "rotation blocked by solid"
		heading = old_heading
		_wait_for_obstacle(_rotation_obstacle,delta)
		return
	_steering = move_toward(_steering,clampf(angle_difference(old_heading,heading)/maxf(delta,.001)*.22,-.45,.45),delta*1.5)
	if model.has_method("steer"): model.steer(_steering)
	pose()
	var forward := Vector2.from_angle(heading)
	var step := forward*minf(speed*delta,offset.length())
	# Braking reserve ahead avoids touching a pedestrian or a stopped vehicle.
	var contact := KinematicCollision2D.new()
	# Parking creeps close to the facade; the road-speed stopping reserve
	# would stop a clear parallel approach before the steering can finish.
	var braking_probe := maxf(4.0,speed*.25) if parking else maxf(20.0,speed*.95)
	if test_move(global_transform,forward*braking_probe,contact):
		_wait_for_obstacle(contact.get_collider() as Node2D,delta)
		return
	var before := global_position
	move_and_collide(step)
	velocity = (global_position-before)/maxf(delta,.001)
	var moved := global_position.distance_to(before)
	travelled += moved
	model.roll(moved/16.6)
	blocked_time = 0
	avoidance_wait = 0
	stationary_time = 0

func _wait_for_obstacle(body: Node2D, delta: float) -> void:
	last_obstacle = str(body.get_path()) if is_instance_valid(body) else "unknown"
	if is_instance_valid(body):
		if obstacle_id == body.get_instance_id() and obstacle_anchor.distance_to(body.global_position)<2:
			stationary_time += delta
		else:
			obstacle_id = body.get_instance_id()
			obstacle_anchor = body.global_position
			stationary_time = 0
	speed = 0
	velocity = Vector2.ZERO
	blocked_time += delta
	avoidance_wait += delta
	if avoidance_wait > 3.0:
		avoidance_wait = 0
		pass_attempts += 1
		if _try_pass_stopped_vehicle(body):
			blocked_time = 0
			return
	if blocked_time > 8:
		blocked_time = 0
		if get_meta("test_audit",false):
			print("TOUR_WAIT at=",global_position," heading=",heading," obstacle=",last_obstacle," attempts=",pass_attempts," reason=",pass_reason)
		obstructed.emit()

func _rotation_clear(from: float, to: float) -> bool:
	var turn := absf(angle_difference(from,to))
	if turn < .0001: return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = Transform2D(lerp_angle(from,to,.5),global_position)
	# Inflate by the furthest corner's swept arc, so a clear final pose
	# cannot hide a bumper crossing a solid in the middle of a turn.
	query.margin = .05 + shape.shape.get_rect().size.length()*.5*sin(turn*.5)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var hits := get_world_2d().direct_space_state.intersect_shape(query,1)
	_rotation_obstacle = hits[0].collider as Node2D if not hits.is_empty() else null
	return hits.is_empty()

func _lookahead(distance: float) -> Vector2:
	var from := global_position
	for i in range(cursor,route.size()):
		var span := from.distance_to(route[i])
		if span >= distance: return from.lerp(route[i],distance/maxf(span,.001))
		distance -= span
		from = route[i]
	return route[-1]

func _exit_tree() -> void:
	engine.stop()

func _try_pass_stopped_vehicle(obstacle: Object) -> bool:
	pass_reason = "obstacle moving or not a vehicle"
	if not obstacle is CharacterBody2D or stationary_time<2.5: return false
	if not obstacle.is_in_group("vehicle") and not String(obstacle.name).begins_with("HarborTraffic"): return false
	pass_lane = null
	var nearest := 120.0
	for lane in get_tree().get_nodes_in_group("unified_traffic_lane"):
		if not lane is Path2D or lane.curve == null or lane.is_in_group("unified_lane_connector"): continue
		var point: Vector2 = lane.to_global(lane.curve.get_closest_point(lane.to_local(global_position)))
		if point.distance_to(global_position) < nearest:
			pass_lane = lane
			nearest = point.distance_to(global_position)
	if pass_lane == null: return false
	pass_join = cursor
	var distance := global_position.distance_to(route[cursor])
	while pass_join < route.size()-1 and distance < 430:
		pass_join += 1
		distance += route[pass_join-1].distance_to(route[pass_join])
	if distance < 160: return false
	pass_side = 0
	_begin_pass_candidate()
	return pass_plan != null

func _begin_pass_candidate() -> void:
	pass_plan = null
	if pass_side >= PASS_OFFSETS.size(): return
	var spine := PackedVector2Array([global_position])
	spine.append_array(route.slice(cursor,pass_join+1))
	var length := 0.0
	for i in range(1,spine.size()): length += spine[i-1].distance_to(spine[i])
	var points := PackedVector2Array([global_position])
	var travelled_along := 0.0
	for i in range(1,spine.size()):
		var span := spine[i-1].distance_to(spine[i])
		var count := maxi(1,ceili(span/3.0))
		for j in range(1,count+1):
			var along := travelled_along+span*j/count
			var blend := smoothstep(0.0,length*.38,along)*smoothstep(0.0,length*.38,length-along)
			var normal := (spine[i]-spine[i-1]).normalized().orthogonal()
			points.append(spine[i-1].lerp(spine[i],float(j)/count)+normal*float(PASS_OFFSETS[pass_side])*blend)
		travelled_along += span
	var poses: Array[Transform2D] = [global_transform]
	for i in range(1,points.size()):
		var tangent := points[mini(i+1,points.size()-1)]-points[i-1]
		var distance := points[i].distance_to(poses.back().origin)
		if absf(angle_difference(poses.back().get_rotation(),tangent.angle())) > distance/28.0:
			pass_side += 1
			_begin_pass_candidate()
			return
		poses.append(Transform2D(tangent.angle(),points[i]))
	pass_plan = MANEUVER.new()
	pass_plan.configure(self,pass_lane,poses)
	pass_reason = "checking opposite lane / sidewalk"

func _advance_pass(delta: float) -> void:
	if pass_plan.pending:
		speed = 0
		velocity = Vector2.ZERO
		pass_plan.advance_plan()
		return
	if not pass_plan.valid:
		pass_reason = pass_plan.failure
		pass_side += 1
		_begin_pass_candidate()
		return
	# Vector2.orthogonal() used by the candidate points is -pose.y.
	var lateral := -float(PASS_OFFSETS[pass_side])
	var half_road := float(pass_lane.get_meta("traffic_road_width",0))*.5
	var lane_offset := absf(float(pass_lane.get_meta("traffic_lane_offset",0)))
	var on_sidewalk := lateral > half_road-lane_offset-18 or lateral < -half_road-lane_offset+18
	var limit := 24.0 if on_sidewalk else 42.0
	speed = move_toward(speed,limit,24.0*delta)
	var next: Transform2D = pass_plan.next(minf(speed*delta,3.0))
	if not pass_plan.clear(global_transform,next):
		speed = 0
		velocity = Vector2.ZERO
		pass_reason = pass_plan.failure
		return
	var before := global_position
	move_and_collide(next.origin-before)
	if global_position.distance_to(next.origin) > .01: return
	heading = next.get_rotation()
	pose()
	var moved := global_position.distance_to(before)
	travelled += moved
	model.roll(moved/16.6)
	velocity = (global_position-before)/maxf(delta,.001)
	if pass_plan.finished():
		cursor = pass_join
		pass_plan = null
		blocked_time = 0
		stationary_time = 0
		pass_reason = "returned to tour route"
