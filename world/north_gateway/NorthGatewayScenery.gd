extends Node3D
## Ponte estática em lote. A progressão e os operários animados pertencem ao dono.
const Layout := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const LEGACY := preload("res://world/north_gateway/NorthGatewayLegacyScenery.gd")
const THICKNESS := 0.75
var completed := false
var _built := false
var _common: Node3D
var _works: Node3D
var _finished: Node3D
static var _materials: Dictionary = {}
static var _box_mesh := BoxMesh.new()
static var _geometry_template: PackedScene
static var _preparing := false
static var _geometry_materials: Array[Material] = []
var _batches: Dictionary = {}
var _body: StaticBody3D
var _part_root: Node3D
var _legacy: Node3D

static func prewarm_geometry() -> void:
	if not KIT.enabled() or _geometry_template != null or _preparing: return
	_preparing = true
	# O script já está residente; a montagem acontece sob a cortina. A cena retém
	# malhas e formas compartilhadas, sem conservar controladores nem corpos vivos.
	var source: Node3D = load("res://world/north_gateway/NorthGatewayScenery.gd").new()
	source.call("_build_geometry")
	var geometry := Node3D.new()
	geometry.name = "NorthGatewayGeometry"
	for part in source.get_children():
		source.remove_child(part)
		geometry.add_child(part)
	_set_template_owners(geometry, geometry)
	_geometry_materials.clear()
	_collect_geometry_materials(geometry)
	var packed := PackedScene.new()
	var error := packed.pack(geometry)
	if error == OK:
		_geometry_template = packed
	else:
		push_error("Falha ao preparar geometria da ponte norte: %d" % error)
	geometry.free()
	source.free()
	_preparing = false

static func geometry_materials() -> Array:
	prewarm_geometry()
	return _geometry_materials.duplicate()

static func _collect_geometry_materials(node: Node) -> void:
	# A obra também contém ferrugem, laranja, aço escuro e tinta: só os materiais
	# do kit não cobrem todas as variantes que a montagem real desenha.
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		for material: Material in [geometry.material_override, geometry.material_overlay]:
			if material != null and material not in _geometry_materials: _geometry_materials.append(material)
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				if material != null and material not in _geometry_materials: _geometry_materials.append(material)
	for child in node.get_children(): _collect_geometry_materials(child)

static func _set_template_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_template_owners(child, scene_root)

static func _clear_template_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children(): _clear_template_owners(child)

func build(initial_completed: bool = false) -> Node3D:
	if _built:
		set_completed(initial_completed)
		return self
	name = "NorthGatewayScenery"
	# A base permanece isolada para comparar exports equivalentes sem trocar fontes.
	if OS.get_environment("GETECO_UNIFIED_BRIDGE") == "0":
		_legacy = LEGACY.new()
		add_child(_legacy)
		_legacy.build(initial_completed)
		_built = true
		completed = initial_completed
		return self
	if _geometry_template == null: prewarm_geometry()
	if _geometry_template != null:
		var geometry: Node3D = _geometry_template.instantiate()
		for part in geometry.get_children():
			_clear_template_owners(part)
			geometry.remove_child(part)
			add_child(part)
		geometry.free()
		_common = get_node("PermanentBridge")
		_finished = get_node("CompletedSpan")
		_works = get_node("ConstructionSite")
	else:
		# Falha de preparação continua oferecendo piso, mas impede aprovar o prewarm.
		_build_geometry()
	_built = true
	set_completed(initial_completed)
	return self

func _build_geometry() -> void:
	_common = _new_part("PermanentBridge")
	_build_decks(false)
	_build_supports()
	_flush_part()
	_finished = _new_part("CompletedSpan")
	_build_decks(true)
	_flush_part()
	_works = _new_part("ConstructionSite")
	_build_works()
	_flush_part()

func set_completed(value: bool) -> void:
	completed = value
	if not _built: return
	if is_instance_valid(_legacy):
		_legacy.set_completed(value)
		return
	# Build both immutable states once. A save restore can safely select either.
	_set_enabled(_finished, value)
	_set_enabled(_works, not value)

func _set_enabled(root: Node3D, enabled: bool) -> void:
	root.visible = enabled
	for body in root.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1 if enabled else 0
	root.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED

func _new_part(part_name: String) -> Node3D:
	var result := Node3D.new()
	result.name = part_name
	add_child(result)
	_part_root = result
	_batches = {}
	_body = StaticBody3D.new()
	_body.name = part_name + "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	result.add_child(_body)
	return result

