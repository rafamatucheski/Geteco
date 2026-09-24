@tool
extends "res://world/harbor/HarborBuilding.gd"
## Physical east-side admission route, separate from the public south entrance.
var hospital_view: Node2D
var emergency_door_open := false
var emergency_door_amount := 0.0
var public_door_amount := 0.0
var public_entrance: Node2D
var overhead_viewport: SubViewport
var overhead_sprite: Sprite2D

func _ready() -> void:
	add_to_group("hospital_emergency_admission")
	hospital_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	hospital_view.name = "HospitalArchitecture3D"
	add_child(hospital_view)
	hospital_view.build_view(preload("res://world/harbor/hospital/HarborHospitalModel3D.gd"), 25.0, 18.0, Vector3(0, 1.2, 0))
	# Geodata needs the calibrated camera to include the projected roof edge.
	super._ready()
	_build_overhead_view()
	public_entrance = get_node_or_null("Entrance")
	if public_entrance:
		public_entrance.self_modulate.a = 0.0
		public_entrance.door_state_changed.connect(func(_door: Node, _open: bool): set_process(true))
	for child in hospital_view.viewport_3d.get_children():
		if child is DirectionalLight3D:
			child.layers = 3
			child.light_cull_mask = 3
			child.shadow_enabled = true
			child.directional_shadow_max_distance = 45.0
			child.light_energy = 0.68
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.40
	set_process(false)

func _build_overhead_view() -> void:
	# Only elevated surfaces cross in front of the independent person/cot
	# viewports. Floor and street frontage remain behind people outside.
	hospital_view.camera_3d.cull_mask = 1
	overhead_viewport = SubViewport.new()
	overhead_viewport.name = "EmergencyOverheadViewport"
	overhead_viewport.size = hospital_view.viewport_3d.size
	overhead_viewport.transparent_bg = true
	overhead_viewport.world_3d = hospital_view.viewport_3d.find_world_3d()
	overhead_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(overhead_viewport)
	var camera := Camera3D.new()
	overhead_viewport.add_child(camera)
	camera.projection = hospital_view.camera_3d.projection
	camera.size = hospital_view.camera_3d.size
	camera.transform = hospital_view.camera_3d.transform
	camera.cull_mask = 2
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.make_current()
	overhead_sprite = Sprite2D.new()
	overhead_sprite.name = "EmergencyOverhead"
	overhead_sprite.texture = overhead_viewport.get_texture()
	overhead_sprite.position = hospital_view.sprite_3d.position
	overhead_sprite.scale = hospital_view.sprite_3d.scale
	overhead_sprite.z_as_relative = false
	overhead_sprite.z_index = 20
	add_child(overhead_sprite)

func _draw() -> void:
	# The architecture is native 3D; the procedural building only supplies access.
	pass

func get_solid_rects() -> Array[Rect2]:
	# The service facade steps back beside the ambulance: the crew can turn
	# around its rear corners without squeezing between a bumper and a wall.
	var solids: Array[Rect2] = [Rect2(-129, -114, 158, 228), Rect2(29, -114, 100, 94), Rect2(29, -20, 75, 26), Rect2(29, 74, 75, 40)]
	if is_instance_valid(hospital_view):
		# Actors share the 2D plane with this render. The elevated north roofs
		# extend beyond their floor bounds, so reserve that visible strip too.
		# Keep the south facade and east admission corridor at ground level.
		var main_top: Vector2 = hospital_view.project_point(hospital_view.model.floor_point(Vector2(-132, -117), 5.265))
		var ward_top: Vector2 = hospital_view.project_point(hospital_view.model.floor_point(Vector2(28.5, -116.5), 4.23))
		solids[0] = Rect2(main_top, Vector2(164, 114 - main_top.y))
		solids[1] = Rect2(ward_top, Vector2(103, -20 - ward_top.y))
	return solids

func get_ambulance_stop_position() -> Vector2:
	return to_global(Vector2(185, 40))

func get_ambulance_stop_rotation() -> float:
	return global_rotation

func get_stretcher_exit_position() -> Vector2:
	return to_global(Vector2(117, 40))

func get_admission_door_position() -> Vector2:
	return to_global(Vector2(102, 40))

func get_admission_inside_position() -> Vector2:
	return to_global(Vector2(74, 40))

func set_emergency_door_open(open: bool) -> void:
	emergency_door_open = open
	set_process(true)

func _process(delta: float) -> void:
	emergency_door_amount = move_toward(emergency_door_amount, 1.0 if emergency_door_open else 0.0, delta*1.4)
	hospital_view.model.set_door_amount(emergency_door_amount)
	if is_instance_valid(public_entrance):
		public_door_amount = public_entrance.open_amount
		hospital_view.model.set_public_door_amount(public_door_amount)
	hospital_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	var public_finished := not is_instance_valid(public_entrance) or is_equal_approx(public_door_amount, 1.0 if public_entrance._door_open else 0.0)
	if public_finished and is_equal_approx(emergency_door_amount, 1.0 if emergency_door_open else 0.0): set_process(false)
