extends SceneTree
## Exporta a geografia preparada do mapa do jogo (terra, estradas, prédios, marcadores e limites das
## regiões) num JSON, para protótipos fora do Godot (maquete 3D do mapa da tecla M, 26/10). Mesmo
## caminho da captura do mapa-múndi: monta Harbor, serra e deserto só como dados, sem Main.
## Uso: "$GODOT" --headless --path . --script res://tests/tools/export_world_map_data.gd -- --no-save
const DATA := preload("res://ui/hud/WorldMapData.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const STATE := preload("res://runtime/GameState.gd")

class Production extends RefCounted:
	var regions := {}
	var _region_cache := {}

class World extends Node3D:
	var production := Production.new()
	var maciota_place: Node3D
	var player: Node3D

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): print("EXPORT_MAP timeout"); quit(3))
	run.call_deferred()

## Douglas-Peucker: estradas com centenas de pontos viram poucos, com erro de até `tolerance` metros.
static func simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3: return points
	var first := points[0]
	var last := points[points.size() - 1]
	var worst := -1.0
	var index := 0
	for i in range(1, points.size() - 1):
		var d := points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], first, last))
		if d > worst:
			worst = d
			index = i
	if worst <= tolerance: return PackedVector2Array([first, last])
	var left := simplify(points.slice(0, index + 1), tolerance)
	var right := simplify(points.slice(index), tolerance)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left

static func flat(points: PackedVector2Array) -> Array:
	var out := []
	for p in points: out.append_array([snappedf(p.x, .1), snappedf(p.y, .1)])
	return out

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): print("EXPORT_MAP --no-save obrigatório"); quit(2); return
	var world := World.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var state := STATE.new()
	# Campanha concluída: a passagem norte aberta, como no mapa de quem já chegou ao deserto.
	if not state.restore_snapshot(FIXTURE.full_snapshot(Vector3(80, .12, 80), true)): print("EXPORT_MAP estado inválido"); quit(1); return
	for id: String in ["harbor", "mountain", "desert"]:
		var region = EDITABLE.build_region(id)
		region.prepare_data()
		world.production._region_cache[id] = region
	var atlas := DATA.new()
	atlas.collect({"state": state, "world": world, "region": world.production._region_cache.harbor}, false)
	var out := {"bounds": [atlas.bounds.position.x, atlas.bounds.position.y, atlas.bounds.size.x, atlas.bounds.size.y], "regions": {}, "lands": [], "roads": [], "buildings": [], "markers": []}
	for id in atlas.region_bounds:
		var r: Rect2 = atlas.region_bounds[id]
		out.regions[id] = [r.position.x, r.position.y, r.size.x, r.size.y]
	for land in atlas.lands: out.lands.append({"biome": land.biome, "points": flat(simplify(land.polygon, 1.5) if land.polygon.size() > 40 else land.polygon)})
	for road in atlas.roads: out.roads.append({"id": road.id, "region": road.region, "surface": road.surface, "width": road.width, "points": flat(simplify(road.points, 1.2))})
	for building in atlas.buildings: out.buildings.append(flat(building))
	for marker in atlas.markers: out.markers.append({"id": marker.id, "title": marker.title, "kind": marker.kind, "region": marker.region, "x": snappedf(marker.point.x, .1), "z": snappedf(marker.point.y, .1)})
	var folder := ProjectSettings.globalize_path("res://evidence/map3d-data")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("world.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	print("EXPORT_MAP terras=%d estradas=%d prédios=%d marcadores=%d -> %s" % [out.lands.size(), out.roads.size(), out.buildings.size(), out.markers.size(), folder])
	quit(0)
