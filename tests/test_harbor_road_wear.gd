extends SceneTree
## Desgaste das ruas do Harbor (HarborRoadWear, 29/10): orçamento por trecho, posições finitas,
## determinismo ao recarregar, tempo de cada fatia, densidade porto x residencial, formato de vértice
## igual ao dos decalques já compilados e a troca do desgaste antigo (A/B pelo interruptor).
##
## Monta só os dados da região (sem jogo); o tempo é do GDScript no editor (debug), mais lento que o
## export: serve de teto, não de medida de quadro.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_harbor_road_wear.gd -- --no-save
const REGION := preload("res://world/regions/NativeRegion.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const WEAR := preload("res://world/shared/roads/HarborRoadWear.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
## Fatia máxima aceita (ms) para o passo 11 inteiro: sorteio antigo numa chamada e cada fatia do novo.
const SLICE_LIMIT_MS := 4.0

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)


func run() -> void:
	check(WEAR.enabled(), "desgaste ligado por padrão (GETECO_HARBOR_ROAD_WEAR != 0)")
	_check_atlas()
	_check_materials()
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	for frame in 3600:
		if region.prepared: break
		await process_frame
	check(region.prepared, "região do Harbor preparada")
	if not region.prepared:
		_finish()
		return
	var geometry = region.harbor_road_geometry
	check(geometry != null and not (geometry._roads as Array).is_empty(), "geometria das ruas carregada")
	var keys := _road_chunks(geometry)
	check(keys.size() > 20, "trechos com rua encontrados (%d)" % keys.size())
	# 1. Planejamento em todos os trechos com rua: orçamento, finitude, fatias e densidade.
	var planned := {}
	var worst_slice := 0.0
	var worst_slice_where := ""
	var worst_legacy := 0.0
	var worst_chunk := {"count": 0}
	var dropped := 0
	var non_finite := 0
	var outside := 0
	var by_zone := {"porto": [0, 0.0], "residencial": [0, 0.0]}
	for key in keys:
		var rect := Rect2(Vector2(key) * REGION.CELL, Vector2.ONE * REGION.CELL)
		var context: Dictionary = DRESSING._context(region, rect)
		var legacy_began := Time.get_ticks_usec()
		DRESSING._road_wear(context, {})
		worst_legacy = maxf(worst_legacy, float(Time.get_ticks_usec() - legacy_began) / 1000.0)
		var result := _plan(context)
		planned[key] = result
		if float(result.max_slice_ms) > worst_slice: worst_slice_where = "%s %s" % [key, result.worst_where]
		worst_slice = maxf(worst_slice, float(result.max_slice_ms))
		dropped += int(result.dropped)
		if int(result.count) > int(worst_chunk.count): worst_chunk = {"count": result.count, "key": key, "kinds": result.kinds}
		_vertices_seen += (result.vertices as PackedVector3Array).size()
		for vertex: Vector3 in result.vertices:
			if not vertex.is_finite(): non_finite += 1
			elif not rect.grow(5.0).has_point(Vector2(vertex.x, vertex.z)): outside += 1
		var base := WEAR.chunk_grit(context)
		var center := rect.get_center()
		var road_length := _road_length(context, rect)
		if road_length < 40.0: continue
		var zone := ""
		if center.y > 170.0 or WEAR.grit(center, base, "") > 0.75: zone = "porto"
		elif base < 0.33: zone = "residencial"
		if zone != "":
			by_zone[zone][0] += int(result.count)
			by_zone[zone][1] += road_length
	print("ROAD_WEAR_BUDGET pior trecho=%s decalques=%d tipos=%s" % [worst_chunk.get("key"), worst_chunk.count, worst_chunk.get("kinds")])
	print("ROAD_WEAR_SLICES pior fatia nova=%.2f ms (%s), sorteio antigo=%.2f ms (limite %.1f ms)" % [worst_slice, worst_slice_where, worst_legacy, SLICE_LIMIT_MS])
	check(int(worst_chunk.count) <= WEAR.MAX_DECALS, "nenhum trecho passa de %d decalques (pior %d)" % [WEAR.MAX_DECALS, worst_chunk.count])
	check(dropped == 0, "orçamento não corta decalques (%d cortados)" % dropped)
	check(non_finite == 0, "todos os vértices finitos (%d não finitos)" % non_finite)
	check(_vertices_seen == int(WEAR.stats.decals) * 4, "lote tem 4 vértices por decalque (%d vértices, %d decalques)" % [_vertices_seen, WEAR.stats.decals])
	check(outside == 0, "decalques ficam no próprio trecho (+5 m de meia peça; %d fora)" % outside)
	check(worst_slice <= SLICE_LIMIT_MS, "fatia do desgaste novo <= %.0f ms (pior %.2f ms)" % [SLICE_LIMIT_MS, worst_slice])
	check(worst_legacy <= SLICE_LIMIT_MS, "sorteio antigo do passo 11 <= %.0f ms (pior %.2f ms)" % [SLICE_LIMIT_MS, worst_legacy])
	check(not _format_reported, "formato de vértice do lote igual ao do QuadMesh dos decalques")
	check(_surfaces_seen <= 2, "no máximo duas superfícies (draw calls) por trecho (%d)" % _surfaces_seen)
	check(_bad_boxes == 0, "caixa do lote finita em todos os trechos")
	var port_density := float(by_zone.porto[0]) / maxf(float(by_zone.porto[1]), 1.0) * 100.0
	var home_density := float(by_zone.residencial[0]) / maxf(float(by_zone.residencial[1]), 1.0) * 100.0
	print("ROAD_WEAR_DENSITY porto=%.1f/100 m (%.0f m) residencial=%.1f/100 m (%.0f m)" % [port_density, by_zone.porto[1], home_density, by_zone.residencial[1]])
	check(by_zone.porto[1] > 100.0 and by_zone.residencial[1] > 100.0, "amostra de rua no porto e em zona residencial")
	check(port_density > home_density * 1.4, "porto/indústria mais gasto que rua residencial")
	# 2. Determinismo: outra ordem de trechos e contexto refeito dão exatamente o mesmo chão.
	DRESSING.invalidate_context(region)
	var reversed := keys.duplicate()
	reversed.reverse()
	var mismatched := 0
	for key in reversed:
		var rect := Rect2(Vector2(key) * REGION.CELL, Vector2.ONE * REGION.CELL)
		var again := _plan(DRESSING._context(region, rect))
		if again.vertices != planned[key].vertices or again.uvs != planned[key].uvs: mismatched += 1
	check(mismatched == 0, "recarregar em outra ordem repete o desgaste (%d trechos diferentes)" % mismatched)
	# 3. A/B: com o interruptor desligado o passo antigo volta; a sujeira da calçada é a mesma.
	_check_legacy_switch(region, keys)
	# 4. Integração: o acabamento real do trecho põe um lote só, sem os MultiMesh antigos de rua.
	await _check_built_chunks(region)
	print("ROAD_WEAR_STATS ", JSON.stringify(WEAR.stats))
	region.free()
	_finish()


