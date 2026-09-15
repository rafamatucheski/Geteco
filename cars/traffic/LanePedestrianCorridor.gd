extends RefCounted
## Predict the real lane corridor instead of extending a turn's tangent ray.
static func blocks(vehicle: Node2D, follow: PathFollow2D, pedestrian: Node) -> bool:
	var path := follow.get_parent() as Path2D
	if path == null or not path.is_in_group("unified_lane_connector") or not pedestrian is Node2D:
		return true
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D:
		return true
	var radius := 11.0
	for child in pedestrian.get_children():
		if child is CollisionShape2D and child.shape != null and not child.disabled:
			var extent: Vector2 = child.shape.get_rect().size * child.global_scale.abs() * 0.5
			radius = maxf(radius, maxf(extent.x, extent.y))
	var lookahead := maxf(180.0, float(vehicle.target_length) * 1.5)
	var remaining := path.curve.get_baked_length() - follow.progress
	if _in_segment(collision,pedestrian,radius,path,follow.progress,minf(path.curve.get_baked_length(),follow.progress+lookahead)):
		return true
	if remaining < lookahead:
		var controller = vehicle._get_junction_traffic_controller()
		if controller == null: return true
		var connection: Dictionary = controller._connections_by_id.get(String(path.get_meta("traffic_connection_id","")),{})
		var next_path: Path2D = controller._lane_paths_by_id.get(String(connection.get("to_lane_id","")))
		if next_path == null or next_path.curve == null: return true
		var start := float(connection.get("exit_curve_offset",0.0))
		return _in_segment(collision,pedestrian,radius,next_path,start,minf(next_path.curve.get_baked_length(),start+lookahead-remaining))
	return false

static func _in_segment(collision:CollisionShape2D,pedestrian:Node2D,radius:float,path:Path2D,begin:float,end:float)->bool:
	var half: Vector2 = collision.shape.size * 0.5 + Vector2.ONE * (radius+6.0)
	var future := pedestrian.global_position
	if pedestrian is CharacterBody2D: future += pedestrian.velocity*0.6
	var samples := maxi(1,ceili((end-begin)/8.0))
	for index in range(samples+1):
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(lerpf(begin,end,float(index)/samples),true) * collision.transform
		var bounds := Rect2(-half,half*2.0)
		var now_local := pose.affine_inverse()*pedestrian.global_position
		var future_local := pose.affine_inverse()*future
		var predicted_area := Rect2(now_local,Vector2.ZERO).expand(future_local).grow(0.001)
		if bounds.has_point(now_local) or bounds.has_point(future_local) or bounds.intersects(predicted_area): return true
	return false