func _build_decks(gap_only: bool) -> void:
	var points := Layout.centerline()
	var kit := KIT.new()
	var distance := 0.0
	var total := Layout.length()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var begin := distance
		distance += length
		if Layout.in_gap((a + b) * 0.5) != gap_only: continue
		var cuts: Array[float] = [0.0, 1.0]
		# Cortar apenas a tesselação, sem mover o eixo, delimita a rampa de passeio
		# a exatamente um metro em cada encontro com a via regional.
		for boundary in [1.0, total - 1.0]:
			if boundary > begin and boundary < distance:
				cuts.append((boundary - begin) / length)
		cuts.sort()
		var sa := _side(points, i)
		var sb := _side(points, i + 1)
		for part in range(cuts.size() - 1):
			var t0 := cuts[part]
			var t1 := cuts[part + 1]
			var pa := a.lerp(b, t0)
			var pb := a.lerp(b, t1)
			var exclusions: Array[PackedVector2Array] = []
			var road_exclusions: Array[PackedVector2Array] = []
			var bounds := Rect2(Vector2(pa.x,pa.z),Vector2.ZERO).expand(Vector2(pb.x,pb.z)).grow(maxf(Layout.deck_half_width(pa),Layout.deck_half_width(pb)))
			if bounds.intersects(KIT.east_bounds(),true):
				exclusions.append(KIT.east_footprint())
				road_exclusions.append(KIT.east_asphalt_footprint())
			# Vão e ponte permanente compartilham perfil; a divisão só atende à campanha.
			kit.add_segment(pa, pb, sa.lerp(sb, t0), sa.lerp(sb, t1),
				_road_half_width(pa), _road_half_width(pb), Layout.deck_half_width(pa),
				Layout.deck_half_width(pb), i >= 2, {
					"walk_height_a": Layout.walk_height_at(begin + length * t0),
					"walk_height_b": Layout.walk_height_at(begin + length * t1),
					"exclusions": exclusions,
					"road_exclusions": road_exclusions,
					"walk_exclusions": exclusions,
					"guard_end": i == points.size() - 2 and part == cuts.size() - 2,
					"start_cap": part == 0 and (i == 0 or is_equal_approx(a.z, Layout.GAP_NORTH)),
					"end_cap": part == cuts.size() - 2 and (i == points.size() - 2 or is_equal_approx(b.z, Layout.GAP_SOUTH)),
				})
	kit.commit(_part_root, "NorthGateway")

func _side(points: PackedVector3Array, index: int) -> Vector3:
	var direction := points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]
	return Vector3(-direction.z, 0.0, direction.x).normalized()

func _road_half_width(point: Vector3) -> float:
	if point.z > -343.0: return Layout.ROAD_HALF_WIDTH
	return lerpf(Layout.ROAD_HALF_WIDTH, 5.0, clampf((-343.0 - point.z) / 30.5, 0.0, 1.0))

func _build_supports() -> void:
	# Encontro real e cavaletes com estacas encontram a face de baixo; sem plano fino flutuando.
	# A cabeceira sustenta o intradorso: seu topo no piso zero criava um segundo
	# chão coplanar sob o asfalto, mesmo depois de recortar os donos regionais.
	_box("concrete", Vector3(356.0, -THICKNESS - 0.40, -255.7), Vector3(2.0, 0.8, 9.5), Basis(Vector3.UP, -0.30), true)
	var points := Layout.centerline()
	for i in [12, 18, 24]:
		var p := points[i]
		_pier(p, _side(points, i), Layout.deck_half_width(p))
	for z in [-292.0, -307.0, -325.0, -343.0, -360.0, -370.5]:
		var p := Vector3(Layout.TERMINAL.x, Layout.DECK_HEIGHT, z)
		_pier(p, Vector3.RIGHT, Layout.deck_half_width(p))
	# As longarinas continuam pela abertura inacabada abaixo do nível da
	# estrada. São aço visual de obra, não uma superfície de estrada transitável.
	for x in [-3.8, 3.8]:
		_box("dark_steel", Vector3(342.5 + x, 1.02, -323.0), Vector3(0.32, 1.05, 100.8))

func _pier(p: Vector3, side: Vector3, half_width: float) -> void:
	var top := p.y - THICKNESS
	for offset in [-minf(half_width - 1.1, 5.0), minf(half_width - 1.1, 5.0)]:
		var center: Vector3 = p + side * offset
		center.y = (top - 4.0) * 0.5
		_box("concrete", center, Vector3(1.15, top + 4.0, 1.45), Basis.IDENTITY, true)
	_beam("concrete", p - side * (half_width - 0.5) + Vector3.DOWN * 1.0,
		p + side * (half_width - 0.5) + Vector3.DOWN * 1.0, 1.25, 0.5, true)

