extends "res://world/mountain_pass/MountainInlineSpecialRoom.gd"

var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var overview_camera: Camera2D

func _init() -> void:
	interior_id = &"mountain_mystery_cave"
	display_name = "CAVERNA DA QUEDA"
	room_size = Vector2(880, 610)
	inline_scale = Vector2(.66, .72)
	inline_pixels_per_metre = 18.0
	inline_bounds = Rect2(-7.8, -6.2, 15.6, 11.7)

func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	room_view.name = "MysteryCaveRoomView"
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/MountainMysteryCaveInterior3D.gd"), 14.5, 42.0, Vector3(0, 1.2, 0), Vector3(0, 18, 15), Vector2i(1280, 960))
	if inline_mode: room_view.model.scale = Vector3(inline_scale.x, 1, inline_scale.y)
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	apply_inline_projection(sprite_3d, camera_3d, viewport_3d)
	for source in viewport_3d.get_children():
		if source is DirectionalLight3D:
			source.light_color = Color("99b7ce")
			source.light_energy = .28
		elif source is WorldEnvironment:
			source.environment.ambient_light_color = Color("91aaa5")
			source.environment.ambient_light_energy = .35
	_build_projected_solids()
	_install_secret_weapon()
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0, 4.0))
		add_child(spawn_point)
	else:
		_create_spawn_and_exit(room_view.project_floor(Vector2(0, 4.0)), room_view.project_floor(Vector2(0, 5.0)), &"waterfall_cave_exterior", "SAIR DA CAVERNA")
		exit_door.name = "CaveExit"
		exit_door.custom_prompt_text = "E"
		exit_door.get_node("Facade").hide()
	overview_camera = Camera2D.new()
	overview_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	overview_camera.name = "CaveOverview"
	overview_camera.enabled = false
	overview_camera.position = sprite_3d.position
	overview_camera.set_meta("mountain_fixed_framing", true)
	add_child(overview_camera)
	_update_overview()
	get_viewport().size_changed.connect(_update_overview)
	_add_evidence(
		"ExpeditionJournal",
		project_floor(Vector2(-3.4, -0.5)),
		"mountain_expedition_journal",
		"DIÁRIO DE ÁLVARO",
		"Terceira noite. As pegadas não são de urso. Elas começam junto à cachoeira e terminam na pedra, como se alguma coisa entrasse na própria montanha. Ouvi a respiração outra vez. Vou subir até a face norte ao amanhecer.",
		"journal"
	)
	_add_evidence(
		"BrokenCamera",
		project_floor(Vector2(4.6, -2.7)),
		"mountain_expedition_camera",
		"CÂMERA QUEBRADA",
		"O último quadro ainda está intacto: uma figura enorme e clara observa o acampamento do outro lado da crista. Ao fundo aparecem os portões pretos da antiga pista de ski.",
		"camera"
	)

func _add_evidence(node_name: String, point: Vector2, id: String, title: String, text: String, kind: String) -> void:
	var evidence := preload("res://world/mountain_pass/MountainEvidence.gd").new()
	evidence.name = node_name
	evidence.configure(id, title, text, kind)
	evidence.position = point
	add_child(evidence)

func project_floor(point: Vector2) -> Vector2:
	return room_view.project_floor(point * inline_scale if inline_mode else point)

func _inline_floor_vertices() -> Array[Vector2]:
	return preload("res://world/mountain_pass/MountainMysteryCaveInterior3D.gd").FLOOR_OUTLINE

func _update_overview() -> void:
	var footprint := Vector2(viewport_3d.size) * sprite_3d.scale
	var screen := get_viewport_rect().size
	overview_camera.zoom = Vector2.ONE * minf(screen.x / footprint.x, screen.y / footprint.y) * .94

func _install_secret_weapon() -> void:
	var pickup := preload("res://world/mountain_pass/CaveSecretWeapon.gd").new()
	pickup.name = "SecretRPG"
	pickup.render_host = self
	pickup.position = project_floor(Vector2(3.1,0.65))
	add_child(pickup)
	# Keep the floating reward over the same clear floor as its contact area.
	pickup.install_model(room_view.model, Vector3(3.1, 0.08, 0.65))
	pickup.model.rotation.y = PI*0.5
	pickup.model.get_node("FloorWeapon").scale = Vector3.ONE*1.4

func contains_actor(actor: Node2D) -> bool:
	if inline_mode: return super.contains_actor(actor)
	return is_instance_valid(actor) and actor.get_meta("mountain_interior_id", &"") == interior_id and global_position.distance_to(actor.global_position) < 900.0

func _build_projected_solids() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedCaveSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(room_view.model,walls_body,project_floor)
	# The actual floor is irregular. Rectangular exterior walls left empty
	# walkable pockets beyond the cave; derive its boundary from the art outline.
	var outline: Array[Vector2] = preload("res://world/mountain_pass/MountainMysteryCaveInterior3D.gd").FLOOR_OUTLINE
	for index in outline.size()-1:
		var start := outline[index]
		var end := outline[index+1]
		var normal := (end-start).normalized().orthogonal() * .9
		var shape := CollisionPolygon2D.new()
		shape.name = "CaveContour%d" % index
		shape.polygon = PackedVector2Array([project_floor(start-normal),project_floor(end-normal),project_floor(end+normal),project_floor(start+normal)])
		walls_body.add_child(shape)
	if not inline_mode: room_view.add_solid(Rect2(-1,5.6,2,.2),"CaveExitThreshold")

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if is_instance_valid(overview_camera):
		overview_camera.enabled = active and not inline_mode
		if active and not inline_mode: overview_camera.make_current()
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
