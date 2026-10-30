@tool
extends RefCounted
## Desgaste de rua por atlas (adesivo, lambe-lambe, pichação, ferrugem, sujeira e plaquetas)
## para postes de luz, postes de energia e placas do Harbor.
##
## Uma textura (assets/urban_detail/street_wear_atlas.png, BC7 com mipmaps, gerada por
## tools/build_street_wear_atlas.py) e UM material para tudo. O material tem exatamente as
## opções da face da placa A-32b (textura de albedo + alpha scissor), então o shader é o mesmo
## que já existe no jogo; mesmo assim entra no pré-aquecimento das fachadas pintadas (prewarm()).
## As malhas têm o leiaute da QuadMesh (posição, normal, tangente, UV, índice), o mesmo da face.
##
## Cada família (poste de luz, concreto, madeira, placa) tem uma malha de decalques no espaço
## local da peça: o lote é um MultiMesh por chunk e cada cópia é "extra" do poste no
## FragileProps3D, então tomba, some e volta junto com ele. Sem sombra, com alcance de detalhe.
## GETECO_HARBOR_POLES=0 desliga junto com os postes de energia.

const ATLAS_PATH := "res://assets/urban_detail/street_wear_atlas.png"
const ATLAS_SIZE := 512.0
## Espelho de tools/build_street_wear_atlas.py (CELLS), em pixels do atlas.
const CELLS := {
	"sticker0": Rect2(0, 0, 64, 64), "sticker1": Rect2(64, 0, 64, 64), "sticker2": Rect2(128, 0, 64, 64),
	"sticker3": Rect2(192, 0, 64, 64), "sticker4": Rect2(256, 0, 64, 64), "sticker5": Rect2(320, 0, 64, 64),
	"sticker6": Rect2(384, 0, 64, 64), "sticker7": Rect2(448, 0, 64, 64),
	"poster0": Rect2(0, 64, 128, 128), "poster1": Rect2(128, 64, 128, 128), "poster2": Rect2(256, 64, 128, 128), "poster3": Rect2(384, 64, 128, 128),
	"tag0": Rect2(0, 192, 128, 64), "tag1": Rect2(128, 192, 128, 64), "tag2": Rect2(256, 192, 128, 64), "tag3": Rect2(384, 192, 128, 64),
	"rust0": Rect2(0, 256, 64, 128), "rust1": Rect2(64, 256, 64, 128), "rust2": Rect2(128, 256, 64, 128), "rust3": Rect2(192, 256, 64, 128),
	"grime0": Rect2(256, 256, 64, 128), "grime1": Rect2(320, 256, 64, 128), "grime2": Rect2(384, 256, 64, 128), "grime3": Rect2(448, 256, 64, 128),
	"plate_number": Rect2(0, 384, 64, 128), "plate_danger": Rect2(64, 384, 64, 64),
	"sticker_cluster": Rect2(128, 384, 128, 128), "tag_wide": Rect2(256, 384, 256, 64), "poster_strip": Rect2(256, 448, 256, 64),
}
## Folga do decalque para a superfície: 4 mm não briga pela profundidade a 40 m (alcance do lote).
const GAP := 0.004
## Alcance (m até a peça) do lote de desgaste; o chamador soma meia diagonal do AABB.
const RANGE := 45.0
const LAMP_HEIGHT := 5.4

static var enabled := OS.get_environment("GETECO_HARBOR_POLES") != "0"
static var _material: StandardMaterial3D
static var _meshes := {}


static func available() -> bool:
	return enabled and ResourceLoader.exists(ATLAS_PATH)


# --- Bairros ---------------------------------------------------------------------------------

## Bairro de cada rua do Harbor (ids de OriginalWorldData.harbor_roads). Executivo = fiação
## enterrada, poste limpo, placa reta; porto e Cobra = poste sujo, placa torta.
const DISTRICT_BY_ROAD := {
	"foundry_avenue": "downtown", "market_street": "downtown", "westgate_drive": "downtown", "union_avenue": "downtown",
	"westgate_service_lane": "downtown", "medical_garden_lane": "downtown",
	"dock_street": "port", "warehouse_way": "port", "quay_boulevard": "port", "south_port_access": "port",
	"east_union_avenue": "island", "eastgate_drive": "island", "island_dock_street": "island",
	"island_esplanade": "executive", "island_market_street": "executive", "exchange_lane": "executive", "courtyard_lane": "executive",
	"vertice_rural_access": "rural", "salvage_access": "rural", "cobra_approach": "cobra",
}
const DISTRICT_PREFIXES := {"south_port_": "port", "cobra_": "cobra", "memorial_": "rural", "northbank_": "executive"}
## Fração dos postes de luz com adesivo/cartaz por bairro.
const WEAR_CHANCE := {"downtown": .5, "port": .85, "island": .25, "executive": 0.0, "cobra": .9, "rural": .4}
## [fração das placas tortas, inclinação mínima e máxima em graus].
const TILT := {"port": [.55, 1.5, 4.5], "cobra": [.6, 1.5, 5.0], "rural": [.5, 1.0, 4.0], "downtown": [.25, .6, 2.0], "island": [.1, .5, 1.2]}

