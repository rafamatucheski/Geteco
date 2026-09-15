extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var front_exit: BuildingEntrance
var slope_exit: BuildingEntrance
var _active := false

func _init() -> void:
	interior_id = &"ski_lodge"
	display_name = "CUME BRANCO"
	room_size = Vector2(840, 570)

func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	room_view.name = "SkiLodgeRoomView"
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/SummitSkiLodgeInterior3D.gd"), 18.5, 43.0, Vector3(0, 1.1, 0), Vector3(0, 23, 20), Vector2i(1280, 960))
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	# Perspective cutaway, as in the cabin. Finalize before projecting gameplay.
	camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_3d.fov = 46.0
	camera_3d.look_at_from_position(Vector3(7.8, 16.8, 20.5), Vector3(0, 0.8, 0))
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * 43.0 / metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale
	_configure_shelter_lighting()
	_build_projected_solids()
	_create_spawn_and_exit(room_view.project_floor(Vector2(0, 4.0)), room_view.project_floor(Vector2(0, 4.8)), &"ski_lodge_front", "SAIR PARA O PÁTIO")
	front_exit = exit_door
	front_exit.name = "FrontExit"
	front_exit.custom_prompt_text = "E"
	front_exit.get_node("Facade").hide()
	slope_exit = _make_extra_exit("SlopeExit", room_view.project_floor(Vector2(0, -4.65)), &"ski_lodge_slope", "SAIR PARA AS PISTAS", true)

	var rental := preload("res://world/mountain_pass/SkiRentalStation.gd").new()
	rental.name = "RentalCounter"
	rental.station_kind = "rental"
	rental.position = room_view.project_floor(Vector2(-4.7, -1.75))
	add_child(rental)
	var rack := preload("res://world/mountain_pass/SkiRentalStation.gd").new()
	rack.name = "EquipmentRack"
	rack.station_kind = "rack"
	rack.position = room_view.project_floor(Vector2(4.8, -1.0))
	add_child(rack)

	var heat := Area2D.new()
	heat.name = "LodgeFireplaceHeat"
	heat.add_to_group("heat_source")
	var heat_shape := CollisionShape2D.new()
	var heat_circle := CircleShape2D.new()
	heat_circle.radius = 520.0
	heat_shape.shape = heat_circle
	heat.add_child(heat_shape)
	add_child(heat)

	_spawn_lodge_npcs()

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
	clerk.position = room_view.project_floor(Vector2(-4.7, -3.6))
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
	guest_fire.position = room_view.project_floor(Vector2(-4.15, 3.1))
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
	guest_lounge.position = room_view.project_floor(Vector2(4.6, 2.3))
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
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(room_view.model,walls_body,room_view.project_floor)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_active = active
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if room_view and room_view.model:
		room_view.model.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
