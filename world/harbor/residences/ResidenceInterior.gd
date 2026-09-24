class_name ResidenceInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

const AUTHORED_VIEWPORT_SIZE := Vector2i(1440, 1000)
# Godot clamps SubViewport render targets to a 2x2 minimum. Keep the runtime
# contract at that effective minimum so residency state matches the real target.
const INACTIVE_VIEWPORT_SIZE := Vector2i(2, 2)
const INLINE_VIEWPORT_SIZE := Vector2i(800, 667)

var property_id := ""
var variant_index := 0
var manager: Node
var inline_mode := false
var inline_property: ResidenceProperty
var inline_floor_polygon := PackedVector2Array()
var inline_door_blocker: CollisionPolygon2D
var _inline_occupied := false
var _inline_door_amount := 0.0
var stations: Array[Dictionary] = []
var viewport_3d: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var art: Node3D
var actor_presentation: Node
var _active := false
var _presentation_compacted := false
var _entry_frame_ready := false
var _entry_generation := 0
var _entry_prepare_started_usec := 0
var last_entry_prepare_usec := 0
var _floor_projection_origin := Vector2.ZERO
var _floor_projection_x := Vector2.ZERO
var _floor_projection_y := Vector2.ZERO
var _floor_projection_ready := false

func configure(definition: Dictionary,index: int,owner_manager: Node) -> void:
	property_id = definition.id
	interior_id = StringName("residence_"+property_id)
	display_name = ""
	variant_index = index
	manager = owner_manager
	inline_mode = true
	room_size = Vector2(230, 170)
	set_meta("fixed_camera",true)

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _build_lights() -> void: pass
func _build_walls_and_floor() -> void: pass

func _setup_interior_content() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ResidenceRoomViewport"
	viewport_3d.size = authored_viewport_size()
	viewport_3d.set_meta("authored_resident_size", authored_viewport_size())
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	viewport_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_3d)
	art = preload("res://world/harbor/residences/ResidenceInterior3D.gd").new()
	art.variant_index = variant_index
	art.compact_mode = inline_mode
	viewport_3d.add_child(art)
	room_camera = Camera3D.new()
	viewport_3d.add_child(room_camera)
	room_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size = 14.0 if inline_mode else 15.8
	if inline_mode:
		room_camera.look_at_from_position(Vector3(0,1.2,0)+Vector3(0,24,20),Vector3(0,1.2,0))
	else:
		room_camera.look_at_from_position(Vector3(0,.4,0)+Vector3(0,18,15),Vector3(0,.4,0))
	room_camera.force_update_transform()
	room_camera.reset_physics_interpolation()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("ccd3d5")
	env.environment.ambient_light_energy = .45
	viewport_3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62,-24,0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	room_display = Sprite2D.new()
	room_display.name = "ProjectedResidence"
	room_display.texture = viewport_3d.get_texture()
	var metre := room_camera.unproject_position(Vector3.RIGHT).distance_to(room_camera.unproject_position(Vector3.ZERO))
	room_display.scale = Vector2.ONE*(22.0 if inline_mode else 40.0)/metre
	# Freeze the authored orthographic floor transform before the render target is
	# compacted. Camera3D.unproject_position() uses the viewport's current size;
	# consulting it later at 2x2 would move physics and interaction coordinates.
	var authored_center := Vector2(authored_viewport_size()) * 0.5
	var screen_origin := room_camera.unproject_position(Vector3.ZERO) - authored_center
	var screen_x := room_camera.unproject_position(Vector3.RIGHT) - authored_center
	var screen_y := room_camera.unproject_position(Vector3(0.0, 0.0, 1.0)) - authored_center
	_floor_projection_origin = screen_origin * room_display.scale
	_floor_projection_x = (screen_x - screen_origin) * room_display.scale
	_floor_projection_y = (screen_y - screen_origin) * room_display.scale
	_floor_projection_ready = true
	if inline_mode: room_display.position = -_floor_projection_origin
	add_child(room_display)
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	for id in art.solid_rects:
		var r: Rect2 = art.solid_rects[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = PackedVector2Array([project_floor(r.position),project_floor(Vector2(r.end.x,r.position.y)),project_floor(r.end),project_floor(Vector2(r.position.x,r.end.y))])
		walls_body.add_child(shape)
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	spawn_point.position = project_floor(Vector2(0,2.15 if inline_mode else 3.7))
	add_child(spawn_point)
	var labels := {"wardrobe":"[E] TROCAR DE ROUPA","arsenal":"[E] ARSENAL","food":"[E] COMER","time":"[E] DESCANSAR","exit":"E"}
	for kind in art.station_points:
		stations.append({"kind":kind,"position":project_floor(art.station_points[kind]),"radius":38.0,"label":labels[kind]})
	add_cash_reward(art,Vector2(0,-.3) if inline_mode else Vector2(-.9,3.65),[300,700,1500][variant_index],"residence_"+property_id+"_cash")
	if inline_mode:
		inline_floor_polygon = _project_rect(Rect2(-4.4,-3.1,8.8,6.2))
		var door := CollisionPolygon2D.new()
		door.name = "DoorLeaves"
		door.polygon = _project_rect(Rect2(-.95,2.98,1.9,.15))
		walls_body.add_child(door)
		inline_door_blocker = door
		room_display.hide()
	set_process(inline_mode)

func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])

