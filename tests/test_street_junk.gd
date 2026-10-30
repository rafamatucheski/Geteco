extends SceneTree
## Objetos soltos da rua de Harbor (StreetJunk / StreetJunkKit, pedido de 29/10: "ruas muito limpas
## para uma cidade portuária"). Três partes:
## 1. contrato do kit, sem mundo: malha montável com UV no atlas, triângulos, apoio no chão, um
##    material só e retido, atlas importado em VRAM comprimida (BC7) com mipmaps;
## 2. cada tipo novo registrado (FragileProps3D, editor de mundo, lista do CityLook) e, atropelado,
##    vira destroço que não decola, para perto e repousa; a 2,5 m/s é empurrado;
## 3. Harbor de verdade (NativeRegion em streaming, com janela: no renderizador dummy o MultiMesh
##    devolve identidade): orçamento por chunk e por tipo, posições finitas, dentro do chunk,
##    fora de prédio e de asfalto, registradas para o carro, um lote por tipo, material retido,
##    mais sujeira no porto que no bairro, orla com mesa/guarda-sol/cadeira, e o mesmo chunk
##    recarregado volta igual.
## Não mede FPS nem draw calls do quadro (isso é tests/capture/capture_harbor_props.gd, com janela).
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_street_junk.gd

const KIT := preload("res://world/city_look/CityPropKit.gd")
const JUNK_KIT := preload("res://world/city_look/StreetJunkKit.gd")
const JUNK := preload("res://world/city_look/StreetJunk.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const PLACEMENTS := preload("res://world/editing/WorldPlacements.gd")
const LITTER := preload("res://world/city_look/CityGroundLitter.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const PREWARM := preload("res://runtime/LateSurfacePrewarm.gd")

class Director extends Node3D:
	func spawn_litter(_p: Vector3, _d: Vector3) -> void: pass
	func spawn_glass(_p: Vector3, _d: Vector3) -> void: pass
	func spawn_geyser(_p: Vector3) -> void: pass
	func play_prop_hit(_p: Vector3, _f: String, _s: float) -> void: pass

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	create_timer(840).timeout.connect(func(): push_error("STREET_JUNK timeout"); quit(3))
	run.call_deferred()


func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)


func run() -> void:
	_kit_contract()
	_registration()
	await _physics()
	if DisplayServer.get_name() == "headless":
		print("STREET_JUNK: parte 3 (Harbor em streaming) precisa de janela; pulada no headless")
	else:
		await _harbor_streaming()
	print("%s STREET_JUNK checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for label in failures.slice(0, 40): print("  - ", label)
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------------------
# 1. Kit.

func _kit_contract() -> void:
	var material := JUNK_KIT.material()
	verify(material == JUNK_KIT.material(), "material único e retido (mesma instância a cada pedido)")
	verify(material.albedo_texture == JUNK_KIT.ATLAS, "material usa o atlas de desgaste")
	verify(material.vertex_color_use_as_albedo and material.vertex_color_is_srgb, "cor do vértice/instância tinge o atlas (sRGB como o kit)")
	verify(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "material opaco (sem passe alfa no jogo)")
	var config := ConfigFile.new()
	verify(config.load("res://assets/city_props/harbor_junk_atlas.png.import") == OK, "atlas tem .import")
	verify(int(config.get_value("params", "compress/mode", -1)) == 2 and bool(config.get_value("params", "compress/high_quality", false)), "atlas em VRAM comprimida de alta qualidade (BC7)")
	verify(bool(config.get_value("params", "mipmaps/generate", false)), "atlas com mipmaps")
	var image: Image = JUNK_KIT.ATLAS.get_image()
	if image != null:
		verify(image.has_mipmaps(), "textura importada tem mipmaps")
		verify(image.is_compressed(), "textura importada comprimida (%s)" % image.get_format())
	# A primeira malha do kit paga a partida do SurfaceTool (test_sidewalk_fill: ~20 ms).
	KIT.mesh("hydrant")
	# A primeira malha do atlas paga a partida dela (14 ms no editor em 30/10): no jogo isso cai no
	# primeiro chunk montado sob a cortina, e o LateSurfacePrewarm monta todas lá também.
	var first_began := Time.get_ticks_usec()
	KIT.mesh(JUNK_KIT.KINDS[0])
	print("primeira malha do atlas (%s): %.2f ms" % [JUNK_KIT.KINDS[0], float(Time.get_ticks_usec() - first_began) / 1000.0])
	var slowest := 0.0
	var total_ms := 0.0
	for kind: String in JUNK_KIT.KINDS:
		var began := Time.get_ticks_usec()
		var mesh: ArrayMesh = KIT.mesh(kind)
		var ms := float(Time.get_ticks_usec() - began) / 1000.0
		slowest = maxf(slowest, ms)
		total_ms += ms
		var triangles := mesh.surface_get_array_len(0) / 3
		var aabb := mesh.get_aabb()
		print("montagem de %s: %.2f ms, %d triângulos, %s" % [kind, ms, triangles, aabb.size])
		verify(mesh.get_surface_count() == 1, "%s: uma superfície (um draw call por lote)" % kind)
		verify(triangles > 20 and triangles < 1600, "%s: %d triângulos (20-1600)" % [kind, triangles])
		verify(aabb.position.is_finite() and aabb.size.is_finite(), "%s: AABB finita" % kind)
		verify(aabb.position.y > -0.05, "%s: apoia no chão (y mínimo %.2f)" % [kind, aabb.position.y])
		verify(aabb.size.x < 4.5 and aabb.size.z < 4.5 and aabb.size.y < 3.0, "%s: tamanho de objeto de rua (%s)" % [kind, aabb.size])
		verify(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV != 0, "%s: tem UV no atlas" % kind)
		verify(mesh.surface_get_material(0) == material, "%s: superfície com o material retido (destroço)" % kind)
		verify(KIT.material_for(kind) == material, "%s: lote do chunk com o material retido" % kind)
		var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var inside := true
		for uv in uvs:
			if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0 or not uv.is_finite(): inside = false
		verify(inside, "%s: UV dentro do atlas" % kind)
		var variation := KIT.variation_for(kind)
		verify(not variation.is_empty() and not (variation.colors as Array).is_empty(), "%s: tem cor por cópia" % kind)
		# Variação determinística pela posição: a mesma peça volta igual.
		var placement := Transform3D(Basis(Vector3.UP, 0.7), Vector3(12.3, 0.012, -4.5))
		verify(KIT.vary(kind, placement) == KIT.vary(kind, placement), "%s: cor e proporção por cópia determinísticas" % kind)
	print("montagem dos %d tipos: %.1f ms no total, %.2f ms o mais lento" % [JUNK_KIT.KINDS.size(), total_ms, slowest])
	verify(slowest < 12.0, "malha nova mais lenta: %.1f ms" % slowest)


# ---------------------------------------------------------------------------
# 2. Registro.

func _registration() -> void:
	for kind: String in JUNK_KIT.KINDS:
		verify(FRAGILE.KINDS.has(kind) and FRAGILE.MASSES.has(kind), "%s registrado no FragileProps3D (perfil e massa)" % kind)
		verify(kind in DRESSING.FRAGILE_KINDS, "%s entra no registro de quebráveis do chunk" % kind)
		verify(kind in PLACEMENTS.KINDS and PLACEMENTS.LABELS.has(kind), "%s editável no editor de mundo" % kind)
		verify(JUNK.RADIUS.has(kind) and LITTER.JUNK_RADIUS.has(kind), "%s tem pegada no chão" % kind)
		verify(str(FRAGILE.KINDS.get(kind, {}).get("family", "")) == "light", "%s é leve (empurra/cai, não ancora)" % kind)
	for area in JUNK.TABLES:
		var total := 0.0
		for row in JUNK.TABLES[area]:
			total += float(row[1])
			verify(row[0] in JUNK_KIT.KINDS, "%s sorteia tipo conhecido %s" % [area, row[0]])
		verify(absf(total - 1.0) < 0.001, "%s: pesos somam 1" % area)
		verify(JUNK.CURB_CHANCE.has(area) and JUNK.CORNER_CHANCE.has(area) and JUNK.BIN_CHANCE.has(area), "%s tem chance de meio-fio, esquina e lixeira" % area)
	verify(float(JUNK.CURB_CHANCE.port) > float(JUNK.CURB_CHANCE.downtown) and float(JUNK.CURB_CHANCE.industrial) > float(JUNK.CURB_CHANCE.residential), "porto e indústria sujam mais")
	# O pré-aquecimento do passe alfa (destroço que some) cobre todos os tipos novos.
	var source := FileAccess.get_file_as_string("res://runtime/LateSurfacePrewarm.gd")
	verify(source.contains("kit.JUNK.KINDS") and source.contains("kit.JUNK.material()"), "LateSurfacePrewarm desenha as peças novas no passe alfa e o material opaco")
	# Contrato do lançamento: não sai mais rápido que o carro, impulso limitado, não decola.
	for kind: String in JUNK_KIT.KINDS:
		for speed in [4.0, 12.0, 25.0]:
			var launch: Vector3 = FRAGILE.launch_velocity(kind, speed, Vector3.RIGHT, 1.05, 0.12)
			var horizontal := Vector2(launch.x, launch.z).length()
			var mass := float(FRAGILE.MASSES[kind])
			verify(horizontal <= speed, "%s a %d m/s: não sai mais rápido que o carro (%.1f)" % [kind, speed, horizontal])
			verify(horizontal * mass <= FRAGILE.IMPULSE_CAP * 1.13, "%s a %d m/s: impulso limitado" % [kind, speed])
			verify(launch.y <= FRAGILE.MAX_LIFT + 0.001, "%s a %d m/s: não decola" % [kind, speed])


# ---------------------------------------------------------------------------
# 3. Física: atropelado em alta velocidade e empurrado devagar.

func _physics() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector3(300, -0.5, 0)
	var director := Director.new()
	root.add_child(director)
	for pass_speed in [16.0, 2.5]:
		FRAGILE.cells.clear()
		var chunk := Node3D.new()
		root.add_child(chunk)
		var items := {}
		var body_kind := {}
		var kinds: Array = JUNK_KIT.KINDS
		for i in kinds.size():
			var kind: String = kinds[i]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.mesh = KIT.mesh(kind)
			multimesh.instance_count = 1
			var origin := Vector3(i * 30.0, 0.012, 0)
			multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, origin))
			multimesh.set_instance_color(0, (KIT.variation_for(kind).colors as Array)[0])
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = multimesh
			visual.material_override = KIT.material_for(kind)
			chunk.add_child(visual)
			FRAGILE.register_instance(kind, multimesh, 0, chunk, [], [], visual)
			var found: Array = FRAGILE.query(origin, 0.5)
			verify(found.size() == 1 and found[0].kind == kind, "%s: registrado e consultável" % kind)
			if found.is_empty(): continue
			verify(FRAGILE.hit(found[0], pass_speed, Vector3.RIGHT, director), "%s cede a %.1f m/s" % [kind, pass_speed])
			items[kind] = origin
			for body in director.find_children("*", "RigidBody3D", true, false):
				if not body_kind.has(body): body_kind[body] = kind
		var bodies: Array = director.find_children("*", "RigidBody3D", true, false)
		verify(bodies.size() >= kinds.size(), "a %.1f m/s cada tipo vira destroço físico (%d corpos)" % [pass_speed, bodies.size()])
		var start := {}
		var center_start := {}
		for body: RigidBody3D in bodies:
			start[body] = body.global_position
			center_start[body] = _shape_center_y(body)
			for child in body.get_children():
				if child is MeshInstance3D:
					var tinted: Material = (child as MeshInstance3D).material_override
					verify(tinted is StandardMaterial3D and (tinted as StandardMaterial3D).albedo_texture == JUNK_KIT.ATLAS, "destroço mantém o atlas (mesmo shader, só a cor muda)")
		var peak := {}
		for frame in 240:
			await physics_frame
			for body: RigidBody3D in bodies:
				# Ponto mais baixo da forma acima do chão: decolar é sair do chão inteiro. O centro sobe
				# sozinho quando uma peça comprida (monte de 2,5 m, guarda-sol) capota de ponta, sem voar.
				if is_instance_valid(body): peak[body] = maxf(float(peak.get(body, 0.0)), _lowest_y(body))
		for body: RigidBody3D in bodies:
			if not is_instance_valid(body): continue
			var moved := Vector2(body.global_position.x - start[body].x, body.global_position.z - start[body].z).length()
			verify(body.global_position.is_finite(), "destroço com posição finita")
			# Guarda-sol: a forma do destroço é a caixa da copa (2,3 m) e a peça tem 8 kg; a 58 km/h ele
			# capota e sai do chão como um guarda-sol de verdade. Teto próprio, ainda sem voar longe.
			var ceiling := 1.5 if str(body_kind.get(body, "")).begins_with("beach_parasol") else 0.6
			verify(float(peak[body]) < ceiling, "%s: destroço não sai do chão (ponto mais baixo a %.2f m, %.1f m/s)" % [body_kind.get(body, "?"), peak[body], pass_speed])
			verify(body.linear_velocity.length() < 1.0, "destroço repousa em 4 s (v=%.2f)" % body.linear_velocity.length())
			if pass_speed > 10.0: verify(moved < 22.0, "atropelado para perto (%.1f m)" % moved)
			else: verify(moved < 4.0, "empurrado devagar não voa (%.1f m)" % moved)
			body.free()
		chunk.free()
	FRAGILE.cells.clear()
	director.free()
	floor_body.free()


