extends RefCounted
## Beira de estrada do deserto (fase 1 do passe de conteúdo, 19/10/2026). Medição de 18/10: cerca
## de 60% de cada estrada não tinha nada a 120 m (o que a câmera de cima mostra), com trechos
## vazios de 340 a 684 m (Route 66 ao sul do Miragem, rodovia oeste, Rua Principal dos dois
## lados da cidade, as pontas da rodovia do sal). Cada lugar fica no meio de um trecho, ~22 m
## fora do eixo da pista e de frente para ela; os eventos de estrada nascem nos trechos que
## continuam vazios. GETECO_DESERT_ROADSIDE=0 desliga tudo (A/B no mesmo export).
const SITE_RADIUS := 18.0
## Monta a ~150 m (um por passo, com o chão pronto) e estaciona a ~220 m.
const BUILD_DISTANCE := 150.0
const PARK_DISTANCE := 220.0
## "yaw" vira a frente local (+z) para a estrada (ver DesertWilds._build).
const SITES := [
	{"id": "sol_poente", "kind": "station", "center": Vector2(366, -1200), "yaw": -PI * .5, "name": "Posto Sol Poente", "marker": "fuel"},
	# Entre dois postes da linha de luz da Rua Principal (x = -812 e -768,5; DesertUtilityLines).
	{"id": "radio_tower", "kind": "tower", "center": Vector2(-790, -858), "yaw": PI, "name": "Torre de rádio", "marker": "place"},
	# Lado leste da rodovia oeste: o lado oeste tem a trilha da mina velha (DesertRelics.approach_paths).
	{"id": "scrapyard", "kind": "scrapyard", "center": Vector2(-1176, -1090), "yaw": -PI * .5, "name": "Ferro-velho do Nonato", "marker": "workshop"},
	# Meio da pista de arrancada, longe do encontro (que já tem baterias de fundo, DragOpenMeet).
	{"id": "food_truck", "kind": "food_truck", "center": Vector2(-480, -1290), "yaw": PI, "name": "Lanche da Reta", "marker": "food"},
	# Fase 2 (20/10): o mapa de ocupação de 20/10 (evidence/deserto-ocupacao-20261020.svg) mostrou a
	# Estrada do Sal com ~800 m sem nada dos dois lados. "radius" é a área que o enfeite respeita
	# (padrão SITE_RADIUS). Posições conferidas com DesertRegion._decoration_clear (test_desert_roadside_session):
	# a salina fica a leste da mina (MiningLayout.BOUNDS termina em x -26), o motel a oeste do acesso ao
	# cânion (x -860 ± 40, DesertTerrainRelief.passage_clear) e a balança longe da Galeria da Rodovia
	# (-640, -1527) e da entrega do assalto (-650, -1510).
	{"id": "salt_works", "kind": "salt_works", "center": Vector2(100, -1600), "yaw": 0.0, "name": "Salinas Estrada do Sal", "marker": "place", "radius": 62.0},
	{"id": "weigh_station", "kind": "weigh_station", "center": Vector2(-750, -1512), "yaw": PI, "name": "Balança rodoviária", "marker": "place", "radius": 22.0},
	{"id": "motel", "kind": "motel", "center": Vector2(-1100, -1567), "yaw": 0.0, "name": "Motel Oásis", "marker": "place", "radius": 26.0},
	# Fase 3 (20/10): capela na beira da Estrada do Sal e arquibancada no lado sul da reta, de frente
	# para a pista (fora da reserva de 55 m da arrancada).
	{"id": "chapel", "kind": "chapel", "center": Vector2(-350, -1516), "yaw": PI, "name": "Capela de Nossa Senhora da Estrada", "marker": "place", "radius": 14.0},
	{"id": "grandstand", "kind": "grandstand", "center": Vector2(-300, -1282), "yaw": PI, "name": "Arquibancada da reta", "marker": "place", "radius": 24.0},
]
## Acabamento dos lugares antigos (20/10): cidade, casas, vila e pátio da oficina. Mesmo coordenador
## (monta perto, estaciona longe), sem marcador no mapa; âncora com giro 0 (ponto local = mundo − âncora).
## "build"/"park": a rua tem 320 m, então monta antes de o jogador chegar ao meio dela.
const DRESSINGS := [
	# "clear": retângulos locais (x, z) onde o enfeite do deserto (pedra, moita) não nasce: piso novo.
	{"id": "town_street", "kind": "town_street", "center": Vector2(-200, -880), "yaw": 0.0, "build": 230.0, "park": 300.0,
		"clear": [Rect2(-86, 7.4, 102, 10.4), Rect2(-160, 4.4, 320, 3.4), Rect2(-160, -7.6, 320, 3.4)]},
	{"id": "homes_yards", "kind": "homes_yards", "center": Vector2(-242, -1048), "yaw": 0.0, "build": 170.0, "park": 240.0},
	{"id": "village_square", "kind": "village_square", "center": Vector2(-528, -822), "yaw": 0.0,
		"clear": [Rect2(-8, -15, 16, 16), Rect2(-2, -19, 4, 3), Rect2(2.5, -21, 4, 6)]},
	{"id": "workshop_yard", "kind": "workshop_yard", "center": Vector2(-140, -955), "yaw": 0.0,
		"clear": [Rect2(-21.5, -8, 9, 18), Rect2(12.5, -8, 9, 18)]},
]

