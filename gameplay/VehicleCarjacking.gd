extends RefCounted
## Finite, boarding-owned choreography. The displaced actor keeps its identity
## and resumes its original AI only after reaching a collision-checked landing.
const ACTOR := preload("res://scripts/Actor.gd")
var world: Node3D
var vehicle: CharacterBody3D
var victim: CharacterBody3D
var landing := Vector3.INF
var gate := Vector3.ZERO
var seat := Vector3.ZERO
var motorcycle := false
var released := false
var hit := false
var side := -1
var _layer := 2
var _mask := 7
var _physics := true
var _visual_transform := Transform3D.IDENTITY
var _seat_visual := Transform3D.IDENTITY
var _seat_root := Transform3D.IDENTITY
var _weapon: Node3D
var _weapon_visible := false
var _body: Node3D

static func driver_side(car: CharacterBody3D) -> int:
	return 1 if car.has_method("boarding_class") and car.boarding_class() == "bus" else -1

static func landing_point(owner_world: Node3D, car: CharacterBody3D, entry_side: int) -> Vector3:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.72
	var door: Vector3 = car.driver_door_anchor(entry_side) if car.has_method("driver_door_anchor") else car.global_position + car.global_basis.x * float(entry_side)
	var layout: Dictionary = car.door_layout(entry_side) if car.has_method("door_layout") else {}
	var base: Vector3 = car.to_global(layout.stand) if not layout.is_empty() else door
	var offsets: Array[float] = [1.25,1.8,2.4]
	# A boarding tube can occupy the pavement behind a bus's front door.
	# Its open front apron is still a legitimate, collision-checked landing.
	var lateral: Array[float] = [.5]
	if car.has_method("boarding_class") and car.boarding_class()=="bus":
		offsets=[0.0,1.25,1.8,2.4,-1.25,-1.8,-2.4]
		lateral=[.5,.9,1.3]
	var samples: Array[Vector2]=[]
	for back in offsets:
		for outward in lateral: samples.append(Vector2(back,outward))
	for sample in samples:
		var point: Vector3 = base + car.global_basis.z * sample.x + car.global_basis.x * float(entry_side) * sample.y
		var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 4, 1, [car.get_rid()])
		var floor_hit := owner_world.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty(): continue
		point.y = floor_hit.position.y + .04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .9)
		query.collision_mask = 7
		query.exclude = [car.get_rid(), owner_world.player.get_rid()]
		if owner_world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return point
	return Vector3.INF

func prepare(owner_world: Node3D, car: CharacterBody3D, person: CharacterBody3D, entry_side: int, destination: Vector3, bike := false) -> void:
	world = owner_world
	vehicle = car
	victim = person
	side = entry_side
	landing = destination
	motorcycle = bike
	seat = car.driver_seat_anchor() if car.has_method("driver_seat_anchor") else car.global_position + Vector3.UP * .96
	gate = car.driver_door_anchor(side) if car.has_method("driver_door_anchor") else car.global_position + car.global_basis.x * float(side)
	var layout: Dictionary = car.door_layout(side) if car.has_method("door_layout") else {}
	if not layout.is_empty(): gate = car.to_global(layout.gate)
	if car.has_method("boarding_class") and car.boarding_class()=="bus": gate.y=maxf(gate.y,landing.y)
	_layer = victim.collision_layer
	_mask = victim.collision_mask
	_physics = victim.is_physics_processing()
	_visual_transform = victim.visual.transform
	if motorcycle and victim.get_script() == ACTOR and not victim.has_method("pose_vehicle"):
		_visual_transform = Transform3D(Basis.IDENTITY, Vector3(0,.77,0))
	victim.set_physics_process(false)
	victim.collision_layer = 0
	victim.collision_mask = 0
	victim.add_collision_exception_with(car)
	if victim.visual.get("weapon") is Node3D:
		_weapon = victim.visual.weapon
		_weapon_visible = _weapon.visible
		_weapon.hide()
	if victim.get("skeleton") is Skeleton3D and victim.has_method("pose_vehicle"):
		victim.global_position = seat
		victim.rotation.y = car.global_rotation.y
		victim.pose_vehicle(1.0)
		victim.visual.position.y -= .40 if motorcycle else .48
		victim.visual.scale *= .88 if not motorcycle else 1.0
	else:
		victim.global_position = seat
		victim.rotation.y = car.global_rotation.y
		if victim.visual.get("body") is Node3D: _body = victim.visual.body
		elif victim.visual.get_child_count() > 0 and victim.visual.get_child(0).get("sit_amount") != null: _body = victim.visual.get_child(0)
		if is_instance_valid(_body):
			_body.sit_amount = 1.0
			_body.seat_height = .38
			if motorcycle and _body.get("motorcycle_helmet_color") != null: _body.motorcycle_helmet_color = Color("dce2df")
	_seat_root = car.global_transform.affine_inverse() * victim.global_transform
	_seat_visual = victim.visual.transform
	victim.show()

