extends Node2D
## A service address is an authored exterior door, never an interior's atlas coordinates.
var is_dead := true
var body: Node2D
var room: Node2D
var entrance: Node2D
var camera: Camera3D
var display: Sprite2D
var visitors := {}
var visitor_parents := {}

static func target_for(subject: Node2D) -> Node2D:
	if subject.has_meta("coroner_access_target"):
		var cached: Variant = subject.get_meta("coroner_access_target")
		if is_instance_valid(cached): return cached
	var interior := subject.get_parent()
	while interior and not interior.is_in_group("harbor_interior"): interior = interior.get_parent()
	if interior == null: return subject
	var scene := subject.get_tree().current_scene
	var manager := scene.get_node_or_null("Interiors")
	if manager == null or not "_door_configs" in manager: return null
	var room_camera: Camera3D
	var room_display: Sprite2D
	for pair in [["camera_3d","sprite_3d"],["room_camera","room_display"]]:
		if interior.get(pair[0]) is Camera3D and interior.get(pair[1]) is Sprite2D:
			room_camera = interior.get(pair[0])
			room_display = interior.get(pair[1])
	if room_camera == null or interior.get("spawn_point") == null or interior.get("exit_door") == null:
		subject.set_meta("medical_access_failure","interior_requires_projected_service_access")
		return null
	for path in manager._door_configs:
		if manager._door_configs[path].interior != interior: continue
		var door := scene.get_node_or_null(path) as Node2D
		if door == null: continue
		var proxy := new()
		proxy.body = subject
		proxy.room = interior
		proxy.entrance = door
		proxy.camera = room_camera
		proxy.display = room_display
		proxy.set_meta("coroner_identity",subject.get_meta("coroner_identity",subject.get_meta("medical_identity","")))
		scene.add_child(proxy)
		proxy.global_position = proxy.outside_point()
		subject.set_meta("coroner_access_target",proxy)
		return proxy
	subject.set_meta("medical_access_failure","interior_service_door_unregistered")
	return null

func outside_point() -> Vector2:
	var marker := entrance.get_node_or_null("OutsideReturn") as Node2D
	return marker.global_position if marker else entrance.to_global(Vector2(0,42))

func can_collect(worker: Node2D) -> bool:
	return visitors.has(worker.get_instance_id()) and is_instance_valid(body)

func owns_obstacle(obstacle: Node) -> bool:
	return is_instance_valid(body) and (obstacle==body or body.is_ancestor_of(obstacle))

func collection_position(worker: Node2D) -> Vector2:
	if not is_instance_valid(body) or not is_instance_valid(room) or not is_instance_valid(entrance): return worker.global_position
	var id := worker.get_instance_id()
	if not visitors.has(id):
		var door_point := outside_point()
		if worker.global_position.distance_to(door_point) < 45 and not entrance._door_open: entrance.open_door()
		if worker.global_position.distance_to(door_point) > 7: return door_point
		if entrance._door_tween and entrance._door_tween.is_running(): return door_point
		var spawn := _free_spawn(worker)
		if spawn == Vector2.INF: return door_point
		visitor_parents[id] = weakref(worker.get_parent())
		worker.reparent(room)
		worker.global_position = spawn
		worker.velocity = Vector2.ZERO
		worker.reset_physics_interpolation()
		var presentation := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		worker.add_child(presentation)
		presentation.configure(worker,camera,display)
		visitors[id] = weakref(presentation)
		worker.set_meta("coroner_portal",self)
		var care := get_node("/root/CoronerCare")
		var key: String = care.identity(self)
		if care.records().has(key): care.records()[key].room_path = String(get_tree().current_scene.get_path_to(room))
	var remains: Variant = body.get_meta("explosion_remains") if body.has_meta("explosion_remains") else null
	if is_instance_valid(remains): return remains.collection_position(worker)
	return body.collection_position(worker) if body.has_method("collection_position") else body.global_position

func _free_spawn(worker: Node2D) -> Vector2:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = 18.0
	query.collision_mask = 7
	query.exclude = [worker.get_rid()]
	for offset in [Vector2.ZERO,Vector2(-36,0),Vector2(36,0),Vector2(0,-36)]:
		var point: Vector2 = room.spawn_point.global_position+offset
		query.transform = Transform2D(0,point)
		if worker.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return point
	return Vector2.INF

func collect_piece(worker: Node2D) -> bool:
	if not can_collect(worker): return false
	var remains: Variant = body.get_meta("explosion_remains") if body.has_meta("explosion_remains") else null
	return remains.collect_piece(worker) if is_instance_valid(remains) else true

func return_point(worker: Node2D) -> Vector2:
	var id := worker.get_instance_id()
	if not visitors.has(id): return Vector2.INF
	var exit_point: Vector2 = room.exit_door.global_position
	if worker.global_position.distance_to(exit_point)>8: return exit_point
	if not room.exit_door._door_open: room.exit_door.open_door()
	if room.exit_door._door_tween and room.exit_door._door_tween.is_running(): return exit_point
	var point := outside_point()
	var renewal := get_node("/root/WorldRenewal")
	if not renewal.free_position(worker,point,18): return exit_point
	var presentation: Variant = visitors[id].get_ref()
	if is_instance_valid(presentation):
		presentation.restore()
		presentation.queue_free()
	visitors.erase(id)
	var original: Variant = visitor_parents[id].get_ref() if visitor_parents.has(id) else null
	worker.reparent(original if is_instance_valid(original) else get_tree().current_scene)
	visitor_parents.erase(id)
	worker.remove_meta("coroner_portal")
	worker.global_position = point
	worker.velocity = Vector2.ZERO
	worker.reset_physics_interpolation()
	var cargo := String(worker.get_meta("coroner_cargo",""))
	var care := get_node("/root/CoronerCare")
	if not cargo.is_empty() and care.records().has(cargo): care.records()[cargo].erase("room_path")
	return Vector2.INF

func _process(_delta: float) -> void:
	if not get_meta("service_complete",false): return
	for id in visitors.keys():
		var worker: Variant = instance_from_id(id)
		if not is_instance_valid(worker) or worker.get("is_dead") == true:
			visitors.erase(id)
			visitor_parents.erase(id)
	if visitors.is_empty(): queue_free()
