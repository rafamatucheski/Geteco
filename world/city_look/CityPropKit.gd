extends RefCounted
## Malhas procedurais dos adereços urbanos (mobiliário, telhado, chão).
##
## Cada tipo vira UMA ArrayMesh com cor por vértice, montada uma vez e
## reutilizada em MultiMesh por chunk: centenas de hidrantes/lixeiras custam
## um draw call por tipo por chunk, não um por objeto. Medidas em metros,
## origem no chão, frente do objeto para +Z.

static var _meshes := {}
static var _material: StandardMaterial3D

# Peças modeladas no Blender (tools/blender/build_city_*.py), com o material do kit
# por cima. "0" volta às versões procedurais no mesmo export, para o A/B.
static var blender_props_enabled := OS.get_environment("GETECO_BLENDER_PROPS") != "0"
const BLENDER_SCENES := {
	"trash_can": preload("res://assets/city_props/trash_can.glb"),
	"hydrant": preload("res://assets/city_props/hydrant.glb"),
	"bench_seat": preload("res://assets/city_props/bench_seat.glb"),
	"phone_booth": preload("res://assets/city_props/phone_booth.glb"),
	"dumpster": preload("res://assets/city_props/dumpster.glb"),
	"news_box": preload("res://assets/city_props/news_box.glb"),
	"bollard": preload("res://assets/city_props/bollard.glb"),
	"mailbox": preload("res://assets/city_props/mailbox.glb"),
	"trash_bags": preload("res://assets/city_props/trash_bags.glb"),
	"planter": preload("res://assets/city_props/planter.glb"),
	# Não é tipo do kit: o CityChunkDressing pede haste e cabeça por blender_mesh().
	"sidewalk_lamp": preload("res://assets/city_props/sidewalk_lamp.glb"),
}
## Terceira onda (tools/blender/build_city_props_wave3.py): um .glb por lote, e o nó de
## cada tipo tem o nome do próprio tipo.
const WAVE3_SCENES := {
	"calcada": preload("res://assets/city_props/wave3_calcada.glb"),
	"sinal": preload("res://assets/city_props/wave3_sinal.glb"),
	"telhado": preload("res://assets/city_props/wave3_telhado.glb"),
	"fachada": preload("res://assets/city_props/wave3_fachada.glb"),
}
const WAVE3_KINDS := {
	"cafe_set": "calcada", "cafe_parasol": "calcada", "cafe_parasol_b": "calcada", "produce_stand": "calcada", "a_frame": "calcada", "beer_crates": "calcada", "wheelie_bins": "calcada", "bike_rack": "calcada", "pallet_stack": "calcada", "tire_stack": "calcada", "drums": "calcada", "food_cart": "calcada", "ice_freezer": "calcada", "clothes_rack": "calcada", "flower_buckets": "calcada", "gas_cylinders": "calcada", "door_bench": "calcada", "motorcycle": "calcada", "street_tree": "calcada", "street_tree_b": "calcada", "pot_plant": "calcada",
	"signal_pole": "sinal", "stop_sign": "sinal", "manhole": "sinal", "drain": "sinal", "hedge": "sinal",
	"ac_unit": "telhado", "vent": "telhado", "antenna": "telhado", "dish": "telhado", "roof_hatch": "telhado", "pipe_run": "telhado", "billboard_frame": "telhado", "water_tank": "telhado", "skylight": "telhado", "solar_row": "telhado", "cooling_tower": "telhado", "roof_shed": "telhado", "roof_chairs": "telhado", "roof_garden": "telhado",
	"window_ac": "fachada", "flower_box": "fachada", "fe_platform": "fachada", "fe_stair": "fachada", "fe_stair_m": "fachada", "fe_ladder": "fachada", "drainpipe": "fachada", "pigeons": "fachada", "laundry": "fachada", "posters": "fachada", "beacon_mast": "fachada", "satellite_row": "fachada", "awning_small": "fachada",
}
## Nó da peça inteira dentro do .glb; as partes soltas servem aos destroços.
const BLENDER_WHOLE := {"trash_can": "TrashCan", "hydrant": "Hydrant", "bench_seat": "BenchSeat",
	"phone_booth": "PhoneBooth", "dumpster": "Dumpster", "news_box": "NewsBox", "bollard": "Bollard",
	"mailbox": "Mailbox", "trash_bags": "TrashBags", "planter": "Planter"}
## Peças que usam o material de quem as desenha (o poste leva material liso por
## MultiMesh), sem o material de cor por vértice do kit.
const BLENDER_OWN_MATERIAL := ["sidewalk_lamp"]

