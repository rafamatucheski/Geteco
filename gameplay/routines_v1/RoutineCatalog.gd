extends RefCounted
## Rotinas ambientais que existem na arvore produtiva do V1 e ainda nao sao
## cobertas pelos residentes/servicos nativos do V2. O catalogo conserva as
## coordenadas e falas de origem; o diretor decide proximidade e ciclo de vida.

const SCALE := 1.0 / 16.0
const MOUNTAIN_OFFSET := Vector2(4300, -4960)

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_ship_dock_crew())
	result.append_array(_south_port_workers())
	# 2026-10-21: os 23 moradores de fora da serra saíram daqui para
	# `routines_v2/MountainVillagerCatalog.gd` (corpo Meshy, sem golpe de machado no vazio).
	result.append_array(_ski_lodge_residents())
	return result

static func _world_point(point: Vector2, region: String) -> Vector3:
	if region == "mountain": point += MOUNTAIN_OFFSET
	return Vector3(point.x, 0.0, point.y) * SCALE

static func _world_route(points: PackedVector2Array, region: String) -> Array[Vector3]:
	var route: Array[Vector3] = []
	for point in points: route.append(_world_point(point, region))
	return route

static func _ship_dock_crew() -> Array[Dictionary]:
	var routes := [
		PackedVector2Array([Vector2(3442,1702),Vector2(3498,1702),Vector2(3498,1768),Vector2(3442,1768)]),
		PackedVector2Array([Vector2(3552,1702),Vector2(3608,1702),Vector2(3608,1768),Vector2(3552,1768)]),
		PackedVector2Array([Vector2(3662,1702),Vector2(3718,1702),Vector2(3718,1768),Vector2(3662,1768)]),
	]
	var result: Array[Dictionary] = []
	for index in routes.size():
		var route: Array[Vector3] = _world_route(routes[index], "harbor")
		result.append({
			"id":"harbor_ship_dock_operator_%02d" % (index + 1),
			"display_name":"Operador do cais",
			"region":"harbor", "place_id":"", "kind":"dock_worker",
			"position":route[0], "route":route, "stations":[route[0],route[2]],
			"worker_index":index, "night_shift":true, "lines":[],
			"source":"world/harbor/HarborWaterfront.gd -> HarborDockCrew.gd",
		})
	return result

static func _south_port_workers() -> Array[Dictionary]:
	# HarborSouthPort._build_life: todos os 32 postos produtivos. O diretor so
	# materializa os mais proximos; manter o catalogo completo evita transformar
	# um recorte de performance em perda de conteudo.
	var bases := [
		Vector2(3900,3370),Vector2(4430,3370),Vector2(5020,3370),Vector2(5860,3760),
		Vector2(5860,4320),Vector2(4030,5500),Vector2(4920,5500),Vector2(3570,3260),
		Vector2(3860,3770),Vector2(4430,3770),Vector2(5480,4020),Vector2(4430,4650),
		Vector2(5550,5410),Vector2(3490,5510),Vector2(4250,3270),Vector2(4400,2880),
		Vector2(4780,2880),Vector2(5140,2880),Vector2(5410,2990),Vector2(3940,2820),
		Vector2(3890,4180),Vector2(4470,4150),Vector2(5100,4160),Vector2(5540,4110),
		Vector2(3920,4630),Vector2(4540,4620),Vector2(5140,4640),Vector2(5380,4650),
		Vector2(4160,5510),Vector2(4610,5520),Vector2(5180,5510),Vector2(5810,4970),
	]
	var night_indexes := [6,7,13,19,20,22,24,27,29,31]
	var result: Array[Dictionary] = []
	for index in bases.size():
		var point: Vector2 = bases[index]
		var route_2d := PackedVector2Array([point,point+Vector2(90,0),point+Vector2(90,65),point+Vector2(0,65)])
		if index < 3: route_2d = PackedVector2Array([point,point+Vector2(60,0),point+Vector2(60,24),point+Vector2(0,24)])
		elif index == 5:
			# O volume nativo atual de pallets ocupa a perna oeste autorada em
			# x=4030. Preserve o mesmo circuito no corredor paralelo livre; nao
			# materialize o trabalhador dentro da carga nem atravesse o solido.
			point += Vector2(90,0)
			route_2d = PackedVector2Array([point,point+Vector2(90,0),point+Vector2(90,65),point+Vector2(0,65)])
		elif index == 7:
			# A quina do volume portuário toca exatamente x=3570 no trecho
			# longo. Entre pelo corredor adjacente x=3552 e preserve o mesmo
			# percurso norte/sul sem admitir o corpo dentro do sólido.
			route_2d = PackedVector2Array([point,Vector2(3552,3260),Vector2(3552,2230),Vector2(3552,2780)])
		elif index == 14: route_2d = PackedVector2Array([point,Vector2(4250,3070),Vector2(4250,2890),Vector2(4250,3070)])
		elif index >= 15 and index <= 17: route_2d = PackedVector2Array([point,point+Vector2(180,0),point+Vector2(180,18),point+Vector2(0,18)])
		elif index == 18: route_2d = PackedVector2Array([point,Vector2(5490,2990),Vector2(5490,3060),Vector2(5410,3080)])
		elif index == 19: route_2d = PackedVector2Array([point,Vector2(3960,2820),Vector2(3960,3020),Vector2(3940,3020)])
		var route: Array[Vector3] = _world_route(route_2d, "harbor")
		result.append({
			"id":"south_port_worker_%02d" % index,
			"display_name":"Trabalhador do Porto Sul",
			"region":"harbor", "place_id":"", "kind":"dock_worker",
			"position":route[0], "route":route, "stations":[route[0],route[2]],
			"worker_index":index + 3, "night_shift":index in night_indexes, "lines":[],
			"source":"world/harbor/HarborPreview.tscn:SouthPort -> HarborSouthPort.gd:_build_life",
		})
	return result

static func _ski_lodge_residents() -> Array[Dictionary]:
	var records := [
		["ski_clerk_matias","MATIAS","ranger",Color("2e5572"),Vector3(-4.7,0,-3.6),["Bem-vindo ao Cume Branco! Alugue o traje e retire seus skis no rack.","O teleférico da base traz você de volta após cada descida.","O resort funciona das 08:00 às 18:00 enquanto há luz do sol."]],
		["ski_guest_helena","HELENA","visitor",Color("8c4436"),Vector3(-4.15,0,3.1),["Nada melhor que um chocolate quente após encarar a face norte.","A vista lá de cima antes da largada é incrível."]],
		["ski_guest_lucas","LUCAS","visitor",Color("4b7259"),Vector3(4.6,0,2.3),["Consegui um tempo ótimo no Slalom do Pinhal!","O teleférico opera até as 18h, aproveite enquanto há dia."]],
	]
	var result: Array[Dictionary] = []
	for index in records.size():
		var record: Array = records[index]
		result.append({
			"id":record[0], "display_name":record[1], "region":"mountain", "place_id":"ski_lodge",
			"kind":"mountain_resident", "role":record[2], "coat_color":record[3],
			"local_position":record[4], "stationary":true, "appearance_variant":40 + index,
			"lines":record[5],
			"source":"world/mountain_pass/MountainPass.gd -> SummitSkiLodgeInterior.gd:_spawn_lodge_npcs",
		})
	return result
