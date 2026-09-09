@tool
class_name CityLot
extends Node2D

## Representa um lote/contorno de terreno poligonal desenhado ou posicionado no mapa.
## Fornece equivalente visual e editável de áreas de terreno, calculando área (shoelace),
## bounding box e verificação de intersecção com segmentos de reta (ex: eixos de ruas).
## Suporta edição visual de vértices via Marker2D ("ControlPoints/Point_N") no editor 2D.

const COLOR_BUILDABLE_FILL := Color(0.72, 0.58, 0.38, 0.40) # Tom terroso translúcido
const COLOR_BUILDABLE_STROKE := Color(0.85, 0.68, 0.45, 0.90) # Contorno terroso
const COLOR_FORBIDDEN_FILL := Color(0.85, 0.25, 0.25, 0.40) # Tom avermelhado translúcido
const COLOR_FORBIDDEN_STROKE := Color(0.95, 0.35, 0.35, 0.90) # Contorno avermelhado
const STROKE_WIDTH := 3.0

## Vértices do polígono em coordenadas locais do nó.
@export var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		if not _is_syncing_markers:
			_sync_markers_to_points()
		queue_redraw()

## Classificação do lote: "buildable" para lotes edificáveis ou "forbidden" para áreas não edificáveis
## (canais, parques, cemitérios, faixa de rodovia, becos, vegetação/zonas verdes).
@export_enum("buildable", "forbidden") var lot_kind: String = "buildable":
	set(value):
		lot_kind = value
		queue_redraw()

## Nome legível do lote (ex: "Mercado").
@export var label: String = "":
	set(value):
		label = value
		queue_redraw()

var _control_points: Node2D
var _is_syncing_markers: bool = false


func _ready() -> void:
	_ensure_control_points()
	if not points.is_empty():
		_sync_markers_to_points()
	set_process(Engine.is_editor_hint())
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_from_markers_if_moved()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if points.size() < 3:
		warnings.append("CityLot requer pelo menos 3 pontos para formar um polígono fechado válido.")
	return warnings


func _draw() -> void:
	var n: int = points.size()
	if n < 2:
		return

	var is_forb: bool = is_forbidden()
	var fill_color: Color = COLOR_FORBIDDEN_FILL if is_forb else COLOR_BUILDABLE_FILL
	var stroke_color: Color = COLOR_FORBIDDEN_STROKE if is_forb else COLOR_BUILDABLE_STROKE

	if n >= 3:
		draw_colored_polygon(points, fill_color)
		var closed_points: PackedVector2Array = points.duplicate()
		closed_points.append(points[0])
		draw_polyline(closed_points, stroke_color, STROKE_WIDTH, true)
	elif n == 2:
		draw_polyline(points, stroke_color, STROKE_WIDTH, true)

	if Engine.is_editor_hint():
		for p in points:
			draw_circle(p, 3.5, stroke_color)

	if not label.is_empty() and n >= 3:
		var font: Font = ThemeDB.fallback_font
		if font != null:
			var font_size: int = 14
			var center: Vector2 = get_bounds().get_center()
			var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos: Vector2 = center - Vector2(text_size.x * 0.5, -font_size * 0.35)
			draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1.0, 1.0, 1.0, 0.9))


## Retorna a área do polígono utilizando a fórmula de Shoelace (Gauss).
## Retorna 0.0 se tiver menos de 3 pontos.
func get_area() -> float:
	var n: int = points.size()
	if n < 3:
		return 0.0
	var sum: float = 0.0
	for i in range(n):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		sum += p1.x * p2.y - p2.x * p1.y
	return absf(sum) * 0.5


## Retorna o Bounding Box (Rect2) que envolve todos os vértices em coordenadas locais.
func get_bounds() -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_pos: Vector2 = points[0]
	var max_pos: Vector2 = points[0]
	for i in range(1, points.size()):
		var p: Vector2 = points[i]
		min_pos.x = minf(min_pos.x, p.x)
		min_pos.y = minf(min_pos.y, p.y)
		max_pos.x = maxf(max_pos.x, p.x)
		max_pos.y = maxf(max_pos.y, p.y)
	return Rect2(min_pos, max_pos - min_pos)


## Retorna true se o lote é do tipo não-edificável/proibido.
func is_forbidden() -> bool:
	return lot_kind != "buildable"


## Retorna true se o lote é edificável.
func is_buildable() -> bool:
	return lot_kind == "buildable"


## Retorna true se o segmento de reta a-b (em coordenadas locais) cruza qualquer aresta do polígono.
## Utiliza Geometry2D.segment_intersects_segment para checagem exata em cada aresta.
func overlaps_segment(a: Vector2, b: Vector2) -> bool:
	var n: int = points.size()
	if n < 2:
		return false
	if n == 2:
		return Geometry2D.segment_intersects_segment(a, b, points[0], points[1]) != null
	for i in range(n):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		if Geometry2D.segment_intersects_segment(a, b, p1, p2) != null:
			return true
	return false


## Versão utilitária que recebe coordenadas globais para a checagem de segmento.
func overlaps_segment_global(global_a: Vector2, global_b: Vector2) -> bool:
	return overlaps_segment(to_local(global_a), to_local(global_b))