# O comparativo da tarefa F usa o mesmo build; "0" restaura os detalhes originais.
static var detail_range_enabled := OS.get_environment("GETECO_DETAIL_RANGE") != "0"
const DETAIL_NEAR_DISTANCE := 40.0
const DETAIL_RANGE_MARGIN := 4.0
const DETAIL_PROP_KINDS := ["hydrant", "trash_can", "news_box", "mailbox", "trash_bags", "bollard", "bench_seat", "planter", "vent", "dish", "pipe_run", "window_ac", "flower_box", "pigeons", "laundry", "posters", "satellite_row", "roof_chairs",
	# Peças baixas do SidewalkFill (as de mesa, banca e árvore ficam de fora: dão volume de longe).
	"a_frame", "beer_crates", "pot_plant", "wheelie_bins", "bike_rack", "tire_stack", "drums", "clothes_rack", "flower_buckets", "gas_cylinders", "door_bench"]


static func apply_detail_range(instance: GeometryInstance3D) -> void:
	if not detail_range_enabled: return
	# O alcance usa o centro do AABB, não a peça mais próxima. Compensar o raio
	# preserva todos os detalhes até 40 m, inclusive lotes espalhados pelo chunk.
	var bounds := instance.get_aabb()
	var world_size := (instance.global_transform * bounds).size if instance.is_inside_tree() else (instance.transform * bounds).size
	instance.visibility_range_end = DETAIL_NEAR_DISTANCE + DETAIL_RANGE_MARGIN + world_size.length() * 0.5
	instance.visibility_range_end_margin = DETAIL_RANGE_MARGIN
	# Mobile não suporta fade de alcance. Histerese evita oscilar no limite;
	# Forward+ pode suavizar a transição sem começar a ocultar antes de 40 m.
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if forward_plus else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func apply_chunk_detail(child: Node) -> void:
	if not detail_range_enabled or not child is MultiMeshInstance3D: return
	var kind := String(child.name).trim_prefix("CityLook_")
	if not kind in DETAIL_PROP_KINDS: return
	if child.multimesh == null or child.multimesh.mesh == null: return
	apply_detail_range(child)


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		# Cores do kit são escritas em sRGB (hex); sem isto saíam desbotadas.
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.82
	return _material


## Adereços em camadas: cada camada vira uma superfície com textura própria
## (granito, folhagem, plástico), em vez da cor lisa do kit, que deixava vaso e
## sacos com cara de brinquedo. Quem desenha estes tipos não põe material_override.
const LAYERED := {"planter": ["stone", "leaves"], "trash_bags": ["plastic"], "hedge": ["leaves"],
	# SidewalkFillKit: árvore de rua e vaso de porta.
	"street_tree": ["bark", "leaves"], "street_tree_b": ["bark", "leaves"], "pot_plant": ["stone", "leaves"]}
const FLORA := preload("res://assets/urban_detail/FloraSurfaces.gd")


## Material do MultiMesh deste tipo; null deixa valer o material de cada superfície.
static func material_for(kind: String) -> StandardMaterial3D:
	return null if LAYERED.has(kind) else material()


## Mesmas opções do FloraSurfaces.bark() (cor de vértice sRGB, triplanar, relevo e
## rugosidade por textura): só textura e valores mudam, então o shader é o mesmo que
## as árvores do porto já compilaram e não há variante nova para pré-aquecer.
static func layer_material(layer: String) -> StandardMaterial3D:
	match layer:
		"stone": return FLORA.material("granite", Color.WHITE, 1.1, 0.9, 0.93, true)
		"bark": return FLORA.bark()
		"leaves": return FLORA.material("foliage", Color.WHITE, 0.55, 1.2, 0.96, true)
		_: return FLORA.material("fabric", Color.WHITE, 0.45, 1.6, 0.48, true)


static func _layered_mesh(kind: String) -> ArrayMesh:
	var result := ArrayMesh.new()
	for layer: String in LAYERED[kind]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(layer_material(layer))
		tool.set_smooth_group(-1)
		match kind + ":" + layer:
			"planter:stone": _planter_stone(tool)
			"planter:leaves": _planter_leaves(tool)
			"trash_bags:plastic": _trash_bags(tool)
			"hedge:leaves": _hedge(tool)
			_: preload("res://world/city_look/SidewalkFillKit.gd").build_layer(kind, layer, tool)
		tool.generate_normals()
		tool.commit(result)
	return result


