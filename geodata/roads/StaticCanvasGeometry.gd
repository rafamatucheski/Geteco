@tool
extends RefCounted
## Divide geometria estática em malhas locais; a câmera descarta os setores distantes.
const CELL := 512.0
var host: Node2D
var chunks: Dictionary = {}
var nodes: Dictionary = {}
var pending := false

func _init(node: Node2D) -> void: host = node

func begin() -> void:
	chunks.clear()
	if not pending:
		pending = true
		flush.call_deferred()

func flush() -> void:
	pending = false
	if not is_instance_valid(host) or not host.is_inside_tree(): return
	for cell in nodes.keys():
		if not chunks.has(cell):
			nodes[cell].queue_free()
			nodes.erase(cell)
	for cell in chunks:
		var data: Dictionary = chunks[cell]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array(data.vertices)
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(data.colors)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if not nodes.has(cell):
			var node := MeshInstance2D.new()
			node.name = "StaticSector_%d_%d" % [cell.x,cell.y]
			node.show_behind_parent = true
			node.use_parent_material = true
			host.add_child(node)
			nodes[cell] = node
		nodes[cell].mesh = mesh

func draw_rect(rect: Rect2, color: Color, filled := true, width := -1.0, _aa := false) -> void:
	if filled:
		draw_colored_polygon(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]),color)
	else:
		var w := maxf(width,1.0)
		draw_rect(Rect2(rect.position-Vector2.ONE*w*0.5,Vector2(rect.size.x+w,w)),color)
		draw_rect(Rect2(Vector2(rect.position.x-w*0.5,rect.end.y-w*0.5),Vector2(rect.size.x+w,w)),color)
		draw_rect(Rect2(rect.position+Vector2(-w*0.5,w*0.5),Vector2(w,maxf(0,rect.size.y-w))),color)
		draw_rect(Rect2(Vector2(rect.end.x-w*0.5,rect.position.y+w*0.5),Vector2(w,maxf(0,rect.size.y-w))),color)

## Pontos consecutivos quase idênticos (menos de MIN_SEGMENT_LENGTH de
## distância) produzem segmentos/arestas de comprimento ~0 -- Geometry2D
## (offset_polyline e triangulate_polygon) volta com um polígono inválido
## pra esses casos e loga "Invalid polygon data, triangulation failed." em
## vez de simplesmente ignorar o ponto redundante. Estradas amostradas por
## Curve2D.sample_baked() (mountain_bridge_outbound/inbound, MountainPassRoad,
## etc.) acumulam esses quase-duplicados nas transições de curvatura --
## multiplicado por toda passada de material (calçada/meio-fio/asfalto) e
## por cada vez que o editor redesenha a cena (todo zoom/pan), isso é o que
## deixava o editor lento e a Saída cheia do mesmo erro repetido.
const MIN_SEGMENT_LENGTH := 0.05

func _deduplicate_consecutive(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2: return points
	var result := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		if points[i].distance_to(result[-1]) >= MIN_SEGMENT_LENGTH:
			result.append(points[i])
	return result

func draw_line(a: Vector2,b: Vector2,color: Color,width := -1.0,_aa := false) -> void:
	if a.distance_to(b) < MIN_SEGMENT_LENGTH: return
	var normal := a.direction_to(b).orthogonal()*maxf(1,width)*0.5
	draw_colored_polygon(PackedVector2Array([a+normal,b+normal,b-normal,a-normal]),color)

func draw_multiline(points: PackedVector2Array,color: Color,width := -1.0,aa := false) -> void:
	for i in range(0,points.size()-1,2): draw_line(points[i],points[i+1],color,width,aa)

func draw_polyline(points: PackedVector2Array,color: Color,width := -1.0,_aa := false) -> void:
	var clean := _deduplicate_consecutive(points)
	if clean.size() < 2: return
	for polygon in Geometry2D.offset_polyline(clean,maxf(1,width)*0.5,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT):
		draw_colored_polygon(polygon,color)

func draw_circle(center: Vector2,radius: float,color: Color,filled := true,width := -1.0,_aa := false) -> void:
	var count := maxi(24,ceili(radius*0.8))
	var points := PackedVector2Array()
	for i in count: points.append(center+Vector2.from_angle(TAU*i/count)*radius)
	if filled: draw_colored_polygon(points,color)
	else:
		for i in count: draw_line(points[i],points[(i+1)%count],color,width)

func draw_colored_polygon(polygon: PackedVector2Array,color: Color) -> void:
	var clean := _deduplicate_consecutive(polygon)
	# Fecha o anel antes de checar o par inicial/final: sem isso, um polígono
	# cujo último ponto for quase igual ao primeiro (comum em anéis gerados
	# por offset_polyline) passa no dedup acima mas ainda chega com aresta
	# de fechamento degenerada no triangulate_polygon.
	if clean.size() >= 2 and clean[0].distance_to(clean[-1]) < MIN_SEGMENT_LENGTH:
		clean.remove_at(clean.size() - 1)
	if clean.size()<3: return
	var indices := Geometry2D.triangulate_polygon(clean)
	for i in range(0,indices.size(),3):
		_triangle(PackedVector2Array([clean[indices[i]],clean[indices[i+1]],clean[indices[i+2]]]),color)

func _triangle(points: PackedVector2Array,color: Color) -> void:
	var bounds := Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2])
	var first := Vector2i((bounds.position/CELL).floor())
	var last := Vector2i((bounds.end/CELL).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell := Vector2i(x,y)
			var clipped := points
			clipped = _clip(clipped,0,x*CELL,true)
			clipped = _clip(clipped,0,(x+1)*CELL,false)
			clipped = _clip(clipped,1,y*CELL,true)
			clipped = _clip(clipped,1,(y+1)*CELL,false)
			if clipped.size()<3: continue
			if not chunks.has(cell): chunks[cell] = {"vertices":[],"colors":[]}
			var data: Dictionary = chunks[cell]
			for j in range(1,clipped.size()-1):
				for point in [clipped[0],clipped[j],clipped[j+1]]:
					data.vertices.append(point)
					data.colors.append(color)

func _clip(polygon: PackedVector2Array,axis: int,edge: float,keep_greater: bool) -> PackedVector2Array:
	if polygon.is_empty(): return polygon
	var output := PackedVector2Array()
	var previous := polygon[-1]
	var previous_inside := previous[axis]>=edge if keep_greater else previous[axis]<=edge
	for current in polygon:
		var inside := current[axis]>=edge if keep_greater else current[axis]<=edge
		if inside != previous_inside:
			output.append(previous.lerp(current,(edge-previous[axis])/(current[axis]-previous[axis])))
		if inside: output.append(current)
		previous = current
		previous_inside = inside
	return output
