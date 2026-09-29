extends CharacterBody3D
## Shared arcade physics for the rider and opponents. Forward is -Z; positive
## steering turns LEFT. Inputs are supplied by the race/world controller.
## Optional combat signals; crashes hurt but always allow recovery.

signal crashed(damage: float)
signal recovered
## quality: "perfect", "clean" or "rough"; only jumps with real flight time.
signal landed(quality: String, air_time: float)

# Calibrated on the real circuit: riders who leave the pitch alone touch down
# 0.27-0.46 rad off the landing face (whoops included), so they stay "clean";
# only an actively matched attitude is perfect, only a badly wrong one rough.
const LANDING_MIN_AIR := .38
const LANDING_PERFECT := .14
const LANDING_ROUGH := .50

var paint_color := Color("e87823")
var rider_color := Color("e4e9ef")
var rider_name := "Piloto"
var is_player := false
var max_speed := 18.0
var acceleration := 8.5
var profile_id := 0
var turn_response := 1.0
var grip_multiplier := 1.0
## Rain-soaked clay reduces drive torque, stopping power and lateral grip.
var wetness := 0.0:
	set(value): wetness = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
var race_enabled := true
var air_lean := 0.0
var speed := 0.0
var health := 100.0
var crash_state := "riding"
var crash_count := 0
var distance_travelled := 0.0
var visual: Node3D
var rider: CharacterBody3D
var _rider_visual
var _rider_shape: CollisionShape3D
var _front: Node3D
var _wheels: Array[Node3D] = []
var _throttle := 0.0
var _steering := 0.0
var _brake := false
var _state_time := 0.0
var _hurt_duration := 1.7
var _crash_side := 1.0
var _wheel_angle := 0.0
var _air_time := 0.0
var _pitch := 0.0
var _recovery_grace := 1.0
var _return_stall := 0.0
var _ground_normal := Vector3.UP
var _planar_velocity := Vector3.ZERO
var _mount_origin := Vector3.ZERO
var _last_rider_position := Vector3.ZERO
var _contact_cooldown := 0.0
var _contact_velocity := Vector3.ZERO
var _contact_roll := 0.0
var _suspension := 0.0
var _ramp_up := 0.0
var _ramp_age := 1.0
var jump_count := 0
var perfect_landings := 0
var rough_landings := 0
var last_landing_error := 0.0
## Player only: pitch minus the slope of the ground under the bike while in the
## air (positive = nose too high). Drives the HUD attitude cue.
var air_attitude_error := 0.0
## Start-gate result timers: surge, bogged engine, or front wheel in the air.
var launch_boost := 0.0
var launch_bog := 0.0
var wheelie := 0.0
var landing_boost := 0.0
var _wheelie_pitch := 0.0
var dead := false
var _combat: Node
var _threat_time := 0.0
var _hit_tween: Tween

func _ready() -> void:
	collision_layer = 4
	collision_mask = 7
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	max_slides = 4
	var hull := CollisionShape3D.new()
	# A rounded longitudinal hull crosses triangulated ramp seams without a
	# box corner catching an internal edge and being reported as a wall.
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.85
	hull.shape = shape
	hull.rotation.x = PI / 2.0
	hull.position.y = 0.34
	add_child(hull)
	_build_visual()
	set_meta("gameplay_role", "motocross_bike")
	add_to_group("motocross_bikes")
	add_to_group("v2_damageable")
	set_meta("impact_material","metal")

func drive(throttle: float, steering: float, brake: bool = false) -> void:
	_throttle = clampf(throttle, -1.0, 1.0) if is_finite(throttle) else 0.0
	_steering = clampf(steering, -1.0, 1.0) if is_finite(steering) else 0.0
	_brake = brake

func bind_combat(gameplay: Node) -> void:
	if _combat==gameplay: return
	_disconnect_combat()
	_combat = gameplay
	if not is_instance_valid(_combat): return
	_combat.weapon_fired.connect(_weapon_fired)
	_combat.npc_gunfire.connect(_npc_gunfire)
	_combat.explosion_occurred.connect(_explosion)

