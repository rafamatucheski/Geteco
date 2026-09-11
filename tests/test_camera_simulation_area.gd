extends SceneTree
const BUDGET := preload("res://world/shared/traffic/CameraSimulationArea.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	var world := Node2D.new()
	root.add_child(world)
	var focus := Vector2(4000,-2000)
	for zoom in [0.5,1.0,2.0]:
		root.canvas_transform = Transform2D(Vector2(zoom,0),Vector2(0,zoom),Vector2(root.size)*0.5-focus*zoom)
		var area := BUDGET.visible_area(world,focus)
		var actual := root.canvas_transform.affine_inverse()*world.get_viewport_rect()
		assert(area.encloses(actual))
		assert(area.has_point(actual.position-Vector2(359,359)))
		assert(not area.has_point(actual.position-Vector2(361,361)))
	# Interior camera must keep the external doorway neighbourhood awake.
	root.canvas_transform = Transform2D.IDENTITY
	var exterior := BUDGET.visible_area(world,focus)
	assert(exterior.has_point(focus+Vector2(800,800)))
	assert(not exterior.has_point(Vector2.ZERO))
	world.free()
	print("CAMERA_SIMULATION_AREA passed")
	quit()