static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind): return _meshes[kind]
	if blender_props_enabled and (BLENDER_WHOLE.has(kind) or WAVE3_KINDS.has(kind)):
		_meshes[kind] = blender_mesh(kind, BLENDER_WHOLE.get(kind, kind))
		return _meshes[kind]
	if LAYERED.has(kind):
		_meshes[kind] = _layered_mesh(kind)
		return _meshes[kind]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Destroços reutilizam a malha fora do MultiMeshInstance e de seu override.
	tool.set_material(material())
	# Normais facetadas: sem isso o generate_normals suaviza as quinas das
	# caixas e tudo fica com cara de sabonete.
	tool.set_smooth_group(-1)
	match kind:
		"hydrant": _hydrant(tool)
		"trash_can": _trash_can(tool)
		"news_box": _news_box(tool)
		"mailbox": _mailbox(tool)
		"phone_booth": _phone_booth(tool)
		"dumpster": _dumpster(tool)
		"bollard": _bollard(tool)
		"signal_pole": _signal_pole(tool)
		"stop_sign": _stop_sign(tool)
		"ac_unit": _ac_unit(tool)
		"vent": _vent(tool)
		"antenna": _antenna(tool)
		"dish": _dish(tool)
		"roof_hatch": _roof_hatch(tool)
		"pipe_run": _pipe_run(tool)
		"billboard_frame": _billboard_frame(tool)
		"manhole": _manhole(tool)
		"drain": _drain(tool)
		"bench_seat": _bench_seat(tool)
		_:
			var fill := preload("res://world/city_look/SidewalkFillKit.gd")
			if kind in fill.KINDS: fill.build(kind, tool)
			else: preload("res://world/city_look/BuildingLifeKit.gd").build(kind, tool)
	tool.generate_normals()
	var result := tool.commit()
	_meshes[kind] = result
	return result


