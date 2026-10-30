extends SceneTree
## Postes de energia e fiação aérea do Harbor (HarborUtilityLines, 29/10) na região de verdade:
## - toda ponta de fio fica a < 5 cm de um ponto de fixação de um poste montado (isolador, roldana,
##   braçadeira ou suporte do rolo), e esse ponto encosta na malha do poste (< 3 cm da superfície);
## - vão que cruza a borda de chunk termina no poste montado pelo vizinho;
## - nenhuma posição infinita/NaN; a curva do fio nunca passa abaixo do chão;
## - orçamento por chunk (postes, fios, lotes novos) e tempo da montagem (impresso);
## - poste de energia longe de poste de luz, placa, árvore e mobília;
## - poste balançando/derrubado leva os fios dele (a outra ponta segue no vizinho, a curva fica
##   acima do chão), os outros vãos não mexem e a recuperação devolve tudo aos isoladores.
## Exige janela: sem renderer real a MultiMesh devolve as instâncias na origem.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_harbor_utility_lines.gd -- --no-save
const REGION := preload("res://world/regions/NativeRegion.gd")
const UTILITY := preload("res://world/city_look/HarborUtilityLines.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const RECOVERY := preload("res://gameplay/street_physics/LampRecovery3D.gd")
## Centro/oeste (Market St.), porto sul, Vila Cobra e acesso rural, com pares vizinhos.
const KEYS := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4), Vector2i(6, 1), Vector2i(7, 1), Vector2i(-1, 0), Vector2i(-2, 0)]
const NEW_BATCH_PREFIXES := ["HarborUtility", "CityLook_lamp_wear"]
var checks := 0
var failures: Array[String] = []


class Director extends Node:
	func play_prop_hit(_point: Vector3, _sound: String, _speed: float) -> void: pass
	func spawn_glass(_point: Vector3, _direction: Vector3) -> void: pass


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FALHA: ", message)


