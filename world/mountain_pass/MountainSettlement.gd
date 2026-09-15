extends Node2D
const PROPS := "res://world/mountain_pass/art/winter_props/"
const SITES := [Vector2(7940,850),Vector2(8610,700),Vector2(7660,-730)]
const VILLAGE := preload("res://world/mountain_pass/MountainVillageLayout.gd")
const BENCH_GEOMETRY := preload("res://world/mountain_pass/transit/MountainBenchGeometry.gd")
const GROUND := preload("res://world/mountain_pass/MountainGroundMaterials.gd")
const SOIL := preload("res://world/mountain_pass/ForestGroundBlend.gd")
const SKI_LAYOUT := preload("res://world/mountain_pass/MountainSkiLayout.gd")
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
	GROUND.apply(driveway,"earth")
	SOIL.path(driveway,18.0,true)
	for trail in [PackedVector2Array([Vector2(7850,580),Vector2(7890,760),Vector2(7940,885)]), PackedVector2Array([Vector2(8700,460),Vector2(8750,670),Vector2(8610,735)]), PackedVector2Array([Vector2(7750,-220),Vector2(7720,-490),Vector2(7660,-695)])]:
		var track := Line2D.new()
		track.z_index = -2
		track.width = 22
		track.default_color = Color("494333")
		track.points = trail
		add_child(track)
		GROUND.apply(track,"earth")
		SOIL.path(track,12.0)
	for i in SITES.size():
		var clearing := Polygon2D.new()
		clearing.z_index = -2
		clearing.position = SITES[i]
		clearing.color = Color("343a2b")
		var points := PackedVector2Array()
		for j in 16: points.append(Vector2(cos(j*TAU/16)*105,sin(j*TAU/16)*75))
		clearing.polygon = points
		add_child(clearing)
		GROUND.apply(clearing,"earth")
		SOIL.polygon(clearing,"earth",28.0)
		var cabin := _prop("LumberjackCabin3D", SITES[i], Color("654b36") if i % 2 == 0 else Color("435e69"))
		await _budget_pause()
		var entrance: BuildingEntrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
		entrance.name = "ForestCabinEntrance%d" % i
		entrance.position = SITES[i] + cabin.project(cabin.model.entrance_local_position) + Vector2(0,12)
		entrance.custom_prompt_text = "E"
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
	for pocket_index in VILLAGE.POCKETS.size():
		var pocket: Vector2 = VILLAGE.POCKETS[pocket_index]
		var apron := Polygon2D.new()
		apron.name = "WinterStopApron%d" % pocket_index
		apron.z_index = 1
		apron.color = Color("a3adb0")
		apron.position = pocket
		if pocket_index == 1:
			apron.polygon = _roadside_apron_polygon(road,pocket)
		elif pocket_index == 2:
			apron.polygon = PackedVector2Array([Vector2(70,-165),Vector2(475,-160),Vector2(620,-105),Vector2(650,48),Vector2(600,125),Vector2(120,130),Vector2(50,80),Vector2(325,-10)])
			apron.internal_vertex_count = 1
			var fades := PackedColorArray()
			for i in 7: fades.append(Color(1,1,1,0))
			fades.append(Color.WHITE)
			apron.vertex_colors = fades
		else:
			apron.polygon = PackedVector2Array([Vector2(-170,-110),Vector2(130,-110),Vector2(145,100),Vector2(-180,100)])
		add_child(apron)
		GROUND.apply(apron,"snow" if pocket_index==2 else "packed")
		var access_curve := VILLAGE.winter_stop_access_curve(road.curve,pocket_index)
		var access := Line2D.new()
		access.name = "WinterStopAccess%d" % pocket_index
		access.z_index = 3 if pocket_index == 1 else 1
		access.width = 62
		access.joint_mode = Line2D.LINE_JOINT_ROUND
		access.begin_cap_mode = Line2D.LINE_CAP_NONE if pocket_index == 1 else Line2D.LINE_CAP_ROUND
		access.end_cap_mode = Line2D.LINE_CAP_NONE if pocket_index == 1 else Line2D.LINE_CAP_ROUND
		access.default_color = apron.color if pocket_index == 1 else Color("84918f")
		# The main junction owns the first 140px of the physical approach.
		# Packed snow blends in beyond the asphalt throat, never across the road.
		var paint_start := 140.0 if pocket_index == 1 else 0.0
		if pocket_index == 1:
			var blend := Gradient.new()
			blend.set_color(0,Color(1,1,1,0))
			blend.set_color(1,Color.WHITE)
			blend.add_point(clampf(40.0/(access_curve.get_baked_length()-paint_start),0.01,0.99),Color.WHITE)
			access.gradient = blend
		for offset in range(int(paint_start),int(access_curve.get_baked_length()),4):
			access.add_point(access_curve.sample_baked(float(offset),true))
		access.add_point(access_curve.sample_baked(access_curve.get_baked_length(),true))
		access.set_meta("access_curve",access_curve)
		access.set_meta("driveable_width",62.0)
		access.set_meta("packed_start_offset",paint_start)
		add_child(access)
		GROUND.apply(access,"packed")
		if pocket_index == 1:
			var bay := VILLAGE.parking_bay(pocket_index)
			var marking := Line2D.new()
			marking.name = "WinterParkingBay1"
			marking.z_index = 3
			marking.width = 1.8
			marking.default_color = Color("d9d8c1")
			marking.points = PackedVector2Array([bay.position,Vector2(bay.end.x,bay.position.y),bay.end,Vector2(bay.position.x,bay.end.y),bay.position])
			add_child(marking)
			marking.set_meta("mountain_parking_rect",bay)
		var shelter: Node2D
		if pocket_index == 2:
			shelter = preload("res://world/mountain_pass/SummitSkiLodgeExterior.gd").new()
			shelter.position = SKI_LAYOUT.LODGE_POSITION
			add_child(shelter)
			shelter.call("install_entrance", get_parent().interior_manager)

			var boutique := preload("res://world/mountain_pass/ResortShopFacade.gd").new()
			boutique.name = "ResortShopFacade"
			boutique.position = Vector2(7400, -2735)
			add_child(boutique)
			boutique.install_entrance(get_parent().interior_manager)

			var promenade := preload("res://world/mountain_pass/ResortPromenade.gd").new()
			promenade.name = "ResortPromenade"
			add_child(promenade)

			var bay2 := Line2D.new()
			bay2.name = "WinterParkingBay2"
			bay2.z_index = 3
			bay2.width = 2.0
			bay2.default_color = Color("d9d8c1")
			bay2.points = PackedVector2Array([
				Vector2(6925, -2658), Vector2(7055, -2658),
				Vector2(7055, -2602), Vector2(6925, -2602),
				Vector2(6925, -2658)
			])
			add_child(bay2)
		else:
			shelter = _prop("PatrolShelter3D",pocket+Vector2(0,-15),Color("455b65"),true)
			shelter.name = "WinterShelter%d" % pocket_index
		await _budget_pause()
		var bench_position := pocket + (Vector2(-115, 62) if pocket_index == 2 else Vector2(90,35))
		var trail_bench := _prop("TrailSignAndBench3D",bench_position,Color("746049"))
		trail_bench.name = "WinterTrailBench%d" % pocket_index
		await _budget_pause()
	for entry in VILLAGE.RESIDENTS:
		var resident := preload("res://world/mountain_pass/WinterResident.gd").new()
		resident.position = entry[0]
		resident.resident_name = entry[1]
		resident.role = entry[2]
		resident.coat_color = entry[3]
		if resident.resident_name == "ÍRIS":
			resident.is_stationary = true
			resident.lines = [
				"Bem-vindo ao Resort Cume Branco! O acesso rodoviário ao concourse está limpo.",
				"A Boutique Alpina ao lado do chalé tem trajes de alta proteção térmica.",
				"O teleférico da face norte opera até as 18:00 com acesso livre para hóspedes."
			]
		elif resident.resident_name == "SÉRGIO":
			resident.is_stationary = true
			resident.lines = [
				"A vista da cordilheira no mirante antes da largada é incrível.",
				"O braseiro central na praça do resort é perfeito para aquecer antes de subir ao teleférico."
			]
		else:
			resident.lines = ["Pode se aquecer no abrigo. A nevasca chega sem aviso.","O pessoal do porto sobe por aqui todos os dias."]
		add_child(resident)
		await _budget_pause()
	for parking_index in VILLAGE.PARKING.size():
		var entry: Array = VILLAGE.PARKING[parking_index]
		var parking_position: Vector2 = Vector2(6990, -2630) if parking_index == 2 else entry[0]
		var parking_angle: float = 0.0 if parking_index == 2 else entry[2]
		var vehicle := ModernTrafficFactory.spawn_parked_vehicle(self,"WinterParking%d"%parking_index,parking_position,parking_angle,entry[1],0,Color("c8d1d3") if entry[1] == "polar_van" else Color("697b7d"))
		vehicle.set_meta("mountain_parking_index",parking_index)
		await _budget_pause()
	preload("res://world/mountain_pass/transit/MountainWinterDressing.gd").install_pockets(self)

func _roadside_apron_polygon(road: Node2D,pocket: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array([Vector2(-148,-135),Vector2(165,-135),Vector2(185,-115),Vector2(185,124),Vector2(165,145)])
	# Follow the actual bend instead of letting the rectangular courtyard's
	# lower-left corner cover its shoulder. This changes surface paint only.
	for y in range(145,-136,-20):
		var x := pocket.x-170.0
		var point := Vector2(x,pocket.y+float(y))
		var setback := lerpf(106.0,142.0,smoothstep(40.0,105.0,float(y)))
		while x < pocket.x+70.0 and point.distance_to(road.curve.get_closest_point(point)) < setback:
			x += 2.0
			point.x = x
		polygon.append(point-pocket)
	return polygon

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
	BENCH_GEOMETRY.install_prop(prop,kind)
	return prop
