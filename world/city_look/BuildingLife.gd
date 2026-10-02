extends RefCounted
## Prédios "vivos": o que faz uma fachada de GTA parecer habitada.
##
## A câmera fixa olha para o norte, então só a fachada SUL e o telhado de cada
## prédio aparecem. Este passo lê essa fachada como ela foi montada pelo
## arquétipo (janelas reais por coluna/andar, trechos livres do térreo) e
## acrescenta, por tipo de prédio:
## - escada de incêndio zigue-zague numa coluna de janelas (residencial/escritório);
## - ar-condicionado de janela e floreira em janelas avulsas;
## - calhas verticais nas quinas;
## - pichação e cartazes lambe-lambe só em parede sem janela/porta/toldo;
## - no telhado: varal (residencial), pombos na platibanda, vapor saindo de
##   respiro (escritório/galpão) e luz vermelha de balizamento (prédio alto);
## - letreiro de neon com o NOME PRÓPRIO no alto dos comerciais (a regra de
##   UrbanSignage — só nome próprio — continua valendo).
## Tudo sem colisão, em MultiMesh por tipo por chunk (as mesmas "batches" do
## CityChunkDressing); sorteio determinístico pelo id do prédio.

const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const NEON_GROUP := &"city_neon_label"
const FONT_PATH := "res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"

const RESIDENTIAL := ["brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block"]
const OFFICE := ["office", "police_precinct", "fire_station", "hospital"]
const COMMERCIAL := ["corner_shop", "shop", "commercial_laundromat", "warehouse_shop", "bank_branch"]
const INDUSTRIAL := ["warehouse", "artisan_workshop", "garage"]
const NEON_COLORS := [Color(1.0, 0.25, 0.55), Color(0.25, 0.9, 1.0), Color(1.0, 0.62, 0.15), Color(0.55, 1.0, 0.35), Color(0.8, 0.4, 1.0)]


static var _graffiti_materials: Array[StandardMaterial3D] = []


static func _roll(key: String) -> float:
	return float(key.hash() % 10007) / 10007.0


static func _push(batches: Dictionary, kind: String, xform: Transform3D) -> void:
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(xform)


## Chamado por CityChunkDressing._rooftops para cada prédio com laje plana,
## depois dos adereços de telhado (occupied já tem tudo que está na laje).
static func decorate(chunk: Node3D, building: UrbanBuildingBase, roof_y: float, roof_center: Vector2, roof_size: Vector2, occupied: Array, batches: Dictionary, has_billboard: bool) -> void:
	var key := building.building_id
	var kind := building.building_kind
	var facade := _read_facade(building)
	if not facade.is_empty():
		if kind in RESIDENTIAL or kind in OFFICE:
			_fire_escape(key, kind, facade, batches, chunk)
		_window_units(key, kind, facade, batches)
		_drainpipes(key, kind, facade, roof_y, batches)
		# Delegacia não leva pichação/lambe-lambe na fachada.
		if kind != "police_precinct": _street_level(key, kind, facade, batches, chunk)
	_roof_life(chunk, building, key, kind, roof_y, roof_center, roof_size, occupied, batches)
	if not has_billboard and (kind in COMMERCIAL or kind in OFFICE) and not building.proper_name.is_empty():
		_roof_neon(chunk, building, key, roof_y, roof_center, roof_size)


# ---------------------------------------------------------------------------
# Leitura da fachada sul (coordenadas globais; prédios da V1 são alinhados à grade).

static func _read_facade(building: UrbanBuildingBase) -> Dictionary:
	var center := building.global_position
	var half := building.building_size * 0.5
	var face_z := center.z + half.y
	var windows := []
	var blocked := []
	var glass := _glass_materials()
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		# Pertence à fachada sul: encosta nela ou avança para a rua.
		if box.end.z < face_z - 0.12 or box.position.z < face_z - 2.5: continue
		if box.size.x > building.building_size.x * 0.95 and box.size.y > 3.0: continue
		if mesh.material_override in glass and box.size.y >= 0.8 and box.size.y < 3.0 and box.size.x < 3.5:
			windows.append({"x": box.get_center().x, "bottom": box.position.y, "top": box.end.y, "width": box.size.x})
		if box.position.y < 2.8 and box.end.y > 0.15:
			blocked.append(Vector2(box.position.x - 0.15, box.end.x + 0.15))
	if windows.is_empty() and blocked.is_empty(): return {}
	return {"face_z": face_z, "left": center.x - half.x, "right": center.x + half.x, "base_y": center.y, "windows": windows, "blocked": blocked, "width": building.building_size.x}


