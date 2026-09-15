extends RefCounted
## Loot shares the room camera, light and depth buffer with the characters.
static func floor_position(room: Node2D, point: Vector2) -> Vector3:
	var pixel:Vector2=room.room_display.to_local(point)+Vector2(room.view.size)*.5
	var origin:Vector3=room.room_camera.project_ray_origin(pixel)
	var ray:Vector3=room.room_camera.project_ray_normal(pixel)
	return origin+ray*(-origin.y/ray.y)

static func place(room: Node2D, visual: Node3D, point: Vector2) -> void:
	# Loot is rigid: reuse the production static-surface batcher instead of
	# submitting every strap, pouch and weapon part as a separate draw.
	preload("res://VehicleMeshBatcher.gd").batch_model(visual)
	room.view.add_child(visual)
	visual.position=floor_position(room,point)
	var bottom:=INF
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		mesh.set_meta("interior_surface","collectible")
		for i in 8:
			bottom=minf(bottom,mesh.to_global(mesh.mesh.get_aabb().get_endpoint(i)).y)
	if is_finite(bottom): visual.position.y+=.025-bottom
	room.view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if room.actor_present() else SubViewport.UPDATE_ONCE

static func clear_drop(room: Node2D, origin: Vector2, preferred: Vector2) -> Vector2:
	var query:=PhysicsShapeQueryParameters2D.new()
	query.collision_mask=1
	if is_instance_valid(room.actor_scale) and is_instance_valid(room.actor_scale.collider):
		query.shape=room.actor_scale.collider.shape
		query.transform=room.actor_scale.collider.global_transform
	else:
		query.shape=CircleShape2D.new()
		query.shape.radius=12
	for offset in [preferred,Vector2(24,0),Vector2(-24,0),Vector2(0,24),Vector2(0,-24),Vector2.ZERO]:
		query.transform.origin=origin+offset
		if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return query.transform.origin
	return origin
