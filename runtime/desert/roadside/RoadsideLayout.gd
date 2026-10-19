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
]
## Trechos (início, fim) no eixo da pista que seguem vazios depois dos lugares acima.
const EVENT_STRETCHES := [
	{"id": "route66_north", "a": Vector2(342.5, -900), "b": Vector2(342.5, -1080)},
	{"id": "route66_south", "a": Vector2(342.5, -1320), "b": Vector2(342.5, -1500)},
	{"id": "main_east", "a": Vector2(300, -880), "b": Vector2(-60, -880)},
	{"id": "salt_west", "a": Vector2(-1140, -1540), "b": Vector2(-790, -1540)},
	{"id": "salt_middle", "a": Vector2(-520, -1540), "b": Vector2(-340, -1540)},
	{"id": "salt_east", "a": Vector2(-70, -1540), "b": Vector2(290, -1540)},
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
		if (candidate.center as Vector2).distance_to(point) < SITE_RADIUS + radius: return true
	return false

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