static func _glass_materials() -> Array:
	var list := [MATERIALS.flat(Color(0.20, 0.29, 0.34), 0.18), MATERIALS.shop_glass(), MATERIALS.window_tv()]
	for index in MATERIALS.WINDOW_TONES.size(): list.append(MATERIALS.window_lit(index))
	for index in MATERIALS.UNLIT_VARIANTS: list.append(MATERIALS.window_unlit(index))
	list.append(UrbanMaterials.glass_window())
	list.append(UrbanMaterials.glass_display())
	return list


## Colunas de janelas acima do térreo, ordenadas de baixo para cima.
static func _columns(facade: Dictionary) -> Dictionary:
	var columns := {}
	for window in facade.windows:
		if float(window.bottom) - float(facade.base_y) < 1.9: continue
		var column := roundi(float(window.x) / 0.4)
		if not columns.has(column): columns[column] = []
		columns[column].append(window)
	for column in columns: columns[column].sort_custom(func(a, b): return a.bottom < b.bottom)
	return columns


# ---------------------------------------------------------------------------
# Escada de incêndio (a marca do prédio residencial de GTA IV).

static func _fire_escape(key: String, kind: String, facade: Dictionary, batches: Dictionary, chunk: Node3D) -> void:
	if _roll(key + "|fe") > (0.55 if kind in RESIDENTIAL else 0.35): return
	var columns := _columns(facade)
	var candidates := []
	for column in columns:
		var branch_stack: Array = columns[column]
		# Duas janelas em andares diferentes: dá para ligar com um lance.
		if branch_stack.size() >= 2 and float(branch_stack[-1].bottom) - float(branch_stack[0].bottom) > 1.8: candidates.append(column)
	if candidates.is_empty(): return
	candidates.sort()
	var column = candidates[int(_roll(key + "|fec") * candidates.size()) % candidates.size()]
	var stack: Array = columns[column]
	var x := clampf(float(stack[0].x), float(facade.left) + 1.35, float(facade.right) - 1.35)
	var z: float = facade.face_z
	var base: float = facade.base_y
	# Patamares nos andares; lance mais íngreme que o chão aceita (rise > 2,6 m)
	# encerra a escada ali.
	var floors := [base]
	for window in stack:
		var y := float(window.bottom) - 0.14
		var rise: float = y - float(floors[-1])
		if rise < 1.6: continue
		if rise > 2.6: break
		floors.append(y)
	if floors.size() < 2: return
	var body := StaticBody3D.new()
	body.name = "FireEscape_" + key
	body.collision_layer = 1
	body.collision_mask = 0
	chunk.add_child(body)
	for index in range(1, floors.size()):
		var y: float = floors[index]
		var below: float = floors[index - 1]
		var rise := y - below
		_push(batches, "fe_platform", Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		_push(batches, "fe_stair", Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, rise / 2.5, 1.0)), Vector3(x, below, z)))
		_box(body, chunk, Vector3(2.6, 0.1, 0.95), Transform3D(Basis.IDENTITY, Vector3(x, y - 0.05, z + 0.5)))
		# Rampa de colisão do lance (mesma inclinação dos degraus).
		var run := 2.6
		var d := Vector3(run, rise, 0).normalized()
		var normal := Vector3.BACK.cross(d)
		var ramp_center := Vector3(x, below + rise * 0.5, z + 1.3) - normal * 0.06
		_box(body, chunk, Vector3(Vector2(run, rise).length(), 0.12, 0.6), Transform3D(Basis(d, normal, Vector3.BACK), ramp_center))
	facade["fire_escape_x"] = x


static func _box(body: StaticBody3D, chunk: Node3D, size: Vector3, global_xform: Transform3D) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.transform = chunk.global_transform.affine_inverse() * global_xform
	body.add_child(collider)


# ---------------------------------------------------------------------------
# Ar-condicionado e floreira em janelas avulsas.

