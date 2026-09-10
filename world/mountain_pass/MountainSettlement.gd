extends Node2D
const PROPS := "res://world/mountain_pass/art/winter_props/"
const SITES := [Vector2(7940,850),Vector2(8610,700),Vector2(7660,-730)]
const VILLAGE := preload("res://world/mountain_pass/MountainVillageLayout.gd")
var region_ready := false
var _streamed := false

func _ready() -> void:
	_streamed = bool(get_parent().get("streamed_region"))
	var driveway := Line2D.new()
	driveway.width = 52
	driveway.z_index = 1
	driveway.default_color = Color("48443a")
	driveway.points = PackedVector2Array(VILLAGE.ACCESS_PATHS[0])
	add_child(driveway)
	for trail in [PackedVector2Array([Vector2(7850,580),Vector2(7890,760),Vector2(7940,885)]), PackedVector2Array([Vector2(8700,460),Vector2(8750,670),Vector2(8610,735)]), PackedVector2Array([Vector2(7750,-220),Vector2(7720,-490),Vector2(7660,-695)])]:
		var track := Line2D.new()
		track.z_index = -2
		track.width = 22
		track.default_color = Color("494333")
		track.points = trail
		add_child(track)
	for i in SITES.size():
		var clearing := Polygon2D.new()
		clearing.z_index = -2
		clearing.position = SITES[i]
		clearing.color = Color("343a2b")
		var points := PackedVector2Array()
		for j in 16: points.append(Vector2(cos(j*TAU/16)*105,sin(j*TAU/16)*75))
		clearing.polygon = points
		add_child(clearing)
		var cabin := _prop("LumberjackCabin3D", SITES[i], Color("654b36") if i % 2 == 0 else Color("435e69"))
		await _budget_pause()
		var entrance: BuildingEntrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
		entrance.name = "ForestCabinEntrance%d" % i
		entrance.position = SITES[i] + cabin.project(cabin.model.entrance_local_position) + Vector2(0,12)
		entrance.custom_prompt_text = "[E] ABRIGO DOS LENHADORES"
		add_child(entrance)
		entrance.get_node("Facade").hide()
		get_parent().interior_manager.register_exterior_entrance(entrance,&"lumberjack_shelter",entrance.global_position+Vector2(0,22))
		_prop("CoveredWoodpile3D",SITES[i]+Vector2(70,-10),Color("594333"))
		await _budget_pause()
	var shelter := _prop("PatrolShelter3D",Vector2(6610,-1250),Color("3b575e"),true)
	await _budget_pause()
	var heat := Marker2D.new()
	heat.add_to_group("heat_source")
	shelter.add_child(heat)
	_prop("TrailSignAndBench3D",Vector2(6710,-1280),Color("69503a"))
	await _budget_pause()
	for entry in [
		[Vector2(8030,895),"ELIAS","logger",Color("93624a"),["O comboio dos Lobos passou antes da nevasca.","Lenha seca vale ouro por aqui."]],
		[Vector2(8560,785),"NORA","ranger",Color("3d6873"),["Não siga os rastros grandes na mata.","O abrigo de patrulha fica antes do mirante."]],
		[Vector2(6560,-1205),"TOMÁS","ranger",Color("59715a"),["Espere a rajada passar antes de subir.","Acima do bunker, as luzes já são da outra cidade."]],
	]:
		var resident := preload("res://world/mountain_pass/WinterResident.gd").new()
		resident.position = entry[0]
		resident.resident_name = entry[1]
		resident.role = entry[2]
		resident.coat_color = entry[3]
		resident.lines.assign(entry[4])
		add_child(resident)
		await _budget_pause()

	for point in [Vector2(8220,-1150),Vector2(8670,-200)]:
		var bear := preload("res://world/mountain_pass/MountainBear.gd").new()
		bear.name = "ForestBear" + str(get_child_count())
		bear.position = point
		add_child(bear)
		await _budget_pause()
		if point == Vector2(8220,-1150):
			for offset in [Vector2(-50,35),Vector2(45,48)]:
				var cub := preload("res://world/mountain_pass/MountainBear.gd").new()
				cub.name = "BearCub" + str(get_child_count())
				cub.is_cub = true
				cub.family_guardian = bear
				cub.family_offset = offset
				cub.position = point + offset
				add_child(cub)
				await _budget_pause()

	await _build_winter_stops()
	region_ready = true

func _build_winter_stops() -> void:
	var road: Node2D = get_parent().road
	for pocket in VILLAGE.POCKETS:
		var apron := Polygon2D.new()
		apron.z_index = 1
		apron.color = Color("a3adb0")
		apron.position = pocket
		apron.polygon = PackedVector2Array([Vector2(-170,-110),Vector2(130,-110),Vector2(145,100),Vector2(-180,100)])
		add_child(apron)
		var access := Line2D.new()
		access.z_index = 1
		access.width = 64
		access.default_color = Color("84918f")
		access.points = PackedVector2Array([road.curve.get_closest_point(pocket),pocket])
		add_child(access)
		_prop("PatrolShelter3D",pocket+Vector2(0,-15),Color("455b65"),true)
		await _budget_pause()
		_prop("TrailSignAndBench3D",pocket+Vector2(90,35),Color("746049"))
		await _budget_pause()
	for entry in VILLAGE.RESIDENTS:
		var resident := preload("res://world/mountain_pass/WinterResident.gd").new()
		resident.position = entry[0]
		resident.resident_name = entry[1]
		resident.role = entry[2]
		resident.coat_color = entry[3]
		resident.lines = ["Pode se aquecer no abrigo. A nevasca chega sem aviso.","O pessoal do porto sobe por aqui todos os dias."]
		add_child(resident)
		await _budget_pause()
	for entry in VILLAGE.PARKING:
		ModernTrafficFactory.spawn_parked_vehicle(self,"WinterParking%d"%get_child_count(),entry[0],entry[2],entry[1],0,Color("c8d1d3") if entry[1] == "polar_van" else Color("697b7d"))
		await _budget_pause()

func _budget_pause() -> void:
	if _streamed: await get_tree().process_frame

func _prop(kind: String, point: Vector2, color: Color, open_front := false) -> Node2D:
	var prop := preload("res://world/mountain_pass/MountainProp.gd").new()
	prop.name = kind + str(get_child_count())
	prop.model_script = load(PROPS + kind + ".gd")
	prop.paint = color
	prop.position = point
	prop.open_front = open_front
	add_child(prop)
	return prop