func attach_inline_property(property: ResidenceProperty) -> void:
	inline_property = property
	global_position = property.global_position
	z_as_relative = false
	z_index = 6
	property.inline_room = self
	var old_body := property.get_node_or_null("HouseFootprint") as StaticBody2D
	if old_body:
		old_body.collision_layer = 0
		old_body.queue_free()

func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point),inline_floor_polygon)
	return super.contains_point(point)

func _process(delta: float) -> void:
	if not inline_mode or not is_instance_valid(inline_property): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(actor): return
	var door_world := to_global(project_floor(Vector2(0,3.1)))
	var near: bool = actor.visible and actor.get("is_dead") != true and actor.global_position.distance_to(door_world) < 65.0
	var inside: bool = actor.visible and actor.get("is_dead") != true and contains_point(actor.global_position)
	var target := 1.0 if (near or inside) and manager.active_home_id() == property_id else 0.0
	var amount := move_toward(_inline_door_amount,target,delta/.42)
	if not is_equal_approx(amount,_inline_door_amount):
		_inline_door_amount = amount
		inline_property.model.set_open_amount(amount)
		inline_property.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	inline_door_blocker.set_deferred("disabled",amount >= .6)
	if near and not inside and _presentation_compacted:
		_restore_presentation_target()
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if inside and not _inline_occupied:
		_inline_occupied = true
		inline_property.sprite_3d.hide()
		set_npc_rendering_active(true)
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		actor.set_meta("harbor_interior",true)
		actor.set_meta("police_exterior_position",inline_property.entrance_position())
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.set_meta("compact_interior",get_camera_rect())
			cam.reset_smoothing()
		get_parent().get_parent().emit_signal("actor_entered_interior",actor,interior_id)
	elif not inside and _inline_occupied:
		_inline_occupied = false
		inline_property.sprite_3d.show()
		set_npc_rendering_active(false)
		actor.remove_meta("harbor_interior")
		actor.remove_meta("police_exterior_position")
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam: cam.remove_meta("compact_interior")
		get_parent().get_parent().emit_signal("actor_returned_to_exterior",actor,interior_id)
	elif not near and not inside and not _presentation_compacted:
		_compact_presentation_target()

func contains_actor(actor: Node2D) -> bool:
	return _active and contains_point(actor.global_position)

