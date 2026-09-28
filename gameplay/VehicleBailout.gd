extends Node
## Owns Dante's physical body only during a moving dismount, never the car.
signal exited(point: Vector3)
signal cancelled(reason: String, point: Vector3)

const MIN_SPEED := 2.0
const ROLL_SECONDS := 0.85
const RECOVER_SECONDS := 0.8
var exiting := true
var active := false
var phase := "jump"
var world: Node
var actor: CharacterBody3D
var vehicle: CharacterBody3D
var side := -1
var age := 0.0
var ground_age := 0.0
var impact_speed := 0.0
var landed := false
var _visual_transform := Transform3D.IDENTITY
var _shape: CollisionShape3D
var _original_shape: Shape3D
var _pose: Array = []
var _yaw := 0.0
var _door_closed := false
var _source_excepted := false

static func damage_for_speed(speed: float) -> float:
	return clampf((absf(speed)-MIN_SPEED)*0.8+3.0,3.0,18.0)

func begin(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, point: Vector3, momentum: Vector3, exit_side: int) -> void:
	world = owner_world
	actor = pedestrian
	vehicle = car
	# Suppress stale broadphase contacts while the seated body is reactivated.
	# Admission already swept the door and the landing hull against the world.
	actor.add_collision_exception_with(vehicle)
	vehicle.add_collision_exception_with(actor)
	_source_excepted = true
	side = exit_side
	impact_speed = momentum.length()
	_visual_transform = actor.visual.transform
	_pose = actor._capture_pose()
	actor.teleport(point)
	actor.show()
	actor.input_locked = true
	actor.set_physics_process(false)
	actor.clear_combat_weapon_pose()
	# Conservative standing-height hull also protects the tucked body at walls.
	for child in actor.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			_shape = child
			_original_shape = child.shape
			var hull = child.shape.duplicate()
			hull.radius = 0.65
			child.shape = hull
			break
	var outward := car.global_basis.x*float(side)
	var planar := momentum.limit_length(9.0)*0.65+outward*2.0
	_yaw = atan2(-planar.x,-planar.z)
	actor.velocity = planar+Vector3.UP*2.0
	vehicle.animate_driver_door(side,true,0.12)
	active = true
	_present(0.0,0.0)

func reverse_entry_to_exit() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(actor): return
	age += delta
	if age > 0.35: _release_source()
	actor.velocity.y -= 20.0*delta
	var planar := Vector3(actor.velocity.x,0,actor.velocity.z)
	planar = planar.move_toward(Vector3.ZERO,(7.0 if landed else 1.5)*delta)
	actor.velocity.x = planar.x
	actor.velocity.z = planar.z
	actor.move_and_slide()
	if actor.is_on_floor() and age > 0.1 and not landed:
		landed = true
		phase = "roll"
		# Armor does not protect against a fall. Apply once, at ground contact.
		if is_instance_valid(world.get("gameplay")):
			world.gameplay.damage_environment(damage_for_speed(impact_speed))
		if not active: return # Death/respawn may synchronously cancel the transition.
		if is_instance_valid(world.get("gameplay")) and world.gameplay.health <= 0:
			abort("death")
			return
	if landed:
		ground_age += delta
		if ground_age >= ROLL_SECONDS: phase = "recover"
		var roll := clampf(ground_age/ROLL_SECONDS,0.0,1.0)
		var recover := smoothstep(ROLL_SECONDS,ROLL_SECONDS+RECOVER_SECONDS,ground_age)
		_present(roll,recover)
		if recover >= 1.0 and actor.is_on_floor(): _finish()
	else:
		_present(0.0,0.0)
	if age > 0.4 and not _door_closed and is_instance_valid(vehicle):
		_door_closed = true
		vehicle.animate_driver_door(side,false,0.2)

func _present(roll: float, recover: float) -> void:
	if not is_instance_valid(actor.visual): return
	actor._apply_pose(actor._idle_pose)
	var tuck := (smoothstep(0.0,0.2,age))*(1.0-recover)
	var skeleton: Skeleton3D = actor.skeleton
	if is_instance_valid(skeleton):
		for prefix in ["Left","Right"]:
			var sign_side := 1.0 if prefix == "Left" else -1.0
			_tuck_limb(prefix+"Arm",prefix+"ForeArm",Vector3(sign_side*.08,-.22,.22),tuck)
			_tuck_limb(prefix+"ForeArm",prefix+"Hand",Vector3(-sign_side*.12,.14,.16),tuck)
			_tuck_limb(prefix+"UpLeg",prefix+"Leg",Vector3(sign_side*.04,.02,.36),tuck)
			_tuck_limb(prefix+"Leg",prefix+"Foot",Vector3(0,-.24,-.20),tuck)
	var fall := smoothstep(0.0,0.22,age)
	var pitch := lerpf(-PI*0.5*fall-TAU*roll,-TAU,recover)
	var basis := Basis.from_euler(Vector3(pitch,_yaw,0))
	actor.visual.basis = basis.scaled(_visual_transform.basis.get_scale())
	# Rotate around the tucked torso, not the feet; keep the body above ground.
	var height := lerpf(0.88,0.62,fall)*(1.0-recover)+0.88*recover
	actor.visual.position = _visual_transform.origin+Vector3.UP*height-basis*Vector3.UP*0.88

func _tuck_limb(name: String, child_name: String, offset: Vector3, weight: float) -> void:
	var skeleton: Skeleton3D = actor.skeleton
	var bone := skeleton.find_bone(name)
	var child := skeleton.find_bone(child_name)
	if bone < 0 or child < 0: return
	var origin := skeleton.get_bone_global_pose(bone).origin
	var current := skeleton.get_bone_global_pose(child).origin
	actor._point_combat_bone(bone,child,current.lerp(origin+offset,weight))

func _release_source() -> void:
	if not _source_excepted: return
	_source_excepted = false
	if is_instance_valid(actor) and is_instance_valid(vehicle):
		actor.remove_collision_exception_with(vehicle)
		vehicle.remove_collision_exception_with(actor)

func _restore() -> void:
	active = false
	_release_source()
	if is_instance_valid(_shape): _shape.shape = _original_shape
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side,false,0.15)
	if not is_instance_valid(actor): return
	actor.velocity = Vector3.ZERO
	actor.visual.transform = _visual_transform
	if not actor.dead: actor._apply_pose(_pose)

func _finish() -> void:
	_restore()
	exited.emit(actor.global_position)
	queue_free()

func abort(reason: String) -> void:
	if not active: return
	_restore()
	cancelled.emit(reason,actor.global_position if is_instance_valid(actor) else Vector3.ZERO)
	queue_free()

func _exit_tree() -> void:
	if active: _restore()