static func all_sites() -> Array:
	return SITES + DRESSINGS

## Trechos (início, fim) no eixo da pista que seguem vazios depois dos lugares acima.
const EVENT_STRETCHES := [
	{"id": "route66_north", "a": Vector2(342.5, -900), "b": Vector2(342.5, -1080)},
	{"id": "route66_south", "a": Vector2(342.5, -1320), "b": Vector2(342.5, -1500)},
	{"id": "main_east", "a": Vector2(300, -880), "b": Vector2(-60, -880)},
	# Entre o Motel Oásis (x -1100) e o acesso ao cânion: evento não nasce na frente do lugar.
	{"id": "salt_west", "a": Vector2(-1060, -1540), "b": Vector2(-920, -1540)},
	# Termina antes da capela (x -350).
	{"id": "salt_middle", "a": Vector2(-520, -1540), "b": Vector2(-400, -1540)},
	# A salina (x 40..160 na beira) divide o trecho leste em dois.
	{"id": "salt_east", "a": Vector2(-70, -1540), "b": Vector2(30, -1540)},
	{"id": "salt_far_east", "a": Vector2(170, -1540), "b": Vector2(290, -1540)},
]
## Pontos de interação, em coordenadas locais do lugar.
const SOL_SERVICE := Vector3(8.5, 0, 3.5)
const SOL_PAYPHONE := Vector3(-6.2, 0, 1.0)
const SOL_MECHANIC := Vector3(8.5, 0, -0.6)
const TOWER_LADDER := Vector3(0, 0, 3.4)
const SCRAP_BAY := Vector3(0, 0, 3.0)
## Nonato fica na frente do escritório (a caixa sólida vai de z -6 a -2) e a Dona Cida ao lado
## do balcão, fora da carroceria (sólida de z -1,2 a 1,2): ator dentro de caixa sólida é expulso.
const SCRAP_DEALER := Vector3(8.5, 0, -0.9)
const FOOD_COUNTER := Vector3(0, 0, 2.6)
const FOOD_VENDOR := Vector3(-2.4, 0, 1.9)
## Moradores da Estrada do Sal: fora das caixas sólidas (mesa, bancada, balcão).
const SALT_FOREMAN := Vector3(14.4, 0, 28.6)
const WEIGH_INSPECTOR := Vector3(.7, 0, 3.6)
const MOTEL_CLERK := Vector3(11.1, 0, -3.6)
const CHAPEL_KEEPER := Vector3(2.6, 0, 3.4)
const TIMEKEEPER := Vector3(18.3, 0, 3.0)
## Veículos de verdade da frota estacionados nos lugares (não carcaças): [modelo, ponto local, giro
## local]. Pintura, vidro, rodas e faróis do modelo, e dá para levar. A frente do carro é -z local.
const PARKED := {
	"salt_works": [["desert_faisca", Vector3(19.5, 0, 36.0), PI * .5]],
	"weigh_station": [["cargo_flatbed_truck", Vector3(-6.5, 0, 12.0), PI * .5]],
	"motel": [["desert_bison", Vector3(-12.6, 0, 8.6), 0.05], ["desert_coyote", Vector3(-5.8, 0, 8.8), -.04], ["desert_mirage", Vector3(1.0, 0, 8.7), .02]],
	"grandstand": [["desert_siroco", Vector3(-6.0, 0, -7.5), PI * .5], ["desert_faisca", Vector3(4.0, 0, -7.6), PI * .5]],
	"town_street": [["desert_coyote", Vector3(-64.5, 0, 10.9), PI], ["desert_bison", Vector3(-58.5, 0, 10.9), PI], ["desert_mirage", Vector3(-25.5, 0, 10.9), PI]],
	"homes_yards": [["desert_siroco", Vector3(-25.0, 0, 26.5), 0.0], ["desert_faisca", Vector3(-25.0, 0, -10.5), 0.0]],
	"workshop_yard": [["desert_coyote", Vector3(17.0, 0, 3.5), PI * .5], ["desert_mirage", Vector3(17.0, 0, -1.2), PI * .5]],
}
## Repõe o carro que o controlador recolheu (> 145 m) só nesta faixa: longe da tela, perto o
## bastante para estar lá quando o jogador chegar.
const PARKED_SPAWN_MIN := 60.0
const PARKED_SPAWN_MAX := 140.0
## Entregas do orelhão do Sol Poente: destino, tempo e pagamento (valores em EconomyBalance).
const COURIER_ROUTES := [
	{"id": "miragem", "name": "Miragem", "point": Vector3(285, 0, -750), "seconds": 140.0},
	{"id": "arrancada", "name": "encontro da arrancada", "point": Vector3(-915, 0, -1304), "seconds": 230.0},
]

