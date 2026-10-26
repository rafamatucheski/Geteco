extends SceneTree
## Mar do mundo orgânico (etapa 1, 26/10/2026): monta o WorldSea sozinho, sem Main, e confere onde há
## água e chão-base, a faixa rasa perto da costa, o esconde-mostra por residência e o tempo de montagem.
## Uso: "$GODOT" --headless --path . --script res://tests/test_world_sea.gd
const SEA := preload("res://world/shape/WorldSea.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const MINING := preload("res://world/mining/MiningExterior.gd")
var checks := 0
var failures: Array[String] = []

class FakeRegion extends Node3D:
	const CELL := 64.0
	var focus := Vector3.ZERO
	func set_focus(_point: Vector3, _complete := false) -> void: pass

class FakeProduction extends Node:
	var regions := {}

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): failures.append("watchdog"); finish())
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("WORLD_SEA ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

## Triângulo de alguma malha do grupo cobre o ponto? Devolve [encontrou, y, cor].
func sample(nodes: Array, at: Vector2) -> Array:
	# Fora das diagonais dos quadrados da malha (a borda de dois triângulos não conta como dentro).
	var point := at + Vector2(.37, .61)
	for node: MeshInstance3D in nodes:
		var aabb := node.get_aabb()
		if point.x < aabb.position.x or point.x > aabb.end.x or point.y < aabb.position.z or point.y > aabb.end.z: continue
		var arrays := node.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var a := Vector2(v[idx[i]].x, v[idx[i]].z)
			var b := Vector2(v[idx[i + 1]].x, v[idx[i + 1]].z)
			var d := Vector2(v[idx[i + 2]].x, v[idx[i + 2]].z)
			if Geometry2D.point_is_inside_triangle(point, a, b, d): return [true, v[idx[i]].y, c[idx[i]]]
	return [false, 0.0, Color.BLACK]

func run() -> void:
	var production := FakeProduction.new()
	root.add_child(production)
	var sea := SEA.new()
	sea.configure(production)
	root.add_child(sea)
	sea.set_process(false)
	await sea.build_sliced(self)
	print("WORLD_SEA montagem %.0f ms, %d blocos de chão-base, %d malhas" % [sea.build_usec / 1000.0, sea.base_tiles.size(), sea.get_child_count()])
	check(sea.build_usec < 6000000, "monta em menos de 6 s (%.0f ms, fatiado sob a cortina)" % (sea.build_usec / 1000.0))
	var water: Array = sea.get_children().filter(func(n): return n.name.begins_with("Water"))
	var base: Array = sea.base_tiles.values()
	# Água: canais, mar aberto e longe; nada dentro das ilhas nem da terra de Harbor. O ponto do canal
	# entre o deserto e a serra sai da própria forma (primeiro mar na linha z = −560).
	var strait := Vector2(440, -560)
	while SHAPE.is_land(strait) and strait.x < 520: strait.x += 2.0
	check(not SHAPE.is_land(strait), "canal deserto–serra achado em %s" % strait)
	for point in [strait + Vector2(2, 0), Vector2(600, -150), Vector2(-1900, -500), Vector2(2500, 2500), Vector2(-6000, 6000)]:
		check(sample(water, point)[0], "água em %s" % point)
	for point in [Vector2(-450, -800), Vector2(650, -500), Vector2(100, 60), Vector2(-1450, -1300)]:
		check(not sample(water, point)[0], "sem água em terra %s (%s)" % [point, SHAPE.island_at(point)])
	# Faixa rasa: a água perto da costa é mais clara (COLOR.r = distância até a margem / 24 m).
	var near := sample(water, strait + Vector2(2, 0))
	var far := sample(water, Vector2(-6000, 6000))
	check(near[0] and far[0] and float(near[2].r) < float(far[2].r), "água do canal mais rasa que o mar aberto (%.2f < %.2f)" % [near[2].r, far[2].r])
	check(far[0] and absf(float(far[1]) - (-0.94 - 0.2)) < .01, "água 0,2 m abaixo da água de Harbor (%.2f)" % far[1])
	# Chão-base: faixa nova do deserto (fora da área jogável), serra e Harbor; nunca sobre a cava.
	var ring := Vector2(DESERT.BOUNDS.position.x - 120, DESERT.BOUNDS.get_center().y)
	var ring_meshes: Array = sea.get_children().filter(func(n): return n.name.begins_with("Ring"))
	check(SHAPE.island_at(ring) == "desert" and sample(ring_meshes, ring)[0], "chão-base na faixa nova do deserto %s" % ring)
	check(sample(base, Vector2(650, -500))[0], "chão-base na serra")
	check(sample(base, Vector2(100, 60))[0], "chão-base em Harbor")
	# Cava e lagos: fundo rebaixado ou água parada, não buraco (de longe aparecia retângulo preto).
	var pit := sample(base, MINING.OWNED_GROUND.get_center())
	check(pit[0] and float(pit[1]) < -28.045, "cava da mineração com fundo rebaixado, abaixo do chão distante da cava (%.1f)" % pit[1])
	# Residência: com uma região focada em Harbor, o chão-base some no quadrado de 3 × 3 células.
	var region := FakeRegion.new()
	region.focus = Vector3(100, 0, 60)
	root.add_child(region)
	production.regions = {"harbor": region}
	sea.refresh_residency()
	var hidden := sea.base_tiles.values().filter(func(t): return not t.visible).size()
	var key := Vector2i(floori(100.0 / SEA.BLOCK), floori(60.0 / SEA.BLOCK))
	check(hidden > 0 and sea.base_tiles.has(key) and not sea.base_tiles[key].visible, "chão-base escondido onde a região montou chão (%d blocos)" % hidden)
	# Faixa nova do deserto (fora do retângulo jogável) não tem chão de região: fica à vista mesmo com o
	# deserto montado ali perto.
	var rings: Array = sea.get_children().filter(func(n): return n.name.begins_with("Ring"))
	region.focus = Vector3(ring.x + 60.0, 0, ring.y)
	sea.refresh_residency()
	var ring_hit := false
	for mesh in rings:
		if sample([mesh], ring)[0]: ring_hit = mesh.visible
	check(ring_hit, "faixa nova do deserto continua à vista com o deserto montado perto")
	region.focus = Vector3(-6000, 0, 6000)
	sea.refresh_residency()
	check(sea.base_tiles.values().all(func(t): return t.visible), "chão-base volta quando o jogador se afasta")
	finish()

func finish() -> void:
	print("WORLD_SEA checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
