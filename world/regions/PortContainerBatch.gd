extends RefCounted
## Contêiner de 40 pés detalhado, já agrupado por material e guardado em cache por tema.
## O convés do Northstar usava caixas de cor chapada; um contêiner completo tem ~330
## peças, então cada tema é montado uma vez e todas as instâncias compartilham as malhas.
const CONTAINER := preload("res://assets/regions/source/prototypes/harbor_art_pack/props/PortContainer40ft3D.gd")
const PortArtMaterials := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortArtMaterials.gd")
const OPTIMIZER := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortMeshOptimizer.gd")

static var _cache: Dictionary = {}

## Lotes {mesh, material} do contêiner no tamanho nativo (2,44 × 2,89 × 12,19 m;
## comprimento em Z, porta em +Z, origem no centro da base).
static func batches(theme: int) -> Array:
	if _cache.has(theme): return _cache[theme]
	if not _cache.has(0): _cache[0] = _build_reference()
	if theme == 0: return _cache[0]
	# A geometria é igual em todos os temas; só o casco e o quadro mudam de cor. Montar
	# cada tema do zero custava ~80 ms em pleno streaming do chunk; aqui só trocam-se
	# os dois materiais sobre as malhas já agrupadas.
	var reference := CONTAINER.new()
	reference.color_theme = 0
	var themed := CONTAINER.new()
	themed.color_theme = theme
	var base_0: StandardMaterial3D = reference._get_theme_material()
	var base_n: StandardMaterial3D = themed._get_theme_material()
	var frame_n := PortArtMaterials.container_paint("container_frame_dark_40_%d" % theme, base_n.albedo_color.darkened(0.28), 0.5, 0.55)
	var rows: Array = []
	for row in _cache[0]:
		var material: Material = row.material
		if material is StandardMaterial3D and material.albedo_texture != null:
			if material.albedo_color.is_equal_approx(base_0.albedo_color.darkened(0.28)):
				material = frame_n
			elif material.albedo_color.is_equal_approx(base_0.albedo_color):
				material = base_n.duplicate()
		rows.append({"mesh": row.mesh, "material": material})
	reference.free()
	themed.free()
	_cache[theme] = rows
	return rows

static func _build_reference() -> Array:
	var source := CONTAINER.new()
	source.color_theme = 0
	source.get_obstacle_bounds() # força a montagem sem precisar entrar na árvore
	OPTIMIZER.optimize_hierarchy(source, false)
	var rows: Array = []
	for batch in source.get_node("BatchedStaticGeometry").get_children():
		rows.append({"mesh": batch.mesh, "material": batch.material_override})
	source.free()
	return rows

## Instancia o contêiner dentro de `size` (X largura, Y altura, Z comprimento); `flip`
## vira a porta para −Z. As malhas são compartilhadas, só o nó é novo.
static func create(theme: int, size: Vector3, flip := false) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ShipContainer"
	holder.scale = Vector3(size.x / CONTAINER.WIDTH, size.y / CONTAINER.HEIGHT, size.z / CONTAINER.LENGTH)
	if flip: holder.rotation.y = PI
	for row in batches(theme):
		var part := MeshInstance3D.new()
		part.mesh = row.mesh
		part.material_override = row.material
		holder.add_child(part)
	return holder
