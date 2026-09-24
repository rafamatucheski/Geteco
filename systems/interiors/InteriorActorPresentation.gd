extends Node
## The existing animated rig shares the room's depth buffer. Physics stays 2D.
## Configure for every player/NPC admitted to a projected 3D interior; restore
## before exit, respawn or unloading. No cloned rig or extra render pass.

const HUMAN_HEIGHT := 1.8
const RIG_HEIGHT := 1.45
var actor: Node2D
var room_camera: Camera3D
var room_display: Sprite2D
var actor_viewport: SubViewport
var display: Sprite2D
var rig: Node3D
var rig_parent: Node
var old_rig_transform := Transform3D.IDENTITY
var anchor: Node3D
var collider: CollisionShape2D
var old_viewport_size := Vector2i.ZERO
var old_scale := Vector2.ONE
var old_position := Vector2.ZERO
var old_collision_scale := Vector2.ONE
var old_visible := true
var old_update_mode := SubViewport.UPDATE_DISABLED
var room_viewport: SubViewport
var _configured := false
var standing_rig_height := RIG_HEIGHT
var hit_area: Area2D
var hit_shape: CollisionShape2D

func configure(target: Node2D, camera: Camera3D, sprite: Sprite2D) -> void:
	if _configured: restore()
	var previous: Node = target.get_meta("interior_actor_presentation") if target.has_meta("interior_actor_presentation") else null
	if is_instance_valid(previous) and previous != self: previous.restore()
	actor = target
	room_camera = camera
	room_display = sprite
	actor_viewport = actor.get("viewport_3d") as SubViewport
	if actor_viewport == null: actor_viewport = actor.get("viewport") as SubViewport
	display = actor.get("sprite_3d_display") as Sprite2D
	if display == null: display = actor.get("presentation_sprite") as Sprite2D
	rig = actor.get("model_root") as Node3D
	if rig == null: rig = actor.get("model") as Node3D
	assert(actor_viewport != null and display != null and rig != null, "Interior actors require an explicit 3D presentation adapter")
	_configured = true
	set_process(true)
	old_viewport_size = actor_viewport.size
	old_update_mode = actor_viewport.render_target_update_mode
	old_scale = display.scale
	old_position = display.position
	old_visible = display.visible
	actor_viewport.size = Vector2i(384, 384)
	for child in actor.get_children():
		if child is CollisionShape2D:
			collider = child
			old_collision_scale = collider.scale
			break
	rig_parent = rig.get_parent()
	old_rig_transform = rig.transform
	anchor = Node3D.new()
	anchor.name = "InteriorActorAnchor"
	anchor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.get_parent().add_child(anchor)
	room_viewport = room_camera.get_viewport() as SubViewport
	var users: int = room_viewport.get_meta("interior_actor_count", 0)
	if users == 0:
		room_viewport.set_meta("interior_idle_update_mode", room_viewport.render_target_update_mode)
	room_viewport.set_meta("interior_actor_count", users + 1)
	room_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Winter residents are authored at 1.79 units; Dante at 1.45.
	# Applying Dante's multiplier to both made cabin residents over two metres tall.
	standing_rig_height = float(rig.get_meta("standing_rig_height", RIG_HEIGHT))
	anchor.scale = Vector3.ONE * HUMAN_HEIGHT / standing_rig_height
	anchor.rotation.y = room_camera.global_rotation.y
	rig.reparent(anchor, false)
	rig.transform = Transform3D(old_rig_transform.basis, Vector3.ZERO)
	display.hide()
	actor.set_meta("interior_actor_presentation", self)
	hit_area = Area2D.new()
	hit_area.name = "InteriorBallisticBody"
	hit_area.collision_layer = 4
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.set_meta("combat_actor", actor)
	actor.add_child(hit_area)
	hit_shape = CollisionShape2D.new()
	hit_shape.shape = CapsuleShape2D.new()
	hit_area.add_child(hit_shape)
	actor.tree_exiting.connect(restore, CONNECT_ONE_SHOT)
	room_camera.tree_exiting.connect(restore, CONNECT_ONE_SHOT)
	process_priority = 50
	_update_scale()
	_ensure_clear_placement()

func _process(_delta: float) -> void:
	_update_scale()

func _ensure_clear_placement() -> void:
	# Old saves and authored NPC spawns may predate a furniture change. Check
	# actual shapes synchronously, including rooms built before a physics tick.
	if collider == null: return
	var room: Node = room_display.get_parent()
	while room != null and not room.get("spawn_point") is Marker2D:
		room = room.get_parent()
	if room == null: return
	if _placement_is_clear(room): return
	actor.global_position = room.spawn_point.global_position
	if actor is CharacterBody2D: actor.velocity = Vector2.ZERO
	_update_scale()
	assert(_placement_is_clear(room), "Interior spawn intersects solid geometry; fix the authored spawn before delivery")