static func _window_units(key: String, kind: String, facade: Dictionary, batches: Dictionary) -> void:
	var ac_ratio := 0.3 if kind in OFFICE else 0.26 if kind in RESIDENTIAL else 0.15
	var flower_ratio := 0.2 if kind in RESIDENTIAL else 0.0
	var fire_x: float = facade.get("fire_escape_x", INF)
	for window in facade.windows:
		if float(window.bottom) - float(facade.base_y) < 1.9: continue
		if absf(float(window.x) - fire_x) < 1.6: continue
		var wkey := "%s|w|%d|%d" % [key, roundi(float(window.x) * 10.0), roundi(float(window.bottom) * 10.0)]
		var roll := _roll(wkey)
		var sill := Vector3(float(window.x), float(window.bottom) - 0.03, float(facade.face_z))
		if roll < ac_ratio:
			var offset := (_roll(wkey + "o") - 0.5) * maxf(0.0, float(window.width) - 0.7)
			_push(batches, "window_ac", Transform3D(Basis.IDENTITY, sill + Vector3(offset, -0.02, 0)))
		elif roll < ac_ratio + flower_ratio:
			_push(batches, "flower_box", Transform3D(Basis.IDENTITY.scaled(Vector3(clampf(float(window.width) / 1.0, 0.7, 1.3), 1, 1)), sill))


static func _drainpipes(key: String, kind: String, facade: Dictionary, roof_y: float, batches: Dictionary) -> void:
	if kind in COMMERCIAL and _roll(key + "|dp") > 0.5: return
	var height := roof_y - float(facade.base_y)
	if height < 3.0: return
	for side in [-1.0, 1.0]:
		if _roll(key + "|dp" + str(side)) > 0.7: continue
		var x: float = (float(facade.right) - 0.22) if side > 0 else (float(facade.left) + 0.22)
		var clear := true
		for window in facade.windows:
			if absf(float(window.x) - x) < float(window.width) * 0.5 + 0.2: clear = false
		if not clear: continue
		_push(batches, "drainpipe", Transform3D(Basis.IDENTITY.scaled(Vector3(1, height, 1)), Vector3(x, float(facade.base_y), float(facade.face_z))))


# ---------------------------------------------------------------------------
# Térreo: pichação e cartaz só em parede livre.

static func _free_spans(facade: Dictionary) -> Array:
	var spans := []
	var cursor: float = float(facade.left) + 0.3
	var blocked: Array = facade.blocked.duplicate()
	blocked.sort_custom(func(a, b): return a.x < b.x)
	for interval in blocked:
		if interval.x > cursor: spans.append(Vector2(cursor, interval.x))
		cursor = maxf(cursor, interval.y)
	if float(facade.right) - 0.3 > cursor: spans.append(Vector2(cursor, float(facade.right) - 0.3))
	return spans.filter(func(span): return span.y - span.x >= 1.7)


static func _street_level(key: String, kind: String, facade: Dictionary, batches: Dictionary, _chunk: Node3D) -> void:
	var spans := _free_spans(facade)
	var graffiti_ratio := 0.85 if kind in INDUSTRIAL else 0.55 if kind in COMMERCIAL else 0.4
	var poster_ratio := 0.5 if kind in COMMERCIAL or kind in INDUSTRIAL else 0.25
	for index in spans.size():
		var span: Vector2 = spans[index]
		var skey := "%s|span|%d" % [key, index]
		var width := span.y - span.x
		var z: float = float(facade.face_z) + 0.012
		if _roll(skey + "g") < graffiti_ratio:
			var tag_w := minf(width - 0.2, 2.6 + _roll(skey + "gw") * 2.2)
			var x := span.x + (width - tag_w) * (0.2 + _roll(skey + "gx") * 0.6) + tag_w * 0.5
			var variant := int(_roll(skey + "gv") * 6.0) % 6
			var y := float(facade.base_y) + 0.3 + tag_w * 0.25 + _roll(skey + "gy") * 0.5
			_push(batches, "graffiti:%d" % variant, Transform3D(Basis.IDENTITY.scaled(Vector3(tag_w, tag_w * 0.5, 1)), Vector3(x, y, z)))
		elif _roll(skey + "p") < poster_ratio and width >= 3.0:
			var x := span.x + 1.5 + _roll(skey + "px") * (width - 3.0)
			_push(batches, "posters", Transform3D(Basis.IDENTITY, Vector3(x, float(facade.base_y) - 0.4, z - 0.01)))


static func graffiti_material(variant: int) -> StandardMaterial3D:
	if _graffiti_materials.size() > variant: return _graffiti_materials[variant]
	while _graffiti_materials.size() <= variant:
		var material := StandardMaterial3D.new()
		material.albedo_texture = _graffiti_texture(_graffiti_materials.size())
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.4
		material.roughness = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_graffiti_materials.append(material)
	return _graffiti_materials[variant]


