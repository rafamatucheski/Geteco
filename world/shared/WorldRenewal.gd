extends Node
## A single clock continues housekeeping while distant districts stop simulating.
const FADE_SECONDS := 5.0
const WRECK_SECONDS := 35.0
const PROP_SECONDS := 90.0
const RETURN_SECONDS := 25.0
var entries := {}
var _clock := 0.0
var fades := {}
var transients := {}

func watch_transient(actor: Node2D, seconds: float) -> void:
	transients[actor.get_instance_id()] = seconds

func _ready() -> void:
	get_tree().node_added.connect(func(node: Node):
		if node is CollisionObject2D: _register_id.call_deferred(node.get_instance_id()))

func _register_id(id: int) -> void:
	var actor := instance_from_id(id) as Node2D
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	if not actor.is_node_ready(): await actor.ready
	if not is_instance_valid(actor): return
	var prop := actor.has_method("restore_world_prop")
	var emergency := actor.has_method("_deactivate") and actor.has_method("activate") and "is_broken" in actor
	if not prop and not emergency and not actor.has_method("repair_vehicle"): return
	entries[id] = {"actor":actor, "prop":prop, "emergency":emergency, "home":actor.global_transform,
		"local_pose":actor.transform, "lane_speed":actor.get("speed"),
		"age":0.0, "hidden":false, "layer":actor.collision_layer, "mask":actor.collision_mask}

func outside_view(actor: Node2D, point: Vector2) -> bool:
	if not actor.is_inside_tree(): return false
	var area: Rect2 = actor.get_canvas_transform().affine_inverse() * actor.get_viewport_rect()
	if area.grow(180.0).has_point(point): return false
	for player in get_tree().get_nodes_in_group("player"):
		if player is Node2D and player.get_world_2d() == actor.get_world_2d() and player.global_position.distance_squared_to(point) < 400.0 * 400.0: return false
	return true

func free_position(actor: CollisionObject2D, point: Vector2, radius := 18.0) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, point)
	query.collision_mask = 7
	query.exclude = [actor.get_rid()]
	return actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _process(delta: float) -> void:
	if get_tree().paused: return
	for id in transients.keys():
		var transient := instance_from_id(id) as Node2D
		if not is_instance_valid(transient):
			transients.erase(id)
			continue
		transients[id] = float(transients[id]) - delta
		if transients[id] < FADE_SECONDS:
			transient.modulate.a = minf(transient.modulate.a, maxf(0, float(transients[id]) / FADE_SECONDS))
		if transients[id] <= 0:
			transient.queue_free()
			transients.erase(id)
	for id in fades.keys():
		var actor := instance_from_id(id) as CanvasItem
		if not is_instance_valid(actor):
			fades.erase(id)
			continue
		fades[id] = minf(FADE_SECONDS, float(fades[id]) + delta)
		actor.modulate.a = 1.0 - float(fades[id]) / FADE_SECONDS
	_clock += delta
	if _clock < 0.5: return
	var elapsed := _clock
	_clock = 0
	for id in entries.keys():
		var item: Dictionary = entries[id]
		var actor: Variant = item.actor
		if not is_instance_valid(actor) or not actor.is_inside_tree():
			entries.erase(id)
			continue
		if item.emergency and not actor.visible:
			item.age = 0.0
			continue
		# A scripted set piece can opt out; owned vehicles keep their identity.
		if actor.get_meta("world_renewal_exempt", false): continue
		var personal: Node = null
		if actor.is_in_group("personal_vehicle"):
			personal = get_tree().get_first_node_in_group("personal_car_manager")
			if personal == null or not actor.unlocked or personal.impounded or personal.delivery_in_progress: continue
			item.home = Transform2D(PI / 2.0, personal.bay_position())
			item.layer = personal._car_layer
			item.mask = personal._car_mask
		var damaged: bool = actor.get("broken") == true if item.prop else actor.get("is_broken") == true or actor.get("is_exploded") == true or (actor.get("health") != null and actor.get("max_health") != null and actor.health < actor.max_health)
		if item.prop and actor.get("health") != null and actor.health <= 0: damaged = true
		if not damaged or actor.get("is_driven_by_player") == true or actor.has_meta("vehicle_boarding") or actor.has_meta("forklift_carried"):
			if item.age > 0.0 or fades.has(id) or item.hidden: actor.modulate.a = 1.0
			item.age = 0.0
			fades.erase(id)
			if item.hidden:
				actor.show()
				actor.collision_layer = item.layer
				actor.collision_mask = item.mask
			item.hidden = false
			continue
		var wreck: bool = actor.get("is_broken") == true or actor.get("is_exploded") == true
		# A dented, usable car is only recycled after abandonment out of sight.
		if not item.prop and not wreck and not outside_view(actor, actor.global_position):
			if fades.has(id):
				actor.modulate.a = 1.0
				fades.erase(id)
			item.age = 0.0
			continue
		item.age += elapsed
		var delay := PROP_SECONDS if item.prop else WRECK_SECONDS if wreck else 180.0
		if not item.prop and actor.get_meta("fire_response_assigned", false) and not actor.get_meta("service_complete", false): delay = 90.0
		if item.age < delay: continue
		if not fades.has(id): fades[id] = 0.0
		if float(fades[id]) < FADE_SECONDS: continue
		if item.emergency:
			actor.modulate.a = 1.0
			fades.erase(id)
			actor._deactivate()
			item.age = 0.0
			continue
		actor.hide()
		actor.collision_layer = 0
		actor.collision_mask = 0
		if not item.hidden: item.return_age = 0.0
		item.hidden = true
		item.return_age += elapsed
		if item.return_age < RETURN_SECONDS: continue
		var point: Vector2 = item.home.origin
		var follower := actor.get_parent() as PathFollow2D
		if follower != null:
			point = follower.global_position
		if not outside_view(actor, point) or not free_position(actor, point, 12.0 if item.prop else 42.0): continue
		if item.prop:
			actor.global_transform = item.home
			if "velocity" in actor: actor.velocity = Vector2.ZERO
			actor.restore_world_prop()
		else:
			actor.repair_vehicle()
			actor.velocity = Vector2.ZERO
			if "speed" in actor: actor.speed = 0.0
			if follower == null:
				actor.global_transform = item.home
			else:
				actor.transform = item.local_pose
				if "_detached_from_lane" in actor: actor._detached_from_lane = false
				if item.lane_speed != null: actor.speed = item.lane_speed
		actor.collision_layer = item.layer
		actor.collision_mask = item.mask
		fades.erase(id)
		actor.modulate.a = 1.0
		actor.show()
		actor.reset_physics_interpolation()
		if personal != null: personal.capture_state()
		item.age = 0.0
		item.hidden = false
