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
## Tempo mínimo no chão antes de levantar. 0 mantém o atropelamento como era; o arremesso do motorista
## puxado do carro usa ~1,3 s para a queda ler como queda, não como tropeço.
var min_down := 0.0
var _visual_base := Transform3D.IDENTITY
var _saved_layer := 2
var _saved_mask := 7
var _saved_physics := false
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
# Shared with DispatchUnit until resumption. Restore/cancellation updates this
# desired state instead of publishing an invisible walking collider.
var _suspension: Dictionary = {}
var _impact_hull: CapsuleShape3D
var _ground_contact: Dictionary = {}

static func actor_visual(body: Object) -> Node3D:
	var presentation := preload("res://gameplay/CharacterFallPresentation3D.gd")
	var visual := presentation._property_node(body, "visual")
	return visual if visual != null else presentation._property_node(body, "model")

func suspend_for_dispatch(state: Dictionary) -> void:
	if _restored or not _suspension.is_empty(): return
	_suspension = state
	state.owner = weakref(self)
	state.owner_physics = is_physics_processing()
	state.tween_running = _recovery_tween != null and _recovery_tween.is_valid() and _recovery_tween.is_running()
	# Only the last real movement support can justify its residual penetration.
	# A new solid inserted before suspension must not become an accepted baseline.
	state.support = _ground_contact.duplicate() if _grounded and _support_matches(_ground_contact,_impact_transform()) else {}
	set_physics_process(false)
	if state.tween_running: _recovery_tween.pause()

func resume_from_dispatch() -> void:
	if _suspension.is_empty(): return
	if actor.get("dead") == true:
		if _recovery_tween != null: _recovery_tween.kill()
		_restore()
		queue_free()
		return
	var state := _suspension
	_suspension = {}
	set_physics_process(bool(state.owner_physics))
	if state.tween_running and _recovery_tween != null and _recovery_tween.is_valid(): _recovery_tween.play()

func suspension_clear(exclude: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _impact_hull
	var impact_transform := _impact_transform()
	query.transform = impact_transform
	query.collision_mask = 7
	query.exclude = exclude
	var space := actor.get_world_3d().direct_space_state
	if not _suspension_shape_clear(space,query,impact_transform,false): return false
	if not flying:
		# A prone survivor may recover on its first resumed tick (health or elapsed
		# down time). Check the actual return shapes before showing the whole unit.
		for child in actor.get_children():
			if not child is CollisionShape3D or child.disabled or child.shape == null or child == _shape: continue
			query.shape = child.shape
			query.transform = child.global_transform
			if not _suspension_shape_clear(space,query,impact_transform,true): return false
	return true

func _suspension_shape_clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D,
	impact_transform: Transform3D, returning: bool) -> bool:
	# Keep every collider in the native query, including floors that may share a
	# StaticBody with walls/ceilings. Saturation cannot certify free space.
	var contacts := space.collide_shape(query,16)
	if contacts.size() >= 32: return false
	for i in range(0,contacts.size(),2):
		var separation: Vector3 = contacts[i+1]-contacts[i]
		var depth := separation.length()
		if depth == 0.0: return false
		var normal := separation/depth
		if normal.y <= .55: return false # Same support criterion as _fly.
		var allowance: float = actor.safe_margin
		var support: Dictionary = _suspension.get("support",{})
		var same_support := _support_matches(support,impact_transform) and normal.is_equal_approx(support.normal) \
			and is_equal_approx(normal.dot(contacts[i+1]-impact_transform.origin),float(support.plane))
		if same_support:
			allowance = maxf(allowance,float(support.depth))
		if returning:
			if not query.shape is CapsuleShape3D: return false
			# Landing replaces the horizontal hull with the original capsule. Its
			# lower support can extend farther into the same floor (about 1 cm for
			# Responder). Accept only that geometric difference + native safe margin;
			# the existing walking solver recovers the contact after normal get-up.
			var return_pose := query.transform
			return_pose.origin -= impact_transform.origin
			allowance += maxf(0.0,_capsule_minimum(_impact_hull,Transform3D(impact_transform.basis,Vector3.ZERO),normal)
				-_capsule_minimum(query.shape,return_pose,normal))
		# Only the unchanged native support may differ by float representation
		# between its geometric support and the query's contact pair (~6e-9 m).
		if depth > allowance and not (same_support and is_equal_approx(depth,allowance)): return false
	return true

