extends SceneTree
## Ilha do deserto (etapa 2 do mundo orgânico, 26/10/2026): as cordilheiras de horizonte cabem dentro da
## ilha. Todo vértice acima da água fica na ilha do deserto, antes da praia e fora da área jogável; a
## crista norte (horizonte da câmera da arrancada) continua alta. Não abre o jogo.
## Lado leste (27/10/2026): os trechos da borda leste do deserto não sobem nada no canal nem perto da
## costa da serra (a fileira de rochedos de 35-50 m de raio era a "montanha de areia" vista do gelo), e a
## borda baixa continua segurando quem anda ali, inteira em cada trecho.
## Uso: "$GODOT" --headless --path . --script res://tests/test_desert_island.gd
const RELIEF := preload("res://world/desert/DesertHorizonRelief.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const L := preload("res://world/desert/DesertLayout.gd")
const DESERT := preload("res://world/desert/DesertRegion.gd")
const BOUNDARY := preload("res://world/regions/ScenarioBoundary3D.gd")
## A parede das fileiras se desloca alguns metros além do pé calculado; a praia tem 18 m.
const BEACH_TOLERANCE := 10.0
## Borda baixa: 1,1 m de pedra mais o relevo do chão do deserto na beira.
const EAST_LOW_HEIGHT := 1.6
## Nada do deserto a menos disto da costa da serra (o canal tem 43 m no ponto mais estreito).
const MOUNTAIN_CLEARANCE := 15.0
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> bool:
	checks += 1
	print("DESERT_ISLAND ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var relief: Node3D = RELIEF.build()
	var outside := 0
	var on_beach := 0
	var inside_play := 0
	var north_top := 0.0
	var south_top := 0.0
	var worst := Vector2.ZERO
	for mesh: MeshInstance3D in relief.get_children():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in vertices:
			if v.y < -.5: continue
			var p := Vector2(v.x, v.z)
			if SHAPE.island_at(p) != "desert": outside += 1; worst = p
			elif SHAPE.signed_distance(p) < RELIEF.BEACH - BEACH_TOLERANCE: on_beach += 1
			if L.BOUNDS.grow(-1.0).has_point(p): inside_play += 1
			if p.y < L.BOUNDS.position.y: north_top = maxf(north_top, v.y)
			if p.y > L.BOUNDS.end.y: south_top = maxf(south_top, v.y)
	check(outside == 0, "nenhum vértice das cordilheiras fora da ilha do deserto (%d fora, ex. %s)" % [outside, worst])
	check(on_beach == 0, "cordilheiras param antes da praia (%d vértices a menos de %.0f m da costa)" % [on_beach, RELIEF.BEACH - BEACH_TOLERANCE])
	check(inside_play == 0, "nenhum vértice dentro da área jogável (%d)" % inside_play)
	check(north_top > 80.0, "crista norte segue alta para o horizonte da arrancada (%.0f m)" % north_top)
	print("DESERT_ISLAND crista sul até %.0f m (o canal até Harbor fica livre)" % south_top)
	relief.free()
	await _check_east_side()
	print("DESERT_ISLAND checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func _check_east_side() -> void:
	var desert := DESERT.new()
	desert.initial_prewarm_only = true
	root.add_child(desert)
	desert.set_process(false)
	# Coluna de trechos da borda leste, de ponta a ponta do retângulo jogável.
	var x := L.BOUNDS.end.x - 8.0
	var samples: Array[float] = []
	var keys := {}
	var z := L.BOUNDS.position.y + 8.0
	while z < L.BOUNDS.end.y:
		samples.append(z)
		keys[Vector2i(floori(x / DESERT.CELL), floori(z / DESERT.CELL))] = true
		desert.prepare_collision_at(Vector3(x, 0, z))
		z += 48.0
	# Faixa além da borda leste, sem as quinas: o selo norte (rochedo da quina e paredão) é de outro lado.
	var east_band := Rect2(L.BOUNDS.end.x + 2.0, L.BOUNDS.position.y + 60.0, 400.0, L.BOUNDS.size.y - 70.0)
	var tall := 0
	var tall_top := 0.0
	var tall_at := Vector3.ZERO
	var in_sea := 0
	var sea_at := Vector3.ZERO
	var sea_owners := {}
	var near_mountain := 0
	var near_at := Vector3.ZERO
	for chunk: Node3D in desert.chunks.values():
		for mesh: MeshInstance3D in chunk.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			for surface in mesh.mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for local in vertices:
					var v: Vector3 = mesh.global_transform * local
					if v.y < -.5: continue
					var p := Vector2(v.x, v.z)
					if v.y <= EAST_LOW_HEIGHT: continue
					# Além da borda leste do retângulo jogável: praia, canal e serra.
					if east_band.has_point(p):
						tall += 1
						if v.y > tall_top: tall_top = v.y; tall_at = v
					if SHAPE.island_at(p) != "desert":
						in_sea += 1
						sea_at = v
						sea_owners[_owner_label(mesh)] = true
					if SHAPE.field_distance("mountain", p) > -MOUNTAIN_CLEARANCE:
						near_mountain += 1
						near_at = v
	var built := 0
	for key in keys:
		if desert.chunks.has(key): built += 1
	check(built == keys.size(), "trechos da borda leste montados (%d/%d)" % [built, keys.size()])
	check(tall == 0, "nada do deserto sobe além da borda leste (%d vértices acima de %.1f m, o mais alto %.0f m em %s)" % [tall, EAST_LOW_HEIGHT, tall_top, tall_at])
	check(in_sea == 0, "nada do deserto acima da água fora da ilha (%d vértices, ex. %s; %s)" % [in_sea, sea_at, ", ".join(sea_owners.keys())])
	check(near_mountain == 0, "nada do deserto a menos de %.0f m da costa da serra (%d vértices, ex. %s)" % [MOUNTAIN_CLEARANCE, near_mountain, near_at])
	# Cada trecho monta a borda inteira na sua faixa: sem depender do vizinho, não abre fresta na divisa.
	var partial := 0
	var partial_key := Vector2i.ZERO
	for key in keys:
		var chunk: Node3D = desert.chunks.get(key)
		if chunk == null: continue
		var cell := Rect2(Vector2(key) * DESERT.CELL, Vector2.ONE * DESERT.CELL).intersection(L.BOUNDS)
		var low := maxf(cell.position.y, L.BOUNDS.position.y + 1.0)
		var high := minf(cell.end.y, L.BOUNDS.end.y - BOUNDARY.INSET)
		var covered := false
		for ridge: MeshInstance3D in chunk.find_children("ScenarioBoundaryRidge", "MeshInstance3D", true, false):
			var box: AABB = ridge.global_transform * ridge.get_aabb()
			if box.position.x > L.BOUNDS.end.x - 8.0 and box.position.z <= low + .01 and box.end.z >= high - .01: covered = true
		if not covered:
			partial += 1
			partial_key = key
	check(partial == 0, "borda leste inteira em cada trecho, sem depender do vizinho (%d trechos com fresta, ex. %s)" % [partial, partial_key])
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var open := 0
	var open_at := 0.0
	for at in samples:
		var y := desert._ground_height(Vector2(x, at)) + .8
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x - 4.0, y, at), Vector3(L.BOUNDS.end.x + 6.0, y, at), 1))
		if hit.is_empty() or not hit.collider.is_in_group(BOUNDARY.GROUP): open += 1; open_at = at
	check(open == 0, "borda leste segura quem anda ali (%d de %d pontos abertos, ex. z=%.0f)" % [open, samples.size(), open_at])
	desert.free()

## Nome e posição do primeiro ancestral com nome próprio (rochedo, paredão), para a falha dizer quem é.
func _owner_label(node: Node) -> String:
	var current := node
	while current != null and current.get_parent() != null and not (current is Node3D and current.name.begins_with("Eroded")) and not current.name.begins_with("ScenarioBoundary"):
		current = current.get_parent()
	if current is Node3D: return "%s em (%.0f, %.0f)" % [current.name, (current as Node3D).global_position.x, (current as Node3D).global_position.z]
	return str(node.name)
