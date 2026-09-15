extends Node
## The actual articulated car shares the room depth buffer, including its driver.
var car: CharacterBody2D
var view: Node2D
var original_parent: Node
var original_transform: Transform3D
var original_shape: Shape2D
var floor_bounds := Rect2()
var last_transform := Transform2D(0,Vector2(INF,INF))

func configure(vehicle: CharacterBody2D, room_view: Node2D) -> void:
	car = vehicle
	view = room_view
	process_mode = Node.PROCESS_MODE_ALWAYS
	original_parent = car.body_model.get_parent()
	original_transform = car.body_model.transform
	original_shape = car.collision.shape
	var first := true
	for mesh in car.body_model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var transform: Transform3D = car.body_model.global_transform.affine_inverse()*mesh.global_transform
		for i in 8:
			var p: Vector3 = transform*mesh.mesh.get_aabb().get_endpoint(i)
			var point := Vector2(p.x,p.z)
			floor_bounds = Rect2(point,Vector2.ZERO) if first else floor_bounds.expand(point)
			first = false
	car.body_model.reparent(view.viewport_3d,false)
	car.set_meta("interior_vehicle_presentation",self)
	car.tree_exiting.connect(restore,CONNECT_ONE_SHOT)
	view.viewport_3d.tree_exiting.connect(restore,CONNECT_ONE_SHOT)
	car.visual.hide()
	car.collision.shape = ConvexPolygonShape2D.new()
	process_priority = 150
	sync()

func project_anchor(point: Vector3) -> Vector2:
	sync()
	return view.to_global(view.project_point(car.body_model.to_global(point)))

func sync() -> void:
	if not is_instance_valid(car) or not is_instance_valid(view): return
	car.visual.hide()
	car.body_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var p: Vector2 = view.unproject_floor(car.global_position)
	car.body_model.position = Vector3(p.x,0,p.y)
	# Use the same yaw contract as vehicle 3D updates to avoid frame-dependent
	# artifacts in handoff scenes (garage conversation / paused states).
	car.body_model.rotation = Vector3(0,-car.global_rotation - PI/2,0)
	var points := PackedVector2Array()
	for corner in [floor_bounds.position,Vector2(floor_bounds.end.x,floor_bounds.position.y),floor_bounds.end,Vector2(floor_bounds.position.x,floor_bounds.end.y)]:
		var world: Vector3 = car.body_model.to_global(Vector3(corner.x,0,corner.y))
		points.append(car.to_local(view.to_global(view.project_point(world))))
	car.collision.shape.points = points
	car.visual.hide()
	car.body_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for light in [car.headlight,car.second_headlight]:
		if is_instance_valid(light): light.hide()

func _process(_delta: float) -> void:
	sync()

func restore() -> void:
	if not is_instance_valid(car): return
	if car.tree_exiting.is_connected(restore): car.tree_exiting.disconnect(restore)
	if is_instance_valid(view) and is_instance_valid(view.viewport_3d) and view.viewport_3d.tree_exiting.is_connected(restore):
		view.viewport_3d.tree_exiting.disconnect(restore)
	if is_instance_valid(car.body_model) and is_instance_valid(original_parent):
		car.body_model.reparent(original_parent,false)
		car.body_model.transform = original_transform
	car.collision.shape = original_shape
	car.remove_meta("interior_vehicle_presentation")
	car.visual.show()
	car.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	car = null

func _exit_tree() -> void:
	restore()