func project_floor(point: Vector2) -> Vector2:
	# Collision, spawn and interactions remain authored in the full projection.
	# Runtime target compaction must never move solids or interaction points.
	if _floor_projection_ready:
		return room_display.position + _floor_projection_origin + _floor_projection_x * point.x + _floor_projection_y * point.y
	return room_display.position+(room_camera.unproject_position(Vector3(point.x,0,point.y))-Vector2(authored_viewport_size())*.5)*room_display.scale

func station_near(world_position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var best := INF
	for station in stations:
		var distance := to_local(world_position).distance_to(station.position)
		if distance < station.radius and distance < best:
			nearest = station
			best = distance
	return nearest

func set_npc_rendering_active(value: bool) -> void:
	if not is_instance_valid(viewport_3d): return
	if value:
		_restore_presentation_target()
		_active = true
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
		if is_instance_valid(room_display): room_display.show()
	elif _active or not _presentation_compacted:
		_active = false
	if value and not is_instance_valid(actor_presentation):
		var actor := get_tree().get_first_node_in_group("player")
		if actor != null and actor.get("viewport_3d") is SubViewport:
			# The actor shares the room's depth buffer; the legacy scale-only adapter
			# cannot occlude the rig behind authored furniture.
			actor_presentation = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
			add_child(actor_presentation)
			actor_presentation.configure(actor,room_camera,room_display)
	elif not value and is_instance_valid(actor_presentation):
		actor_presentation.restore()
		actor_presentation.queue_free()
		actor_presentation = null
	if not value:
		_compact_presentation_target()


## Called only while HarborInteriorManager's curtain is fully black. The room
## stays hidden until a full authored-size render has completed, so fade-in can
## never reveal the freshly resized target before it contains the room.
func prepare_presentation_for_entry(ready: Callable) -> void:
	if not is_instance_valid(viewport_3d):
		if ready.is_valid(): ready.call_deferred()
		return
	_entry_generation += 1
	var generation := _entry_generation
	_entry_frame_ready = false
	_entry_prepare_started_usec = Time.get_ticks_usec()
	_restore_presentation_target()
	if is_instance_valid(room_display): room_display.hide()
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if DisplayServer.get_name() == "headless":
		_entry_frame_drawn.call_deferred(generation, ready)
	else:
		RenderingServer.frame_post_draw.connect(_entry_frame_drawn.bind(generation, ready), CONNECT_ONE_SHOT)


func _entry_frame_drawn(generation: int, ready: Callable) -> void:
	if generation != _entry_generation or not is_instance_valid(viewport_3d):
		return
	_entry_frame_ready = true
	last_entry_prepare_usec = Time.get_ticks_usec() - _entry_prepare_started_usec
	if is_instance_valid(room_display): room_display.show()
	if ready.is_valid(): ready.call()


func _restore_presentation_target() -> void:
	if not is_instance_valid(viewport_3d): return
	# RenderQuality defers dormant MSAA changes. Consume its event hook while the
	# target is still at Godot's 2x2 minimum, then allocate the authored target
	# exactly once.
	var quality_hook: Callable = viewport_3d.get_meta("quality_residency_hook", Callable())
	if quality_hook.is_valid(): quality_hook.call()
	if viewport_3d.size != authored_viewport_size():
		viewport_3d.size = authored_viewport_size()
	_presentation_compacted = false


func _compact_presentation_target() -> void:
	if not is_instance_valid(viewport_3d): return
	_entry_generation += 1
	_entry_frame_ready = false
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(room_display): room_display.hide()
	if viewport_3d.size != INACTIVE_VIEWPORT_SIZE:
		viewport_3d.size = INACTIVE_VIEWPORT_SIZE
	_presentation_compacted = true


func authored_viewport_size() -> Vector2i:
	return INLINE_VIEWPORT_SIZE if inline_mode else AUTHORED_VIEWPORT_SIZE


func is_presentation_compacted() -> bool:
	return _presentation_compacted


func is_entry_frame_ready() -> bool:
	return _entry_frame_ready

func _exit_tree() -> void:
	if is_instance_valid(actor_presentation): actor_presentation.restore()
