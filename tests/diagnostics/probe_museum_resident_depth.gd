extends "res://tests/test_vertice_depth.gd"
## Foto próxima e focada do visitante atrás da exposição do navio no museu.
## A direção da câmera é a de jogo; só o zoom muda para a inspeção.
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var folder := preload("res://tests/fixtures/NorthGatewayFixtures.gd").output_dir("museum-resident-depth")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,960)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bac3c8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-25,0)
	stage.add_child(sun)
	var room = preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd").new()
	room.definition = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").find("harbor_building_maritime_museum")
	stage.add_child(room)
	var people: Node3D = preload("res://world/places/harbor_buildings/HarborBuildingOccupants.gd").populate(room.floor_room,room.definition,0)
	for frame in 8: await physics_frame
	var visitor: CharacterBody3D = people.residents.back()
	visitor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	visitor.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	stage.add_child(camera)
	var target := visitor.global_position+Vector3(0,.65,0)
	camera.position = target+Vector3(0,18,15)
	camera.look_at(target)
	camera.current = true
	(await capture()).save_png(folder.path_join("natural-close.png"))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1,0,1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_meshes(visitor.visual,material)
	var actual := await capture()
	actual.save_png(folder.path_join("visitor-native-mask.png"))
	people.reparent(stage,true)
	room.hide()
	var control := await capture()
	control.save_png(folder.path_join("visitor-control.png"))
	print("MUSEUM_RESIDENT_DEPTH ",folder," actor=",visitor.global_position," visible=",mask_count(actual)," control=",mask_count(control)," clear=",room.is_floor_clear(visitor.global_position)," overlap=",visitor.test_move(visitor.global_transform,Vector3.UP*.002))
	quit(0)
