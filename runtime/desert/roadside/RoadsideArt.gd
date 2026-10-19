extends RefCounted
## Peças de arte da beira de estrada (passe gráfico de 19/10/2026 sobre o greybox de 644b67c3):
## materiais, o lote de malha por material, as carcaças de carro e a luz do lugar.
##
## Por que um lote próprio em vez de G.box: o greybox tinha ~60 caixas por lugar, uma malha e um
## desenho por caixa, sem UV útil (BoxMesh espalha as seis faces num atlas 3x2). Aqui cada lugar
## vira UMA malha por material, com UV em metros (chapa corrugada repete do tamanho certo) ou no
## retângulo do atlas pintado (placa com nome). A montagem dos vértices sai do quadro: o
## pré-aquecimento das fachadas pintadas compõe os quatro lugares sob a cortina e o jogo só cria
## os nós (RoadsideBuild.prewarm).
##
## Nenhum shader novo: o atlas usa as mesmas opções do material de parede do PaintedFacadeKit
## (textura, rugosidade, emissão por máscara acesa pelo relógio de PaintedWindow); chapa e
## concreto reaproveitam materiais já existentes; cor chapada é o G.material de sempre.
const G := preload("res://world/desert/DesertGeometry.gd")
const TOWN := preload("res://world/desert/DesertTownMaterials.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const ATLAS := "res://assets/roadside/roadside_atlas"
static var _atlas: StandardMaterial3D
static var _uv: Dictionary = {}
## id do modelo → [{"mesh", "xform", "roles"}] sem rodas (carcaça), extraído uma vez.
static var _wreck_parts: Dictionary = {}
static var _paints: Dictionary = {}

# --- Materiais --------------------------------------------------------------------------------

## Placas, letreiros e pinturas do lanche. Mesmas opções do material de parede pintada: o shader
## já existe; a máscara acende à noite pelo relógio das janelas.
static func atlas() -> StandardMaterial3D:
	if _atlas == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(ATLAS + ".jpg")
		mat.roughness = 0.88
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.emission_enabled = true
		mat.emission = Color.BLACK
		mat.emission_texture = load(ATLAS + "_glow.jpg")
		PaintedWindow.register_night(mat)
		_atlas = mat
	return _atlas

static func uv(panel: String) -> Rect2:
	if _uv.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS + ".json"))
		if parsed is Dictionary: _uv = parsed.get("uv", {})
	var rect: Array = _uv.get(panel, [0.0, 0.0, 1.0, 1.0])
	return Rect2(rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1])

## Trecho [a, b] (0..1) da largura de um painel: faixa comprida repartida entre lados.
static func uv_span(panel: String, a: float, b: float) -> Rect2:
	var rect := uv(panel)
	return Rect2(rect.position.x + rect.size.x * a, rect.position.y, rect.size.x * (b - a), rect.size.y)

## Chapa corrugada das fachadas pintadas (telhado: dupla face, sem emissão), já pré-aquecida.
static func rust_sheet() -> Material: return PaintedFacadeKit.material("galpao-deserto", "roof")
static func white_sheet() -> Material: return PaintedFacadeKit.material("escritorio-mina", "roof")
static func concrete() -> Material: return TOWN.material("chalk")
## Mesmo material do asfalto das estradas do deserto (DesertRegion.prewarm).
static func asphalt() -> Material: return G.material(Color("706d61"), false, true)
static func gravel(tint: Color) -> Material: return G.material(tint, true)
static func color(tint: Color) -> Material: return G.material(tint)

# --- Lote de malha ----------------------------------------------------------------------------