func _impact_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP,_yaw)*Basis(Vector3.RIGHT,PI*.5),actor.to_global(Vector3.UP*.4))

func _support_matches(support: Dictionary, pose: Transform3D) -> bool:
	return not support.is_empty() and support.pose == pose and support.world == actor.get_world_3d().space \
		and support.hull == Vector2(_impact_hull.radius,_impact_hull.height)

func _remember_support(contact: KinematicCollision3D, normal: Vector3) -> void:
	var pose := _impact_transform()
	# Plane math stays relative to the hull center, even far from the world origin.
	var plane := normal.dot(contact.get_position()-pose.origin)
	var relative := Transform3D(pose.basis,Vector3.ZERO)
	_ground_contact = {"pose":pose,"world":actor.get_world_3d().space,
		"hull":Vector2(_impact_hull.radius,_impact_hull.height),"normal":normal,"plane":plane,
		"depth":maxf(0.0,plane-_capsule_minimum(_impact_hull,relative,normal))}

static func _capsule_minimum(hull: CapsuleShape3D, pose: Transform3D, axis: Vector3) -> float:
	# Exact support of the transformed sphere + axial segment, including scale.
	return pose.origin.dot(axis)-hull.radius*(pose.basis.transposed()*axis).length() \
		-maxf(0.0,hull.height*.5-hull.radius)*absf(pose.basis.y.dot(axis))

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
	# Stop the old hit writer before capturing the base pose for this owner.
	preload("res://gameplay/CharacterFallPresentation3D.gd")._cancel_hit(actor)
	_saved_layer = actor.collision_layer
	_saved_mask = actor.collision_mask
	_saved_physics = actor.is_physics_processing()
	actor.collision_layer = 0
	actor.collision_mask = 1
	actor.set_physics_process(false)
	actor.set_meta("street_flying", true)
	actor.set_meta("street_down", true)
	actor.set_meta("street_pose_owned", true)
	var visual := actor_visual(actor)
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
	_impact_hull = hull
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
			_remember_support(contact,normal)
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
	var visual := actor_visual(actor)
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
	if down_time < min_down: return
	var health: Variant = actor.get("health")
	if (health != null and float(health) >= 60.0) or down_time >= (SELF_RECOVERY_SECONDS if health != null else 8.0): _get_up()

func _get_up() -> void:
	_getting_up = true
	_recovery_tween = create_tween()
	_recovery_tween.tween_method(func(t: float): _present(smoothstep(0,1,t)),0.0,1.0,GET_UP_SECONDS)
	_recovery_tween.tween_callback(func():
		if not is_instance_valid(actor) or actor.get("dead") == true: return
		if actor.get("health") != null: actor.set("health", maxf(float(actor.get("health")),35.0))
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
	if actor.is_queued_for_deletion():
		if not _suspension.is_empty(): _suspension.owner = null
		_suspension = {}
		return
	_restore_shapes()
	actor.remove_meta("street_pose_owned")
	actor.remove_meta("street_flying")
	actor.remove_meta("street_down")
	var dead: bool = actor.get("dead") == true
	if not _suspension.is_empty():
		_suspension.layer = 0 if dead else _saved_layer
		_suspension.mask = 0 if dead else _saved_mask
		_suspension.physics = false if dead else _saved_physics
		_suspension.owner = null
		_suspension = {}
	elif not dead:
		actor.collision_layer = _saved_layer
		actor.collision_mask = _saved_mask
		actor.set_physics_process(_saved_physics)
	if dead: return
	actor.velocity = Vector3.ZERO
	var visual := actor_visual(actor)
	if is_instance_valid(visual): visual.transform = _visual_base
	_pose.restore()

func _exit_tree() -> void:
	_restore()