## Variação por cópia na rua, para a calçada não repetir a mesma peça igualzinha:
## "colors" é a paleta (multiplica a cor de vértice; as partes "pintáveis" dos modelos
## são claras, as de metal e borracha escuras e quase não mudam) e "scale" é quanto cada
## eixo pode crescer ou encolher. Tudo continua numa MultiMesh por tipo e por chunk
## (cor por instância), então não custa draw call. Só vale com as peças do Blender.
const VARIATION := {
	"cafe_set": {"colors": [Color("c23b2e"), Color("2f7a55"), Color("2d6fb6"), Color("e3b02e"), Color("ececec")], "scale": Vector3(0.04, 0.05, 0.04)},
	"cafe_parasol": {"colors": [Color("c23b2e"), Color("2f7a55"), Color("2d6fb6"), Color("e3b02e"), Color("e07a2e")], "scale": Vector3(0.04, 0.05, 0.04)},
	"cafe_parasol_b": {"colors": [Color("2f7a55"), Color("c23b2e"), Color("3a5a8a"), Color("d8b03a"), Color("7a3a5a")], "scale": Vector3(0.04, 0.05, 0.04)},
	"produce_stand": {"colors": [Color("ffffff"), Color("f0e6d8"), Color("e6dccb")], "scale": Vector3(0.06, 0.05, 0.05)},
	"a_frame": {"colors": [Color("ffffff"), Color("eadfcc"), Color("d8e0e4")], "scale": Vector3(0.05, 0.08, 0.03)},
	"beer_crates": {"colors": [Color("b23a2e"), Color("c9a634"), Color("2f6b4f"), Color("2d6fb6")], "scale": Vector3(0.03, 0.03, 0.03)},
	"wheelie_bins": {"colors": [Color("3e6b48"), Color("5d6366"), Color("2d4f7a"), Color("8a4a2a"), Color("3a3a3a")], "scale": Vector3(0.04, 0.06, 0.04)},
	"bike_rack": {"colors": [Color("ffffff"), Color("dfe8ff"), Color("ffe0dc")], "scale": Vector3(0.0, 0.0, 0.0)},
	"pallet_stack": {"colors": [Color("ffffff"), Color("e8dcc8"), Color("d8ccb8")], "scale": Vector3(0.03, 0.1, 0.03)},
	"tire_stack": {"colors": [Color("ffffff")], "scale": Vector3(0.05, 0.08, 0.05)},
	"drums": {"colors": [Color("2c5a8a"), Color("8e3a2a"), Color("6d5a3a"), Color("2f6b4f"), Color("c9a634")], "scale": Vector3(0.04, 0.04, 0.04)},
	"food_cart": {"colors": [Color("c23b2e"), Color("e3b02e"), Color("2d6fb6"), Color("2f7a55")], "scale": Vector3(0.03, 0.03, 0.03)},
	"ice_freezer": {"colors": [Color("ffffff"), Color("dfe9ff"), Color("ffe9d6")], "scale": Vector3(0.05, 0.04, 0.04)},
	"flower_buckets": {"colors": [Color("ffffff"), Color("e8ecf0"), Color("f4e8dc")], "scale": Vector3(0.04, 0.06, 0.04)},
	"gas_cylinders": {"colors": [Color("4a6f8c"), Color("5d6366"), Color("8e3a2a"), Color("2f6b4f"), Color("c9a634")], "scale": Vector3(0.03, 0.05, 0.03)},
	"door_bench": {"colors": [Color("ffffff"), Color("e8dcc8"), Color("d0c4b0")], "scale": Vector3(0.06, 0.04, 0.04)},
	"motorcycle": {"colors": [Color("a8322b"), Color("2d6fb6"), Color("2f2f33"), Color("e3b02e"), Color("2f7a55")], "scale": Vector3(0.03, 0.03, 0.03)},
	"street_tree": {"colors": [Color("ffffff"), Color("e8f0dc"), Color("f4ecd0"), Color("dfe6e0")], "scale": Vector3(0.12, 0.12, 0.12)},
	"street_tree_b": {"colors": [Color("ffffff"), Color("e8f0dc"), Color("f4ecd0"), Color("dfe6e0")], "scale": Vector3(0.12, 0.12, 0.12)},
	"pot_plant": {"colors": [Color("ffffff"), Color("f2e0d4"), Color("e4e8ec")], "scale": Vector3(0.1, 0.12, 0.1)},
	"hedge": {"colors": [Color("ffffff"), Color("e8f0dc"), Color("dfe8d8")], "scale": Vector3(0.06, 0.15, 0.08)},
	"ac_unit": {"colors": [Color("ffffff"), Color("e6ebe8"), Color("f2ede2"), Color("dde3e8")], "scale": Vector3(0.05, 0.05, 0.05)},
	"vent": {"colors": [Color("ffffff"), Color("e8e4dc")], "scale": Vector3(0.08, 0.15, 0.08)},
	"water_tank": {"colors": [Color("ffffff"), Color("e8dcc8"), Color("d8d0c0")], "scale": Vector3(0.05, 0.06, 0.05)},
	"cooling_tower": {"colors": [Color("ffffff"), Color("e6ebe8"), Color("dde3e8")], "scale": Vector3(0.04, 0.04, 0.04)},
	"roof_shed": {"colors": [Color("a39b8c"), Color("8e9aa0"), Color("b0a08a"), Color("9fa8a0"), Color("c4b8a4")], "scale": Vector3(0.08, 0.05, 0.08)},
	"roof_chairs": {"colors": [Color("2f7bbf"), Color("e0b23c"), Color("c23b2e"), Color("2f7a55")], "scale": Vector3(0.0, 0.0, 0.0)},
	"roof_garden": {"colors": [Color("ffffff"), Color("e8f0dc")], "scale": Vector3(0.04, 0.06, 0.04)},
	"window_ac": {"colors": [Color("ffffff"), Color("e6ebe8"), Color("f2ede2")], "scale": Vector3(0.06, 0.06, 0.0)},
	"flower_box": {"colors": [Color("ffffff"), Color("e8dcd0"), Color("dce6ec")], "scale": Vector3(0.08, 0.0, 0.0)},
	"awning_small": {"colors": [Color("b8352f"), Color("2f7a55"), Color("2d6fb6"), Color("e3b02e"), Color("5a3a6a")], "scale": Vector3(0.0, 0.0, 0.0)},
}


static func variation_for(kind: String) -> Dictionary:
	return VARIATION.get(kind, {}) if blender_props_enabled else {}


## [transform com a proporção mudada, cor da paleta]. A escolha sai da posição (e de
## `salt`), não de sorteio: a mesma peça volta igual quando o chunk recarrega.
static func vary(kind: String, placement: Transform3D, salt := 0) -> Array:
	var spec := variation_for(kind)
	if spec.is_empty(): return [placement, Color.WHITE]
	var key := hash([kind, roundi(placement.origin.x * 10.0), roundi(placement.origin.z * 10.0), salt])
	var colors: Array = spec.get("colors", [Color.WHITE])
	var color: Color = colors[posmod(key, colors.size())]
	var spread: Vector3 = spec.get("scale", Vector3.ZERO)
	var unit := func(shift: int) -> float: return float(posmod(key >> shift, 1000)) / 999.0 * 2.0 - 1.0
	var stretch := Vector3(1.0 + spread.x * unit.call(3), 1.0 + spread.y * unit.call(11), 1.0 + spread.z * unit.call(19))
	return [Transform3D(placement.basis * Basis.from_scale(stretch), placement.origin), color]


