extends RefCounted
## Short, pausable mounting shot; no tweens or extra viewport remain afterwards.
const DURATION := 2.4
var active := false
var elapsed := 0.0
var controller: Node
var camera: Camera3D

func begin(owner_controller: Node) -> void:
	controller = owner_controller
	active = true
	elapsed = 0
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.far = 220
	controller.session.world.add_child(camera)
	for row in controller.racers:
		row.bike.race_enabled = false
		row.bike.set_physics_process(false)
		# Grid spawn normally settles by gravity; the frozen shot needs that
		# same physical floor now so tires and the standing rider do not hover.
		var origin: Vector3 = row.bike.global_position
		var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP,origin-Vector3.UP*2,1)
		var hit: Dictionary = row.bike.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): row.bike.global_position.y = float(hit.position.y)+.015
	controller.player_bike.pose_start_mount(0)
	_frame()
	camera.make_current()

func update(delta: float) -> void:
	if not active: return
	elapsed = minf(DURATION,elapsed+delta)
	controller.player_bike.pose_start_mount(clampf((elapsed-.25)/1.1,0,1))
	_frame()
	if elapsed >= DURATION: stop()

func _frame() -> void:
	var bike: Node3D = controller.player_bike
	var focus := bike.global_position+Vector3.UP*.9
	var orbit := bike.global_basis*Vector3(-5.0,3.7,5.5)
	var normal = controller.session.world.camera
	var blend := smoothstep(1.55,DURATION,elapsed)
	camera.global_position = (focus+orbit).lerp(normal.global_position,blend)
	camera.look_at(focus.lerp(normal.focus,blend))
	camera.size = lerpf(7.5,normal.size,blend)

func stop() -> void:
	if not active: return
	active = false
	if is_instance_valid(controller):
		if is_instance_valid(controller.player_bike): controller.player_bike._seat_rider()
		for row in controller.racers:
			if is_instance_valid(row.bike): row.bike.set_physics_process(true)
		if is_instance_valid(controller.session.world.camera): controller.session.world.camera.make_current()
	if is_instance_valid(camera): camera.queue_free()
	camera = null
