extends RefCounted
## Malhas mínimas com o MESMO formato de vértice das superfícies do jogo, para os pré-aquecimentos (22/10,
## 3ª rodada de desempenho).
##
## Por quê: o pipeline do Vulkan é por shader × formato de vértice × passe. Desenhar uma variante de
## material numa BoxMesh compila o shader, mas o pipeline da lataria (posição, normal, tangente, cor, UV,
## às vezes UV2) ficava para o jogo. A sonda de pipelines (GETECO_PIPELINE_PROBE=1) no estresse a quente do
## oeste viu 58 pipelines `surface` novas com a partida jogável, quase todas pintura suja, molhada ou limpa
## depois de suja, para-brisa molhado e a porta recortada da viatura, nos formatos dos carros; com o cache
## frio cada uma dessas é um quadro de 0,1–1 s. Um triângulo com os mesmos atributos, sem compressão como as
## malhas da frota, tem o mesmo formato (conferido em `mesh_for`; formato que não bate fica de fora).
const ATTRIBUTES := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT \
	| Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2
## Esqueleto, atributos custom e compressão mudam o leiaute de um jeito que o triângulo não reproduz.
const UNSUPPORTED := Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 \
	| Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3 \
	| Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES | Mesh.ARRAY_FLAG_USE_2D_VERTICES
const V := Mesh.ARRAY_FORMAT_VERTEX
const N := Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT
const C := Mesh.ARRAY_FORMAT_COLOR
const UV := Mesh.ARRAY_FORMAT_TEX_UV
const UV2 := Mesh.ARRAY_FORMAT_TEX_UV2
## Formatos que o jogo cria fora da frota: folha da porta recortada (VehicleDoorBuilder.to_mesh: posição,
## normal e UV, mais cor quando não é branca), bordas da folha (SurfaceTool com normais geradas e cor) e
## acabamento/poço da porta (só cor). Vistos pela sonda na porta da viatura que chega.
const DOOR_FORMATS := [V | N | UV, V | N | UV | C, V | N | C, V | C]
const SPACING := .34
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 30
static var _meshes: Dictionary = {}

static func enabled() -> bool:
	return OS.get_environment("GETECO_FORMAT_PREWARM") != "0"

static func attributes(format: int) -> int:
	return format & ATTRIBUTES

static func supported(format: int) -> bool:
	return (format & UNSUPPORTED) == 0 and (format & V) != 0

## Formatos (só atributos) das superfícies ArrayMesh de `node` em `into` (atributos → true).
static func collect(node: Node, into: Dictionary) -> void:
	if node == null: return
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if not part.mesh is ArrayMesh: continue
		var mesh := part.mesh as ArrayMesh
		for surface in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var format := mesh.surface_get_format(surface)
			if supported(format): into[attributes(format)] = true

## Triângulo com exatamente `attrs`; null se o motor montar outro formato (ex.: normal sem tangente).
static func mesh_for(attrs: int) -> ArrayMesh:
	if _meshes.has(attrs): return _meshes[attrs]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.15, -.12, 0), Vector3(.15, -.12, 0), Vector3(0, .15, 0)])
	if attrs & Mesh.ARRAY_FORMAT_NORMAL: arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	if attrs & Mesh.ARRAY_FORMAT_TANGENT: arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	if attrs & C: arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	if attrs & UV: arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(.5, 0)])
	if attrs & UV2: arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(.5, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var made: ArrayMesh = mesh if attributes(mesh.surface_get_format(0)) == attrs else null
	_meshes[attrs] = made
	return made

## Uma peça por par [material, atributos] numa grade diante da câmera, debaixo de `parent`.
## Devolve quantas peças entraram (pares com formato que não se reproduz ficam de fora).
## `transparency` > 0 põe cada peça no passe alfa (carcaça sumindo, Vehicle._tick_wreck).
static func build_grid(parent: Node3D, pairs: Array, origin := Vector3.ZERO, transparency := 0.0) -> int:
	var columns := maxi(1, ceili(sqrt(float(pairs.size()))))
	var placed := 0
	for pair in pairs:
		var material: Material = pair[0]
		var mesh := mesh_for(int(pair[1]))
		if material == null or mesh == null: continue
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = material
		part.transparency = transparency
		part.position = origin + Vector3((placed % columns - (columns - 1) * .5) * SPACING, -floorf(float(placed) / columns) * SPACING, 0)
		parent.add_child(part)
		placed += 1
	return placed

## Pares [material, atributos] para cada material × cada formato, sem repetir.
static func cross(materials: Array, formats: Array, into: Array, seen: Dictionary) -> void:
	for material in materials:
		if not material is Material: continue
		for attrs in formats:
			var key := "%d:%d" % [(material as Material).get_instance_id(), int(attrs)]
			if seen.has(key): continue
			seen[key] = true
			into.append([material, int(attrs)])