## Malha de um nó do .glb do Blender. O .glb sai sem UV, tangente nem material, só
## posição, normal e cor por vértice, como as procedurais: com material() por cima o
## shader é o mesmo, então não há variante nova para pré-aquecer. A cena é pequena e já
## vem pré-carregada; instanciar uma vez por peça custa menos que montar à mão.
## Peças em camadas saem do Blender com uma superfície por camada, na ordem de LAYERED.
static func blender_mesh(kind: String, part: String) -> ArrayMesh:
	var key := kind + ":" + part
	if _meshes.has(key): return _meshes[key]
	var packed: PackedScene = WAVE3_SCENES[WAVE3_KINDS[kind]] if WAVE3_KINDS.has(kind) else BLENDER_SCENES[kind]
	var result := _scene_meshes(packed)[part] as ArrayMesh
	if LAYERED.has(kind):
		for index in result.get_surface_count(): result.surface_set_material(index, layer_material(LAYERED[kind][index]))
	elif not kind in BLENDER_OWN_MATERIAL:
		result.surface_set_material(0, material())
	_meshes[key] = result
	return result


## Malhas de uma cena do Blender por nome de nó. Cada .glb é instanciado uma vez só: os
## de lote têm dezenas de tipos, e instanciar o lote inteiro por tipo custava à toa.
static var _scene_index := {}

static func _scene_meshes(packed: PackedScene) -> Dictionary:
	if _scene_index.has(packed.resource_path): return _scene_index[packed.resource_path]
	var index := {}
	var scene := packed.instantiate()
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		index[String(node.name)] = node.mesh
	scene.free()
	_scene_index[packed.resource_path] = index
	return index


# --- Primitivas ---

static func box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
	var h := size * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	tool.set_color(color)
	for face in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		# Ordem conferida com generate_normals: normal para fora.
		tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
		tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(d)


static func cylinder(tool: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, sides := 8, top_radius := -1.0) -> void:
	var top := radius if top_radius < 0.0 else top_radius
	tool.set_color(color)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + d0 * radius
		var b1 := base + d1 * radius
		var t0 := base + d0 * top + Vector3.UP * height
		var t1 := base + d1 * top + Vector3.UP * height
		tool.add_vertex(b0); tool.add_vertex(b1); tool.add_vertex(t0)
		tool.add_vertex(b1); tool.add_vertex(t1); tool.add_vertex(t0)
		var cap := base + Vector3.UP * height
		tool.add_vertex(cap); tool.add_vertex(t0); tool.add_vertex(t1)


## Volume orgânico baixo (tufo de folhagem, saco cheio): dois anéis irregulares
## e um polo, sem fundo porque sempre apoia em terra ou chão. Topo achatado e
## contorno torto de propósito: a versão lisa e simétrica lia como bola de
## brinquedo. Cada triângulo leva um tom levemente diferente (folha ao sol e à
## sombra); a textura do material faz o resto de perto.
## `variant` gira e deforma cada cópia; `tip` puxa o polo (nó do saco de lixo).
## Com 6 lados são 30 triângulos.
static func blob(tool: SurfaceTool, base: Vector3, radius: Vector2, height: float, color: Color, sides := 6, variant := 0, tip := 0.0, roughness := 0.2) -> void:
	# [altura relativa, raio relativo, clareamento]: base mais escura, topo mais claro.
	var rings := [[0.0, 0.92, -0.16], [0.48, 1.04, -0.04], [0.82, 0.72, 0.06]]
	var points := []
	for r in rings.size():
		var row := []
		for i in sides:
			var angle := TAU * (float(i) + 0.35 * sin(float(i * 3 + variant))) / sides + float(variant) * 0.9
			var wobble := 1.0 + roughness * sin(float(i * 7 + variant * 5 + r * 11) * 1.3)
			var reach: float = rings[r][1] * wobble
			var lift: float = rings[r][0] + (0.0 if r == 0 else roughness * 0.35 * sin(float(i * 5 + variant * 3)))
			row.append(base + Vector3(cos(angle) * radius.x * reach, height * lift, sin(angle) * radius.y * reach))
		points.append(row)
	var face := 0
	for r in rings.size() - 1:
		for i in sides:
			var j := (i + 1) % sides
			var l0: Vector3 = points[r][i]
			var l1: Vector3 = points[r][j]
			var u0: Vector3 = points[r + 1][i]
			var u1: Vector3 = points[r + 1][j]
			tool.set_color(_mottle(color, rings[r][2], face, variant)); face += 1
			tool.add_vertex(l0); tool.add_vertex(l1); tool.add_vertex(u0)
			tool.set_color(_mottle(color, rings[r][2], face, variant)); face += 1
			tool.add_vertex(l1); tool.add_vertex(u1); tool.add_vertex(u0)
	var pole := base + Vector3.UP * height * (0.94 + tip)
	for i in sides:
		tool.set_color(_mottle(color, rings[-1][2] + 0.04, face, variant)); face += 1
		tool.add_vertex(pole); tool.add_vertex(points[-1][i]); tool.add_vertex(points[-1][(i + 1) % sides])


