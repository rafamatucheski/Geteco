extends "res://world/mountain_pass/MountainInlineSpecialRoom.gd"

var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var front_exit: BuildingEntrance
var slope_exit: BuildingEntrance
var _active := false
var overview_camera: Camera2D

func _init() -> void:
	interior_id = &"ski_lodge"
	display_name = "CUME BRANCO"
	room_size = Vector2(840, 570)
	inline_scale = Vector2(.82, .75)
	inline_pixels_per_metre = 18.0
	inline_bounds = Rect2(-7.70, -5.25, 15.40, 10.50)

func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	room_view.name = "SkiLodgeRoomView"
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/SummitSkiLodgeInterior3D.gd"), 14.2, 43.0, Vector3(0, 1.1, 0), Vector3(0, 18, 15), Vector2i(1440, 1000))
	if inline_mode:
		room_view.model.scale = Vector3(inline_scale.x, 1, inline_scale.y)
		# Keep the two doors connected by a real centre aisle. The fitting booth
		# occupies the west bay between the rental desk and fireplace.
		for fixture in room_view.model.get_children():
			if fixture.get_meta("interior_solid_id", &"") == &"ChangingRooms":
				fixture.position.x -= 3.75
			elif fixture.get_meta("interior_solid_id", &"") == &"RentalCounter":
				fixture.position.z -= .45
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	# Match the approved aligned cutaway before deriving physical footprints.
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * 43.0 / metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale
	apply_inline_projection(sprite_3d, camera_3d, viewport_3d)
	_configure_shelter_lighting()
	_build_projected_solids()
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0, 3.75))
		add_child(spawn_point)
	else:
		_create_spawn_and_exit(room_view.project_floor(Vector2(0, 4.0)), room_view.project_floor(Vector2(0, 4.8)), &"ski_lodge_front", "SAIR PARA O PÁTIO")
		front_exit = exit_door
		front_exit.name = "FrontExit"
		front_exit.custom_prompt_text = "E"
		front_exit.get_node("Facade").hide()
		slope_exit = _make_extra_exit("SlopeExit", room_view.project_floor(Vector2(0, -4.65)), &"ski_lodge_slope", "SAIR PARA AS PISTAS", true)

	var rental := preload("res://world/mountain_pass/SkiRentalStation.gd").new()
	rental.name = "RentalCounter"
	rental.station_kind = "rental"
	rental.position = project_floor(Vector2(-4.7, -1.75))
	add_child(rental)
	var rack := preload("res://world/mountain_pass/SkiRentalStation.gd").new()
	rack.name = "EquipmentRack"
	rack.station_kind = "rack"
	rack.position = project_floor(Vector2(4.8, -1.0))
	add_child(rack)

	var heat := Area2D.new()
	heat.name = "LodgeFireplaceHeat"
	heat.add_to_group("heat_source")
	var heat_shape := CollisionShape2D.new()
	var heat_circle := CircleShape2D.new()
	heat_circle.radius = 72.0 if inline_mode else 520.0
	heat_shape.shape = heat_circle
	if inline_mode: heat_shape.position = project_floor(Vector2(-5.9, 3.15))
	heat.add_child(heat_shape)
	add_child(heat)

	_spawn_lodge_npcs()
	add_cash_reward(room_view.model, Vector2(1.7, 3.4), 900, "summit_lodge_cash_01")
	# Collectibles have no solid footprint; retain explicit mesh classification.
	for mesh in get_node("RoomCash").model.find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("interior_solid_id", &"")
	overview_camera = Camera2D.new()
	overview_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	overview_camera.name = "LodgeOverview"
	overview_camera.enabled = false
	overview_camera.position = sprite_3d.position
	overview_camera.set_meta("mountain_fixed_framing", true)
	add_child(overview_camera)
	_update_overview()
	get_viewport().size_changed.connect(_update_overview)

func project_floor(point: Vector2) -> Vector2:
	return room_view.project_floor(point * inline_scale if inline_mode else point)