static func district(road_id: String) -> String:
	var id := road_id.trim_prefix("road/")
	if DISTRICT_BY_ROAD.has(id): return DISTRICT_BY_ROAD[id]
	for prefix in DISTRICT_PREFIXES:
		if id.begins_with(prefix): return DISTRICT_PREFIXES[prefix]
	return ""


## Bairro da rua mais próxima de `point` (pontos em Vector2 ou Vector3, como vierem).
static func district_at(roads: Array, point: Vector2) -> String:
	var best := INF
	var found := ""
	for road in roads:
		var points: Variant = road.get("points", PackedVector2Array())
		for i in points.size() - 1:
			var a: Vector2 = _flat_point(points[i])
			var b: Vector2 = _flat_point(points[i + 1])
			var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) - float(road.get("width", 7.5)) * .5
			if distance < best:
				best = distance
				found = district(str(road.get("id", "")))
	return found


static func _flat_point(value: Variant) -> Vector2:
	return Vector2(value.x, value.z) if value is Vector3 else value


static func roll(key: String) -> float:
	return float(posmod(key.hash(), 10007)) / 10007.0


## Placa/poste leve torto no bairro: gira na base (a origem fica no chão), eixo horizontal sorteado.
static func lean(placement: Transform3D, district_id: String, key: String) -> Transform3D:
	if not enabled or not TILT.has(district_id): return placement
	var spec: Array = TILT[district_id]
	if roll(key + "tilt") >= float(spec[0]): return placement
	var degrees := lerpf(float(spec[1]), float(spec[2]), roll(key + "amount"))
	var heading := roll(key + "axis") * TAU
	return Transform3D(Basis(Vector3(cos(heading), 0, sin(heading)), deg_to_rad(degrees)) * placement.basis, placement.origin)


## Mesmas opções da face da placa (HarborTrafficSigns "paint"): shader compartilhado.
static func material() -> StandardMaterial3D:
	if _material != null: return _material
	_material = StandardMaterial3D.new()
	# Atlas pequeno (512², ~340 KB em BC7) carregado no primeiro chunk, sob a cortina.
	_material.albedo_texture = load(ATLAS_PATH) if ResourceLoader.exists(ATLAS_PATH) else null
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = .5
	_material.roughness = .72
	return _material


## Pré-aquecimento (PaintedFacadePrewarm): o material retido aqui é o mesmo dos lotes.
static func prewarm() -> Array:
	return [material()] if available() else []


## Lote por chunk: transformações já locais ao chunk. Sem sombra (cartão fino) e com alcance.
static func batch(name: String, mesh: ArrayMesh, transforms: Array) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = multimesh
	instance.material_override = material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# O alcance mede até o centro do AABB do lote inteiro: meia diagonal evita sumir no canto.
	instance.visibility_range_end = RANGE + multimesh.get_aabb().size.length() * .5
	instance.visibility_range_end_margin = 4.0
	preload("res://runtime/GraphicsOptions.gd").tag_detail(instance)
	return instance


static func uv(cell: String) -> Rect2:
	var px: Rect2 = CELLS[cell]
	# Meio texel para dentro: a célula vizinha não vaza no filtro bilinear.
	return Rect2((px.position + Vector2.ONE * .5) / ATLAS_SIZE, (px.size - Vector2.ONE) / ATLAS_SIZE)


# --- Malhas por família --------------------------------------------------------------------