func _placement_is_clear(room: Node) -> bool:
	for node in room.find_children("*", "", true, false):
		if not (node is CollisionPolygon2D or node is CollisionShape2D): continue
		var body := node.get_parent() as StaticBody2D
		if body == null or (body.collision_layer & 1) == 0 or node.disabled: continue
		if node is CollisionShape2D:
			if node.shape != null and collider.shape.collide(collider.global_transform, node.shape, node.global_transform): return false
		else:
			for polygon in Geometry2D.decompose_polygon_in_convex(node.polygon):
				var shape := ConvexPolygonShape2D.new()
				shape.points = polygon
				if collider.shape.collide(collider.global_transform, shape, node.global_transform): return false
	return true

func floor_position(canvas_position: Vector2) -> Vector3:
	var pixel := room_display.to_local(canvas_position) + room_display.texture.get_size() * 0.5
	var origin := room_camera.project_ray_origin(pixel)
	var direction := room_camera.project_ray_normal(pixel)
	return origin + direction * (-origin.y / direction.y)

func project_world(point: Vector3) -> Vector2:
	return room_display.to_global(room_camera.unproject_position(point) - room_display.texture.get_size() * 0.5)

func project_node(node: Node3D) -> Vector2:
	# Weapon fire happens during physics, before the next presentation frame.
	_update_scale()
	return project_world(node.global_position)

func pixels_per_rig_unit(direction: Vector2) -> float:
	var foot := floor_position(actor.global_position)
	var next := floor_position(actor.global_position + direction.normalized())
	return anchor.scale.x / maxf(foot.distance_to(next), .0001)

func _update_scale() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(room_camera): return
	var foot := floor_position(actor.global_position)
	anchor.global_position = foot
	var screen_direction := Vector2(-sin(rig.rotation.y), -cos(rig.rotation.y))
	var facing := floor_position(actor.global_position + screen_direction) - foot
	anchor.rotation.y = atan2(-facing.x, -facing.z) - rig.rotation.y
	anchor.visible = actor.is_visible_in_tree()
	var head := actor.to_local(project_world(foot + Vector3.UP * HUMAN_HEIGHT))
	hit_area.position = head * .5
	hit_shape.shape.radius = maxf(2.0, head.length() * .15)
	hit_shape.shape.height = maxf(hit_shape.shape.radius * 2.0, head.length())
	hit_area.rotation = head.angle() + PI * .5
	hit_area.collision_layer = 0 if actor.get("is_dead") == true else 4
	# Preserve the sprite calibration contract for gait and collision callers.
	var projected_height := room_camera.unproject_position(foot + Vector3.UP * HUMAN_HEIGHT).distance_to(room_camera.unproject_position(foot)) * room_display.scale.y
	var player_camera := actor_viewport.get_camera_3d()
	var native_origin := old_rig_transform.origin
	var player_height := player_camera.unproject_position(native_origin + Vector3.UP * standing_rig_height).distance_to(player_camera.unproject_position(native_origin))
	var factor := clampf(projected_height / maxf(player_height, 1.0), 0.05, 2.0)
	display.scale = Vector2.ONE * factor
	display.position = -(player_camera.unproject_position(native_origin) - Vector2(actor_viewport.size) * 0.5) * factor
	if collider:
		var metre := room_camera.unproject_position(foot + Vector3.RIGHT).distance_to(room_camera.unproject_position(foot)) * room_display.scale.x
		var depth := room_camera.unproject_position(foot + Vector3.BACK).distance_to(room_camera.unproject_position(foot)) * room_display.scale.y
		var half := collider.shape.get_rect().size * 0.5
		collider.scale = Vector2(metre * 0.23 / maxf(half.x, 0.01), depth * 0.23 / maxf(half.y, 0.01))
	actor_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func restore() -> void:
	if not _configured: return
	_configured = false
	if is_instance_valid(hit_area): hit_area.queue_free()
	if is_instance_valid(room_viewport):
		var users: int = maxi(0, int(room_viewport.get_meta("interior_actor_count", 1)) - 1)
		room_viewport.set_meta("interior_actor_count", users)
		if users == 0 and room_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			room_viewport.render_target_update_mode = room_viewport.get_meta("interior_idle_update_mode", SubViewport.UPDATE_ONCE)
	room_viewport = null
	if is_instance_valid(rig) and is_instance_valid(rig_parent):
		rig.reparent(rig_parent, false)
		rig.transform = old_rig_transform
	if is_instance_valid(actor):
		actor.remove_meta("interior_actor_presentation")
		if actor.tree_exiting.is_connected(restore): actor.tree_exiting.disconnect(restore)
	if is_instance_valid(room_camera) and room_camera.tree_exiting.is_connected(restore):
		room_camera.tree_exiting.disconnect(restore)
	if is_instance_valid(actor_viewport):
		actor_viewport.size = old_viewport_size
		actor_viewport.render_target_update_mode = old_update_mode
	if is_instance_valid(display):
		display.scale = old_scale
		display.position = old_position
		display.visible = old_visible
	if is_instance_valid(collider): collider.scale = old_collision_scale
	if is_instance_valid(anchor): anchor.queue_free()
	actor = null
	rig = null
	set_process(false)

func _exit_tree() -> void:
	restore()
