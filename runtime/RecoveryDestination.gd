extends RefCounted
## Para onde Dante volta depois de morrer ou ser preso. Função pura (sem árvore nem física) para o
## teste poder perguntar "morreu aqui, acorda onde?" sem carregar o mundo.
##
## Antes (até 31/10) só o Harbor tinha destino próprio; serra e deserto caíam no spawn_position da
## região, e os dois ficam em cima de conexão: o da serra no tabuleiro da ponte unificada (logo a
## leste da emenda, x≈472) e o do deserto na cabeça da ponte norte (DesertLayout.BRIDGE_END). Quem
## morria na serra, no túnel ou na metade leste da ponte acordava na ponte (relato do dono, 31/10).
##
## Regra:
##   - morte: hospital da região. Harbor: Bay Medical. Serra e deserto não têm hospital nem clínica
##     no catálogo; a serra usa o Abrigo dos Lenhadores (abrigo com gente, longe da ponte) e o
##     deserto o pátio do posto Miragem (único ponto de serviço da cidade, longe da cabeça da ponte).
##   - prisão: delegacia. Harbor: Harbor Patrol. Serra: Posto Florestal (a autoridade que existe lá).
##     Deserto: não há delegacia, fica o mesmo pátio do Miragem.
##   - ponte e túnel não são região de ninguém para o resgate: decide a ponta mais próxima
##     (oeste = Harbor, leste = serra), mesmo que a região lógica diga outra coisa por causa da
##     emenda em x≈456, que fica bem mais perto da ponta do Harbor do que da boca do túnel.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")

const HARBOR_HOSPITAL := "harbor_hospital"
const HARBOR_PRECINCT := "harbor_police"
const MOUNTAIN_HOSPITAL := "lumberjack_shelter"
const MOUNTAIN_PRECINCT := "mountain_cabin_forest"
## Entre a fachada do Miragem (TRUCK_STOP+(-13,0,-30), 10 m de fundo) e a entrada da estrada (z=-498).
const DESERT_RECOVERY := DESERT.TRUCK_STOP + Vector3(-13, 0, -20)

## Faixa da ponte + túnel, das cabeças até as bocas. Meia largura folgada: o tabuleiro tem ~11 m de
## meia largura e quem cai pela borda ainda está "na ponte" para esta escolha.
const CORRIDOR_WEST_X := CONNECTION.HARBOR_CONNECTOR_X
const CORRIDOR_EAST_X := CONNECTION.TUNNEL_END_X
const CORRIDOR_HALF_WIDTH := 30.0

static func on_bridge(point: Vector3) -> bool:
	if not point.is_finite(): return false
	return point.x >= CORRIDOR_WEST_X and point.x <= CORRIDOR_EAST_X and absf(point.z - CONNECTION.CENTER_Z) <= CORRIDOR_HALF_WIDTH

## Região cujo resgate vale para quem morreu em `point`. `current_region` é o state.region_id; ponto
## infinito (morreu dentro de interior) mantém a região atual.
static func region_for(point: Vector3, current_region: String) -> String:
	if not point.is_finite(): return current_region
	if on_bridge(point):
		return "harbor" if point.x < (CORRIDOR_WEST_X + CORRIDOR_EAST_X) * 0.5 else "mountain"
	var logical := CONNECTION.logical_region(point)
	return logical if logical in ["harbor", "mountain", "desert"] else current_region

static func place_for(region_id: String, arrested: bool) -> String:
	match region_id:
		"harbor": return HARBOR_PRECINCT if arrested else HARBOR_HOSPITAL
		"mountain": return MOUNTAIN_PRECINCT if arrested else MOUNTAIN_HOSPITAL
	return ""

## {region, place_id, position}. position sem a folga vertical; o deserto vem com y=0 e quem chama
## acerta a altura pelo chão da região (o relevo do deserto não é plano).
static func choose(point: Vector3, current_region: String, arrested: bool) -> Dictionary:
	return for_region(region_for(point, current_region), arrested)

static func for_region(region_id: String, arrested: bool) -> Dictionary:
	if region_id == "desert": return {"region": "desert", "place_id": "", "position": DESERT_RECOVERY}
	var place_id := place_for(region_id, arrested)
	var definition: Dictionary = PLACES.get_definition(place_id)
	if definition.is_empty(): return {"region": region_id, "place_id": "", "position": Vector3.INF}
	return {"region": region_id, "place_id": place_id, "position": definition.return_position}
