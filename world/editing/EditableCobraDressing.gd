extends "res://world/urban_detail/HarborAreaDressing3D.gd"
## Editor adapter: preserve the authored constructor, then give coherent pieces
## their own transform. Shared meshes/materials and source scripts stay intact.
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
var _piece_depth := 0
var _pieces: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	for child in get_children():
		if child.name == "CobraCommunalGarden": _track_piece("Jardim", [child], [])
	_publish_pieces()

func _tree(point: Vector2, scale_factor: float, dry: bool) -> void:
	var start := _begin_piece()
	super._tree(point, scale_factor, dry)
	_end_piece("Árvore", start)

func _rock(point: Vector2, scale_factor: float) -> void:
	var start := _begin_piece()
	super._rock(point, scale_factor)
	_end_piece("Pedra", start)

func _lamp(point: Vector2) -> void:
	var start := _begin_piece()
	super._lamp(point)
	_end_piece("Poste", start)

func _barrel(point: Vector2) -> void:
	var start := _begin_piece()
	super._barrel(point)
	_end_piece("Barril", start)

func _tire_barricade(point: Vector2) -> void:
	var start := _begin_piece()
	super._tire_barricade(point)
	_end_piece("Pneus", start)

func _bench(point: Vector2) -> void:
	var start := _begin_piece()
	super._bench(point)
	_end_piece("Banco", start)

func _box(label: String, point: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := super._box(label, point, size, color, solid)
	_track_primitive(label, mesh, solid)
	return mesh

func _cylinder(label: String, radius: float, height: float, point: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := super._cylinder(label, radius, height, point, color, solid)
	_track_primitive(label, mesh, solid)
	return mesh

func _begin_piece() -> Vector2i:
	_piece_depth += 1
	return Vector2i(get_child_count(), _solid_root.get_child_count())

func _end_piece(label: String, start: Vector2i) -> void:
	_piece_depth -= 1
	_track_piece(label, get_children().slice(start.x), _solid_root.get_children().slice(start.y))

func _track_primitive(label: String, mesh: Node3D, solid: bool) -> void:
	if _piece_depth > 0: return
	var shapes: Array = []
	if solid: shapes.append(_solid_root.get_child(_solid_root.get_child_count()-1))
	_track_piece(label, [mesh], shapes)

func _track_piece(label: String, meshes: Array, shapes: Array) -> void:
	_pieces.append({"label":label, "meshes":meshes, "shapes":shapes})

func _publish_pieces() -> void:
	var counts := {}
	for piece in _pieces:
		var label: String = piece.label
		var serial: int = int(counts.get(label, 0))
		counts[label] = serial+1
		var nodes: Array = piece.meshes.duplicate()
		if not piece.shapes.is_empty():
			var body := StaticBody3D.new()
			body.name = "PieceSolids"
			body.collision_layer = _solid_root.collision_layer
			body.collision_mask = _solid_root.collision_mask
			add_child(body)
			for shape in piece.shapes: shape.reparent(body, false)
			nodes.append(body)
		var labels := {"CobraDryMeadow":"Terreno do bairro", "CobraApproachGround":"Acostamento", "CobraFootpathEdge":"Borda do caminho", "CobraFootpath":"Caminho", "CobraGardenPath":"Caminho do jardim", "CobraEntrancePath":"Acesso da casa", "CobraSecretDrive":"Acesso do estacionamento", "CobraYardFence":"Cerca", "CobraParkingWheelStop":"Batente", "CobraHomeGravel":"Piso do lote"}
		var readable: String = labels.get(label, label.trim_prefix("Cobra").capitalize())
		PIECES.group(self, nodes, "cobra/%s/%d" % [label.to_snake_case(), serial], readable)
	_pieces.clear()

static func tag_route(zone: Node3D, zone_id: String) -> void:
	# Factory children already hold their matching mesh and collision bodies.
	for index in zone.get_child_count():
		var child := zone.get_child(index) as Node3D
		if child == null: continue
		var label := str(child.name)
		if label.begins_with("@") and child.get_child_count() > 0: label = str(child.get_child(0).name)
		PIECES.mark(child, "route/%s/%d" % [zone_id, index], label.capitalize())