func _build_works() -> void:
	var gate := Layout.WORK_POSITION
	# A wide, visibly solid barrier spans road AND shoulders. Workers remain
	# visible through a closely barred upper fence, with no walking bypass.
	_box("concrete", gate + Vector3.UP * 0.34, Vector3(Layout.GATE_WIDTH, 0.68, 0.65), Basis.IDENTITY, true)
	_box("", gate + Vector3.UP * Layout.GATE_HEIGHT * 0.5,
		Vector3(Layout.GATE_WIDTH, Layout.GATE_HEIGHT, 0.32), Basis.IDENTITY, true)
	for x in range(43):
		_box("steel", gate + Vector3(-8.4 + float(x) * 0.4, 1.46, 0), Vector3(0.045, 1.57, 0.045))
	for y in [0.85, 1.75, 2.22]:
		_box("steel", gate + Vector3.UP * y, Vector3(17.0, 0.065, 0.07))
	for x in range(17):
		_box("orange" if x % 2 == 0 else "white", gate + Vector3(-8.0 + x, 0.46, 0.347), Vector3(0.97, 0.27, 0.022))
	# Tampas separadas protegem o vão inacabado mesmo que o jogador chegue por uma
	# direção incomum; a conclusão remove todas essas barreiras de obra juntas.
	for z in [Layout.GAP_SOUTH + 0.45, Layout.GAP_NORTH - 0.45]:
		var center := Vector3(342.5, Layout.DECK_HEIGHT, z)
		_box("orange", center + Vector3.UP * 0.55, Vector3(9.8, 1.1, 0.55), Basis.IDENTITY, true)
		for x in range(10):
			_box("white", center + Vector3(-4.5 + x, 0.57, 0.288), Vector3(0.38, 0.58, 0.024))
	# Barras expostas do tabuleiro, ancoradas nas duas faces inacabadas reais.
	for z in [Layout.GAP_SOUTH - 0.45, Layout.GAP_NORTH + 0.45]:
		for x in range(13):
			_box("rust", Vector3(338.9 + x * 0.6, 2.16, z), Vector3(0.028, 0.028, 1.35))
	# Guindaste fixo compacto e pilha de material nos acostamentos da obra. Sem
	# simulação física, luzes, partículas ou scripts de construção por quadro.
	_box("orange", Vector3(336.3, 2.85, -295.1), Vector3(1.9, 0.9, 2.0), Basis.IDENTITY, true)
	_box("yellow", Vector3(336.3, 6.35, -295.1), Vector3(0.42, 6.5, 0.42), Basis.IDENTITY, true)
	_box("yellow", Vector3(336.3, 9.4, -297.8), Vector3(0.40, 0.44, 9.1))
	_beam("dark_steel", Vector3(336.3, 9.3, -302.1), Vector3(336.3, 4.9, -302.1), 0.035, 0.035)
	_box("dark_steel", Vector3(336.3, 4.85, -302.1), Vector3(0.24, 0.30, 0.08))
	for row in range(3):
		_box("concrete", Vector3(349.0, 2.57 + row * 0.28, -295.0), Vector3(1.6, 0.24, 2.2), Basis.IDENTITY, true)

func _beam(id: String, a: Vector3, b: Vector3, width: float, height: float, solid: bool = false) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001: return
	var planar := Vector2(direction.x, direction.z).length()
	var orientation := Basis(Vector3.UP, atan2(direction.x, direction.z)) * Basis(Vector3.RIGHT, -atan2(direction.y, planar))
	_box(id, (a + b) * 0.5, Vector3(width, height, direction.length() + 0.018), orientation, solid)

func _box(id: String, center: Vector3, size: Vector3, orientation: Basis = Basis.IDENTITY, solid: bool = false) -> void:
	if not id.is_empty():
		if not _batches.has(id): _batches[id] = []
		_batches[id].append(Transform3D(orientation.scaled_local(size), center))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(orientation, center)
		_body.add_child(collider)

func _flush_part() -> void:
	for id in _batches:
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = _box_mesh
		mesh.instance_count = _batches[id].size()
		for i in mesh.instance_count: mesh.set_instance_transform(i, _batches[id][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = id + "Parts"
		instance.multimesh = mesh
		if Engine.get_meta("geteco_live_preview_build",false): instance.set_meta("preview_instance_transforms",_batches[id])
		instance.material_override = _material(id)
		_part_root.add_child(instance)
	_batches.clear()

func _material(id: String) -> Material:
	# Pilares, cabeceira e canteiro reaproveitam o concreto do corredor inteiro.
	if id in ["asphalt", "concrete"]: return KIT.material(id)
	if id == "steel": return KIT.material("metal")
	if _materials.has(id): return _materials[id]
	var result := StandardMaterial3D.new()
	var colors := {"steel": "879094", "dark_steel": "344047", "white": "e2dfcf",
		"yellow": "d5a63e", "orange": "df7633", "rust": "785b49"}
	result.albedo_color = Color(colors.get(id, "848b8c"))
	result.roughness = 0.88
	if id in ["steel", "dark_steel", "rust"]: result.metallic = 0.35
	# Cor lisa lia como plano chapado: relevo e rugosidade em espaço de mundo, mesmo tom.
	if result.albedo_color.a >= 1.0 and not result.emission_enabled:
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(result, "metal" if result.metallic > 0.1 else "plaster", 2.0, .7)
		result.albedo_color = Color(minf(result.albedo_color.r * result.albedo_color.r, 1.0), minf(result.albedo_color.g * result.albedo_color.g, 1.0), minf(result.albedo_color.b * result.albedo_color.b, 1.0))
		result.roughness = 1.0
	_materials[id] = result
	return result
