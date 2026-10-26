extends SceneTree
## Costa curva de Harbor (etapa 3 do mundo orgânico, 26/10/2026), bairro por bairro: o chão natural de
## HarborCoast fica dentro da ilha da forma e da zona do bairro, entra na terra de Harbor (chão com colisão,
## mar sem água por cima, muro só na costa nova) e não deixa água presa entre a costa nova e a terra de antes.
## Monta Harbor só como dados, sem Main.
## Uso: "$GODOT" --headless --path . --script res://tests/test_harbor_coast.gd -- --no-save
const COAST := preload("res://world/shape/HarborCoast.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const CELL := 64.0
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> bool:
	checks += 1
	print("HARBOR_COAST ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	check(COAST.enabled(), "costa curva ligada (GETECO_HARBOR_COAST)")
	var natural := COAST.natural_land()
	check(not natural.is_empty(), "bairros prontos têm chão natural (%d pedaços)" % natural.size())
	# Dentro da zona do bairro e da ilha da forma.
	var outside_zone := 0
	var outside_island := 0
	for polygon in natural:
		for point in polygon:
			if point.x > -80.0 + .01: outside_zone += 1
			if SHAPE.signed_distance(point) < -.05: outside_island += 1
	check(outside_zone == 0, "chão natural só na mata a oeste (%d pontos a leste de x = −80)" % outside_zone)
	check(outside_island == 0, "chão natural dentro da ilha da forma (%d pontos fora)" % outside_island)

	var region = EDITABLE.build_region("harbor")
	region.prepare_data()
	var land: Array[PackedVector2Array] = []
	for row in region.source_data.harbor_land: land.append(GROUND_CUT.rect_polygon(Rect2(row[0] / 16.0, row[1] / 16.0, row[2] / 16.0, row[3] / 16.0)))
	land.append_array(region.extra_land)
	check(natural.all(func(p): return region.extra_land.has(p)), "chão natural entra na terra de Harbor (extra_land)")
	# A terra nova cresce de verdade: pontos da faixa que antes eram mar.
	var band: Array[Vector2] = []
	for polygon in natural:
		var bounds := GROUND_CUT.bounds(polygon)
		var x := bounds.position.x
		while x < bounds.end.x:
			var z := bounds.position.y
			while z < bounds.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, polygon) and SHAPE.signed_distance(p) > 3.0 and not _on(p, land.slice(0, land.size() - natural.size())): band.append(p)
				z += 8.0
			x += 8.0
	check(band.size() > 200, "faixa nova de terra entre os retângulos e a costa (%d amostras de 8 m)" % band.size())
	var walled := 0
	for p in band:
		if region.coastal_protection.on_land(p) == false: walled += 1
	check(walled == 0, "muro da costa trata a faixa como terra (%d pontos fora)" % walled)
	# Chão com colisão e sem água por cima nas células da faixa.
	var wet := 0
	var bare := 0
	var cells := {}
	for p in band: cells[Vector2i(floori(p.x / CELL), floori(p.y / CELL))] = true
	for key: Vector2i in cells:
		var chunk := Node3D.new()
		root.add_child(chunk)
		region._build_surfaces(chunk, Rect2(Vector2(key) * CELL, Vector2.ONE * CELL), key)
		var floor_faces := 0
		for body in chunk.find_children("*", "StaticBody3D", true, false): floor_faces += 1
		if floor_faces == 0: bare += 1
		for water in chunk.find_children("Water", "MeshInstance3D", true, false):
			var vertices: PackedVector3Array = (water as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = (water as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for p in band:
				if Vector2i(floori(p.x / CELL), floori(p.y / CELL)) != key: continue
				for i in range(0, indices.size(), 3):
					var a := vertices[indices[i]]
					var b := vertices[indices[i + 1]]
					var c := vertices[indices[i + 2]]
					if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)): wet += 1; break
		chunk.free()
	check(bare == 0, "toda célula da faixa tem chão com colisão (%d sem)" % bare)
	check(wet == 0, "mar de Harbor não passa por cima da faixa (%d pontos com água)" % wet)
	# Sem água presa: dentro da zona do bairro, a água encostada na costa nova é o mar da forma. A leste
	# da zona (bairros ainda sem costa curva) a terra da forma continua sendo água no jogo, de propósito.
	var trapped := 0
	var stub := 0
	for polygon in natural:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var normal := (b - a).normalized().orthogonal()
			var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
			for s in steps:
				var p := a.lerp(b, (s + .5) / steps)
				for side in [normal, -normal]:
					var probe: Vector2 = p + side * 1.5
					if _on(probe, land): continue
					if probe.x > -80.0:
						# Só conta o corte novo: onde do outro lado é terra que não existia antes.
						if not _on(p - side * 1.5, land.slice(0, land.size() - natural.size())): stub += 1
						continue
					if SHAPE.is_land(probe) and SHAPE.signed_distance(probe) > 1.5: trapped += 1
	check(trapped == 0, "costa nova encosta no mar de verdade, sem água presa na terra da forma (%d pontos)" % trapped)
	print("HARBOR_COAST corte na divisa com os bairros sem costa curva: %d m" % (stub * 2))
	# Mata da faixa nova: árvores fora da terra de antes e longe da costa (o muro fica na beira).
	var woods := preload("res://world/shape/HarborCoastWoodland.gd")
	var old_land := land.slice(0, land.size() - natural.size())
	var misplaced := 0
	var total := 0
	for key: Vector2i in woods._cells:
		for tree in woods._cells[key].trees:
			total += 1
			var p := Vector2(tree.point.x, tree.point.z)
			if _on(p, old_land) or SHAPE.signed_distance(p) < 6.0: misplaced += 1
	check(total > 100 and misplaced == 0, "mata na faixa nova: %d árvores, %d em terra antiga ou na beira" % [total, misplaced])
	region.free()
	print("HARBOR_COAST checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

static func _on(point: Vector2, polygons: Array) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon): return true
	return false