## Insere um novo vértice entre os dois mais próximos na ordem do polígono.
## Se new_point for omitido (Vector2.INF), subdivide a aresta mais longa no ponto médio.
## Retorna o índice onde o novo vértice foi inserido.
func add_point(new_point: Vector2 = Vector2.INF) -> int:
	var n: int = points.size()

	if n == 0:
		var pos: Vector2 = Vector2.ZERO if new_point == Vector2.INF else new_point
		points.append(pos)
		_sync_markers_to_points()
		queue_redraw()
		return 0

	if n == 1:
		var pos: Vector2 = points[0] + Vector2(100.0, 0.0) if new_point == Vector2.INF else new_point
		points.append(pos)
		_sync_markers_to_points()
		queue_redraw()
		return 1

	if n == 2:
		var pos: Vector2
		if new_point == Vector2.INF:
			pos = (points[0] + points[1]) * 0.5 + Vector2(0.0, 50.0)
		else:
			pos = new_point
		points.insert(1, pos)
		_sync_markers_to_points()
		queue_redraw()
		return 1

	var insert_index: int = -1
	var pos_to_add: Vector2

	if new_point == Vector2.INF:
		# Encontra a aresta mais longa e insere no ponto médio
		var max_dist_sq: float = -1.0
		var best_edge: int = 0
		for i in range(n):
			var p1: Vector2 = points[i]
			var p2: Vector2 = points[(i + 1) % n]
			var d_sq: float = p1.distance_squared_to(p2)
			if d_sq > max_dist_sq:
				max_dist_sq = d_sq
				best_edge = i
		pos_to_add = (points[best_edge] + points[(best_edge + 1) % n]) * 0.5
		insert_index = best_edge + 1
	else:
		pos_to_add = new_point
		# Encontra a aresta com menor distância ao novo ponto
		var min_dist_sq: float = INF
		var best_edge: int = 0
		for i in range(n):
			var p1: Vector2 = points[i]
			var p2: Vector2 = points[(i + 1) % n]
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pos_to_add, p1, p2)
			var d_sq: float = pos_to_add.distance_squared_to(closest)
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq
				best_edge = i
		insert_index = best_edge + 1

	if insert_index >= points.size():
		points.append(pos_to_add)
		insert_index = points.size() - 1
	else:
		points.insert(insert_index, pos_to_add)

	_sync_markers_to_points()
	queue_redraw()
	return insert_index


## Remove o vértice no índice especificado.
func remove_point(index: int) -> bool:
	if index < 0 or index >= points.size():
		return false
	points.remove_at(index)
	_sync_markers_to_points()
	queue_redraw()
	return true


# --- GERENCIAMENTO DE CONTROL POINTS (Marker2D) ---

func _ensure_control_points() -> void:
	if _control_points == null:
		_control_points = get_node_or_null("ControlPoints") as Node2D
		if _control_points == null:
			_control_points = Node2D.new()
			_control_points.name = "ControlPoints"
			add_child(_control_points)
			_assign_editor_owner(_control_points)

	if _control_points != null and points.is_empty():
		var markers := _get_control_point_markers()
		if not markers.is_empty():
			var loaded_points := PackedVector2Array()
			for m in markers:
				loaded_points.append(to_local(m.global_position))
			_is_syncing_markers = true
			points = loaded_points
			_is_syncing_markers = false


func _sync_markers_to_points() -> void:
	_ensure_control_points()
	if _control_points == null:
		return

	var markers := _get_control_point_markers()
	var common_count: int = mini(markers.size(), points.size())

	# Atualiza existentes
	for i in range(common_count):
		markers[i].name = "Point_%d" % i
		if not markers[i].position.is_equal_approx(points[i]):
			markers[i].position = points[i]
		_assign_editor_owner(markers[i])

	# Remove excedentes
	if markers.size() > points.size():
		for i in range(points.size(), markers.size()):
			var m := markers[i]
			m.name = "Old_" + m.name
			_control_points.remove_child(m)
			m.queue_free()

	# Cria novos faltantes
	elif points.size() > markers.size():
		for i in range(markers.size(), points.size()):
			var marker := Marker2D.new()
			marker.name = "Point_%d" % i
			marker.position = points[i]
			_control_points.add_child(marker)
			_assign_editor_owner(marker)


func _sync_from_markers_if_moved() -> void:
	if _control_points == null:
		return

	var markers := _get_control_point_markers()
	if markers.is_empty():
		return

	if markers.size() != points.size():
		var new_points := PackedVector2Array()
		for m in markers:
			new_points.append(to_local(m.global_position))
		_is_syncing_markers = true
		points = new_points
		_is_syncing_markers = false
		queue_redraw()
		notify_property_list_changed()
		return

	var changed := false
	for i in range(markers.size()):
		var local_pos := to_local(markers[i].global_position)
		if not points[i].is_equal_approx(local_pos):
			points[i] = local_pos
			changed = true

	if changed:
		queue_redraw()
		notify_property_list_changed()


func _get_control_point_markers() -> Array[Marker2D]:
	var marker_list: Array[Marker2D] = []
	if _control_points == null:
		return marker_list
	for child in _control_points.get_children():
		if child is Marker2D and String(child.name).begins_with("Point_"):
			marker_list.append(child as Marker2D)
	marker_list.sort_custom(func(first: Marker2D, second: Marker2D) -> bool:
		return _control_point_index(first) < _control_point_index(second)
	)
	return marker_list


func _control_point_index(marker: Marker2D) -> int:
	return int(String(marker.name).trim_prefix("Point_"))


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var edited_scene_root := get_tree().edited_scene_root
	if edited_scene_root != null and (node == edited_scene_root or edited_scene_root.is_ancestor_of(node)):
		node.owner = edited_scene_root
