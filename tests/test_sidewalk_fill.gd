extends SceneTree
## SidewalkFill: toda peça nova tem malha montável, as em camadas usam as superfícies de
## flora já existentes (sem shader novo), e cada peça do térreo é quebrável e editável.
## Não cobre o posicionamento na cidade: isso é visto em capture_sidewalk_fill.gd.

const FILL := preload("res://world/city_look/SidewalkFill.gd")
const FILL_KIT := preload("res://world/city_look/SidewalkFillKit.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const PLACEMENTS := preload("res://world/editing/WorldPlacements.gd")

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition: print("ok   ", label)
	else:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	var kinds: Array = FILL.TREE_KINDS + FILL.FRONTAGE_KINDS
	# No jogo as superfícies de flora e o vaso do CityLook já existem quando o chunk monta.
	for layer in ["stone", "leaves", "bark"]: KIT.layer_material(layer)
	# A primeira malha do kit paga ~20 ms de partida (medido 17/10), seja qual for o tipo; no jogo
	# é o hidrante ou a lixeira quem paga, bem antes destas peças.
	KIT.mesh("planter")
	KIT.mesh("hydrant")
	var slowest := 0.0
	for kind: String in kinds:
		var began := Time.get_ticks_usec()
		KIT.mesh(kind)
		var kind_ms := float(Time.get_ticks_usec() - began) / 1000.0
		slowest = maxf(slowest, kind_ms)
		print("montagem de %s: %.2f ms" % [kind, kind_ms])
	# Montadas na primeira aparição (como as demais peças do kit), cada uma no passo do chunk
	# onde aparece primeiro. A árvore é a mais cara: ~7 ms neste build de debug (17/10).
	check(slowest < 10.0, "malha nova mais lenta: %.1f ms" % slowest)
	for kind: String in kinds:
		var mesh := KIT.mesh(kind)
		var triangles := 0
		for surface in mesh.get_surface_count():
			triangles += mesh.surface_get_array_len(surface) / 3
		var expected := 2 if KIT.LAYERED.has(kind) else 1
		check(mesh.get_surface_count() == expected and triangles > 20, "%s: %d superfície(s), %d triângulos" % [kind, mesh.get_surface_count(), triangles])
		# Árvore com 3-4 copas de 280 triângulos: acima de ~1500 o lote do chunk pesaria.
		check(triangles < 1600, "%s abaixo de 1600 triângulos" % kind)
		var aabb := mesh.get_aabb()
		check(aabb.position.y > -0.05, "%s apoia no chão (y mínimo %.2f)" % [kind, aabb.position.y])
	# Superfícies de flora: mesmos parâmetros de shader do vaso do CityLook.
	var stone := KIT.layer_material("stone")
	var bark := KIT.layer_material("bark")
	check(bark.vertex_color_is_srgb == stone.vertex_color_is_srgb and bark.vertex_color_use_as_albedo == stone.vertex_color_use_as_albedo, "casca usa as mesmas opções de shader do vaso")
	for kind: String in FILL.FRONTAGE_KINDS:
		check(kind in DRESSING.FRAGILE_KINDS and FRAGILE.KINDS.has(kind) and FRAGILE.MASSES.has(kind), "%s é quebrável" % kind)
		check(FILL.ITEMS.has(kind), "%s tem medida de térreo" % kind)
	for kind: String in kinds:
		check(kind in PLACEMENTS.KINDS and PLACEMENTS.LABELS.has(kind), "%s é editável no editor de mundo" % kind)
	for kind: String in FILL_KIT.KINDS:
		check(not KIT.LAYERED.has(kind), "%s monta pelo material do kit" % kind)
	# Temas: todo item sorteado existe e os pesos fecham 1.
	for theme_kind in ["corner_shop", "shop", "warehouse_shop", "commercial_laundromat", "office", "brownstone", "warehouse"]:
		var theme := FILL._theme(theme_kind, "teste")
		var total := 0.0
		for item in theme.items:
			total += float(item[1])
			check(FILL.ITEMS.has(item[0]), "%s sorteia %s" % [theme_kind, item[0]])
		check(absf(total - 1.0) < 0.001, "%s: pesos somam 1" % theme_kind)
	for theme: Dictionary in [FILL.CAFE, FILL.PRODUCE, FILL.STORE, FILL.HOME, FILL.WORK]:
		for item in theme.get("curb", []):
			check(FILL.ITEMS.has(item[0]), "meio-fio sorteia %s" % item[0])
	check(FILL._merge([Vector2(4, 5), Vector2(0, 1), Vector2(1.3, 2)]) == [Vector2(0, 2), Vector2(4, 5)], "vãos de porta próximos viram um intervalo")
	print("RESULT ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