func _finish() -> void:
	print("HARBOR_ROAD_WEAR checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("  falhou: ", failure)
	quit(0 if failures.is_empty() else 1)


func _check_atlas() -> void:
	var path := "res://assets/materials/harbor_road_wear/road_wear_atlas.png"
	var texture := load(path) as Texture2D
	check(texture != null and texture.get_width() == 1024 and texture.get_height() == 1024, "atlas 1024x1024 carregado")
	var text := FileAccess.get_file_as_string(path + ".import")
	check(text.contains("compress/mode=2") and text.contains("compress/high_quality=true"), "atlas importado em VRAM BC7 (alta qualidade)")
	check(text.contains("mipmaps/generate=true"), "atlas com mipmaps")
	check(text.contains("bptc"), "atlas tem a versão BPTC (BC7) importada")


func _check_materials() -> void:
	var mats := WEAR.materials()
	check(mats.size() == 2 and WEAR.materials()[0] == mats[0], "dois materiais compartilhados (fosco e molhado)")
	var decal := MATERIALS.ground_decal("road_wear_test_probe", ImageTexture.new(), Color(0, 0, 0, 0.5))
	for material in mats:
		var same := material.transparency == decal.transparency and material.depth_draw_mode == decal.depth_draw_mode \
			and material.shading_mode == decal.shading_mode and material.cull_mode == decal.cull_mode \
			and material.texture_filter == decal.texture_filter and material.albedo_texture != null \
			and not material.normal_enabled and material.roughness_texture == null and not material.vertex_color_use_as_albedo
		check(same, "%s com os mesmos recursos do decalque de chão (sem shader novo)" % material.resource_name)
	check(mats[0].render_priority == -3 and mats[1].render_priority == -2, "prioridade -3/-2: abaixo dos decalques de chão existentes (-1)")
	WEAR.set_wetness(1.0)
	check(mats[1].roughness < 0.1 and mats[1].albedo_color.a > 0.99, "chuva deixa a poça lisa e cheia")
	WEAR.set_wetness(0.0)
	check(mats[1].roughness > 0.5 and mats[0].albedo_color.r > 0.99, "seco volta ao fosco")


func _plan(context: Dictionary) -> Dictionary:
	var holder := Node3D.new()
	var state := WEAR.begin(holder, context)
	var max_slice := 0.0
	var worst_where := ""
	var slices := 0
	while true:
		var phase_before := int(state.get("phase", -1))
		var road_before := int(state.get("road", -1))
		var began := Time.get_ticks_usec()
		var done := WEAR.step(state)
		var spent := float(Time.get_ticks_usec() - began) / 1000.0
		if spent > max_slice:
			max_slice = spent
			worst_where = "fase %d rua %d->%d decalques %d" % [phase_before, road_before, int(state.get("road", -1)), int(state.get("count", 0))]
		slices += 1
		if done or slices > 200: break
	# Vértices em metros de mundo, como o lote guardou antes de montar (sem ler a malha da GPU).
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	if not state.is_empty():
		for surface in 2:
			for layer in WEAR.LAYERS:
				vertices.append_array(PackedVector3Array(state.buckets[surface][layer].v))
				uvs.append_array(PackedVector2Array(state.buckets[surface][layer].uv))
	var node := holder.get_node_or_null("HarborRoadWear") as MeshInstance3D
	if node != null:
		for surface in node.mesh.get_surface_count():
			var format: int = node.mesh.surface_get_format(surface)
			if format != _reference_format() and not _format_reported:
				_format_reported = true
				check(false, "formato de vértice igual ao QuadMesh dos decalques (%d != %d)" % [format, _reference_format()])
		_surfaces_seen = maxi(_surfaces_seen, node.mesh.get_surface_count())
		var box := node.get_aabb()
		if not box.position.is_finite() or not box.size.is_finite(): _bad_boxes += 1
	holder.free()
	return {"count": int(state.get("count", 0)), "dropped": int(state.get("dropped", 0)), "kinds": state.get("kinds", {}),
		"max_slice_ms": max_slice, "worst_where": worst_where, "slices": slices, "vertices": vertices, "uvs": uvs}

var _format_reported := false
var _surfaces_seen := 0
var _vertices_seen := 0
var _bad_boxes := 0
var _format := -1


## Formato do QuadMesh (FACE_Y) dos decalques do CityLook: as mesmas listas que o PrimitiveMesh
## entrega ao servidor, sem compressão. O par shader x formato já é compilado sob a cortina.
func _reference_format() -> int:
	if _format >= 0: return _format
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	var copy := ArrayMesh.new()
	copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad.get_mesh_arrays())
	_format = copy.surface_get_format(0)
	print("ROAD_WEAR_FORMAT quad=%d" % _format)
	return _format