## Tag procedural: traço grosso com contorno escuro e brilho, 2–3 cores por tag.
static func _graffiti_texture(seed_value: int) -> ImageTexture:
	var width := 192
	var height := 96
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 51013 + seed_value * 131
	var palettes := [[Color("ff4f9a"), Color("ffd23f")], [Color("3ee0d0"), Color("1d3cff")], [Color("ffffff"), Color("e63946")], [Color("7cff4f"), Color("222222")], [Color("ff8c1a"), Color("ffef5a")], [Color("b06bff"), Color("45e0ff")]]
	var palette: Array = palettes[seed_value % palettes.size()]
	var strokes := []
	var letters := rng.randi_range(3, 5)
	for letter in letters:
		var x0 := 18.0 + letter * (width - 36.0) / letters
		var points := []
		for p in rng.randi_range(3, 5):
			points.append(Vector2(x0 + rng.randf_range(-6, (width - 36.0) / letters), rng.randf_range(22, height - 22)))
		strokes.append(points)
	# Contorno, preenchimento e brilho: três passadas do mesmo traço.
	for pass_index in 3:
		var radius: float = [10.0, 7.0, 2.0][pass_index]
		var color: Color = [Color("141414"), palette[0], palette[1]][pass_index]
		for points in strokes:
			for i in points.size() - 1:
				var a: Vector2 = points[i]
				var b: Vector2 = points[i + 1]
				var steps := int(a.distance_to(b) / 2.0) + 1
				for s in steps:
					var p := a.lerp(b, float(s) / steps) + (Vector2(-2, -2) if pass_index == 2 else Vector2.ZERO)
					_stamp(image, p, radius, color)
	# Respingos e escorrido de tinta.
	for drip in rng.randi_range(3, 7):
		var x := rng.randi_range(20, width - 20)
		var y := rng.randi_range(40, height - 30)
		for d in rng.randi_range(6, 18): _stamp(image, Vector2(x, y + d), 1.2, palette[0])
	return ImageTexture.create_from_image(image)


