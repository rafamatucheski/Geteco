extends Node2D
## Variable anatomical fragments form one coroner incident.
const MAX_REMAINS := 16
var pieces: Array[Node2D] = []
var claims := {}
var is_dead := true
var elapsed := 0.0

class Piece extends CharacterBody2D:
	var part_keys: Array = []
	var fragment_model: Node3D
	var fragment_sprite: Sprite2D
	var visual_ground_offset := 0.0
	var shadow_radius := 3.5
	var tumble := Vector3.ZERO
	var tumble_speed := Vector3.ZERO
	var rest_rotation := Vector3.ZERO
	var height := 0.0
	var lift := 145.0
	var spin := 5.0
	var angle := 0.0
	var age := 0.0
	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 | 2
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 3.0
		shape.shape = circle
		add_child(shape)
		z_index = 7
	func _physics_process(delta: float) -> void:
		age += delta
		var hit := move_and_collide(velocity * delta)
		if hit: velocity = velocity.bounce(hit.get_normal()) * 0.28
		velocity = velocity.move_toward(Vector2.ZERO, (85.0 if height > 0 else 420.0) * delta)
		height = maxf(0.0, height + lift * delta)
		lift -= 600.0 * delta
		if height <= 0 and lift < 0:
			lift = -lift * 0.18 if age < 0.8 else 0.0
			spin *= 0.6
		angle += spin * delta
		if height > .1: tumble += tumble_speed * delta
		else: tumble = tumble.lerp(rest_rotation, minf(1, delta*14))
		if is_instance_valid(fragment_sprite): fragment_sprite.position.y = -height + visual_ground_offset
		queue_redraw()
		if age > 1.8:
			tumble = rest_rotation
			velocity = Vector2.ZERO
			height = 0.0
			queue_redraw()
			set_physics_process(false)
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, .5))
		draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, clampf(1.0-height/100.0, .12, .32)))

static func spawn(actor: Node2D, origin: Vector2, source: CollisionObject2D = null, saved: Array = []) -> Node2D:
	if actor.has_meta("explosion_remains"): return actor.get_meta("explosion_remains")
	if actor.get_tree().get_nodes_in_group("explosion_remains").size() >= MAX_REMAINS: return null
	var remains := new()
	actor.get_parent().add_child(remains)
	remains.global_position = actor.global_position
	actor.set_meta("explosion_remains", remains)
	var care := actor.get_node_or_null("/root/NPCMedicalCare")
	if care: care.report_injury(actor)
	remains.set_meta("coroner_identity", actor.get_meta("medical_identity", ""))
	remains.set_meta("medical_pending", true)
	var death_care := actor.get_node_or_null("/root/CoronerCare")
	if death_care and death_care.records().has(death_care.identity(actor)):
		death_care.records()[death_care.identity(actor)].cause = "explosion"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(actor.get_meta("fragment_seed", randi()))
	if actor.has_method("ensure_presentation"): actor.ensure_presentation()
	var plans := preload("res://world/shared/combat/BodyFragmentMesh.gd").plans(actor, rng)
	if not saved.is_empty(): plans = saved.map(func(fragment): return fragment.parts)
	if plans.is_empty():
		actor.remove_meta("explosion_remains")
		remains.queue_free()
		return null
	var outward := origin.direction_to(actor.global_position)
	if outward.is_zero_approx(): outward = Vector2.from_angle(rng.randf_range(-PI, PI))
	for i in plans.size():
		var piece := Piece.new()
		piece.part_keys = plans[i]
		piece.fragment_model = preload("res://world/shared/combat/BodyFragmentMesh.gd").build(actor, plans[i])
		var bounds: AABB = piece.fragment_model.get_meta("fragment_bounds")
		piece.shadow_radius = clampf(bounds.size.length()*5.5, 2, 6)
		var spread := lerpf(-1.4, 1.4, float(i)/maxf(1, plans.size()-1)) + rng.randf_range(-.32, .32)
		piece.velocity = outward.rotated(spread) * rng.randf_range(95, 235)
		piece.spin = rng.randf_range(-8, 8)
		piece.tumble = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-.5, .5))
		piece.tumble_speed = Vector3(rng.randf_range(-9, 9), piece.spin, rng.randf_range(-5, 5))
		piece.rest_rotation = Vector3(PI*.5 + rng.randf_range(-.18, .18), rng.randf_range(-PI, PI), rng.randf_range(-.1, .1))
		piece.lift = rng.randf_range(100, 210)
		remains.add_child(piece)
		if not saved.is_empty():
			piece.global_position = Vector2(saved[i].x,saved[i].y)
			piece.velocity = Vector2.ZERO
			piece.lift = 0.0
			piece.age = 2.0
		if source is PhysicsBody2D: piece.add_collision_exception_with(source)
		remains.pieces.append(piece)
	var visual: Node
	if actor.has_meta("interior_actor_presentation"):
		visual = preload("res://world/shared/combat/InteriorRemainsPresentation.gd").new()
	else:
		visual = preload("res://world/shared/combat/FragmentAtlasPresentation.gd").new()
	remains.add_child(visual)
	visual.configure(actor, remains)
	actor.hide()
	if actor.has_meta("interior_actor_presentation"):
		var presentation: Node = actor.get_meta("interior_actor_presentation")
		if is_instance_valid(presentation): presentation.anchor.hide()
	actor.set_physics_process(false)
	# Witnesses report the victim once; fragments never dispatch their own fleet.
	if death_care and death_care.records().has(death_care.identity(actor)):
		death_care.records()[death_care.identity(actor)].fragments = remains.custody_snapshot()
	return remains

func custody_snapshot() -> Array:
	var snapshot := []
	for piece in pieces:
		if is_instance_valid(piece) and not piece.is_queued_for_deletion():
			snapshot.append({"parts":piece.part_keys.duplicate(),"x":piece.global_position.x,"y":piece.global_position.y})
	return snapshot

func _ready() -> void:
	add_to_group("explosion_remains")

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 150.0 and not get_meta("medical_pending", false): queue_free()

func collection_position(worker: Node2D) -> Vector2:
	var key := worker.get_instance_id()
	for id in claims.keys():
		var claimant := instance_from_id(id)
		if not is_instance_valid(claimant) or claimant.get("is_dead") == true: claims.erase(id)
	if claims.has(key) and is_instance_valid(claims[key]): return claims[key].global_position
	var nearest: Node2D
	var distance := INF
	for piece in pieces:
		if not is_instance_valid(piece) or piece.is_queued_for_deletion() or piece.height > 0.1 or claims.values().has(piece): continue
		var d := worker.global_position.distance_squared_to(piece.global_position)
		if d < distance:
			distance = d
			nearest = piece
	if nearest:
		claims[key] = nearest
		return nearest.global_position
	return global_position

func collect_piece(worker: Node2D) -> bool:
	var piece: Node2D = claims.get(worker.get_instance_id())
	if is_instance_valid(piece) and worker.global_position.distance_to(piece.global_position) <= 28.0:
		pieces.erase(piece)
		claims.erase(worker.get_instance_id())
		piece.queue_free()
		var care := get_node("/root/CoronerCare")
		var key: String = care.identity(self)
		if care.records().has(key):
			care.records()[key].fragments = custody_snapshot()
			care.records()[key].collected_parts = int(care.records()[key].get("collected_parts",0))+1
	if pieces.is_empty():
		set_meta("service_complete", true)
		queue_free()
		return true
	return false