## Junta caixas, cilindros e quadros por material e entrega uma malha por material. Só dados
## (PackedArrays): pode ser composto sob a cortina e reaproveitado na montagem.
class Batch:
	const FACES := [
		# normal, direita e cima vistos de fora (direita × cima = normal: ordem horária do Godot).
		["+z", Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		["-z", Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		["+x", Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		["-x", Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		["+y", Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		["-y", Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	## Material do atlas pintado, para as faces que recebem um Rect2.
	var atlas: Material
	var groups: Dictionary = {}
	var order: Array = []
	## [Transform3D, Vector3 tamanho] de cada caixa sólida (colisão).
	var solids: Array = []

	func _group(mat: Material) -> Dictionary:
		var id := mat.get_instance_id()
		if not groups.has(id):
			groups[id] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedVector2Array(), "i": PackedInt32Array()}
			order.append(id)
		return groups[id]

	## Quadro de centro `c` com meia-largura `right` e meia-altura `up` (vistos de frente).
	func quad(mat: Material, c: Vector3, right: Vector3, up: Vector3, rect: Rect2) -> void:
		var g := _group(mat)
		var base: int = g.v.size()
		var normal := right.cross(up).normalized()
		g.v.append(c - right + up)
		g.v.append(c + right + up)
		g.v.append(c + right - up)
		g.v.append(c - right - up)
		for k in 4: g.n.append(normal)
		g.t.append(rect.position)
		g.t.append(Vector2(rect.end.x, rect.position.y))
		g.t.append(rect.end)
		g.t.append(Vector2(rect.position.x, rect.end.y))
		g.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## Caixa em `xf` (base pode girar). `skin` troca faces: "+z" → Rect2 do atlas, Material
	## (UV em metros/`tile`) ou null (face omitida, ex. o fundo apoiado no chão).
	func box(mat: Material, xf: Transform3D, size: Vector3, skin := {}, tile := Vector2(2, 2)) -> void:
		var half := size * 0.5
		for face in FACES:
			var key: String = face[0]
			var choice: Variant = skin.get(key, mat)
			if choice == null: continue
			var n: Vector3 = face[1]
			var r: Vector3 = face[2]
			var u: Vector3 = face[3]
			var extent_r := absf(r.dot(half))
			var extent_u := absf(u.dot(half))
			var center := xf * (n * absf(n.dot(half)))
			var right := xf.basis * (r * extent_r)
			var up := xf.basis * (u * extent_u)
			if choice is Rect2: quad(atlas, center, right, up, choice)
			else: quad(choice, center, right, up, Rect2(0, 0, extent_r * 2.0 / tile.x, extent_u * 2.0 / tile.y))

	func solid(xf: Transform3D, size: Vector3) -> void:
		solids.append([xf, size])

	## Cilindro em pé no eixo y local de `xf`, centro no meio da altura; `top` < 0 = mesmo raio.
	func cylinder(mat: Material, xf: Transform3D, radius: float, height: float, segments := 10, top := -1.0, caps := true) -> void:
		var g := _group(mat)
		var top_radius := radius if top < 0.0 else top
		var h := height * 0.5
		var slope := (radius - top_radius) / maxf(height, .001)
		var circumference := TAU * radius
		for s in segments:
			var a0 := TAU * float(s) / float(segments)
			var a1 := TAU * float(s + 1) / float(segments)
			var base: int = g.v.size()
			# Vista de fora, a direita anda para o ângulo menor: a1 é a esquerda.
			for corner in [[a1, h, top_radius], [a0, h, top_radius], [a0, -h, radius], [a1, -h, radius]]:
				var a: float = corner[0]
				var rr: float = corner[2]
				g.v.append(xf * Vector3(cos(a) * rr, corner[1], sin(a) * rr))
				g.n.append((xf.basis * Vector3(cos(a), slope, sin(a))).normalized())
				g.t.append(Vector2(a / TAU * circumference / 2.0, (h - float(corner[1])) / 2.0))
			g.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		if not caps: return
		for cap in [[h, top_radius, 1.0], [-h, radius, -1.0]]:
			if float(cap[1]) <= .001: continue
			var base: int = g.v.size()
			var normal := (xf.basis * Vector3(0, float(cap[2]), 0)).normalized()
			g.v.append(xf * Vector3(0, float(cap[0]), 0))
			g.n.append(normal)
			g.t.append(Vector2.ZERO)
			for s in segments:
				var a := TAU * float(s) / float(segments)
				g.v.append(xf * Vector3(cos(a) * float(cap[1]), float(cap[0]), sin(a) * float(cap[1])))
				g.n.append(normal)
				g.t.append(Vector2(cos(a), sin(a)) * float(cap[1]))
			for s in segments:
				var a_i := base + 1 + s
				var b_i := base + 1 + (s + 1) % segments
				# Ângulo crescente é horário visto de cima: tampa de cima (center, a, b), de baixo invertida.
				if float(cap[2]) > 0.0: g.i.append_array(PackedInt32Array([base, a_i, b_i]))
				else: g.i.append_array(PackedInt32Array([base, b_i, a_i]))

	## Meia esfera (concha) aberta para +z local, com as duas faces: o orelhão.
	func shell(mat: Material, xf: Transform3D, radius: Vector3, segments := 10, rings := 5) -> void:
		var g := _group(mat)
		for side in [1.0, -1.0]:
			for ring in rings:
				for s in segments:
					var base: int = g.v.size()
					var corners := []
					for corner in [[ring, s], [ring, s + 1], [ring + 1, s + 1], [ring + 1, s]]:
						# Latitude de 0 (fundo da concha, -z) a 90° (borda aberta, z = 0).
						var lat := PI * 0.5 * float(corner[0]) / float(rings)
						var lon := TAU * float(corner[1]) / float(segments)
						var dir := Vector3(cos(lon) * sin(lat), sin(lon) * sin(lat), -cos(lat))
						corners.append(dir)
					for dir: Vector3 in corners:
						g.v.append(xf * (dir * radius))
						g.n.append((xf.basis * (dir / radius).normalized() * side).normalized())
						g.t.append(Vector2(dir.x, dir.y))
					if side > 0.0: g.i.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
					else: g.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## Malhas prontas (uma por material) e as caixas de colisão, para guardar em cache.
	func bake() -> Dictionary:
		var meshes: Array = []
		for id in order:
			var g: Dictionary = groups[id]
			if g.v.is_empty(): continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g.v
			arrays[Mesh.ARRAY_NORMAL] = g.n
			arrays[Mesh.ARRAY_TEX_UV] = g.t
			arrays[Mesh.ARRAY_INDEX] = g.i
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			meshes.append([mesh, g.mat])
		return {"meshes": meshes, "solids": solids.duplicate()}

static func batch() -> Batch:
	var result := Batch.new()
	result.atlas = atlas()
	return result

## Nós do lugar a partir do que Batch.bake() guardou: uma malha por material e um corpo só com
## todas as caixas sólidas (camada 1, como G.collision).
static func instantiate(root: Node3D, baked: Dictionary) -> void:
	for index in baked.meshes.size():
		var pair: Array = baked.meshes[index]
		var node := MeshInstance3D.new()
		node.name = "RoadsideArt%d" % index
		node.mesh = pair[0]
		node.material_override = pair[1]
		root.add_child(node)
	if baked.solids.is_empty(): return
	var body := StaticBody3D.new()
	body.name = "RoadsideSolids"
	body.collision_layer = 1
	body.collision_mask = 0
	var shapes := {}
	for entry in baked.solids:
		var size: Vector3 = entry[1]
		if not shapes.has(size):
			var shape := BoxShape3D.new()
			shape.size = size
			shapes[size] = shape
		var collider := CollisionShape3D.new()
		collider.shape = shapes[size]
		collider.transform = entry[0]
		body.add_child(collider)
	root.add_child(body)

# --- Montagem em etapas -----------------------------------------------------------------------

## Termina a montagem de um lugar nos quadros seguintes, uma etapa por quadro (prédio pintado,
## carcaças): no editor o posto inteiro custava 4,3 ms num quadro só, 2,5 ms deles no prédio
## pintado (teste de sessão de 19/10). Roda antes do deserto e pede para o enfeite ceder a vez,
## como DesertRoadside faz com a primeira etapa.
class Stages extends Node:
	const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
	var steps: Array[Callable] = []
	var _region: Node

	func _ready() -> void:
		process_priority = -1
		var node := get_parent()
		while node != null and node.get("session") == null: node = node.get_parent()
		if node != null: _region = node.session.controller.regions.get("desert")

	func _process(_delta: float) -> void:
		if steps.is_empty():
			set_process(false)
			return
		if is_instance_valid(_region): _region.yield_dressing_this_frame()
		var trace := STALL_WORK.begin()
		var step: Callable = steps.pop_front()
		step.call()
		STALL_WORK.finish_slow("desert.roadside.build_stage", trace, 2000)

## Etapas para depois deste quadro (fora da árvore, como no teste sem sessão, roda tudo já).
static func later(root: Node3D, steps: Array[Callable]) -> void:
	if not root.is_inside_tree():
		for step in steps: step.call()
		return
	var stages := Stages.new()
	stages.name = "RoadsideStages"
	stages.steps = steps
	root.add_child(stages)

# --- Carcaças ---------------------------------------------------------------------------------

## Peças da carroceria de um modelo da frota (sem rodas), lidas uma vez de uma instância. Só
## modelos da frota comum: a cena já fica retida e desenhada no pré-aquecimento da frota.
static func wreck_parts(model: String) -> Array:
	if _wreck_parts.has(model): return _wreck_parts[model]
	var parts: Array = []
	var visual: Node3D = FLEET.create(model)
	if visual != null:
		for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null or part.has_meta("wheel_center"): continue
			var xform := Transform3D.IDENTITY
			var node: Node = part
			while node != visual and node is Node3D:
				xform = (node as Node3D).transform * xform
				node = node.get_parent()
			var roles: Array = []
			for surface in part.mesh.get_surface_count(): roles.append(ROLES.key(part, surface))
			parts.append({"mesh": part.mesh, "xform": xform, "roles": roles, "materials": _active_materials(part)})
		visual.free()
	_wreck_parts[model] = parts
	return parts

static func _active_materials(part: MeshInstance3D) -> Array:
	var list: Array = []
	for surface in part.mesh.get_surface_count(): list.append(part.get_active_material(surface))
	return list

## Pintura desbotada: cópia da pintura original só com outra cor (mesmo shader).
static func _faded(original: Material, tint: Color) -> Material:
	var key := "%d:%s" % [original.get_instance_id(), tint.to_html(false)]
	if not _paints.has(key):
		var copy := original.duplicate() as StandardMaterial3D
		copy.albedo_color = tint
		_paints[key] = copy
	return _paints[key]

## Várias carcaças de uma vez: [[modelo, Transform3D, cor], ...] (uma etapa de montagem).
static func wrecks(root: Node3D, list: Array) -> void:
	for entry in list: wreck(root, entry[0], entry[1], entry[2])

## Prédio pintado do PaintedFacadeKit num nó próprio, com a colisão (uma caixa) dentro dele.
static func painted(root: Node3D, style: String, size: Vector3, center: Vector3) -> void:
	if not PaintedFacadeKit.enabled() or not is_instance_valid(root): return
	var holder := Node3D.new()
	holder.name = "Painted_" + style
	holder.position = center
	root.add_child(holder)
	PaintedFacadeKit.build(holder, style, size, holder, NAN, {"snow": false})

## Carcaça sem rodas apoiada no chão: pintura desbotada, vidro escuro (sem transparência).
static func wreck(root: Node3D, model: String, xf: Transform3D, tint: Color) -> Node3D:
	if not is_instance_valid(root): return null
	var holder := Node3D.new()
	holder.name = "Wreck_" + model
	holder.transform = xf
	root.add_child(holder)
	for entry in wreck_parts(model):
		var node := MeshInstance3D.new()
		node.mesh = entry.mesh
		node.transform = entry.xform
		var roles: Array = entry.roles
		for surface in roles.size():
			var role := str(roles[surface]).get_slice("#", 0)
			var original: Material = entry.materials[surface]
			if role in ["paint", "roof_paint"] and original is StandardMaterial3D: node.set_surface_override_material(surface, _faded(original, tint))
			elif role == "glass" or ROLES.is_headlight_lens(role): node.set_surface_override_material(surface, G.material(Color("17191a")))
		holder.add_child(node)
	return holder

## Materiais que a carcaça usa, para o pré-aquecimento desenhar junto (as cópias de pintura).
static func wreck_materials(model: String, tints: Array) -> Array:
	var list: Array = [G.material(Color("17191a"))]
	for entry in wreck_parts(model):
		for surface in entry.roles.size():
			var role := str(entry.roles[surface]).get_slice("#", 0)
			var original: Material = entry.materials[surface]
			if role in ["paint", "roof_paint"] and original is StandardMaterial3D:
				for tint in tints: list.append(_faded(original, tint))
	return list
