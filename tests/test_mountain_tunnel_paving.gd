extends SceneTree

const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func run() -> void:
	var connection := CONNECTION.new()
	root.add_child(connection)
	var walker := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.8
	collision.shape = capsule
	walker.add_child(collision)
	root.add_child(walker)
	await physics_frame
	await physics_frame
	var middle := (CONNECTION.TUNNEL_START_X+CONNECTION.TUNNEL_END_X)*.5
	var eye := Vector3(middle,1.6,CONNECTION.CENTER_Z)
	for direction in [Vector3.UP,Vector3.FORWARD,Vector3.BACK]:
		var enclosure := PhysicsRayQueryParameters3D.create(eye,eye+direction*12.0,1,[walker.get_rid()])
		var hit := root.world_3d.direct_space_state.intersect_ray(enclosure)
		check(not hit.is_empty(),"solid ceiling and both walls %s" % direction)
		if not hit.is_empty():
			check(hit.collider.get_parent().is_visible_in_tree(),"enclosure remains visible %s" % direction)
	check(CONNECTION.tunnel_camera_weight(eye)==1.0,"low camera inside tunnel")
	check(CONNECTION.tunnel_camera_weight(Vector3(CONNECTION.TUNNEL_START_X-7.0,0,CONNECTION.CENTER_Z))==1.0,"camera below roof before portal")
	check(CONNECTION.tunnel_camera_weight(Vector3(CONNECTION.TUNNEL_END_X+25.0,0,CONNECTION.CENTER_Z))==0.0,"street camera restored beyond exit")
	for side in [-1.0, 1.0]:
		for i in 22:
			var x := lerpf(CONNECTION.TUNNEL_START_X-.5, CONNECTION.TUNNEL_END_X+.5, float(i)/21.0)
			for offset in [4.5, 5.7, 6.6]:
				var point := Vector3(x, 1.0, CONNECTION.CENTER_Z+side*offset)
				var query := PhysicsRayQueryParameters3D.create(point,point-Vector3.UP*2.0,1,[walker.get_rid()])
				var hit := root.world_3d.direct_space_state.intersect_ray(query)
				check(not hit.is_empty() and absf(hit.position.y-.07)<.005,"continuous supported pavement %s" % point)
		walker.position = Vector3(CONNECTION.TUNNEL_START_X-.45,.98,CONNECTION.CENTER_Z+side*5.7)
		check(not walker.test_move(walker.transform,Vector3(CONNECTION.TUNNEL_END_X-CONNECTION.TUNNEL_START_X+.9,0,0)),"pedestrian corridor clear on side %s" % side)
		check(walker.test_move(walker.transform,Vector3(0,0,side*3.0)),"wall blocks lateral escape on side %s" % side)
	# Crossbeams must physically reach a support on both ends, even where the
	# camera-facing wall is hidden. A gap leaves an unsupported end in gameplay.
	for rib in connection.get_children():
		if not rib is MeshInstance3D or not is_equal_approx(rib.position.y,4.25): continue
		for side in [-1.0,1.0]:
			var point := Vector3(rib.position.x,4.095,CONNECTION.CENTER_Z+side*CONNECTION.TUNNEL_CLEAR_HALF_WIDTH)
			var query := PhysicsRayQueryParameters3D.create(point,point-Vector3.UP*4.0,1,[walker.get_rid()])
			query.hit_from_inside = true
			check(not root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"crossbeam end supported %s" % point)
	for failure in failures: push_error(failure)
	print("MOUNTAIN_TUNNEL_PAVING failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
