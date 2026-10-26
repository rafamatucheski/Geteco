extends RefCounted
## O que a torre de rádio pode apontar: cavernas do DesertWilds, relíquias da expansão e a casa e
## a cabana abandonadas, só enquanto não foram achadas. Antes esse conteúdo ficava escondido longe
## das estradas e quase ninguém chegava nele (revisão de 18/10); do alto da torre ele vira marcador.
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const DISCOVERY := preload("res://runtime/desert/expansion/DesertDiscoveryState.gd")
const SECRET := preload("res://runtime/desert/DesertSecretState.gd")
const ABANDONED := preload("res://world/desert/DesertAbandonedSite.gd")
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const RELIC_NAMES := {"desert_relic_station": "Estação abandonada", "desert_relic_mine": "Mina velha",
	"desert_relic_wagon": "Carroça tombada", "desert_relic_wreck": "Destroços"}

## Todos os achados que ainda faltam: {id, name, point}.
static func missing(world_state: Dictionary, economy) -> Array:
	var result := []
	for site in WILDS.SITES:
		if str(site.kind) != "cave" or WILDS.cave_claimed(economy, site): continue
		# A caverna do Coyote só aparece pela décima carta de Vicente, nunca pela torre.
		var secret := bool(site.get("secret", false))
		if secret and not preload("res://data/catalogs/VicenteLetters.gd").complete(economy._data.get("collectibles", [])): continue
		var center: Vector2 = site.center
		result.append({"id": "cave:" + str(site.id), "name": "Caverna do Vicente" if secret else str(site.get("title", "Caverna")), "point": Vector3(center.x, 0, center.y)})
	for relic in RELICS.secrets():
		var id := str(relic.id)
		if DISCOVERY.collected(world_state, id): continue
		result.append({"id": "relic:" + id, "name": str(RELIC_NAMES.get(id, "Ruína")), "point": relic.position})
	for definition in ABANDONED.definitions():
		var id := str(definition.id)
		if SECRET.collected(world_state, id): continue
		result.append({"id": "secret:" + id, "name": "Casa abandonada" if id == SECRET.HOUSE_ID else "Cabana abandonada", "point": definition.position})
	return result

## Os `count` achados que faltam mais perto de `origin`, sem os ids de `exclude`.
static func nearest(world_state: Dictionary, economy, origin: Vector3, count := 3, exclude: Array = []) -> Array:
	var candidates := missing(world_state, economy).filter(func(entry): return not exclude.has(entry.id))
	candidates.sort_custom(func(a, b): return Vector2(a.point.x, a.point.z).distance_to(Vector2(origin.x, origin.z)) < Vector2(b.point.x, b.point.z).distance_to(Vector2(origin.x, origin.z)))
	return candidates.slice(0, count)

## Marcadores do mapa: revelados pela torre e ainda não achados.
static func revealed_markers(world_state: Dictionary, economy, revealed: Array) -> Array:
	var result := []
	for entry in missing(world_state, economy):
		if revealed.has(entry.id): result.append(entry)
	return result

## Marcadores do mapa (WorldMapData): os lugares da beira de estrada e o que a torre revelou e
## ainda não foi achado. {id, title, point, kind, detail}.
static func map_markers(world_state: Dictionary, economy) -> Array:
	if not LAYOUT.enabled(): return []
	var result := []
	for definition in LAYOUT.SITES:
		var center: Vector2 = definition.center
		result.append({"id": "roadside_" + str(definition.id), "title": str(definition.name), "point": Vector3(center.x, 0, center.y), "kind": str(definition.marker), "detail": ""})
	for entry in revealed_markers(world_state, economy, STATE.data(world_state).revealed):
		result.append({"id": "roadside_seen_" + str(entry.id), "title": str(entry.name), "point": entry.point, "kind": "place", "detail": "Avistado da torre de rádio."})
	return result
