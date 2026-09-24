extends RefCounted
## Delegacia com cara de delegacia (Harbor Patrol, id "Police").
##
## O arquétipo UrbanServiceBuilding monta corpo, portão de viaturas, porta,
## escudo, faixa azul/branca, janelas gradeadas e uma antena. Isto acrescenta a
## leitura de "prédio da polícia" de jogo:
## - fachada: marquise com letreiro luminoso POLÍCIA, lampiões azuis ladeando a
##   porta, giroflex vermelho/azul na marquise, faixa de neon azul, pilastras,
##   mural PROCURADOS com cartazes, câmeras de segurança, frades de proteção,
##   mastros com bandeiras e aviso de VIATURAS no portão com zebrado no chão;
## - telhado: heliponto com H e luzes de borda, torre de rádio treliçada com
##   balizamento, holofote e parabólicas.
## Tudo visual (sem colisão), numa malha estática com cor por vértice + poucas
## malhas emissivas compartilhadas que o CityLook acende/pisca.

const KIT := preload("res://world/city_look/CityPropKit.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const FONT_PATH := "res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"

const NAVY := Color("1d2c4a")
const STEEL := Color("5f676c")
const CONCRETE := Color("a7a59c")


static func decorate(chunk: Node3D, building: UrbanBuildingBase, roof_y: float, roof_center: Vector2, roof_size: Vector2, occupied: Array, batches: Dictionary) -> void:
	var hw := building.building_size.x * 0.5
	var hz := building.building_size.y * 0.5
	var ex := 0.0 if building.data.has("entry_position") else hw - 0.8 - 1.2
	# roof_y/roof_center/roof_size já vêm no espaço local do prédio (_roof_box).
	var local_roof := roof_y
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var glow := {"lightbox": [], "globe": [], "neon": [], "red": [], "blue": [], "pad": []}
	var obstacles := _ground_obstacles(chunk, building)
	_facade(t, glow, building, hw, hz, ex, obstacles)
	_roof(t, glow, hw, hz, local_roof, roof_center, roof_size, occupied, batches, building)
	t.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "PoliceStationDetail"
	mesh.mesh = t.commit()
	mesh.material_override = KIT.material()
	chunk.add_child(mesh)
	mesh.global_transform = building.global_transform
	for key in glow:
		if glow[key].is_empty(): continue
		chunk.add_child(_emissive(key, glow[key], building.global_transform))
	_labels(chunk, building, hw, hz, ex)


# ---------------------------------------------------------------------------

## Objetos pequenos que já estão no chão perto da delegacia (ralo, poste,
## floreira da zona de rota...), no espaço local do prédio. Frade e mastro não
## podem nascer em cima deles.
static func _ground_obstacles(chunk: Node3D, building: UrbanBuildingBase) -> Array:
	var result := []
	var inverse := building.global_transform.affine_inverse()
	for node in chunk.get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if building.is_ancestor_of(mesh): continue
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.x > 3.0 or box.size.z > 3.0 or box.end.y < 0.02 or box.position.y > 1.5: continue
		if box.position.z < building.building_size.y * 0.5 - 0.5 or box.position.z > building.building_size.y * 0.5 + 5.0: continue
		result.append(box)
	return result


static func _clear(obstacles: Array, x: float, z: float, radius: float) -> bool:
	for box in obstacles:
		if x > box.position.x - radius and x < box.end.x + radius and z > box.position.z - radius and z < box.end.z + radius: return false
	return true


static func _facade(t: SurfaceTool, glow: Dictionary, building: UrbanBuildingBase, hw: float, hz: float, ex: float, obstacles: Array) -> void:
	var h := building.height
	# Pilastras de concreto no andar de cima (quebram a fachada lisa).
	if h > 5.0:
		var count := int(building.building_size.x / 2.2)
		for i in count + 1:
			var x := -hw + 0.15 + i * (building.building_size.x - 0.3) / count
			KIT.box(t, Vector3(x, (3.9 + h) * 0.5, hz + 0.08), Vector3(0.3, h - 3.9, 0.16), CONCRETE)
		KIT.box(t, Vector3(0, h - 0.2, hz + 0.1), Vector3(building.building_size.x, 0.3, 0.2), CONCRETE)
	# Rodapé de granito escuro.
	KIT.box(t, Vector3(0, 0.25, hz + 0.05), Vector3(building.building_size.x, 0.5, 0.1), Color("3a3d42"))
	# Faixa de neon azul logo acima da faixa pintada do arquétipo.
	glow.neon.append([Vector3(0, 3.95, hz + 0.12), Vector3(building.building_size.x - 0.2, 0.07, 0.05)])
	# Marquise da entrada com colunas e letreiro luminoso.
	var canopy_w := 4.4
	KIT.box(t, Vector3(ex, 3.02, hz + 1.0), Vector3(canopy_w, 0.2, 2.0), NAVY)
	KIT.box(t, Vector3(ex, 3.14, hz + 1.0), Vector3(canopy_w + 0.1, 0.05, 2.1), Color("2e3b55"))
	KIT.box(t, Vector3(ex, 3.17, hz + 2.03), Vector3(canopy_w + 0.1, 0.04, 0.08), Color("d9b43a"))
	for side in [-1.0, 1.0]:
		KIT.cylinder(t, Vector3(ex + side * (canopy_w * 0.5 - 0.2), 0, hz + 1.85), 0.1, 2.95, STEEL, 8)
	glow.lightbox.append([Vector3(ex, 2.72, hz + 2.03), Vector3(canopy_w - 0.2, 0.4, 0.05)])
	# Giroflex nas pontas da marquise.
	glow.red.append([Vector3(ex - canopy_w * 0.5 + 0.25, 3.25, hz + 1.9), Vector3(0.28, 0.14, 0.18)])
	glow.blue.append([Vector3(ex + canopy_w * 0.5 - 0.25, 3.25, hz + 1.9), Vector3(0.28, 0.14, 0.18)])
	# Lampiões azuis ladeando a porta (a marca da delegacia de filme).
	for side in [-1.0, 1.0]:
		var x: float = ex + side * 1.55
		KIT.box(t, Vector3(x, 0.1, hz + 0.55), Vector3(0.36, 0.2, 0.36), Color("26292c"))
		KIT.cylinder(t, Vector3(x, 0.2, hz + 0.55), 0.06, 1.75, Color("26292c"), 8)
		KIT.box(t, Vector3(x, 1.97, hz + 0.55), Vector3(0.12, 0.08, 0.12), Color("26292c"))
		glow.globe.append([Vector3(x, 2.2, hz + 0.55), Vector3(0.36, 0.4, 0.36)])
		KIT.box(t, Vector3(x, 2.44, hz + 0.55), Vector3(0.2, 0.06, 0.2), Color("26292c"))
	# Mural PROCURADOS com cartazes.
	var board_x := clampf(ex + 3.1, -hw + 1.2, hw - 1.2)
	KIT.box(t, Vector3(board_x, 1.65, hz + 0.05), Vector3(1.8, 1.2, 0.08), Color("3a2a1c"))
	KIT.box(t, Vector3(board_x, 1.65, hz + 0.1), Vector3(1.65, 1.05, 0.02), Color("a0764c"))
	for row in 2:
		for col in 3:
			var p := Vector3(board_x - 0.52 + col * 0.52, 1.4 + row * 0.5, hz + 0.115)
			KIT.box(t, p, Vector3(0.38, 0.44, 0.01), Color("ede6cf"))
			KIT.box(t, p + Vector3(0, 0.05, 0.006), Vector3(0.2, 0.22, 0.004), [Color("5a4a3c"), Color("3a3230"), Color("6e5a48")][(row + col) % 3])
			KIT.box(t, p + Vector3(0, -0.15, 0.006), Vector3(0.28, 0.04, 0.004), Color("a1231f"))
	# Câmeras de segurança nas quinas.
	for side in [-1.0, 1.0]:
		var x: float = side * (hw - 0.3)
		KIT.box(t, Vector3(x, 3.5, hz + 0.18), Vector3(0.08, 0.08, 0.3), Color("2b2f31"))
		KIT.box(t, Vector3(x - side * 0.08, 3.42, hz + 0.38), Vector3(0.18, 0.14, 0.34), Color("e3e4df"), -side * 0.5)
	# Frades de proteção na calçada, com vão na porta.
	var x0 := -hw + 0.6
	while x0 < hw - 0.4:
		if absf(x0 - ex) > 1.4 and _clear(obstacles, x0, hz + 2.4, 0.2):
			KIT.cylinder(t, Vector3(x0, 0, hz + 2.4), 0.13, 0.9, Color("3b3f42"), 8)
			KIT.cylinder(t, Vector3(x0, 0.62, hz + 2.4), 0.135, 0.12, Color("d9b43a"), 8)
		x0 += 1.3
	# Mastros com bandeiras (fictícias: Harbor, polícia, estado).
	var flags := [[Color("1b3f8b"), Color("f2f2ee")], [Color("0f1c33"), Color("d9b43a")], [Color("2c7a4b"), Color("f2f2ee")]]
	# Os três mastros juntos: procura, da direita da porta para a quina, o
	# primeiro trecho livre (a tampa do bueiro do esgoto fica nessa calçada).
	var start := INF
	var fz := hz + 3.0
	for row in [hz + 3.0, hz + 0.7]:
		# Junto à parede, só depois do mural PROCURADOS (ocupa ex+2,2 a ex+4,0).
		var candidate: float = ex + 2.2 if row > hz + 1.0 else ex + 4.15
		while candidate < hw + 1.5 and start == INF:
			var ok := true
			for i in 3:
				if not _clear(obstacles, candidate + i * 0.9, row, 0.3): ok = false
			if ok:
				start = candidate
				fz = row
			candidate += 0.3
		if start != INF: break
	for i in (3 if start != INF else 0):
		var fx: float = start + i * 0.9
		KIT.cylinder(t, Vector3(fx, 0, fz), 0.05, 7.2, Color("c9ccd0"), 8)
		KIT.cylinder(t, Vector3(fx, 7.2, fz), 0.09, 0.12, Color("d9b43a"), 8)
		var colors: Array = flags[i]
		KIT.box(t, Vector3(fx + 0.62, 6.55, fz), Vector3(1.2, 0.8, 0.02), colors[0], 0.25)
		KIT.box(t, Vector3(fx + 0.62, 6.55, fz + 0.012), Vector3(1.2, 0.18, 0.02), colors[1], 0.25)
		KIT.box(t, Vector3(fx + 0.34, 6.72, fz + 0.02), Vector3(0.22, 0.22, 0.02), colors[1], 0.25)
	# Zebrado amarelo em frente ao portão de viaturas.
	var bay_w := building.building_size.x * 0.48
	var bay_x := -hw + 0.6 + bay_w * 0.5
	for i in int(bay_w / 0.6):
		KIT.box(t, Vector3(bay_x - bay_w * 0.5 + 0.3 + i * 0.6, 0.035, hz + 1.2), Vector3(0.3, 0.01, 2.2), Color("d9b43a"), 0.6)


static func _roof(t: SurfaceTool, glow: Dictionary, hw: float, hz: float, roof_y: float, center: Vector2, size: Vector2, occupied: Array, batches: Dictionary, building: UrbanBuildingBase) -> void:
	var xf := building.global_transform
	# Heliponto: o maior disco que cabe longe dos obstáculos.
	# Heliponto: o maior disco (4,8 m → 2,4 m) que cabe longe dos obstáculos.
	var radius := clampf(minf(size.x, size.y) * 0.5 - 0.8, 2.4, 4.8)
	var pad := Vector2.INF
	while pad == Vector2.INF and radius >= 2.4:
		for attempt in 25:
			var candidate := center + Vector2((attempt % 5 - 2) * 0.9, (attempt / 5 - 2) * 0.9)
			if absf(candidate.x - center.x) + radius > size.x * 0.5 - 0.3 or absf(candidate.y - center.y) + radius > size.y * 0.5 - 0.3: continue
			var free := true
			for other in occupied:
				if candidate.distance_to(other.point) < radius + float(other.radius) * 0.5: free = false; break
			if free:
				pad = candidate
				break
		if pad == Vector2.INF: radius -= 0.4
	if pad.is_finite():
		var y := roof_y + 0.02
		KIT.cylinder(t, Vector3(pad.x, y - 0.02, pad.y), radius, 0.04, Color("3d4145"), 20)
		KIT.cylinder(t, Vector3(pad.x, y, pad.y), radius * 0.92, 0.03, Color("d9b43a"), 20)
		KIT.cylinder(t, Vector3(pad.x, y + 0.003, pad.y), radius * 0.86, 0.03, Color("3d4145"), 20)
		var hs := radius * 0.5
		KIT.box(t, Vector3(pad.x - hs * 0.45, y + 0.04, pad.y), Vector3(hs * 0.22, 0.01, hs * 1.3), Color("f2f2ee"))
		KIT.box(t, Vector3(pad.x + hs * 0.45, y + 0.04, pad.y), Vector3(hs * 0.22, 0.01, hs * 1.3), Color("f2f2ee"))
		KIT.box(t, Vector3(pad.x, y + 0.04, pad.y), Vector3(hs * 0.7, 0.01, hs * 0.22), Color("f2f2ee"))
		for i in 8:
			var a := TAU * i / 8.0
			glow.pad.append([Vector3(pad.x + cos(a) * radius, y + 0.06, pad.y + sin(a) * radius), Vector3(0.14, 0.08, 0.14)])
		occupied.append({"point": pad, "radius": radius})
	# Torre de rádio treliçada (6 m) num canto livre, com balizamento.
	var corner := Vector2(center.x - size.x * 0.5 + 1.2, center.y - size.y * 0.5 + 1.2)
	var tower_h := 6.0
	for leg in 3:
		var a := TAU * leg / 3.0
		var base := Vector3(corner.x + cos(a) * 0.45, roof_y, corner.y + sin(a) * 0.45)
		KIT.cylinder(t, base, 0.04, tower_h, Color("b9bdb8"), 5, 0.035)
	for level in 6:
		var y := roof_y + 0.8 + level * 0.95
		KIT.box(t, Vector3(corner.x, y, corner.y), Vector3(0.9, 0.03, 0.9), Color("c33a2f") if level % 2 else Color("e8e6de"))
	KIT.box(t, Vector3(corner.x, roof_y + tower_h - 0.8, corner.y + 0.4), Vector3(0.3, 0.8, 0.08), Color("e8e6de"))
	var top := xf * Vector3(corner.x, roof_y + tower_h + 0.05, corner.y)
	if not batches.has("beacon_lens"): batches["beacon_lens"] = []
	batches["beacon_lens"].append(Transform3D(Basis.IDENTITY, top))
	occupied.append({"point": corner, "radius": 0.9})
	# Holofote de busca no canto oposto e parabólicas.
	var light := Vector2(center.x + size.x * 0.5 - 1.0, center.y + size.y * 0.5 - 1.0)
	KIT.box(t, Vector3(light.x, roof_y + 0.25, light.y), Vector3(0.6, 0.5, 0.6), Color("3b3f42"))
	KIT.cylinder(t, Vector3(light.x, roof_y + 0.5, light.y), 0.28, 0.5, Color("5f676c"), 10, 0.34)
	occupied.append({"point": light, "radius": 0.7})
	for i in 2:
		var dish := Vector2(center.x + size.x * 0.5 - 1.0, center.y - size.y * 0.5 + 1.2 + i * 1.3)
		KIT.box(t, Vector3(dish.x, roof_y + 0.35, dish.y), Vector3(0.08, 0.7, 0.08), Color("6c7274"))
		KIT.cylinder(t, Vector3(dish.x, roof_y + 0.6, dish.y + 0.08), 0.05, 0.08, Color("e3e4df"), 12, 0.5)
		occupied.append({"point": dish, "radius": 0.7})


# ---------------------------------------------------------------------------

static func _emissive(kind: String, boxes: Array, xform: Transform3D) -> MeshInstance3D:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	for entry in boxes:
		if kind == "globe": KIT.cylinder(t, entry[0] - Vector3(0, entry[1].y * 0.5, 0), entry[1].x * 0.5, entry[1].y, Color.WHITE, 10, entry[1].x * 0.42)
		else: KIT.box(t, entry[0], entry[1], Color.WHITE)
	t.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "PoliceGlow_" + kind
	mesh.mesh = t.commit()
	mesh.material_override = MATERIALS.police(kind)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = xform
	return mesh


static func _labels(chunk: Node3D, building: UrbanBuildingBase, hw: float, hz: float, ex: float) -> void:
	var xf := building.global_transform
	_label(chunk, xf * Transform3D(Basis.IDENTITY, Vector3(ex, 2.72, hz + 2.065)), "POLÍCIA", 96, 0.0085, Color("12306e"), 4.0)
	_label(chunk, xf * Transform3D(Basis.IDENTITY, Vector3(clampf(ex + 3.1, -hw + 1.2, hw - 1.2), 2.4, hz + 0.1)), "PROCURADOS", 64, 0.005, Color("f2e9d0"), 1.7)
	var bay_w := building.building_size.x * 0.48
	var bay_x := -hw + 0.6 + bay_w * 0.5
	# Esquerda da marquise, que cobre o meio do portão vista de cima.
	_label(chunk, xf * Transform3D(Basis.IDENTITY, Vector3(-hw + 0.6 + (bay_w - 2.2) * 0.5, 2.3, hz + 0.12)), "VIATURAS", 90, 0.008, Color("f2f2ee"), bay_w - 2.6)


static func _label(chunk: Node3D, xform: Transform3D, text: String, font_size: int, pixel: float, color: Color, max_width: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load(FONT_PATH)
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var width: float = label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * pixel
	if width > max_width: label.pixel_size *= max_width / width
	chunk.add_child(label)
	label.global_transform = xform