static var _enabled := -1

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_DESERT_ROADSIDE") == "0" else 1
	return _enabled == 1

static func site(id: String) -> Dictionary:
	for candidate in SITES:
		if candidate.id == id: return candidate
	return {}

## Posição no mundo de um ponto local do lugar.
static func at(definition: Dictionary, local: Vector3, ground_height := 0.0) -> Vector3:
	var basis := Basis(Vector3.UP, float(definition.yaw))
	var center: Vector2 = definition.center
	return Vector3(center.x, ground_height, center.y) + basis * local

## Usado por DesertWilds.reserved → DesertRegion._decoration_clear (sem cacto dentro do posto).
static func reserved(point: Vector2, radius := 0.0) -> bool:
	if not enabled(): return false
	for candidate in SITES:
		if (candidate.center as Vector2).distance_to(point) < float(candidate.get("radius", SITE_RADIUS)) + radius: return true
	for dressing in DRESSINGS:
		var local: Vector2 = point - (dressing.center as Vector2)
		for rect: Rect2 in _dressing_clear(dressing):
			if rect.grow(radius).has_point(local): return true
	return false

## Quintais das casas: um retângulo atrás de cada uma (RoadsideTown.compose_homes_yards).
static var _homes_clear: Array = []
static func _dressing_clear(dressing: Dictionary) -> Array:
	if str(dressing.kind) != "homes_yards": return dressing.get("clear", [])
	if _homes_clear.is_empty():
		var anchor: Vector2 = dressing.center
		for i in 10:
			var home := Vector2(-300.0 + float(i % 5) * 29.0, -1030.0 - float(floori(i / 5.0)) * 37.0) - anchor
			var half := (14.0 + float(i % 3) * 2.0) * .5 + .6
			_homes_clear.append(Rect2(home.x - half, home.y - 5.5 - 7.4, half * 2.0, 7.4))
	return _homes_clear

## Ponto do trecho vazio ~`ahead` metros à frente de quem dirige pela estrada do trecho, ou {} se
## o jogador não está nessa estrada, não anda ao longo dela ou o ponto cairia fora do trecho.
## O jogador pode estar antes do trecho (na mesma reta): com a exigência antiga de já estar
## dentro dele, os trechos de 180 m nunca tinham um ponto 240 m à frente, e a Route 66 inteira
## ficava sem evento (A/B em release de 19/10). Puro: o teste de contrato usa sem mundo.
static func event_point(position: Vector2, heading: Vector2, ahead := 240.0, max_offset := 14.0) -> Dictionary:
	if heading.length() < .01: return {}
	for stretch in EVENT_STRETCHES:
		var a: Vector2 = stretch.a
		var b: Vector2 = stretch.b
		var along := b - a
		var length := along.length()
		var direction := along / length
		# Distância lateral à reta do trecho; quem cruza a estrada de lado não conta.
		if absf((position - a).cross(direction)) > max_offset: continue
		var travel := heading.normalized().dot(direction)
		if absf(travel) < .8: continue
		var sign := 1.0 if travel > 0.0 else -1.0
		var target_t := ((position - a).dot(direction) + sign * ahead) / length
		# Só no miolo do trecho: nada nasce colado num lugar ou num cruzamento.
		if target_t < .06 or target_t > .94: continue
		return {"stretch": str(stretch.id), "point": a + along * target_t, "direction": direction * sign}
	return {}