## Poste de luz do Blender (CityChunkDressing._lamp_mesh): haste de 12 lados, raio 8,5 cm em
## y=0,5 até 6 cm no topo. Adesivo e lambe-lambe do lado da calçada (-Z), pichação de lado.
static func lamp_mesh() -> ArrayMesh:
	if _meshes.has("lamp"): return _meshes["lamp"]
	var radius := func(y: float) -> float: return .085 - .025 * clampf((y - .5) / (LAMP_HEIGHT - .6), 0.0, 1.0)
	var quads: Array = []
	_wrap(quads, radius, PI, 1.32, 1.66, .2, "poster1", 4)
	_wrap(quads, radius, PI - 1.15, 1.9, 1.98, .075, "sticker2", 2)
	_wrap(quads, radius, PI + 1.0, 1.14, 1.22, .075, "sticker5", 2)
	_wrap(quads, radius, .5, 2.12, 2.2, .07, "sticker7", 2)
	_wrap(quads, radius, PI * .5, .82, 1.0, .22, "tag1", 4)
	_wrap(quads, radius, -PI * .5, 2.5, 2.62, .06, "sticker0", 2)
	_meshes["lamp"] = _commit(quads)
	return _meshes["lamp"]


## Poste de concreto duplo T (HarborUtilityLines): abas planas em ±Z, meia largura hx(y) e
## meia profundidade hz(y) afinando até o topo. `height` muda a conicidade, então uma malha
## por altura de estilo.
static func concrete_mesh(height: float) -> ArrayMesh:
	var key := "concrete_%.2f" % height
	if _meshes.has(key): return _meshes[key]
	var hx := func(y: float) -> float: return lerpf(.11, .065, y / height)
	var hz := func(y: float) -> float: return lerpf(.15, .085, y / height)
	var quads: Array = []
	# Sujeira subindo do chão nas duas abas (respingo de rua e de chuva).
	for side in [1.0, -1.0]: _flange(quads, hx, hz, side, 0.0, .58, 0.0, 1.0, "grime%d" % (1 if side > 0 else 2))
	# Lado da calçada: lambe-lambe empilhado, adesivos, pichação e a placa de perigo.
	_flange(quads, hx, hz, -1.0, 1.24, 1.5, 0.0, .9, "poster0")
	_flange(quads, hx, hz, -1.0, 1.53, 1.79, 0.0, .9, "poster3")
	_flange(quads, hx, hz, -1.0, 1.98, 2.07, -.35, .45, "sticker3")
	_flange(quads, hx, hz, -1.0, .62, .84, 0.0, .95, "tag2")
	_flange(quads, hx, hz, -1.0, 2.3, 2.46, 0.0, .7, "plate_danger")
	# Lado da rua: plaqueta de número e ferrugem escorrendo dos parafusos.
	_flange(quads, hx, hz, 1.0, 2.5, 2.74, 0.0, .5, "plate_number")
	_flange(quads, hx, hz, 1.0, 3.1, 3.6, .3, .35, "rust1")
	_flange(quads, hx, hz, 1.0, 1.5, 1.58, -.2, .5, "sticker6")
	_meshes[key] = _commit(quads)
	return _meshes[key]


## Poste de madeira redondo (raio 15 cm no pé a 11 cm no topo): cartaz grampeado, adesivos,
## plaqueta, pichação e anel de sujeira/creosoto no pé.
static func wood_mesh(height: float) -> ArrayMesh:
	var key := "wood_%.2f" % height
	if _meshes.has(key): return _meshes[key]
	var radius := func(y: float) -> float: return lerpf(.15, .11, y / height)
	var quads: Array = []
	for index in 6: _wrap(quads, radius, TAU * index / 6.0, 0.0, .5, TAU * .15 / 6.0 * 1.02, "grime%d" % (index % 4), 1)
	_wrap(quads, radius, PI, 1.25, 1.62, .3, "poster2", 4)
	_wrap(quads, radius, PI + .9, 1.7, 1.95, .2, "poster1", 3)
	_wrap(quads, radius, PI - .9, 1.9, 1.98, .08, "sticker4", 2)
	_wrap(quads, radius, PI * .5, .66, .86, .3, "tag3", 4)
	_wrap(quads, radius, 0.0, 2.35, 2.6, .1, "plate_number", 2)
	_wrap(quads, radius, .9, 3.0, 3.5, .1, "rust2", 2)
	_meshes[key] = _commit(quads)
	return _meshes[key]