static func _stamp(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var r := int(ceil(radius))
	for y in range(int(center.y) - r, int(center.y) + r + 1):
		for x in range(int(center.x) - r, int(center.x) + r + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			if Vector2(x, y).distance_to(center) <= radius: image.set_pixel(x, y, color)


# ---------------------------------------------------------------------------
# Telhado vivo.

static func _roof_life(chunk: Node3D, building: UrbanBuildingBase, key: String, kind: String, roof_y: float, roof_center: Vector2, roof_size: Vector2, occupied: Array, batches: Dictionary) -> void:
	var xform := building.global_transform
	# Pombos na platibanda sul (a que a câmera vê).
	if _roll(key + "|pig") < 0.35:
		var x := (_roll(key + "|pigx") - 0.5) * maxf(0.0, roof_size.x - 2.5)
		_push(batches, "pigeons", xform * Transform3D(Basis(Vector3.UP, (_roll(key + "|pigr") - 0.5) * 0.6), Vector3(roof_center.x + x, roof_y + 0.36, roof_center.y + roof_size.y * 0.5 - 0.05)))
	# Varal nos residenciais.
	if (kind in RESIDENTIAL or kind == "cobra_house") and _roll(key + "|lau") < 0.5 and roof_size.x > 4.5:
		var spot := _free_roof_spot(key + "|lau", roof_center, roof_size, occupied, 1.9)
		if spot.is_finite():
			var yaw := 0.0 if _roll(key + "|laur") < 0.7 else PI * 0.5
			_push(batches, "laundry", xform * Transform3D(Basis(Vector3.UP, yaw), Vector3(spot.x, roof_y, spot.y)))
			occupied.append({"point": spot, "radius": 1.9})
	# Fileira de parabólicas em prédio residencial alto.
	if kind in RESIDENTIAL and _roll(key + "|sat") < 0.3:
		var spot := _free_roof_spot(key + "|sat", roof_center, roof_size, occupied, 1.2)
		if spot.is_finite():
			_push(batches, "satellite_row", xform * Transform3D(Basis.IDENTITY, Vector3(spot.x, roof_y, spot.y)))
			occupied.append({"point": spot, "radius": 1.2})
	# Vapor de respiro: vida visível mesmo parado. No máximo dois por chunk.
	if (kind in OFFICE or kind in INDUSTRIAL) and _roll(key + "|steam") < 0.45 and int(chunk.get_meta("city_steam", 0)) < 2:
		var spot := _free_roof_spot(key + "|steam", roof_center, roof_size, occupied, 0.6)
		if spot.is_finite():
			chunk.set_meta("city_steam", int(chunk.get_meta("city_steam", 0)) + 1)
			_push(batches, "vent", xform * Transform3D(Basis.IDENTITY, Vector3(spot.x, roof_y, spot.y)))
			chunk.add_child(_steam(xform * Vector3(spot.x, roof_y + 0.85, spot.y), key))
			occupied.append({"point": spot, "radius": 0.6})
	# Balizamento vermelho em prédio alto.
	if roof_y - building.global_position.y >= 9.0:
		var spot := _free_roof_spot(key + "|bea", roof_center, roof_size * 0.5, occupied, 0.5)
		if spot.is_finite():
			var base := xform * Vector3(spot.x, roof_y, spot.y)
			_push(batches, "beacon_mast", Transform3D(Basis.IDENTITY, base))
			_push(batches, "beacon_lens", Transform3D(Basis.IDENTITY, base + Vector3.UP * 1.9))


static func _free_roof_spot(key: String, center: Vector2, size: Vector2, occupied: Array, radius: float) -> Vector2:
	for attempt in 8:
		var local := center + Vector2((_roll(key + str(attempt) + "x") - 0.5) * maxf(0.0, size.x - radius * 2.0 - 0.6), (_roll(key + str(attempt) + "z") - 0.5) * maxf(0.0, size.y - radius * 2.0 - 0.6))
		var free := true
		for other in occupied:
			if local.distance_to(other.point) < radius + float(other.radius): free = false; break
		if free: return local
	return Vector2.INF


static func _steam(point: Vector3, _key: String) -> CPUParticles3D:
	var steam := CPUParticles3D.new()
	steam.name = "RoofSteam"
	steam.amount = 10
	steam.lifetime = 3.2
	steam.preprocess = 3.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	steam.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = MATERIALS.radial_texture("steam", [Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)], [0.0, 0.5, 1.0], 64)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	steam.material_override = material
	steam.direction = Vector3(0.25, 1, 0.1)
	steam.spread = 12.0
	steam.gravity = Vector3(0.35, 0.4, 0)
	steam.initial_velocity_min = 0.5
	steam.initial_velocity_max = 0.9
	steam.scale_amount_min = 0.8
	steam.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	steam.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.92, 0.93, 0.94, 0.0), Color(0.92, 0.93, 0.94, 0.5), Color(0.9, 0.9, 0.92, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	steam.color_ramp = ramp
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steam.position = point
	steam.emitting = true
	return steam


## Letreiro de neon com o nome próprio, em pé na borda sul do telhado.
static func _roof_neon(chunk: Node3D, building: UrbanBuildingBase, key: String, roof_y: float, roof_center: Vector2, roof_size: Vector2) -> void:
	if roof_size.x < 6.0 or _roll(key + "|neon") > 0.6: return
	var name := building.proper_name.to_upper()
	var color: Color = NEON_COLORS[int(_roll(key + "|neonc") * NEON_COLORS.size()) % NEON_COLORS.size()]
	if building.building_id == "NorthFrontage0":
		name = "$"
		color = Color("d8c46b")
	var root := Node3D.new()
	root.name = "RoofNeon_" + key
	chunk.add_child(root)
	root.global_transform = building.global_transform * Transform3D(Basis.IDENTITY, Vector3(roof_center.x, roof_y, roof_center.y + roof_size.y * 0.5 - 0.9))
	# Treliça de sustentação atrás das letras.
	var frame := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(minf(roof_size.x - 1.0, name.length() * 0.95 + 0.6), 0.08, 0.08)
	frame.mesh = bar
	frame.material_override = MATERIALS.flat(Color("2b2f31"), 0.6)
	frame.position = Vector3(0, 0.25, -0.1)
	root.add_child(frame)
	var label := Label3D.new()
	label.text = name
	label.font = load(FONT_PATH)
	label.font_size = 128
	label.pixel_size = 0.013
	label.outline_size = 18
	label.outline_modulate = Color(color.r, color.g, color.b, 0.35)
	var boost := lerpf(1.0, 1.55, MATERIALS.night)
	label.modulate = Color(color.r * boost, color.g * boost, color.b * boost)
	label.position = Vector3(0, 1.05, 0)
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var font_width: float = label.font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 128).x * label.pixel_size
	var max_width := roof_size.x - 1.0
	if font_width > max_width: label.pixel_size *= max_width / font_width
	label.set_meta("neon_color", color)
	label.add_to_group(NEON_GROUP)
	root.add_child(label)