func _road_chunks(geometry) -> Array[Vector2i]:
	var seen := {}
	for road in geometry._roads:
		var points: PackedVector2Array = road.points
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b) / 8.0))
			for i in steps + 1:
				var p := a.lerp(b, float(i) / float(steps))
				seen[Vector2i(floori(p.x / REGION.CELL), floori(p.y / REGION.CELL))] = true
	var keys: Array[Vector2i] = []
	for key in seen: keys.append(key)
	keys.sort()
	return keys


func _road_length(context: Dictionary, rect: Rect2) -> float:
	var total := 0.0
	for road in context.roads:
		var points: PackedVector2Array = road.points
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b)))
			for i in steps:
				if rect.has_point(a.lerp(b, (float(i) + 0.5) / float(steps))): total += a.distance_to(b) / float(steps)
	return total


func _check_legacy_switch(region, keys: Array[Vector2i]) -> void:
	var legacy_kinds := ["decal:oil", "decal:patch", "decal:crack", "manhole", "drain"]
	var on_found := 0
	var off_found := 0
	var grime_same := true
	for key in keys:
		var rect := Rect2(Vector2(key) * REGION.CELL, Vector2.ONE * REGION.CELL)
		var context: Dictionary = DRESSING._context(region, rect)
		var on := {}
		DRESSING._road_wear(context, on)
		WEAR._enabled = false
		var off := {}
		DRESSING._road_wear(context, off)
		var holder := Node3D.new()
		var empty := WEAR.begin(holder, context)
		holder.free()
		WEAR._enabled = true
		for kind in legacy_kinds:
			on_found += (on.get(kind, []) as Array).size()
			off_found += (off.get(kind, []) as Array).size()
		if on.get("decal:grime", []) != off.get("decal:grime", []): grime_same = false
		if not empty.is_empty(): grime_same = false
	check(on_found == 0, "ligado: sem óleo/remendo/rachadura/bueiro/grelha antigos (%d)" % on_found)
	check(off_found > 100, "desligado: desgaste antigo volta igual (%d peças)" % off_found)
	check(grime_same, "sujeira da calçada idêntica com e sem o desgaste novo")


