extends "res://world/mountain_pass/MountainCabinInterior.gd"
var room_view: Node2D
var _active := false
func _init() -> void:
	interior_id = &"lumberjack_shelter"
	display_name = "ABRIGO DOS LENHADORES"
	inline_model_script = preload("res://world/mountain_pass/LumberjackBunkhouseInline3D.gd")
func _setup_interior_content() -> void:
	if inline_mode:
		super._setup_interior_content()
		return
	_setup_3d_cabin_viewport()
	_setup_heat_source()
	_build_projected_furniture()
	var pickup := preload("res://world/mountain_pass/MountainWeaponPickup.gd").new()
	pickup.name = "WoodAxeStation"
	pickup.weapon_id = "axe"
	pickup.pickup_id = "lumberjack_shelter_axe"
	pickup.render_host = self
	pickup.position = project_floor(Vector2(2.2,-2.7))
	add_child(pickup)
	pickup.install_model(cabin_3d_world, Vector3(2.2,0.08,-2.7))
	_create_spawn_and_exit(project_floor(Vector2(0,3.0)),project_floor(Vector2(0,4.15)),&"lumberjack_exterior_return","SAIR DO ABRIGO DOS LENHADORES")
	exit_door.custom_prompt_text = "E"
	exit_door.get_node("Facade").hide()
	_setup_overview_camera()
func _setup_weapon_stations() -> void:
	if not inline_mode: return
	var pickup := preload("res://world/mountain_pass/MountainWeaponPickup.gd").new()
	pickup.name = "WoodAxeStation"
	pickup.weapon_id = "axe"
	pickup.pickup_id = "lumberjack_shelter_axe"
	pickup.render_host = self
	pickup.position = project_floor(Vector2(.38, .35))
	add_child(pickup)
	pickup.install_model(cabin_3d_world, Vector3(.38, .08, .35))
	_active_weapon_stations.append(pickup)
func _setup_heat_source() -> void:
	super._setup_heat_source()
	if inline_mode:
		var heat_area := get_node_or_null("FireplaceHeatSource") as Area2D
		if heat_area != null and heat_area.get_child_count() > 0:
			var heat_shape := heat_area.get_child(0) as CollisionShape2D
			heat_shape.position = project_floor(Vector2(-1.14, 1.08))
func _setup_3d_cabin_viewport() -> void:
	if inline_mode:
		super._setup_3d_cabin_viewport()
		return
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/LumberjackBunkhouse3D.gd"),14.0,44.0,Vector3(0,0.8,0),Vector3(0,18,15),Vector2i(1080,750))
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	cabin_3d_world = room_view.model
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 11.5
	var target := Vector3(0, .9, -.2)
	camera_3d.look_at_from_position(target + Vector3(0, 18, 15), target, Vector3.UP)
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * 44.0 / maxf(metre, 0.001)
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale
	_configure_room_presentation()

func _configure_room_presentation() -> void:
	for source in viewport_3d.get_children():
		if source is DirectionalLight3D:
			source.light_color = Color("c7d7e5")
			source.light_energy = 0.46
			source.shadow_enabled = true
			source.directional_shadow_max_distance = 24.0
		elif source is WorldEnvironment:
			source.environment.ambient_light_color = Color("b49a7d")
			source.environment.ambient_light_energy = 0.48
	var practical := OmniLight3D.new()
	practical.name = "BunkhouseWarmPractical"
	practical.position = Vector3(0.0, 2.75, 0.1)
	practical.light_color = Color("ffd09a")
	practical.light_energy = 1.15
	practical.omni_range = 7.5
	practical.shadow_enabled = false
	viewport_3d.add_child(practical)
func project_floor(point: Vector2) -> Vector2:
	if inline_mode: return super.project_floor(point)
	return room_view.project_floor(point)
func _build_projected_furniture() -> void:
	if inline_mode:
		super._build_projected_furniture()
		return
	var footprints := {
		"NorthWall":Rect2(-5,-4.8,10,0.2),"WestWall":Rect2(-5.1,-4.7,0.2,9.4),
		"EastWall":Rect2(4.9,-4.7,0.2,9.4),"SouthWall":Rect2(-5,4.7,10,0.2),
		"Workbench":Rect2(-1.85,-4.12,3.7,1.15),"CommunalTable":Rect2(-1.2,-0.27,2.4,1.24),
		"NorthBench":Rect2(-1.15,-0.80,2.3,0.4),"SouthBench":Rect2(-1.15,1.1,2.3,0.4),
		"Stove":Rect2(-4.35,2.35,1.2,1.3),"Woodpile":Rect2(3.0,2.55,1.2,1.3)
	}
	for key in footprints: room_view.add_solid(footprints[key],key)
	for side in [-1.0,1.0]:
		for row in 2: room_view.add_solid(Rect2(side*3.75-0.62,-3.67+row*2.8,1.24,2.34),"WorkerBunk")
func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_active = active
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
func _process(delta: float) -> void:
	super._process(delta)