## Tom por triângulo: a maioria um pouco mais escura, uma ou outra mais clara.
static func _mottle(color: Color, amount: float, face: int, variant: int) -> Color:
	var noise := fposmod(sin(float(face * 37 + variant * 101) * 12.9898) * 43758.5453, 1.0)
	return _shade(color, amount + (noise - 0.6) * 0.14)


static func _shade(color: Color, amount: float) -> Color:
	return color.lightened(amount) if amount > 0.0 else color.darkened(-amount)


# --- Mobiliário de calçada ---

static func _hydrant(t: SurfaceTool) -> void:
	var red := Color("b8322a")
	cylinder(t, Vector3.ZERO, .17, .08, Color("7c2520"), 6)
	cylinder(t, Vector3(0, .08, 0), .12, .5, red, 6)
	cylinder(t, Vector3(0, .58, 0), .14, .08, red, 6, .06)
	box(t, Vector3(0, .38, 0), Vector3(.42, .09, .09), Color("d8c24a"))
	box(t, Vector3(0, .38, .12), Vector3(.09, .09, .1), Color("d8c24a"))


static func _trash_can(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .26, .82, Color("2f5a43"), 7, .29)
	cylinder(t, Vector3(0, .82, 0), .31, .06, Color("1f3a2c"), 7)
	cylinder(t, Vector3(0, .88, 0), .22, .05, Color("16261e"), 7)


static func _news_box(t: SurfaceTool) -> void:
	box(t, Vector3(-.26, .55, 0), Vector3(.46, .75, .42), Color("c63a2f"))
	box(t, Vector3(-.26, .72, .215), Vector3(.36, .22, .02), Color("dfe7e8"))
	box(t, Vector3(.26, .55, 0), Vector3(.46, .75, .42), Color("2d6fb6"))
	box(t, Vector3(.26, .72, .215), Vector3(.36, .22, .02), Color("dfe7e8"))
	for x in [-.44, -.08, .08, .44]: box(t, Vector3(x, .09, 0), Vector3(.04, .18, .36), Color("2a2e30"))


static func _mailbox(t: SurfaceTool) -> void:
	box(t, Vector3(0, .1, 0), Vector3(.5, .2, .44), Color("1d2a55"))
	box(t, Vector3(0, .62, 0), Vector3(.5, .84, .44), Color("27418a"))
	box(t, Vector3(0, 1.08, 0), Vector3(.46, .12, .4), Color("27418a"))
	box(t, Vector3(0, .9, .225), Vector3(.3, .05, .02), Color("0f152b"))
	box(t, Vector3(0, .6, .225), Vector3(.26, .14, .02), Color("e6e2d4"))


static func _phone_booth(t: SurfaceTool) -> void:
	box(t, Vector3(0, .06, 0), Vector3(.9, .12, .9), Color("5b6063"))
	for x in [-.41, .41]: box(t, Vector3(x, 1.15, 0), Vector3(.08, 2.1, .9), Color("8a9396"))
	box(t, Vector3(0, 1.15, -.41), Vector3(.9, 2.1, .08), Color("8a9396"))
	box(t, Vector3(0, 2.26, 0), Vector3(.98, .16, .98), Color("c9a634"))
	box(t, Vector3(0, 1.25, -.34), Vector3(.34, .5, .1), Color("2c3134"))
	box(t, Vector3(0, 2.26, .5), Vector3(.7, .12, .02), Color("f3efe0"))


static func _dumpster(t: SurfaceTool) -> void:
	var body := Color("2f6b4f")
	box(t, Vector3(0, .62, 0), Vector3(1.9, 1.05, 1.1), body)
	box(t, Vector3(0, 1.17, -.05), Vector3(1.95, .08, 1.2), Color("24523c"), 0.0)
	box(t, Vector3(0, .9, .56), Vector3(1.7, .1, .04), Color("1c3c2d"))
	for x in [-.8, .8]:
		for z in [-.45, .45]: cylinder(t, Vector3(x, 0, z), .07, .1, Color("222"))
	box(t, Vector3(.95, .7, 0), Vector3(.06, .14, .9), Color("1c3c2d"))


