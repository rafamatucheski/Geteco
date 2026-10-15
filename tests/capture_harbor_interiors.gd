extends "res://tests/test_vertice_depth.gd"
## Capturas comparáveis (antes/depois) de andares do porto com os moradores
## ativos, na câmera de jogo do prédio. Uso:
##   --script res://tests/capture_harbor_interiors.gd -- --tag=antes
## Grava em evidence/interiors-rework-20261015/<tag>/ (fora do Git).
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACE = preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")
const CONTENT = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const OCCUPANTS = preload("res://world/places/harbor_buildings/HarborBuildingOccupants.gd")
const BUILDING_CAMERA = preload("res://world/places/harbor_buildings/HarborBuildingCamera.gd")
const SHOTS := [
	["harbor_union_apartments", 0], ["harbor_union_apartments", 1], ["harbor_union_apartments", 3],
	["harbor_building_freight_office", 0], ["harbor_building_corner_diner", 0],
	["harbor_building_union_workshop", 0], ["harbor_building_northbank_homes_0", 0],
	["harbor_building_northbank_homes_1", 0], ["harbor_building_island_grocer", 0],
	["harbor_building_porch_house", 0], ["harbor_customs_house", 2],
]

func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("CAPTURE timeout"); quit(3))
	var tag := "antes"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	var folder := "res://evidence/interiors-rework-20261015".path_join(tag)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = .55
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1d2224")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9c4b8")
	environment.environment.ambient_light_energy = .45
	stage.add_child(environment)
	var saved := 0
	for shot in SHOTS:
		var definition := CATALOG.find(str(shot[0]))
		if definition.is_empty(): continue
		var floor_index := int(shot[1])
		var room = PLACE.new()
		room.definition = definition.duplicate(true)
		room.floor_index = floor_index
		stage.add_child(room)
		await physics_frame
		await physics_frame
		var inhabitants: Node3D = OCCUPANTS.populate(room.floor_room, definition, floor_index)
		camera.size = room.camera_size
		camera.position = room.camera_target + BUILDING_CAMERA.offset(definition, floor_index)
		camera.look_at(room.camera_target)
		# Poses (sentar, deitar, caminhar) assentam em poucos segundos.
		await create_timer(2.5).timeout
		var label := "%s-%d-%s" % [definition.id, floor_index, CONTENT.floor_spec(definition, floor_index).program]
		var activities := []
		for resident in inhabitants.residents: activities.append(str(resident.work_activity))
		var image: Image = await capture()
		if image.save_png(folder.path_join(label + ".png")) == OK: saved += 1
		print("CAPTURE ", label, " moradores=", activities)
		room.free()
		await physics_frame
	print("CAPTURE_DONE ", folder, " imagens=", saved)
	quit(0 if saved > 0 else 1)