func _disconnect_combat() -> void:
	if not is_instance_valid(_combat): return
	for entry in [["weapon_fired",_weapon_fired],["npc_gunfire",_npc_gunfire],["explosion_occurred",_explosion]]:
		if _combat.is_connected(entry[0],entry[1]): _combat.disconnect(entry[0],entry[1])

func _exit_tree() -> void: _disconnect_combat()

func _weapon_fired(weapon: String,origin: Vector3) -> void:
	if weapon in ["fists","grenade"]: return
	var data: Dictionary = _combat.weapon_data(weapon) if is_instance_valid(_combat) and _combat.has_method("weapon_data") else {}
	_react_to_shot(origin,13.0 if data.get("suppressed",false) else 27.0)
func _npc_gunfire(origin: Vector3,_direction: Vector3,_shooter: Node3D) -> void: _react_to_shot(origin,27.0)
func _explosion(origin: Vector3,radius: float,_source: Node) -> void: _react_to_shot(origin,radius+22.0)

func _react_to_shot(origin: Vector3,radius: float) -> void:
	if not is_inside_tree() or not race_enabled or is_player: return
	if global_position.distance_squared_to(origin)>radius*radius: return
	_threat_time = 2.8
	_contact_roll = .10 if (origin-global_position).dot(global_basis.x)<0 else -.10

