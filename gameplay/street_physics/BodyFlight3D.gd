extends Node
## One swept capsule and articulated follow-through; no per-limb physics solver.
const GRAVITY := 22.0
const SELF_RECOVERY_SECONDS := 45.0
const GET_UP_SECONDS := 0.9
const POSE := preload("res://gameplay/street_physics/BodyImpactPose3D.gd")
const AUDIO := preload("res://audio/VehicleCrashAudio.gd")
var actor: CharacterBody3D
var director: Node
var velocity := Vector3.ZERO
var vertical := 0.0
var lethal := false
var flying := true
var down_time := 0.0
var bounces := 0
var source: WeakRef
var impact_speed := 0.0
var _visual_base := Transform3D.IDENTITY
var _saved_layer := 2
var _saved_mask := 7
var _getting_up := false
var _age := 0.0
var _grounded := false
var _yaw := 0.0
var _heading := Vector3.BACK
var _shape: CollisionShape3D
var _shapes: Array[Dictionary] = []
var _pose := POSE.new()
var _restored := false
var _recovery_tween: Tween

static func launch(p_actor: CharacterBody3D, impact_velocity: Vector3, p_lethal: bool, p_director: Node, p_source: Node) -> Node:
	if not is_instance_valid(p_actor) or not impact_velocity.is_finite(): return null
	if preload("res://gameplay/DamageProtection.gd").is_protected(p_actor): return null
	if p_actor.has_meta("street_down") or p_actor.get("dead") == true: return null
	var flight = load("res://gameplay/street_physics/BodyFlight3D.gd").new()
	flight.name = "BodyFlight3D"
	flight.actor = p_actor
	flight.director = p_director
	flight.lethal = p_lethal
	flight.source = weakref(p_source) if is_instance_valid(p_source) else null
	flight.impact_speed = impact_velocity.length()
	var flat := Vector3(impact_velocity.x, 0, impact_velocity.z)
	var speed := minf(flat.length(), 37.5)
	flight._heading = flat.normalized() if speed > .01 else Vector3.BACK
	flight.velocity = flight._heading * minf(speed*.65, 16.0)
	flight.vertical = clampf(speed*.16, 1.0, 4.0)
	flight._yaw = atan2(flight._heading.x, flight._heading.z)
	p_actor.add_child(flight)
	return flight

func _ready() -> void:
	_saved_layer = actor.collision_layer
	_saved_mask = actor.collision_mask
	actor.collision_layer = 0
	actor.collision_mask = 1
	actor.set_physics_process(false)
	actor.set_meta("street_flying", true)
	actor.set_meta("street_down", true)
	actor.set_meta("street_pose_owned", true)
	var visual: Node3D = actor.get("visual")
	if is_instance_valid(visual):
		_visual_base = visual.transform
		_pose.capture(visual)
	for child in actor.get_children():
		if child is CollisionShape3D:
			_shapes.append({"node":child,"disabled":child.disabled})
			child.disabled = true
	_shape = CollisionShape3D.new()
	var hull := CapsuleShape3D.new()
	hull.radius = .38
	hull.height = 1.85
	_shape.shape = hull
	_shape.position = Vector3.UP*.4
	_shape.basis = actor.global_basis.inverse()*Basis(Vector3.UP,_yaw)*Basis(Vector3.RIGHT,PI*.5)
	actor.add_child(_shape)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor): queue_free(); return
	if flying: _fly(delta)
	elif not lethal: _wait_for_help(delta)

func _fly(delta: float) -> void:
	_age += delta
	# External fire/explosion damage can clear the actor's mask mid-flight.
	actor.collision_mask = 1
	vertical -= GRAVITY*delta
	var motion := velocity + Vector3.UP*vertical
	var contact := actor.move_and_collide(motion*delta)
	_grounded = false
	if contact != null:
		var normal := contact.get_normal()
		var speed := maxf(0.0,-motion.dot(normal))
		if speed > 1.2:
			var audio_context: Node3D = director if director is Node3D else actor
			AUDIO.play_body_impact(audio_context,actor,actor.global_position+Vector3.UP*.4,speed,true)
		if normal.y > .55:
			_grounded = true
			if vertical < -3.0 and bounces == 0:
				vertical = -vertical*.16
				bounces += 1
			else: vertical = 0.0
			velocity = velocity.slide(normal)
			velocity.y = 0
		else:
			velocity = velocity.slide(normal)*.35
			vertical = minf(vertical,0.0)
	velocity = velocity.move_toward(Vector3.ZERO,(22.0 if _grounded else 5.0)*delta)
	_present()
	if _grounded and vertical == 0 and velocity.length() < .3 and _age > .35: _land()

func _present(recovery := 0.0) -> void:
	var visual: Node3D = actor.get("visual")
	if not is_instance_valid(visual): return
	var fall := smoothstep(0.0,.38,_age)
	var target := Basis(Vector3.UP,_yaw)*Basis(Vector3.RIGHT,PI*.5)*Basis(Vector3.UP,.06)
	var start := _visual_base.basis.orthonormalized()
	var basis := start.slerp(target,fall*(1.0-recovery))
	visual.basis = basis.scaled(_visual_base.basis.get_scale())
	# Rotate around the pelvis, preserving the same settled pose at landing.
	var center := lerpf(.86,.19,fall)*(1.0-recovery)+.86*recovery
	visual.position = _visual_base.origin+Vector3.UP*center-basis*Vector3.UP*.86
	_pose.apply(_age,_grounded,recovery)

func _land() -> void:
	flying = false
	actor.remove_meta("street_flying")
	actor.collision_mask = 0
	_restore_shapes()
	if is_instance_valid(director):
		director.on_body_landed(actor,lethal,source.get_ref() if source != null else null,impact_speed,_heading)
	actor.remove_meta("street_pose_owned")
	if lethal or actor.get("dead") == true:
		_restored = true
		queue_free()

func _wait_for_help(delta: float) -> void:
	if actor.get("dead") == true:
		if _recovery_tween != null: _recovery_tween.kill()
		_restored = true
		queue_free()
		return
	if _getting_up: return
	down_time += delta
	if float(actor.get("health")) >= 60.0 or down_time >= SELF_RECOVERY_SECONDS: _get_up()

func _get_up() -> void:
	_getting_up = true
	_recovery_tween = create_tween()
	_recovery_tween.tween_method(func(t: float): _present(smoothstep(0,1,t)),0.0,1.0,GET_UP_SECONDS)
	_recovery_tween.tween_callback(func():
		if not is_instance_valid(actor) or actor.get("dead") == true: return
		actor.health = maxf(float(actor.get("health")),35.0)
		_restore()
		queue_free())

func _restore_shapes() -> void:
	if is_instance_valid(_shape):
		_shape.disabled = true
		_shape.queue_free()
	for saved in _shapes:
		if is_instance_valid(saved.node): saved.node.disabled = saved.disabled
	_shapes.clear()

func _restore() -> void:
	if _restored or not is_instance_valid(actor): return
	_restored = true
	_restore_shapes()
	actor.remove_meta("street_pose_owned")
	actor.remove_meta("street_flying")
	actor.remove_meta("street_down")
	if actor.get("dead") == true: return
	actor.collision_layer = _saved_layer
	actor.collision_mask = _saved_mask
	actor.velocity = Vector3.ZERO
	actor.set_physics_process(true)
	var visual: Node3D = actor.get("visual")
	if is_instance_valid(visual): visual.transform = _visual_base
	_pose.restore()

func _exit_tree() -> void:
	_restore()