func _initialize() -> void: run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("test_harbor_utility_lines exige renderer real (MultiMesh)")
		quit(2)
		return
	if not UTILITY.enabled:
		printerr("GETECO_HARBOR_POLES=0: nada a testar")
		quit(2)
		return
	preload("res://world/chunk_bake/ChunkCellMerge.gd").slice_budget_usec = 0
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	var stats := {}
	for key in KEYS:
		if not region.chunks.has(key): region._build_chunk(key)
		stats[key] = UTILITY.last_stats.duplicate()
	for frame in 6: await process_frame
	var poles := _poles(region)
	var spans := _spans(region)
	print("UTILITY chunks=%d poles=%d spans=%d" % [KEYS.size(), poles.size(), spans.size()])
	for key in KEYS: print("UTILITY chunk %s %s" % [key, JSON.stringify(stats[key])])
	check(poles.size() >= 12, "postes de energia montados nos chunks de rua (achou %d)" % poles.size())
	check(spans.size() >= 40, "fios montados (achou %d)" % spans.size())
	_check_budget(region)
	_check_mesh_attachments()
	_check_wire_ends(region, poles, spans)
	_check_clearances(region, poles)
	await _check_fall(region, poles, spans)
	region.queue_free()
	await process_frame
	print("HARBOR_UTILITY_LINES checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)


## [{key, style, world: Transform3D, item}] dos postes de energia dos chunks montados.
func _poles(region) -> Array:
	var result: Array = []
	for rows in FRAGILE.cells.values():
		for item in rows:
			if not item.has("wires") or not item.has("multimesh"): continue
			var chunk: Variant = item.chunk.get_ref()
			if not is_instance_valid(chunk) or chunk.get_parent() != region: continue
			var entry: Variant = UTILITY._poles.get(item.wires)
			result.append({"key": item.wires, "style": entry.style if entry != null else "", "item": item,
				"world": (chunk as Node3D).global_transform * item.multimesh.get_instance_transform(item.index)})
	return result


## [{spec, world: Transform3D}] dos fios lidos da MultiMesh de verdade (não do registro).
func _spans(region) -> Array:
	var seen := {}
	var result: Array = []
	for list in UTILITY._spans.values():
		for spec in list:
			if seen.has(spec): continue
			seen[spec] = true
			var chunk: Variant = spec.chunk.get_ref()
			var multimesh: MultiMesh = spec.multimesh.get_ref()
			if not is_instance_valid(chunk) or chunk.get_parent() != region or multimesh == null: continue
			result.append({"spec": spec, "world": (chunk as Node3D).global_transform * multimesh.get_instance_transform(spec.index)})
	return result


func _check_budget(region) -> void:
	for key in KEYS:
		var chunk: Node3D = region.chunks.get(key)
		if chunk == null: continue
		var batches := 0
		var pole_count := 0
		var wire_count := 0
		for child in chunk.get_children():
			if not child is MultiMeshInstance3D: continue
			var label := String(child.name)
			for prefix in NEW_BATCH_PREFIXES:
				if label.begins_with(prefix): batches += 1
			if label.begins_with("HarborUtilityPoles_"): pole_count += child.multimesh.instance_count
			if label.begins_with("HarborUtilityWires"):
				wire_count += child.multimesh.instance_count
				check(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: fio sem sombra" % key)
				check(child.visibility_range_end > 0.0 and child.visibility_range_end < 220.0, "%s: fio com visibility_range (%.0f m)" % [key, child.visibility_range_end])
		for body in chunk.find_children("*", "CollisionObject3D", true, false):
			check(not String(body.name).begins_with("HarborUtility"), "%s: fio/poste de energia sem corpo de colisão" % key)
		check(pole_count <= UTILITY.MAX_POLES_PER_CHUNK, "%s: %d postes <= %d" % [key, pole_count, UTILITY.MAX_POLES_PER_CHUNK])
		check(wire_count <= UTILITY.MAX_WIRES_PER_CHUNK, "%s: %d fios <= %d" % [key, wire_count, UTILITY.MAX_WIRES_PER_CHUNK])
		var styles := 0
		for child in chunk.get_children():
			if String(child.name).begins_with("HarborUtilityPoles_"): styles += 1
		# Por estilo de poste: poste, transformador e desgaste; mais fio esticado, fio frouxo e o
		# desgaste do poste de luz. Chunk de divisa de bairro tem dois estilos.
		check(batches <= 3 * maxi(styles, 1) + 3 and styles <= 2, "%s: %d lotes novos <= %d (draw calls, %d estilos)" % [key, batches, 3 * maxi(styles, 1) + 3, styles])
		print("UTILITY budget %s batches=%d poles=%d wires=%d" % [key, batches, pole_count, wire_count])


## Cada ponto de fixação do estilo encosta na malha do poste (isolador, roldana, braçadeira, barra).
func _check_mesh_attachments() -> void:
	for style_id in UTILITY.STYLES:
		var mesh := UTILITY.pole_mesh(style_id)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var points: Array = []
		for slot in UTILITY.slots(style_id): points.append([slot.id, slot.at])
		if float(UTILITY.STYLES[style_id].coil) > 0.0:
			for loop in UTILITY.coil_slots(style_id):
				points.append(["coil", loop[0]])
				points.append(["coil", loop[1]])
		for entry in points:
			var gap := _distance_to_mesh(entry[1], vertices, indices)
			check(gap < 0.03, "%s/%s: ponto de fixação a %.3f m da malha do poste" % [style_id, entry[0], gap])


func _distance_to_mesh(point: Vector3, vertices: PackedVector3Array, indices: PackedInt32Array) -> float:
	var best := INF
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in range(0, count - 2, 3):
		var a := vertices[indices[i] if not indices.is_empty() else i]
		var b := vertices[indices[i + 1] if not indices.is_empty() else i + 1]
		var c := vertices[indices[i + 2] if not indices.is_empty() else i + 2]
		best = minf(best, point.distance_to(_closest_on_triangle(point, a, b, c)))
	return best


## Ericson, Real-Time Collision Detection, 5.1.5.
func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var total := va + vb + vc
	if absf(total) < 1e-12: return a
	return a + ab * (vb / total) + ac * (vc / total)


## Pontos de fixação (mundo) de todos os postes montados.
func _attachments(poles: Array) -> Array:
	var result: Array = []
	for pole in poles:
		if str(pole.style).is_empty(): continue
		var world: Transform3D = pole.world
		for slot in UTILITY.slots(pole.style): result.append([world * slot.at, pole.key])
		for loop in UTILITY.coil_slots(pole.style):
			result.append([world * loop[0], pole.key])
			result.append([world * loop[1], pole.key])
	return result


func _nearest(attachments: Array, point: Vector3) -> Array:
	var best := INF
	var owner := ""
	for entry in attachments:
		var gap: float = point.distance_to(entry[0])
		if gap < best:
			best = gap
			owner = entry[1]
	return [best, owner]


func _check_wire_ends(region, poles: Array, spans: Array) -> void:
	var attachments := _attachments(poles)
	var built := {}
	for pole in poles: built[pole.key] = true
	var verified := 0
	var crossing := 0
	var worst := 0.0
	var below := 0
	for span in spans:
		var world: Transform3D = span.world
		check(world.origin.is_finite() and world.basis.x.is_finite() and world.basis.y.is_finite() and world.basis.z.is_finite(), "fio com transformação finita")
		var ends := [world.origin, world.origin + world.basis.x]
		var refs := [span.spec.a[0], span.spec.b[0]]
		for e in 2:
			if not built.has(refs[e]): continue
			var hit := _nearest(attachments, ends[e])
			worst = maxf(worst, hit[0])
			check(hit[0] < 0.05 and hit[1] == refs[e], "ponta do fio a %.3f m do isolador do poste %s (mais perto: %s)" % [hit[0], refs[e], hit[1]])
			verified += 1
		if built.has(refs[0]) and built.has(refs[1]) and refs[0] != refs[1]:
			var a_chunk: Variant = UTILITY._poles[refs[0]].chunk.get_ref()
			var b_chunk: Variant = UTILITY._poles[refs[1]].chunk.get_ref()
			if a_chunk != b_chunk: crossing += 1
		if _lowest(world) < 0.03: below += 1
	check(verified >= 60, "pontas conferidas contra postes montados (%d)" % verified)
	check(crossing >= 2, "vãos que cruzam a borda do chunk terminam no poste do vizinho (%d)" % crossing)
	check(below == 0, "nenhuma curva abaixo do chão (%d abaixo)" % below)
	print("UTILITY ends verified=%d crossing=%d worst=%.4f m" % [verified, crossing, worst])


func _lowest(world: Transform3D) -> float:
	var table := UTILITY.catenary()
	var lowest := INF
	for i in table.size():
		var t := float(i) / (table.size() - 1)
		lowest = minf(lowest, (world.origin + world.basis.x * t + world.basis.y * table[i]).y)
	return lowest


## Poste de energia não nasce em cima de poste de luz, placa, árvore ou mobília.
func _check_clearances(region, poles: Array) -> void:
	var others: Array = []
	for rows in FRAGILE.cells.values():
		for item in rows:
			if item.has("wires"): continue
			if not item.has("multimesh") and not item.has("root"): continue
			others.append([item.kind, Vector2(item.point.x, item.point.z)])
	var tight := 0
	for pole in poles:
		var at := Vector2(pole.world.origin.x, pole.world.origin.z)
		for other in others:
			var limit := 2.0 if other[0] == "lamp" else 0.9
			if at.distance_to(other[1]) < limit:
				tight += 1
				printerr("perto: poste %s de %s a %.2f m" % [pole.key, other[0], at.distance_to(other[1])])
		var geometry: Variant = region.get("harbor_road_geometry")
		if geometry != null:
			for record in geometry._traffic_signs.records:
				if at.distance_to(record.position) < 1.5:
					tight += 1
					printerr("perto: poste %s de placa A-32b" % pole.key)
	check(tight == 0, "poste de energia longe de poste de luz/placa/árvore/mobília (%d conflitos)" % tight)


func _span_transforms(spans: Array) -> Dictionary:
	var result := {}
	for span in spans:
		var multimesh: MultiMesh = span.spec.multimesh.get_ref()
		var chunk: Node3D = span.spec.chunk.get_ref()
		result[span.spec] = chunk.global_transform * multimesh.get_instance_transform(span.spec.index)
	return result


func _check_fall(region, poles: Array, spans: Array) -> void:
	# Poste com fio dos dois lados (vizinhos montados), num chunk montado.
	var target: Dictionary = {}
	for pole in poles:
		var attached: Array = spans.filter(func(span): return span.spec.a[0] == pole.key or span.spec.b[0] == pole.key)
		var neighbors := {}
		for span in attached:
			for ref in [span.spec.a[0], span.spec.b[0]]:
				if ref != pole.key: neighbors[ref] = true
		if neighbors.size() >= 2:
			target = pole
			break
	check(not target.is_empty(), "achou poste de energia com vão dos dois lados")
	if target.is_empty(): return
	var director := Director.new()
	root.add_child(director)
	var item: Dictionary = target.item
	var before := _span_transforms(spans)
	var mine: Array = spans.filter(func(span): return span.spec.a[0] == target.key or span.spec.b[0] == target.key)
	var others: Array = spans.filter(func(span): return not mine.has(span))
	# Balanço (abaixo do limiar): o fio acompanha e volta.
	FRAGILE.hit(item, 3.0, Vector3(1, 0, 0), director)
	check(item.state == "standing", "balanço: poste de energia segura a 3 m/s")
	# O balanço dura ~0,5 s: guarda o maior desvio de cada fio quadro a quadro.
	var moved_specs := {}
	var pole_moved := false
	for frame in 20:
		await physics_frame
		pole_moved = pole_moved or not item.multimesh.get_instance_transform(item.index).is_equal_approx(item.base)
		var swaying := _span_transforms(mine)
		for span in mine:
			if (swaying[span.spec] as Transform3D).origin.distance_to((before[span.spec] as Transform3D).origin) + ((swaying[span.spec] as Transform3D).basis.x - (before[span.spec] as Transform3D).basis.x).length() > 0.005: moved_specs[span.spec] = true
	print("UTILITY wobble pole_moved=%s state=%s" % [pole_moved, item.state])
	check(moved_specs.size() == mine.size(), "balanço: os %d fios do poste acompanham (mexeram %d)" % [mine.size(), moved_specs.size()])
	for frame in 30: await physics_frame
	# Tombo: a 8 m/s cai; os fios dele descem com a ponta, os outros ficam.
	# Ao longo da rua (X local do poste): um vão encurta e o outro estica.
	var direction: Vector3 = (target.world as Transform3D).basis.x.normalized()
	check(FRAGILE.hit(item, 8.0, direction, director), "poste de energia cede a 8 m/s")
	for frame in 75: await physics_frame
	var fallen: Transform3D = (item.chunk.get_ref() as Node3D).global_transform * item.multimesh.get_instance_transform(item.index)
	check(absf(fallen.basis.y.normalized().y) < .15, "poste de energia deitado depois do tombo")
	check(fallen.origin.distance_to(target.world.origin) < .01, "tomba na base")
	var poles_now := _poles(region)
	for pole in poles_now:
		if pole.key == target.key: pole.world = fallen
	var attachments := _attachments(poles_now)
	var after := _span_transforms(spans)
	var followed := 0
	for span in mine:
		var world: Transform3D = after[span.spec]
		check(world.origin.is_finite() and world.basis.x.is_finite() and world.basis.y.is_finite(), "fio do poste caído finito")
		for end in [world.origin, world.origin + world.basis.x]:
			var hit := _nearest(attachments, end)
			check(hit[0] < 0.05, "fio do poste caído: ponta a %.3f m de um isolador (sem fio solto no ar)" % hit[0])
			if hit[1] == target.key and hit[0] < 0.05: followed += 1
		check(_lowest(world) >= 0.03, "fio do poste caído acima do chão (%.2f m)" % _lowest(world))
	check(followed >= mine.size(), "as pontas presas no poste caído foram com ele (%d de %d vãos)" % [followed, mine.size()])
	var still := 0
	for span in others:
		if (after[span.spec] as Transform3D).is_equal_approx(before[span.spec]): still += 1
	check(still == others.size(), "vãos de outros postes não mexeram (%d de %d)" % [still, others.size()])
	# Recuperação (45 s no jogo): tudo de volta aos isoladores.
	RECOVERY.restore(item)
	# Com interpolação de física ligada, a leitura da MultiMesh só reflete o set no tique seguinte.
	for frame in 3: await physics_frame
	var restored := _span_transforms(spans)
	var back := 0
	for span in spans:
		if (restored[span.spec] as Transform3D).origin.distance_to((before[span.spec] as Transform3D).origin) < .01 \
			and ((restored[span.spec] as Transform3D).origin + (restored[span.spec] as Transform3D).basis.x).distance_to((before[span.spec] as Transform3D).origin + (before[span.spec] as Transform3D).basis.x) < .01:
			back += 1
	if back != spans.size():
		var pole_now: Transform3D = item.multimesh.get_instance_transform(item.index)
		print("UTILITY restore pole_at_base=%s has_recovery=%s state=%s" % [pole_now.is_equal_approx(item.base), item.has("recovery"), item.state])
		for span in mine.slice(0, 3):
			print("UTILITY restore span a=%s b=%s before_a=%s" % [(restored[span.spec] as Transform3D).origin, (restored[span.spec] as Transform3D).origin + (restored[span.spec] as Transform3D).basis.x, (before[span.spec] as Transform3D).origin])
	check(back == spans.size(), "recuperação devolve os fios aos isoladores (%d de %d)" % [back, spans.size()])
	director.queue_free()
