extends SceneTree
const FLOW := preload("res://world/shared/traffic/TrafficFlowModel.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(100,0),Vector2(-20,40))
	curve.add_point(Vector2(180,120),Vector2(-30,-15))
	for i in 50:
		var point := Vector2(i*5-20,i*3-35)
		assert(FLOW.project_offset(curve,point) == curve.get_closest_offset(point))
		assert(FLOW.project_offset(curve,point) == curve.get_closest_offset(point))
	var changed_point := Vector2(160,60)
	FLOW.project_offset(curve,changed_point)
	curve.set_point_position(1,Vector2(30,160))
	assert(FLOW.project_offset(curve,changed_point) == curve.get_closest_offset(changed_point), "Same-frame curve editing invalidates projection")
	curve.bake_interval = 2.0
	assert(FLOW.project_offset(curve,changed_point) == curve.get_closest_offset(changed_point))
	var actor := Node2D.new()
	root.add_child(actor)
	var shape := CollisionShape2D.new()
	shape.name = "Collision"
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(71,23)
	actor.add_child(shape)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12092026
	for i in 300:
		actor.position = Vector2(rng.randf_range(-500,500),rng.randf_range(-500,500))
		actor.rotation = rng.randf_range(-PI,PI)
		actor.scale = Vector2(rng.randf_range(.5,2),rng.randf_range(.5,2))
		shape.position = Vector2(rng.randf_range(-20,20),rng.randf_range(-20,20))
		shape.rotation = rng.randf_range(-PI,PI)
		shape.skew = rng.randf_range(-.3,.3)
		var axis := Vector2.from_angle(rng.randf_range(-PI,PI))
		var expected := Vector2.ZERO
		var half: Vector2 = shape.shape.size * .5
		for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
			var distance: float = (shape.to_global(corner)-actor.global_position).dot(axis)
			expected.x = maxf(expected.x,distance)
			expected.y = maxf(expected.y,-distance)
		assert(FLOW.extent(actor,axis).distance_to(expected)<.0002, "Projected rectangle extent includes offsets, rotation, scale and skew")
	actor.free()
	print("TRAFFIC_PROJECTION PASS projections=100 extents=300 live_curve_edits=2")
	quit(0)