static func _trash_bags(t: SurfaceTool) -> void:
	# Sacos estufados com o nó puxado para cima; o plástico (textura "fabric",
	# rugosidade baixa) dá vinco e brilho. Caixa de papelão desbotada ao lado.
	blob(t, Vector3.ZERO, Vector2(.3, .27), .44, Color("1a1c1e"), 6, 0, .16, .14)
	blob(t, Vector3(.42, 0, .12), Vector2(.25, .23), .38, Color("222528"), 6, 3, .18, .14)
	blob(t, Vector3(.18, 0, -.34), Vector2(.24, .22), .34, Color("2c3327"), 6, 6, .18, .14)
	box(t, Vector3(-.4, .16, .2), Vector3(.4, .32, .34), Color("7d6a50"), .4)


static func _bollard(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .11, .85, Color("2e3336"), 8)
	cylinder(t, Vector3(0, .62, 0), .115, .1, Color("d6b43c"), 8)


static func _bench_seat(t: SurfaceTool) -> void:
	preload("res://world/urban_detail/BenchFinish.gd").append_to(t, 1.7, .44, .49, .93)


## Vaso de granito de Harbor (tom das jardineiras do porto, #6e736b, um pouco mais
## escuro porque a textura clareia): corpo,
## tampa um pouco mais larga e clara que marca a borda, e a terra só como face
## de cima, 1 cm acima da tampa para não piscar.
static func _planter_stone(t: SurfaceTool) -> void:
	box(t, Vector3(0, .21, 0), Vector3(1.02, .42, 1.02), Color("5f625d"))
	box(t, Vector3(0, .46, 0), Vector3(1.1, .08, 1.1), Color("71746e"))
	t.set_color(Color("2a241e"))
	var soil := [Vector3(-.43, .51, -.43), Vector3(.43, .51, -.43), Vector3(.43, .51, .43), Vector3(-.43, .51, .43)]
	# Mesma ordem da face de cima de box(): normal para +Y.
	for index in [0, 1, 2, 0, 2, 3]: t.add_vertex(soil[index])


## Verdes do porto: o marítimo #3d5945 do HarborRouteMaterials puxado para o
## cinza e o oliva (a textura de folhagem ainda clareia e satura um pouco).
const HARBOR_LEAVES := ["37443b", "3f4b3e", "333f37", "454a39", "3a4636"]


## Moita do vaso: sete tufos pequenos de alturas diferentes, mais altos no meio.
## Tufo grande e único lia como pedra facetada ou bola.
static func _planter_leaves(t: SurfaceTool) -> void:
	var spots := [Vector2(0, 0), Vector2(.24, .1), Vector2(-.22, .16), Vector2(.12, -.24), Vector2(-.18, -.2), Vector2(.02, .27), Vector2(.28, -.14)]
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var size := .2 - spot.length() * .12
		var height := .44 - spot.length() * .42 + .05 * float(i % 3)
		blob(t, Vector3(spot.x, .5, spot.y), Vector2(size, size * .92), height, Color(HARBOR_LEAVES[i % HARBOR_LEAVES.size()]), 5, i * 2 + 1, 0.0, .26)


## Fileira de tufos para jardineira de 1,65 m (fachadas das casas). Uma malha
## compartilhada no lugar de cinco cilindros de 12 lados: 175 triângulos, não 480.
static func _hedge(t: SurfaceTool) -> void:
	for i in 7:
		var x := -.66 + i * .22
		blob(t, Vector3(x, 0, .04 * float(i % 2 * 2 - 1)), Vector2(.16, .15), .26 + .07 * float((i * 5) % 3), Color(HARBOR_LEAVES[i % HARBOR_LEAVES.size()]), 5, i + 2, 0.0, .26)


# --- Sinalização viária ---

## Poste de semáforo com braço sobre a via. Braço para -X; a cabeça do sinal
## fica separada (malha emissiva que pisca) e é posicionada pelo chamador.
static func _signal_pole(t: SurfaceTool) -> void:
	var metal := Color("2d3437")
	cylinder(t, Vector3.ZERO, .16, .3, Color("3c4447"), 8)
	cylinder(t, Vector3.ZERO, .09, 5.2, metal, 8)
	box(t, Vector3(-2.1, 5.05, 0), Vector3(4.2, .1, .1), metal)
	box(t, Vector3(-.5, 4.75, 0), Vector3(1.0, .06, .06), metal, 0.0)
	# Caixa do sinal pendurada no braço (as lentes vêm do CityChunkDressing).
	box(t, Vector3(-3.3, 4.55, 0), Vector3(.36, 1.0, .3), Color("1f2426"))
	box(t, Vector3(-3.3, 4.55, .17), Vector3(.5, 1.14, .04), Color("15191a"))
	# Placa de nome de rua (verde, padrão americano do Harbor).
	box(t, Vector3(.0, 3.2, 0), Vector3(1.3, .26, .03), Color("1f6b3e"))
	box(t, Vector3(.0, 3.2, 0), Vector3(1.22, .18, .035), Color("2a8a50"))
	# Botoeira de pedestre.
	box(t, Vector3(.13, 1.1, 0), Vector3(.1, .2, .12), Color("c9a634"))


