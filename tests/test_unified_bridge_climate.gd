extends SceneTree
## Contrato geográfico: toda a travessia conserva o clima costeiro; os biomas
## continuam ativos em terra. Não substitui captura temporal no Main renderizado.
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const NORTH := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const COLD := preload("res://runtime/ColdSurvival.gd")
var failures := 0
var checks := 0

class SessionStub extends Node:
	var state := {"region_id":"mountain","place_id":""}
	var world: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	create_timer(45,true,false,true).timeout.connect(func():
		push_error("Validação climática excedeu 45 s")
		quit(3))
	run.call_deferred()

func run() -> void:
	var points: Array[Vector3] = []
	# Tronco dividido e curvas anteriores à bifurcação pertencem à mesma obra.
	for z in [-125.0,-140.0,-175.0,-210.0,-245.0,-262.5]:
		for x in [367.5,375.0,382.5]: points.append(Vector3(x,0,z))
	for point in [Vector3(365,0,-262),Vector3(385,0,-281),Vector3(405,0,-292)]:
		points.append(point)
	# Centro e ambos os passeios, incluindo cabeceiras e saída do túnel.
	for x in [393.75,405.0,430.0,456.25,468.25,508.0,559.375,578.125,610.0,631.25,643.25]:
		for z in [-291.5,-285.0,-278.5]: points.append(Vector3(x,0,z))
	for i in 31:
		var point := NORTH.sample(NORTH.length()*float(i)/30.0)
		points.append(point)
		points.append(point+Vector3(4,0,0))
		points.append(point-Vector3(4,0,0))
	points.append(Vector3(342.5,2.4,-385.5))
	var player := Node3D.new()
	root.add_child(player)
	var session := SessionStub.new()
	session.world = {"player":player,"driving":{"occupied":false}}
	root.add_child(session)
	var cold := COLD.new()
	cold.session = session
	root.add_child(cold)
	cold.active = false
	for point in points:
		check(is_zero_approx(CONNECTION.mountain_weight(point)),"Sem frio/neve na travessia: %s"%point)
		check(is_zero_approx(ATMOSPHERE.desert_weight(point)),"Sem secagem/deserto na travessia: %s"%point)
		player.position = point
		check(not cold._cold_zone_active(),"Frio não entra na ponte: %s"%point)
		# Também cobre a volta, quando a histerese térmica já estava ativa.
		cold._in_cold_zone = true
		check(not cold._cold_zone_active(),"Frio desativa ao voltar à ponte: %s"%point)
		for hour in [.5,.92]:
			for clouds in [0.0,1.0]:
				var coastal := ATMOSPHERE.sample_at(Vector3(350,0,-240),hour,clouds,1.0)
				var sample := ATMOSPHERE.sample_at(point,hour,clouds,1.0)
				check(sample==coastal,"Paleta costeira uniforme de dia/noite/chuva: %s"%point)
	# As transições continuam graduais fora da estrutura e a montanha conserva o frio.
	check(CONNECTION.mountain_weight(Vector3(655,0,-285))>0.0,"Transição da serra em terra")
	check(is_equal_approx(CONNECTION.mountain_weight(Vector3(700,0,-485)),1.0),"Bioma da montanha preservado")
	check(ATMOSPHERE.desert_weight(Vector3(342.5,0,-410))>0.0,"Transição do deserto em terra")
	check(is_equal_approx(ATMOSPHERE.desert_weight(Vector3(342.5,0,-500)),1.0),"Bioma do deserto preservado")
	player.position = Vector3(700,0,-485)
	check(cold._cold_zone_active(),"Frio continua ativo na montanha")
	cold.free()
	session.free()
	player.free()
	print("UNIFIED_BRIDGE_CLIMATE ",checks," verificações; ",failures," falhas")
	quit(1 if failures else 0)