func _update_overview() -> void:
	var footprint := Vector2(viewport_3d.size) * sprite_3d.scale
	var screen := get_viewport_rect().size
	overview_camera.zoom = Vector2.ONE * minf(screen.x / footprint.x, screen.y / footprint.y) * .94

func _configure_shelter_lighting() -> void:
	# Rebalance the existing rig once. Actors share these lights and room depth.
	# A cool window fill stays visible beneath the warm practical lamps.
	for source in viewport_3d.get_children():
		if source is DirectionalLight3D:
			source.light_color = Color("c1d7ef")
			source.light_energy = 0.48
		elif source is WorldEnvironment:
			source.environment.ambient_light_color = Color("d3b99b")
			source.environment.ambient_light_energy = 0.55

func _spawn_lodge_npcs() -> void:
	# 1. Atendente do balcão de aluguel
	var clerk := preload("res://world/mountain_pass/WinterResident.gd").new()
	clerk.name = "SkiClerk"
	clerk.position = project_floor(Vector2(-4.7, -4.05 if inline_mode else -3.6))
	clerk.resident_name = "MATIAS"
	clerk.role = "ranger"
	clerk.coat_color = Color("2e5572")
	clerk.is_stationary = true
	clerk.lines = [
		"Bem-vindo ao Cume Branco! Alugue o traje e retire seus skis no rack.",
		"O teleférico da base traz você de volta após cada descida.",
		"O resort funciona das 08:00 às 18:00 enquanto há luz do sol."
	]
	clerk.home = clerk.position
	clerk.destination = clerk.position
	add_child(clerk)

	# 2. Hóspede se aquecendo na lareira
	var guest_fire := preload("res://world/mountain_pass/WinterResident.gd").new()
	guest_fire.name = "LodgeGuestFireplace"
	guest_fire.position = project_floor(Vector2(-4.15, 3.1))
	guest_fire.resident_name = "HELENA"
	guest_fire.role = "visitor"
	guest_fire.coat_color = Color("8c4436")
	guest_fire.is_stationary = true
	guest_fire.lines = [
		"Nada melhor que um chocolate quente após encarar a face norte.",
		"A vista lá de cima antes da largada é incrível."
	]
	guest_fire.home = guest_fire.position
	guest_fire.destination = guest_fire.position
	add_child(guest_fire)

	# 3. Esquiador descansando no banco do lounge
	var guest_lounge := preload("res://world/mountain_pass/WinterResident.gd").new()
	guest_lounge.name = "LodgeGuestLounge"
	guest_lounge.position = project_floor(Vector2(4.6, 2.3))
	guest_lounge.resident_name = "LUCAS"
	guest_lounge.role = "visitor"
	guest_lounge.coat_color = Color("4b7259")
	guest_lounge.is_stationary = true
	guest_lounge.lines = [
		"Consegui um tempo ótimo no Slalom do Pinhal!",
		"O teleférico opera até as 18h, aproveite enquanto há dia."
	]
	guest_lounge.home = guest_lounge.position
	guest_lounge.destination = guest_lounge.position
	add_child(guest_lounge)

func _make_extra_exit(node_name: String, point: Vector2, destination: StringName, label: String, north: bool) -> BuildingEntrance:
	var door := ENTRANCE_SCENE.instantiate() as BuildingEntrance
	door.name = node_name
	door.position = point
	door.rotation = PI if north else 0.0
	door.destination_id = destination
	door.display_name = label
	door.custom_prompt_text = "E"
	door.add_to_group("harbor_interior_exit")
	door.get_node("Facade").hide()
	add_child(door)
	return door

func _build_projected_solids() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedRoomSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(room_view.model,walls_body,project_floor)
	if inline_mode:
		for child in walls_body.get_children():
			if String(child.name).begins_with("ExitThreshold"): child.queue_free()

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_active = active
	if is_instance_valid(overview_camera):
		overview_camera.enabled = active and not inline_mode
		if active and not inline_mode: overview_camera.make_current()
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if room_view and room_view.model:
		room_view.model.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