## Placa A-32b (HarborTrafficSigns): base no chão, poste de 3,5 cm de raio até 2,8 m, chapa em
## losango de 42 cm de meia diagonal no centro 2,63 m, costas em z = -1,75 cm. Adesivos nas
## costas e no poste, ferrugem no pé do poste.
static func sign_mesh() -> ArrayMesh:
	if _meshes.has("sign"): return _meshes["sign"]
	var radius := func(_y: float) -> float: return .035
	var quads: Array = []
	for index in 4: _wrap(quads, radius, TAU * index / 4.0 + PI * .25, 0.0, .2, TAU * .035 / 4.0 * 1.04, "rust%d" % index, 1)
	_wrap(quads, radius, PI, 1.32, 1.4, .09, "sticker1", 3)
	_wrap(quads, radius, 0.0, 1.62, 1.69, .09, "sticker4", 3)
	_wrap(quads, radius, PI * .5, 1.0, 1.18, .11, "tag0", 3)
	# Costas da chapa (normal -Z): conjunto de adesivos dentro do losango (|x|+|y| < 0,42).
	var back_z := -.0175 - GAP
	quads.append(_flat(Vector3(0, 2.6, back_z), Vector3(-1, 0, 0), Vector3.UP, Vector2(.3, .3), "sticker_cluster"))
	_meshes["sign"] = _commit(quads)
	return _meshes["sign"]


# --- Montagem das malhas -------------------------------------------------------------------

## Decalque enrolado num poste de raio radius(y), centrado no ângulo `angle` (0 = +Z local,
## crescendo para +X), entre y0 e y1, com `width` metros de arco em `facets` facetas.
static func _wrap(quads: Array, radius: Callable, angle: float, y0: float, y1: float, width: float, cell: String, facets: int) -> void:
	var r_mid: float = radius.call((y0 + y1) * .5)
	var span := width / maxf(r_mid, .01)
	var rect := uv(cell)
	for j in facets:
		var a0 := angle - span * .5 + span * float(j) / facets
		var a1 := angle - span * .5 + span * float(j + 1) / facets
		var at := func(a: float, y: float) -> Vector3:
			var r: float = radius.call(y) + GAP
			return Vector3(sin(a) * r, y, cos(a) * r)
		var u0 := rect.position.x + rect.size.x * float(j) / facets
		var u1 := rect.position.x + rect.size.x * float(j + 1) / facets
		var mid := (a0 + a1) * .5
		quads.append({"corners": [at.call(a0, y0), at.call(a0, y1), at.call(a1, y1), at.call(a1, y0)],
			"normal": Vector3(sin(mid), 0, cos(mid)), "tangent": Vector3(cos(mid), 0, -sin(mid)),
			"uv": Rect2(Vector2(u0, rect.position.y), Vector2(u1 - u0, rect.size.y))})


## Decalque numa aba do concreto (normal ±Z), entre y0 e y1, de u_center-largura... em fração
## da meia largura hx(y): `x_center` e `x_half` em [-1, 1], acompanhando a conicidade.
static func _flange(quads: Array, hx: Callable, hz: Callable, side: float, y0: float, y1: float, x_center: float, x_half: float, cell: String) -> void:
	var rect := uv(cell)
	# Vista de fora: para +Z a direita é +X; para -Z, -X (u × n, como no CityPropKit.box).
	var right := Vector3(side, 0, 0)
	var at := func(fx: float, y: float) -> Vector3:
		return Vector3(side * fx * float(hx.call(y)), y, side * (float(hz.call(y)) + GAP))
	var left := x_center - x_half
	var right_edge := x_center + x_half
	quads.append({"corners": [at.call(left, y0), at.call(left, y1), at.call(right_edge, y1), at.call(right_edge, y0)],
		"normal": Vector3(0, 0, side), "tangent": right, "uv": rect})


static func _flat(center: Vector3, right: Vector3, up: Vector3, size: Vector2, cell: String) -> Dictionary:
	var r := right * size.x * .5
	var u := up * size.y * .5
	return {"corners": [center - r - u, center - r + u, center + r + u, center + r - u],
		"normal": right.cross(up).normalized(), "tangent": right, "uv": uv(cell)}


## BL, TL, TR, BR vistos de fora; dois triângulos no sentido horário (frente no Godot).
static func _commit(quads: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for quad in quads:
		var base := vertices.size()
		var rect: Rect2 = quad.uv
		var corner_uv := [Vector2(rect.position.x, rect.end.y), rect.position, Vector2(rect.end.x, rect.position.y), rect.end]
		for k in 4:
			vertices.append(quad.corners[k])
			normals.append(quad.normal)
			var tangent: Vector3 = quad.tangent
			tangents.append_array([tangent.x, tangent.y, tangent.z, 1.0])
			uvs.append(corner_uv[k])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Material na superfície também: destroço/cópia fora do lote (sem override) continua certo.
	mesh.surface_set_material(0, material())
	return mesh
