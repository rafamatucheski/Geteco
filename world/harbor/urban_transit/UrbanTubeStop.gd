extends Node2D
## Physical station with native 3D architecture and no floating text.
var stop_id := 0
var stop_name := "Estação"
var lane: Path2D
var offset := 0.0
var terminal := false
var operating := true
var waiting_count := 0
var service_bus: Node2D
var view: Node2D
var gate_shape: CollisionPolygon2D
var gate_open := false
var presentations: Dictionary = {}
var pending_actors: Dictionary = {}
var admission_timer := 0.0
var spawn_point: Marker2D
func _ready() -> void:
	add_to_group("urban_bus_stop")
	z_index = 4
	view = preload("res://world/harbor/urban_transit/UrbanStationView.gd").new()
	view.name = "NativeStation3D"
	view.orientation = global_rotation
	view.terminal = terminal
	view.rotation = -global_rotation
	add_child(view)
	var body := StaticBody2D.new()
	body.name = "StationSolids"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(view.model, body, func(point: Vector2): return to_local(view.to_global(view.project_floor(point))))
	gate_shape = body.get_node("BoardingGate")
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	spawn_point.position = Vector2(207,8)
	add_child(spawn_point)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 6
	var detection := CollisionShape2D.new()
	detection.shape = RectangleShape2D.new()
	detection.shape.size = Vector2(440,210)
	detection.position = Vector2(20,-25)
	area.add_child(detection)
	area.body_entered.connect(func(actor): _actor_entered.call_deferred(actor))
	area.body_exited.connect(func(actor): _actor_exited.call_deferred(actor))
	add_child(area)
	# Keep existing street furniture outside the new passenger platform.
	for lamp in get_tree().get_nodes_in_group("street_lamp"):
		var point := to_local(lamp.global_position)
		if Rect2(-170,-60,425,95).has_point(point):
			lamp.global_position = to_global(Vector2(point.x,-75))
	# Stations are created after junctions. Reapply the same placement rule that
	# future junction rebuilds use, keeping signal meshes and foundations together.
	for junction in get_tree().get_nodes_in_group("junction_signal_visual"):
		junction._rebuild_posts()

func clear_signal_position(world_base: Vector2, world_outward: Vector2) -> Vector2:
	# Include the access ramp and the projected height of both the canopy and
	# signal. Move along the sidewalk, never sideways into traffic or the railway.
	var reserved := Rect2(-235, -70, 490, 140)
	var point := to_local(world_base)
	if not reserved.has_point(point): return world_base
	var direction := global_transform.basis_xform_inv(world_outward).normalized()
	if absf(direction.x) < 0.9: return world_base
	var edge := reserved.end.x + 1.0 if direction.x > 0 else reserved.position.x - 1.0
	return to_global(point + direction * ((edge - point.x) / direction.x))

func refresh(active: bool, count: int) -> void:
	var changed := operating != active
	operating = active
	waiting_count = count
	if changed and is_instance_valid(view): view.set_service(active)

func queue_position(slot: int) -> Vector2:
	return to_global(Vector2(31+clampi(slot,0,3)*23,-4))
func sidewalk_position(slot: int) -> Vector2:
	# Stay inside the platform footprint while keeping the walking row beyond
	# the off-tracking envelope of both articulated trailers at nearby turns.
	return to_global(Vector2(211+(maxi(slot,0)%2)*28,-18-(maxi(slot,0)/2)*28))
func platform_exit() -> Vector2: return to_global(Vector2(151,7))

func floor_height(point: Vector2) -> float:
	if Rect2(-157,-32,314,67).has_point(point): return 0.20
	if Rect2(155,-6,39,30).has_point(point): return 0.20 * clampf((193-point.x)/38.0,0,1)
	return 0.0

func ramp_approach() -> Vector2: return to_global(Vector2(207,8))
func boarding_position() -> Vector2: return to_global(Vector2(123,14))
func can_board_from(point: Vector2) -> bool:
	return gate_open and Rect2(104,0,35,26).has_point(to_local(point))

func _actor_entered(actor) -> void:
	if not is_instance_valid(actor) or not is_inside_tree(): return
	if presentations.has(actor): return
	if not actor.get("model_root") is Node3D or not actor.get("sprite_3d_display") is Sprite2D:
		if actor.is_in_group("pedestrian") or actor.is_in_group("player"): pending_actors[actor] = true
		return
	if actor.has_meta("interior_actor_presentation"): return
	pending_actors.erase(actor)
	var presentation := preload("res://world/harbor/urban_transit/UrbanStationActorPresentation.gd").new()
	presentation.station = self
	add_child(presentation)
	presentation.configure(actor, view.camera_3d, view.sprite_3d)
	presentations[actor] = presentation
	view.animated_people = presentations.size()
	view.request_redraw()

func _actor_exited(actor) -> void:
	pending_actors.erase(actor)
	if not presentations.has(actor): return
	var presentation: Node = presentations[actor]
	presentation.restore()
	presentation.queue_free()
	presentations.erase(actor)
	view.animated_people = presentations.size()
	view.request_redraw()

func _physics_process(delta: float) -> void:
	admission_timer += delta
	if admission_timer >= 0.25:
		admission_timer = 0.0
		for actor in pending_actors.keys():
			if is_instance_valid(actor): _actor_entered(actor)
			else: pending_actors.erase(actor)
	var open: bool = is_instance_valid(service_bus) and service_bus.get("dwelling") == true and service_bus.get("doors") >= 0.95 and service_bus.get("is_broken") == false
	if open != gate_open:
		# Do not close a physical panel through an actor already crossing it.
		if not open:
			var panel := ConvexPolygonShape2D.new()
			panel.points = gate_shape.polygon
			for actor in presentations:
				var collider: CollisionShape2D = presentations[actor].collider
				if is_instance_valid(collider) and collider.shape.collide(collider.global_transform,panel,gate_shape.global_transform): return
		gate_open = open
		gate_shape.set_deferred("disabled", open)
		for mesh in view.model.get_children():
			if mesh.get_meta("interior_solid_id", &"") == &"BoardingGate": mesh.visible = not open
		view.request_redraw()
	for actor in presentations.keys():
		if not is_instance_valid(actor):
			presentations[actor].queue_free()
			presentations.erase(actor)
	view.animated_people = presentations.size()

func _exit_tree() -> void:
	for actor in presentations.keys(): _actor_exited(actor)