func receive_damage(amount: float,source: Node = null) -> void:
	if not is_finite(amount) or amount<=0 or preload("res://gameplay/DamageProtection.gd").is_protected(self): return
	health = maxf(15.0,health-amount*.5)
	if race_enabled and rider.visible:
		crash(clampf(amount/45.0,.2,.9))
	else:
		# Parked rental props are still physical, targetable motorcycles.
		if is_instance_valid(_hit_tween): _hit_tween.kill()
		visual.rotation.z = -.12+clampf(amount*.003,.04,.15)
		_hit_tween = create_tween()
		_hit_tween.tween_property(visual,"rotation:z",-.12,.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func reset_to(where: Transform3D) -> void:
	if not where.origin.is_finite(): return
	global_transform = where
	velocity = Vector3.ZERO
	_planar_velocity = Vector3.ZERO
	_contact_velocity = Vector3.ZERO
	_contact_roll = 0.0
	_suspension = 0.0
	_ramp_up = 0.0
	_ramp_age = 1.0
	speed = 0.0
	_air_time = 0.0
	_pitch = 0.0
	_ground_normal = Vector3.UP
	_recovery_grace = 1.3
	_throttle = 0.0
	_steering = 0.0
	launch_boost = 0.0
	launch_bog = 0.0
	wheelie = 0.0
	landing_boost = 0.0
	_wheelie_pitch = 0.0
	crash_state = "riding"
	_state_time = 0.0
	if is_instance_valid(visual):
		visual.rotation = Vector3.ZERO
		visual.position = Vector3.ZERO
	if is_instance_valid(rider): _seat_rider()
	reset_physics_interpolation()

func crash(severity: float = 0.5) -> void:
	if crash_state != "riding" or not is_inside_tree(): return
	var force := clampf(severity, 0.1, 1.0) if is_finite(severity) else 0.5
	var damage := minf(health - 15.0, 8.0 + force * 24.0)
	health -= maxf(0.0, damage)
	crash_count += 1
	crash_state = "fallen"
	_state_time = 0.0
	launch_boost = 0.0
	wheelie = 0.0
	landing_boost = 0.0
	_wheelie_pitch = 0.0
	visual.position = Vector3.ZERO
	_hurt_duration = 1.6 + force * 1.5 + (100.0 - health) * 0.007
	_crash_side = -1.0 if _steering > 0.0 else 1.0
	rider.top_level = true
	rider.collision_layer = 2
	rider.collision_mask = 5
	_rider_shape.disabled = false
	rider.add_collision_exception_with(self)
	add_collision_exception_with(rider)
	# The detached body moves through physics, including its first sideways fall.
	rider.velocity = -global_basis.z * minf(absf(speed) * 0.35, 4.0) + global_basis.x * _crash_side * 2.2 + Vector3.UP * 2.0
	speed *= 0.25
	crashed.emit(maxf(0.0, damage))

func _physics_process(delta: float) -> void:
	if delta <= 0.0: return
	_recovery_grace = maxf(0.0, _recovery_grace - delta)
	_contact_cooldown = maxf(0.0,_contact_cooldown-delta)
	_contact_velocity = _contact_velocity.move_toward(Vector3.ZERO,delta*5.0)
	_contact_roll = move_toward(_contact_roll,0.0,delta*.9)
	_suspension = move_toward(_suspension,0.0,delta*.22)
	_ramp_age += delta
	_threat_time = maxf(0.0,_threat_time-delta)
	launch_boost = maxf(0.0,launch_boost-delta)
	launch_bog = maxf(0.0,launch_bog-delta)
	wheelie = maxf(0.0,wheelie-delta)
	landing_boost = maxf(0.0,landing_boost-delta)
	var grounded := is_on_floor()
	var incoming_y := velocity.y
	var before := global_position
	var riding := crash_state == "riding" and race_enabled
	if riding:
		var mud_speed := lerpf(1.0, 0.82, wetness)
		var target := _throttle * (max_speed * mud_speed if _throttle >= 0.0 else 3.2)
		if _threat_time>0 and not is_player: target *= .68
		var rate := acceleration * lerpf(1.0, 0.70, wetness) if absf(_throttle) > 0.01 else lerpf(2.3, 3.8, wetness)
		if _throttle > 0.0:
			# A matched landing carries the rider briefly past the normal pace.
			if landing_boost > 0.0:
				target *= 1.12
				rate *= 1.5
			if wheelie > 0.0: rate *= .35
			elif launch_boost > 0.0: rate *= 1.75
			elif launch_bog > 0.0: rate *= .55
		if _brake:
			target = 0.0
			rate = lerpf(17.0, 11.0, wetness)
		speed = move_toward(speed, target, rate * delta)
		if absf(speed) > 0.15:
			var turning := _steering * minf(absf(speed) / 3.0, 1.0) * lerpf(1.65, 0.9, clampf(absf(speed) / maxf(0.1, max_speed), 0.0, 1.0))
			rotation.y += turning * turn_response * signf(speed) * delta * (lerpf(1.0, 0.88, wetness) if grounded else 0.3)
	else:
		speed = move_toward(speed, 0.0, 14.0 * delta)
	var forward := -global_basis.z
	var motion := forward * speed
	var grip := lerpf(18.0, 5.5, wetness) * grip_multiplier if grounded else 2.5
	_planar_velocity = _planar_velocity.lerp(motion, 1.0 - exp(-grip * delta))
	motion = _planar_velocity+_contact_velocity
	if grounded:
		_ground_normal = get_floor_normal()
		motion = motion.slide(_ground_normal)
		velocity.y = motion.y - 0.1
		_air_time = 0.0
		# Preserve uphill momentum at a convex crest. Projecting onto the new
		# flat/downhill normal used to erase it and glue the bike to the ramp.
		if riding and speed>6 and _ramp_age<.16 and _ramp_up>1.5 and motion.y<_ramp_up*.5:
			velocity.y = _ramp_up*.95
			_ramp_up = 0.0
			_ramp_age = 1.0
			_suspension = -.04
		elif motion.y>1.5:
			_ramp_up = motion.y
			_ramp_age = 0.0
	else:
		velocity.y -= 20.0 * delta
		_air_time += delta
		if is_player and _air_time > .1: _sample_ground_below()
	velocity.x = motion.x
	velocity.z = motion.z
	var impact_speed := absf(speed)
	var incoming_motion := velocity
	move_and_slide()
	if grounded and not is_on_floor() and riding and velocity.y>1.0:
		jump_count += 1
	_planar_velocity = Vector3(velocity.x, 0.0, velocity.z)
	distance_travelled += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var real_wall := false
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var other = collision.get_collider()
		if other is CharacterBody3D and other.is_in_group("motocross_bikes"):
			if riding and _contact_cooldown<=0.0 and other._contact_cooldown<=0.0:
				var normal := collision.get_normal().slide(Vector3.UP).normalized()
				var relative: Vector3 = incoming_motion-other.velocity
				var strength := maxf(0.0,-relative.dot(normal))
				if strength>.5:
					_receive_contact(normal,strength)
					other._receive_contact(-normal,strength)
	if is_on_wall():
		for index in get_slide_collision_count():
			var collision := get_slide_collision(index)
			var collider = collision.get_collider()
			if collider is Node and collider.is_in_group("motocross_bikes"): continue
			var normal := collision.get_normal()
			if normal.y < cos(floor_max_angle) and normal.dot(forward * signf(speed)) < -0.3:
				real_wall = true
	if real_wall:
		var actual := Vector2(velocity.x, velocity.z).length()
		if riding and _recovery_grace <= 0.0 and impact_speed > 7.0 and impact_speed - actual > 3.8:
			crash(clampf(impact_speed / maxf(0.1, max_speed), 0.1, 1.0))
		speed = minf(absf(speed), actual) * signf(speed)
	if riding and not grounded and is_on_floor() and _recovery_grace <= 0.0:
		_suspension = -clampf(-incoming_y*.008,0.0,.055)
		# Proper ramp landings are forgiving; nose-diving and very hard falls hurt.
		if incoming_y < -11.0 or (incoming_y < -6.0 and absf(_pitch) > 0.85):
			crash(clampf((-incoming_y - 5.0) / 12.0, 0.1, 1.0))
		elif _air_time >= LANDING_MIN_AIR:
			_grade_landing()
	_front.rotation.y = lerpf(_front.rotation.y,_steering*.4 if crash_state=="riding" else .5,minf(1.0,delta*14.0))
	if crash_state != "riding":
		if race_enabled: _update_recovery(delta)
	else:
		_pose_riding(delta)
	_wheel_angle -= speed * delta / 0.36
	for wheel in _wheels: wheel.rotation.x = _wheel_angle

func launch(quality: String) -> void:
	match quality:
		"holeshot":
			launch_boost = 1.5
			speed = maxf(speed, 3.2)
		"wheelie": wheelie = .8
		"bog": launch_bog = 1.1

func _grade_landing() -> void:
	# `_pitch` still holds the in-flight attitude; compare it with the face the
	# tires just met. Leaning (W/S in the air) is what changes this match.
	var normal := get_floor_normal()
	var slope := atan2(-normal.dot(-global_basis.z), maxf(.05, normal.y))
	last_landing_error = absf(_pitch - slope)
	var quality := "clean"
	if last_landing_error <= LANDING_PERFECT:
		quality = "perfect"
		perfect_landings += 1
		landing_boost = 1.3
	elif last_landing_error >= LANDING_ROUGH:
		quality = "rough"
		rough_landings += 1
		speed *= .85
		_suspension = -.07
	landed.emit(quality, _air_time)

func _sample_ground_below() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.2,global_position-Vector3.UP*14.0,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var normal: Vector3 = hit.normal
	air_attitude_error = _pitch-atan2(-normal.dot(-global_basis.z),maxf(.05,normal.y))

func _receive_contact(normal: Vector3,strength: float) -> void:
	_contact_cooldown = .35
	_contact_velocity = normal*clampf(strength*.32,.25,2.8)
	_contact_roll = clampf(-normal.dot(global_basis.x)*strength*.04,-.22,.22)
	if crash_state!="riding": return
	# Rubbing fairings unsettles a rider. A fall needs relative impact energy,
	# not just a fast bike touching another equally fast bike from behind.
	if strength>5.8 and _recovery_grace<=0.0:
		crash(clampf(strength/16.0,.2,.9))
	else: speed *= .96

func _pose_riding(delta: float) -> void:
	var forward := -global_basis.z
	var slope := atan2(-_ground_normal.dot(forward),maxf(.05,_ground_normal.y))
	var flight_pitch := atan2(velocity.y,maxf(3.0,absf(speed)))*.8
	var desired_pitch := slope if is_on_floor() else lerpf(_pitch,flight_pitch,minf(1.0,delta*3.0))
	_pitch = lerpf(_pitch, clampf(desired_pitch, -1.1, 1.1), minf(1.0, delta * 10.0))
	# Rider lean acts directly on the attitude. Inside the double lerp above it
	# was damped to ~0.24 rad/s and could not square a 0.4 s flight to a face.
	if not is_on_floor(): _pitch = clampf(_pitch + clampf(air_lean, -1.0, 1.0) * delta * 2.4, -1.1, 1.1)
	var wheelie_goal := .40 if wheelie > 0.0 and is_on_floor() else 0.0
	_wheelie_pitch = lerpf(_wheelie_pitch, wheelie_goal, minf(1.0, delta * (8.0 if wheelie_goal > 0.0 else 4.0)))
	visual.rotation.x = _pitch + _wheelie_pitch
	# The wheelie pivots on the rear tire patch instead of sinking it into the ground.
	var pivot := Vector3(0, 0, .83)
	visual.position = pivot - Basis(Vector3.RIGHT, _wheelie_pitch) * pivot
	var slip := clampf(_planar_velocity.dot(global_basis.x)*.035,-.10,.10)
	visual.rotation.z = lerpf(visual.rotation.z, _steering * clampf(absf(speed) / maxf(0.1, max_speed), 0.0, 1.0) * 0.32+slip+_contact_roll, minf(1.0, delta * 9.0))
	var lift := .035*smoothstep(.05,.22,_air_time)
	rider.transform = visual.transform*Transform3D(Basis.IDENTITY,Vector3(0,.96+_suspension+lift,.04))
	_rider_visual.position = Vector3.ZERO
	var posture := -.5+(.06 if _brake and speed>2 else -.025*_throttle)-lift
	_rider_visual.rotation.x = lerpf(_rider_visual.rotation.x,posture,minf(1.0,delta*8))
	_rider_visual.rotation.z = lerpf(_rider_visual.rotation.z,-_contact_roll*.5,minf(1.0,delta*8))
	_pose_limbs(0.0, true)

func pose_start_mount(blend: float) -> void:
	# Staged on the clear grid while bike physics is held by the race controller.
	var t := smoothstep(0.0,1.0,blend)
	rider.position = Vector3(lerpf(-.95,0.0,t),lerpf(.79,.96,t)+sin(t*PI)*.18,.04)
	rider.rotation = Vector3.ZERO
	_rider_visual.rotation = Vector3(-.50*t,0.0,-sin(t*PI)*.22)
	_rider_visual.pose(self,smoothstep(.65,1,t),sin(t*TAU)*.25)

func _update_recovery(delta: float) -> void:
	_state_time += delta
	visual.rotation.z = lerpf(visual.rotation.z, _crash_side * 1.3, minf(1.0, delta * 7.0))
	visual.rotation.x = lerpf(visual.rotation.x, 0.0, minf(1.0, delta * 5.0))
	rider.velocity.y = -0.6 if rider.is_on_floor() else rider.velocity.y - 20.0 * delta
	match crash_state:
		"fallen":
			rider.velocity.x = move_toward(rider.velocity.x, 0.0, delta * 4.0)
			rider.velocity.z = move_toward(rider.velocity.z, 0.0, delta * 4.0)
			_rider_visual.rotation.z = lerpf(_rider_visual.rotation.z, _crash_side * 1.45, minf(1.0, delta * 8.0))
			_rider_visual.position.y = lerpf(_rider_visual.position.y, -0.55, minf(1.0, delta * 8.0))
			if _state_time >= _hurt_duration: _change_state("standing")
		"standing":
			rider.velocity.x = 0.0
			rider.velocity.z = 0.0
			var blend := clampf(_state_time / 0.7, 0.0, 1.0)
			_rider_visual.rotation = Vector3(-0.25 * sin(blend * PI), 0.0, _crash_side * 1.45 * (1.0 - blend))
			_rider_visual.position.y = -0.55 * (1.0 - blend)
			_pose_limbs(0.0, false)
			if blend >= 1.0:
				_return_stall = 0.0
				_last_rider_position = rider.global_position
				_change_state("returning")
		"returning":
			var goal := global_position + global_basis.x * _crash_side * 0.75
			var toward := goal - rider.global_position
			toward.y = 0.0
			var direction := toward.normalized()
			rider.velocity.x = direction.x * 1.8
			rider.velocity.z = direction.z * 1.8
			if toward.length() > 0.1: rider.rotation.y = atan2(-direction.x, -direction.z)
			_pose_limbs(sin(_state_time * 9.0) * 0.4, false)
			if toward.length() < 0.22:
				_mount_origin = rider.global_position
				_change_state("mounting")
			# If a solid blocks the direct approach, try the other side, never teleport.
			if rider.global_position.distance_to(_last_rider_position) < 0.01:
				_return_stall += delta
			else: _return_stall = 0.0
			_last_rider_position = rider.global_position
			if _return_stall > 0.8:
				_crash_side *= -1.0
				_return_stall = 0.0
		"mounting":
			var blend := clampf(_state_time / 0.7, 0.0, 1.0)
			visual.rotation.z = _crash_side * 1.3 * (1.0 - blend)
			var seat := to_global(Vector3(0.0, 0.96, 0.04))
			var next := _mount_origin.lerp(seat, blend)
			rider.velocity = (next - rider.global_position) / maxf(delta, 0.001)
			rider.rotation.y = lerp_angle(rider.rotation.y, rotation.y, blend)
			_rider_visual.pose(self,smoothstep(.65,1,blend),0)
			if blend >= 1.0:
				_seat_rider()
				crash_state = "riding"
				_recovery_grace = 1.5
				recovered.emit()
				return
	rider.move_and_slide()

func _change_state(next: String) -> void:
	crash_state = next
	_state_time = 0.0

func _seat_rider() -> void:
	rider.top_level = false
	rider.collision_layer = 0
	rider.collision_mask = 0
	_rider_shape.disabled = true
	rider.velocity = Vector3.ZERO
	rider.transform = visual.transform*Transform3D(Basis.IDENTITY,Vector3(0,.96,.04))
	_rider_visual.position = Vector3.ZERO
	_rider_visual.rotation = Vector3(-0.50, 0.0, 0.0)
	_pose_limbs(0.0, true)
	rider.reset_physics_interpolation()

func _pose_limbs(stride: float, mounted: bool) -> void:
	if is_instance_valid(_rider_visual): _rider_visual.pose(self,1.0 if mounted else 0.0,stride)

static func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.78
	return result

func _build_visual() -> void:
	preload("res://activities/motocross/MotocrossBikeArt.gd").build(self)
	_build_rider()

func _build_rider() -> void:
	rider = CharacterBody3D.new()
	rider.name = "Rider"
	rider.collision_layer = 0
	rider.collision_mask = 0
	rider.floor_snap_length = 0.4
	add_child(rider)
	_rider_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.55
	_rider_shape.shape = capsule
	_rider_shape.disabled = true
	_rider_shape.position.y = -0.05
	rider.add_child(_rider_shape)
	_rider_visual = preload("res://activities/motocross/MotocrossRiderArt.gd").new()
	_rider_visual.jersey_color = rider_color
	_rider_visual.accent_color = paint_color
	rider.add_child(_rider_visual)
	_seat_rider()