static func _stop_sign(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .04, 2.2, Color("8a9396"), 6)
	# Octógono aproximado por quatro barras giradas em 45°.
	var red := Color("c0231e")
	var face_z := .05
	for i in 4:
		var angle := PI / 4.0 * i
		var basis := Basis(Vector3.FORWARD, angle)
		var center := Vector3(0, 2.2, face_z)
		var size := Vector3(.72, .3, .03)
		_rotated_box(t, center, size, red, basis)
	box(t, Vector3(0, 2.2, face_z + .02), Vector3(.5, .1, .01), Color("f4f1e8"))


static func _rotated_box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	t.set_color(color)
	for face in faces:
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[1]]); t.add_vertex(corners[face[2]])
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[2]]); t.add_vertex(corners[face[3]])


# --- Telhado ---

static func _ac_unit(t: SurfaceTool) -> void:
	box(t, Vector3(0, .05, 0), Vector3(1.3, .1, 1.0), Color("5a5f61"))
	box(t, Vector3(0, .45, 0), Vector3(1.2, .7, .9), Color("b9bdb8"))
	box(t, Vector3(.61, .45, 0), Vector3(.02, .5, .7), Color("6c7274"))
	cylinder(t, Vector3(-.2, .8, 0), .3, .04, Color("3a3f41"), 10)
	box(t, Vector3(-.2, .85, 0), Vector3(.5, .02, .06), Color("8a8f90"))


static func _vent(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .16, .7, Color("9aa0a2"), 8)
	cylinder(t, Vector3(0, .7, 0), .3, .1, Color("7e8486"), 8, .08)


static func _antenna(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .04, 2.6, Color("5a6063"), 5)
	for y in [1.6, 2.0, 2.35]: box(t, Vector3(0, y, 0), Vector3(1.0 - (y - 1.6) * .6, .03, .03), Color("5a6063"))


static func _dish(t: SurfaceTool) -> void:
	box(t, Vector3(0, .3, 0), Vector3(.08, .6, .08), Color("6c7274"))
	cylinder(t, Vector3(0, .5, .05), .05, .06, Color("dfe0dc"), 10, .42)


static func _roof_hatch(t: SurfaceTool) -> void:
	box(t, Vector3(0, .2, 0), Vector3(1.0, .4, 1.0), Color("7d8284"))
	box(t, Vector3(0, .43, 0), Vector3(.9, .06, .9), Color("4b5052"))


static func _pipe_run(t: SurfaceTool) -> void:
	for x in [-.12, .12]: box(t, Vector3(x, .14, 0), Vector3(.12, .12, 4.0), Color("8f5a3a"))
	for z in [-1.8, 0.0, 1.8]: box(t, Vector3(0, .05, z), Vector3(.5, .1, .12), Color("4b5052"))


## Estrutura de outdoor de telhado: dois pés e passarela. O painel com a marca
## é montado por cima pelo CityChunkDressing (material/texto por marca).
static func _billboard_frame(t: SurfaceTool) -> void:
	var steel := Color("3a4043")
	for x in [-2.4, 2.4]:
		box(t, Vector3(x, 1.2, 0), Vector3(.14, 2.4, .14), steel)
		box(t, Vector3(x, 1.0, -.8), Vector3(.1, 2.0, .1), steel)
		box(t, Vector3(x, 1.2, -.4), Vector3(.06, .06, .9), steel)
	box(t, Vector3(0, 1.2, .18), Vector3(5.4, .06, .5), Color("2a2f31"))
	box(t, Vector3(0, 2.4, 0), Vector3(6.2, 3.1, .12), Color("1d2123"))
	# Três refletores voltados para o painel.
	for x in [-2.0, 0.0, 2.0]: box(t, Vector3(x, 1.28, .5), Vector3(.2, .14, .2), Color("55595b"))


# --- Chão ---

static func _manhole(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .42, .015, Color("2a2c2c"), 10)
	cylinder(t, Vector3(0, .0, 0), .34, .02, Color("3d403f"), 10)
	for z in [-.16, 0.0, .16]: box(t, Vector3(0, .02, z), Vector3(.5, .006, .05), Color("2a2c2c"))


static func _drain(t: SurfaceTool) -> void:
	box(t, Vector3(0, .008, 0), Vector3(.9, .016, .4), Color("2c2f30"))
	for x in [-.3, -.15, 0.0, .15, .3]: box(t, Vector3(x, .018, 0), Vector3(.06, .006, .34), Color("111314"))