func follow_seat() -> void:
	if released or not is_instance_valid(victim) or not is_instance_valid(vehicle): return
	victim.global_transform = vehicle.global_transform * _seat_root

func apply(thief: CharacterBody3D, progress: float) -> void:
	if released or not is_instance_valid(victim): return
	var t := clampf(progress, 0.0, 1.0)
	var grip := victim.global_position + Vector3.UP * 1.05
	var toward := grip - thief.global_position
	toward.y = 0
	thief.visual.rotation.y = atan2(-toward.x, -toward.z) - thief.global_rotation.y
	thief.show()
	if motorcycle and t < .32:
		if is_instance_valid(thief.animation) and thief.animation.has_animation("ual/Punch_Cross"):
			thief._pose_clip("ual/Punch_Cross", t / .32 * .38)
		else:
			thief.pose_vehicle(0.0)
	else:
		thief.pose_vehicle(0.0)
		var reach := smoothstep(0.0, .18, t) * (1.0 - smoothstep(.68, 1.0, t))
		for arm in ["Left", "Right"]:
			var sign_side := -1.0 if arm == "Left" else 1.0
			var idle := Vector3(sign_side * .23, .9, -.28)
			var target := idle.lerp(thief.visual.to_local(grip + Vector3.UP * .12), reach)
			thief._solve_combat_arm(arm, target, Basis.IDENTITY, true, sign_side)
		thief._set_combat_grips(reach > .5, reach > .5, motorcycle, motorcycle)
	if t >= .26 and not hit:
		hit = true
		if victim.has_method("present_hit"): victim.present_hit()
		if is_instance_valid(_body) and _body.has_method("take_hit"): _body.take_hit(vehicle.global_basis.x * float(side), .65)
		if motorcycle and is_instance_valid(world.get("gameplay")) and world.gameplay.has_method("_melee_hit_sound"):
			world.gameplay._melee_hit_sound("fists", victim, grip, 0.0)
	var pull := smoothstep(.26, .78, t)
	if is_instance_valid(_body): _body.sit_amount = 1.0 - pull
	var seat_now: Vector3 = vehicle.to_global(_seat_root.origin)
	# Through the actual doorway first, then behind the thief and out of the swing.
	victim.global_position = seat_now.lerp(gate, minf(pull * 2.0, 1.0)).lerp(landing, maxf(pull * 2.0 - 1.0, 0.0))
	victim.visual.transform = _seat_visual.interpolate_with(_visual_transform, pull)
	victim.visual.rotation.z += float(side) * sin(pull * PI) * (.85 if motorcycle else .45)
	victim.visual.position.y -= sin(pull * PI) * .32
	if t >= 1.0: release()

func release() -> void:
	if released: return
	released = true
	if not is_instance_valid(victim): return
	if not victim.is_inside_tree() or not is_instance_valid(world) or not world.is_inside_tree(): return
	victim.global_position = landing
	victim.visual.transform = _visual_transform
	# Actor locomotion steers Visual in world yaw. Remove the seat's root
	# rotation while retaining the current appearance before handing AI back.
	if victim.get_script() == ACTOR:
		var facing: Basis = victim.visual.global_basis
		victim.global_rotation = Vector3.ZERO
		victim.visual.global_basis = facing
	if victim.get("skeleton") is Skeleton3D and victim.has_method("release_seated"): victim.release_seated()
	if is_instance_valid(_body): _body.sit_amount = 0.0
	if victim.has_method("_finish_exit"): victim._finish_exit()
	if victim.get("mode") == "disembark": victim.mode = "combat"
	if is_instance_valid(_weapon): _weapon.visible = _weapon_visible
	var dead: bool = victim.get("dead") == true
	victim.collision_layer = 0 if dead else _layer
	victim.collision_mask = 0 if dead else _mask
	victim.velocity = Vector3.ZERO
	victim.reset_physics_interpolation()
	victim.set_physics_process(_physics and not dead)
	if victim.get_script() == ACTOR:
		victim.route = PackedVector3Array([landing, landing + (landing - vehicle.global_position).normalized() * 8]) if is_instance_valid(vehicle) and vehicle.is_inside_tree() else PackedVector3Array([landing])
		if is_instance_valid(world.player) and world.player.is_inside_tree() and is_instance_valid(world.get("production")):
			var reactions = world.production.get("civilian_reactions")
			if is_instance_valid(reactions): reactions.report_assault(victim, world.player)
