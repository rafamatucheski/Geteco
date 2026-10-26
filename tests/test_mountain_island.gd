extends SceneTree
## Serra ilha (etapa 4 do mundo orgânico, 26/10/2026): terreno desce para o mar fora da costa, células mar
## adentro sem terreno, muro de pedra com colisão acompanhando a costa e aberto na ponte leste, nenhuma
## árvore na encosta da costa. Monta a serra só como dados, sem Main.
## Uso: "$GODOT" --headless --path . --script res://tests/test_mountain_island.gd
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const BOUNDARY := preload("res://world/regions/ScenarioBoundary3D.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const CELL := 64.0
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> bool:
	checks += 1
	print("MOUNTAIN_ISLAND ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	check(TERRAIN.island_enabled(), "serra ilha ligada (GETECO_MOUNTAIN_ISLAND)")
	var region = EDITABLE.build_region("mountain")
	region.prepare_data()
	var terrain = region.terrain
	# Ponto de mar no canal até o deserto e ponto do interior da serra.
	var sea := Vector2(470, -700)
	while SHAPE.is_land(sea) and sea.x < 560: sea.x += 2.0
	sea.x += 15.0
	check(not SHAPE.is_land(sea) and terrain.height_at(sea) < -2.0, "terreno abaixo da água no canal %s (%.1f m)" % [sea, terrain.height_at(sea)])
	var inland := Vector2(650, -500)
	check(terrain.height_at(inland) > -0.5, "terreno normal no interior (%.1f m)" % terrain.height_at(inland))
	# Células mar adentro sem terreno; a do interior com terreno.
	var far := Vector2i(floori(1400.0 / CELL), floori(-1500.0 / CELL))
	var home := Vector2i(floori(650.0 / CELL), floori(-500.0 / CELL))
	check(not region._mountain_owns_terrain(far) and region._mountain_owns_terrain(home), "terreno só perto da ilha (mar adentro: não; interior: sim)")
	# Muro: célula com costa tem pedra com colisão.
	var line := BOUNDARY.mountain_coast_line()
	check(line.size() > 10, "contorno do muro da serra (%d pontos)" % line.size())
	var blocked := func(point: Vector2) -> bool: return region.route_geometry.contains(Vector3(point.x, 0, point.y), 8.0)
	var walls := 0
	var near_road := 0
	var cells_with_wall := 0
	for point in line:
		var key := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
		var parent := Node3D.new()
		BOUNDARY.build_mountain(parent, Rect2(Vector2(key) * CELL, Vector2.ONE * CELL), terrain.surface_height_at, blocked)
		var ridges := parent.find_children("ScenarioBoundaryRidge", "MeshInstance3D", true, false)
		if not ridges.is_empty():
			cells_with_wall += 1
			if not ridges[0].find_children("*", "StaticBody3D", true, false).is_empty(): walls += 1
			var vertices: PackedVector3Array = ridges[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in vertices:
				if v.y > terrain.surface_height_at(Vector2(v.x, v.z)) and region.route_geometry.contains(Vector3(v.x, 0, v.z), 1.0): near_road += 1
		parent.free()
	check(cells_with_wall > 0 and walls == cells_with_wall, "muro com colisão nas células da costa (%d/%d)" % [walls, cells_with_wall])
	check(near_road == 0, "muro não cobre estrada nem trilha (%d vértices em cima de via)" % near_road)
	# Abertura na ponte leste: nenhum pedaço de muro no ponto onde a pista da serra cruza a costa.
	var landing := Vector2.ZERO
	for road in region.map_routes():
		if str(road.get("id", "")) != "mountain_pass": continue
		var points: PackedVector3Array = road.points
		for i in points.size() - 1:
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			if SHAPE.is_land(a) != SHAPE.is_land(b): landing = (a + b) * .5
	var gap_parent := Node3D.new()
	var landing_key := Vector2i(floori(landing.x / CELL), floori(landing.y / CELL))
	BOUNDARY.build_mountain(gap_parent, Rect2(Vector2(landing_key) * CELL, Vector2.ONE * CELL), terrain.surface_height_at, blocked)
	var blocking := 0
	for ridge in gap_parent.find_children("ScenarioBoundaryRidge", "MeshInstance3D", true, false):
		for v in ridge.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if Vector2(v.x, v.z).distance_to(landing) < 6.0: blocking += 1
	gap_parent.free()
	check(landing != Vector2.ZERO and blocking == 0, "muro aberto onde a ponte leste chega %s" % landing)
	# Árvores fora da encosta da costa.
	var wet_trees := 0
	for records in region.records.values():
		for record in records:
			# Células da ponte leste e árvores movidas no editor de mundo ficam fora: lá vale a escolha feita à mão.
			if record.kind != "tree" or region._cell(record.position) in region.MOUNTAIN_BRIDGE_VOID_CELLS or record.has("editor_id"): continue
			if SHAPE.field_distance("mountain", Vector2(record.position.x, record.position.z)) < 10.0: wet_trees += 1
	check(wet_trees == 0, "nenhuma árvore na encosta da costa (%d)" % wet_trees)
	region.free()
	print("MOUNTAIN_ISLAND checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