func _check_built_chunks(region) -> void:
	# Porto, centro e rua residencial (64 m por trecho).
	var probes := [Vector2i(4, 3), Vector2i(1, 1), Vector2i(4, -1)]
	for key in probes:
		if not region.records.has(key) and not _has_roads(region, key): continue
		region._build_chunk(key)
		var chunk: Node = region.chunks.get(key)
		if chunk == null: continue
		for frame in 2: await process_frame
		var wear := chunk.find_children("HarborRoadWear", "MeshInstance3D", true, false)
		var legacy := 0
		for node in chunk.find_children("*", "GeometryInstance3D", true, false):
			if str(node.name) in ["CityLook_decal_oil", "CityLook_decal_patch", "CityLook_decal_crack", "CityLook_manhole", "CityLook_drain"]: legacy += 1
		check(wear.size() == 1, "trecho %s montado com um lote de desgaste (%d)" % [key, wear.size()])
		check(legacy == 0, "trecho %s sem os MultiMesh antigos de rua (%d)" % [key, legacy])
		if wear.size() == 1:
			var node := wear[0] as MeshInstance3D
			var decals := int(node.get_meta(&"road_wear_decals", 0))
			print("ROAD_WEAR_CHUNK %s decalques=%d superfícies=%d tipos=%s" % [key, decals, node.mesh.get_surface_count(), node.get_meta(&"road_wear_kinds", {})])
			check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "trecho %s: desgaste sem sombra" % key)
		region.chunks.erase(key)
		region._detach_cached_records(chunk)
		chunk.free()


func _has_roads(region, key: Vector2i) -> bool:
	var rect := Rect2(Vector2(key) * REGION.CELL, Vector2.ONE * REGION.CELL)
	return not (DRESSING._context(region, rect).roads as Array).is_empty()