# ---------------------------------------------------------------------------
# 4. Harbor de verdade.

const POINTS := {"centro": Vector3(86.7, 0.05, 101.5), "orla": Vector3(110.0, 0.05, 146.0), "cais": Vector3(300.0, 0.05, 255.0), "bairro": Vector3(318.0, 0.05, 27.0)}


func _idle(region: Node3D) -> bool:
	var began := Time.get_ticks_msec()
	while not region.is_streaming_idle() and Time.get_ticks_msec() - began < 60000:
		await process_frame
	return region.is_streaming_idle()


func _lowest_y(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var shape := child as CollisionShape3D
			var basis := body.global_basis * shape.basis
			var half: Vector3 = (shape.shape as BoxShape3D).size * 0.5
			var reach := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
			return (body.global_transform * shape.position).y - reach
	return body.global_position.y


func _shape_center_y(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D: return (body.global_transform * (child as CollisionShape3D).position).y
	return body.global_position.y


func _junk_layout(chunk: Node3D) -> Array:
	var rows := []
	for kind: String in JUNK_KIT.KINDS:
		var view := chunk.get_node_or_null("CityLook_" + kind) as MultiMeshInstance3D
		if view == null: continue
		for index in view.multimesh.instance_count:
			rows.append([kind, view.multimesh.get_instance_transform(index), view.multimesh.get_instance_color(index)])
	return rows


func _harbor_streaming() -> void:
	var region = REGION.build_region("harbor", POINTS.centro)
	root.add_child(region)
	verify(await _idle(region), "streaming inicial termina")
	var seen := {}
	var by_zone := {}
	var shore_sets := 0
	var max_ms := 0.0
	var max_step_ms := 0.0
	var reload_key := Vector2i.ZERO
	for label in ["centro", "orla", "cais", "bairro"]:
		region.set_focus(POINTS[label])
		verify(await _idle(region), "%s: streaming termina" % label)
		for frame in 6: await process_frame
		for key: Vector2i in region.chunks:
			if seen.has(key): continue
			var chunk: Node3D = region.chunks[key]
			if not is_instance_valid(chunk) or not chunk.has_meta("street_junk_items"): continue
			seen[key] = true
			var rect := Rect2(Vector2(key) * 64.0, Vector2(64, 64))
			var context: Dictionary = DRESSING._context(region, rect)
			var site: Dictionary = JUNK._site(context, {})
			var area := JUNK.zone(context, site, rect.get_center())
			max_ms = maxf(max_ms, float(chunk.get_meta("street_junk_ms", 0.0)))
			max_step_ms = maxf(max_step_ms, float(chunk.get_meta("street_junk_step_max_ms", 0.0)))
			var total := 0
			var batches := 0
			for kind: String in JUNK_KIT.KINDS:
				var views := chunk.find_children("CityLook_" + kind, "MultiMeshInstance3D", false, false)
				if views.is_empty(): continue
				batches += 1
				verify(views.size() == 1, "%s %s: um lote por tipo" % [key, kind])
				var view: MultiMeshInstance3D = views[0]
				verify(view.material_override == JUNK_KIT.material(), "%s %s: material retido" % [key, kind])
				var count := view.multimesh.instance_count
				total += count
				verify(count <= JUNK.MAX_PER_KIND, "%s %s: %d por tipo (teto %d)" % [key, kind, count, JUNK.MAX_PER_KIND])
				if kind in ["beach_parasol", "beach_parasol_b", "bar_table", "beach_chairs"]: shore_sets += count
				for index in count:
					var world: Transform3D = chunk.global_transform * view.multimesh.get_instance_transform(index)
					var point := Vector2(world.origin.x, world.origin.z)
					verify(world.origin.is_finite() and world.basis.x.is_finite() and world.basis.z.is_finite(), "%s %s: posição finita" % [key, kind])
					verify(absf(world.origin.y - 0.012) < 0.05, "%s %s: no chão (y=%.3f)" % [key, kind, world.origin.y])
					verify(rect.grow(0.01).has_point(point), "%s %s: nasce no chunk dono" % [key, kind])
					verify(DRESSING._road_clearance(context, point) > 0.1, "%s %s em %s: fora do asfalto" % [key, kind, point])
					verify(not DRESSING._inside_building(context, point, 0.0), "%s %s em %s: fora de prédio" % [key, kind, point])
					var registered := false
					for item in FRAGILE.query(world.origin, 0.2):
						if item.kind == kind and (item.point as Vector3).distance_to(world.origin) < 0.05: registered = true
					verify(registered, "%s %s em %s: o carro derruba (registrado)" % [key, kind, point])
			verify(total == int(chunk.get_meta("street_junk_items")), "%s: contagem do lote bate com a do passo" % key)
			verify(total <= JUNK.MAX_ITEMS, "%s: %d peças (teto %d)" % [key, total, JUNK.MAX_ITEMS])
			if not by_zone.has(area): by_zone[area] = []
			by_zone[area].append(total)
			print("chunk %s (%s): %d peças em %d lotes, montagem %.2f ms (fatia máx. %.2f ms)" % [key, area, total, batches, chunk.get_meta("street_junk_ms", 0.0), chunk.get_meta("street_junk_step_max_ms", 0.0)])
			# Chunk do ponto da orla (pode ter sido visto já do centro).
			if key == Vector2i(floori(POINTS.orla.x / 64.0), floori(POINTS.orla.z / 64.0)) and total > 0: reload_key = key
	var averages := {}
	for area in by_zone:
		var sum := 0
		for value in by_zone[area]: sum += int(value)
		averages[area] = float(sum) / maxf(1.0, float((by_zone[area] as Array).size()))
	print("média de peças por chunk: ", averages, " | montagem máx. %.2f ms, fatia máx. %.2f ms" % [max_ms, max_step_ms])
	verify(shore_sets > 0, "orla tem mesa de boteco, guarda-sol ou cadeira de praia (%d)" % shore_sets)
	if averages.has("port") and averages.has("residential"):
		verify(float(averages.port) > float(averages.residential), "porto mais sujo que o bairro residencial (%.1f × %.1f)" % [averages.port, averages.residential])
	# Fatias do streaming: no editor (debug) o teto é folgado; o release é medido à parte.
	verify(max_step_ms < 8.0, "fatia mais lenta do passo: %.2f ms" % max_step_ms)
	# Recarregar: o mesmo chunk volta com as mesmas peças, cores e posições.
	region.set_focus(POINTS.orla)
	verify(await _idle(region), "volta à orla")
	if region.chunks.has(reload_key):
		var layout := _junk_layout(region.chunks[reload_key])
		verify(not layout.is_empty(), "chunk da orla tem objetos para comparar")
		region.set_focus(Vector3(600, 0.05, 250))
		verify(await _idle(region), "streaming para longe termina")
		for frame in 12: await process_frame
		verify(not region.chunks.has(reload_key), "chunk da orla descarregado")
		region.set_focus(POINTS.orla)
		verify(await _idle(region), "streaming de volta termina")
		for frame in 6: await process_frame
		verify(region.chunks.has(reload_key) and _junk_layout(region.chunks[reload_key]) == layout, "recarregado: mesmas peças, posições e cores")
	else:
		verify(false, "chunk da orla com objetos encontrado")
	region.queue_free()
	for frame in 12: await process_frame
