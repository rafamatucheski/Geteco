extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D

func _init() -> void:
	interior_id = &"mountain_mystery_cave"
	display_name = "CAVERNA DA QUEDA"
	room_size = Vector2(880, 610)

func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	room_view.name = "MysteryCaveRoomView"
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/MountainMysteryCaveInterior3D.gd"), 18.5, 42.0, Vector3(0, 1.2, 0), Vector3(0, 23, 20), Vector2i(1280, 960))
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	_build_projected_solids()
	_install_secret_weapon()
	_create_spawn_and_exit(room_view.project_floor(Vector2(0, 4.0)), room_view.project_floor(Vector2(0, 5.0)), &"waterfall_cave_exterior", "SAIR DA CAVERNA")
	exit_door.name = "CaveExit"
	exit_door.custom_prompt_text = "E"
	exit_door.get_node("Facade").hide()
	_add_evidence(
		"ExpeditionJournal",
		room_view.project_floor(Vector2(-3.4, -0.5)),
		"mountain_expedition_journal",
		"DIÁRIO DE ÁLVARO",
		"Terceira noite. As pegadas não são de urso. Elas começam junto à cachoeira e terminam na pedra, como se alguma coisa entrasse na própria montanha. Ouvi a respiração outra vez. Vou subir até a face norte ao amanhecer.",
		"journal"
	)
	_add_evidence(
		"BrokenCamera",
		room_view.project_floor(Vector2(4.6, -2.7)),
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

func _install_secret_weapon() -> void:
	var pickup := preload("res://world/mountain_pass/CaveSecretWeapon.gd").new()
	pickup.name = "SecretRPG"
	pickup.render_host = self
	pickup.position = room_view.project_floor(Vector2(3.1,0.65))
	add_child(pickup)
	pickup.install_model(room_view.model,preload("res://world/mountain_pass/MountainMysteryCaveInterior3D.gd").SECRET_POSITION)
	pickup.model.rotation.y = PI*0.5
	pickup.model.get_node("FloorWeapon").scale = Vector3.ONE*1.4

func contains_actor(actor: Node2D) -> bool:
	return is_instance_valid(actor) and actor.get_meta("mountain_interior_id", &"") == interior_id and global_position.distance_to(actor.global_position) < 900.0

func _build_projected_solids() -> void:
	for entry in [
		[Rect2(-8.0, -5.5, 16.0, 0.65), "CaveBackWall"],
		[Rect2(-8.0, -5.5, 0.70, 11.0), "CaveWestWall"],
		[Rect2(7.3, -5.5, 0.70, 11.0), "CaveEastWall"],
		[Rect2(-8.0, 5.0, 6.9, 0.55), "CaveMouthLeft"],
		[Rect2(1.1, 5.0, 6.9, 0.55), "CaveMouthRight"],
		[Rect2(-6.5, -4.5, 3.0, 2.0), "CaveRockWest"],
		[Rect2(4.2, -4.6, 3.2, 2.0), "CaveRockEast"],
		[Rect2(1.92,-1.18,2.36,1.16), "SecretWeaponCase"],
	]:
		room_view.add_solid(entry[0], entry[1])

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED
