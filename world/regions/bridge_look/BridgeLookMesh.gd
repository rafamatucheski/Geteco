extends RefCounted
## Acumula a geometria do acabamento da ponte Harbor–Mountain por material e por trecho, e
## entrega poucas malhas no fim. Antes cada viga, montante e poste era um MeshInstance3D com
## BoxMesh próprio (~190 peças só na ponte). Aqui as peças são prismas convexos com normais
## por face (low-poly, como o resto do porto), cor no vértice e UV com dados para o shader.
##
## Os trechos existem por causa do renderizador Mobile: ele aplica no máximo 8 luzes omni por
## objeto. Uma malha única de 185 m ficaria sob os 7 postes da ponte, as luzes do túnel e as do
## porto ao mesmo tempo e perderia algumas à noite. Cortes em x mantêm cada trecho sob poucas.

const CONCRETE := "concrete"
const STEEL := "steel"
const GLASS := "glass"

var cuts: PackedFloat32Array
## "material|trecho" -> SurfaceTool
var _tools := {}
## Trecho fixo para as peças seguintes (ou -1 = escolher pela posição).
var forced_segment := -1

func _init(segment_cuts: PackedFloat32Array) -> void:
	cuts = segment_cuts

func _segment(x: float) -> int:
	if forced_segment >= 0: return forced_segment
	var index := 0
	while index < cuts.size() and x >= cuts[index]: index += 1
	return index

func _tool(material: String, segment: int) -> SurfaceTool:
	var key := "%s|%d" % [material, segment]
	if not _tools.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = surface
	return _tools[key]

## Triângulo com a frente para `normal` (Godot: horário visto de fora, como em _pavement_face).
func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color, data: Vector2) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared() < 1e-12: return
	var points := [a, b, c]
	if cross.dot(normal) > 0.0: points = [a, c, b]
	for point in points:
		surface.set_color(color)
		surface.set_uv(data)
		surface.set_normal(normal)
		surface.add_vertex(point)

func polygon(material: String, points: PackedVector3Array, normal: Vector3, color: Color, data := Vector2(-100.0, 0.0)) -> void:
	var center := Vector3.ZERO
	for point in points: center += point
	center /= float(points.size())
	var surface := _tool(material, _segment(center.x))
	for index in range(1, points.size()-1):
		_tri(surface, points[0], points[index], points[index+1], normal, color, data)

## Extrusão de um perfil convexo (u = lateral, v = altura) ao longo de um caminho horizontal
## de `a` a `b`. Lateral = direção × cima (para +x, lateral é +z). Peças longas são cortadas
## nos limites dos trechos; as tampas só existem nas pontas de verdade.
func extrude(material: String, a: Vector3, b: Vector3, profile: PackedVector2Array, color: Color, data := Vector2(-100.0, 0.0), caps := true) -> void:
	var direction := b-a
	direction.y = 0.0
	if direction.length_squared() < 1e-8: return
	var breaks: Array[float] = [0.0]
	if forced_segment < 0 and absf(b.x-a.x) > 1e-4:
		for cut in cuts:
			var t := (cut-a.x)/(b.x-a.x)
			if t > 1e-4 and t < 1.0-1e-4: breaks.append(t)
	breaks.append(1.0)
	breaks.sort()
	for index in breaks.size()-1:
		var t0: float = breaks[index]
		var t1: float = breaks[index+1]
		_extrude_piece(material, a.lerp(b, t0), a.lerp(b, t1), profile, color, data, caps and index == 0, caps and index == breaks.size()-2)

func _extrude_piece(material: String, a: Vector3, b: Vector3, profile: PackedVector2Array, color: Color, data: Vector2, cap_start: bool, cap_end: bool) -> void:
	var direction := (b-a)
	direction.y = 0.0
	direction = direction.normalized()
	var lateral := direction.cross(Vector3.UP)
	var surface := _tool(material, _segment((a.x+b.x)*.5))
	var centroid := Vector2.ZERO
	for point in profile: centroid += point
	centroid /= float(profile.size())
	var start := PackedVector3Array()
	var finish := PackedVector3Array()
	for point in profile:
		var offset := lateral*point.x + Vector3.UP*point.y
		start.append(a+offset)
		finish.append(b+offset)
	for index in profile.size():
		var next := (index+1)%profile.size()
		var edge := profile[next]-profile[index]
		var outward := Vector2(edge.y, -edge.x).normalized()
		if outward.dot((profile[index]+profile[next])*.5-centroid) < 0.0: outward = -outward
		var normal := (lateral*outward.x + Vector3.UP*outward.y).normalized()
		_tri(surface, start[index], start[next], finish[next], normal, color, data)
		_tri(surface, start[index], finish[next], finish[index], normal, color, data)
	for index in range(1, profile.size()-1):
		if cap_start: _tri(surface, start[0], start[index], start[index+1], -direction, color, data)
		if cap_end: _tri(surface, finish[0], finish[index], finish[index+1], direction, color, data)

## Caixa alinhada (com giro em y opcional) como extrusão de um retângulo ao longo do seu eixo x.
func box(material: String, center: Vector3, size: Vector3, color: Color, rotation_y := 0.0, data := Vector2(-100.0, 0.0)) -> void:
	var axis := Vector3(cos(rotation_y), 0.0, -sin(rotation_y))
	var half := size*.5
	var profile := PackedVector2Array([Vector2(-half.z, -half.y), Vector2(half.z, -half.y), Vector2(half.z, half.y), Vector2(-half.z, half.y)])
	extrude(material, center-axis*half.x, center+axis*half.x, profile, color, data)

## Octógono de meia-largura `half` com cantos chanfrados em `chamfer` (fração da meia-largura).
static func octagon(half: Vector2, chamfer: float) -> PackedVector2Array:
	var c := minf(half.x, half.y)*chamfer
	return PackedVector2Array([
		Vector2(half.x, -half.y+c), Vector2(half.x, half.y-c), Vector2(half.x-c, half.y), Vector2(-half.x+c, half.y),
		Vector2(-half.x, half.y-c), Vector2(-half.x, -half.y+c), Vector2(-half.x+c, -half.y), Vector2(half.x-c, -half.y)])

## Prisma vertical que pode afinar: polígono convexo `bottom` em y0 e `top` em y1 (mesmo
## número de vértices, coordenadas xz relativas a `center`).
func shaft(material: String, center: Vector3, y0: float, bottom: PackedVector2Array, y1: float, top: PackedVector2Array, color: Color, data := Vector2(-100.0, 0.0), cap_bottom := false, cap_top := true) -> void:
	var surface := _tool(material, _segment(center.x))
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for index in bottom.size():
		lower.append(Vector3(center.x+bottom[index].x, y0, center.z+bottom[index].y))
		upper.append(Vector3(center.x+top[index].x, y1, center.z+top[index].y))
	for index in bottom.size():
		var next := (index+1)%bottom.size()
		var normal := (upper[next]-lower[index]).cross(lower[next]-lower[index]).normalized()
		var middle := (lower[index]+lower[next]+upper[index]+upper[next])*.25
		var axis := Vector3(center.x, middle.y, center.z)
		if normal.dot(middle-axis) < 0.0: normal = -normal
		_tri(surface, lower[index], lower[next], upper[next], normal, color, data)
		_tri(surface, lower[index], upper[next], upper[index], normal, color, data)
	for index in range(1, bottom.size()-1):
		if cap_bottom: _tri(surface, lower[0], lower[index], lower[index+1], Vector3.DOWN, color, data)
		if cap_top: _tri(surface, upper[0], upper[index], upper[index+1], Vector3.UP, color, data)

## Uma MeshInstance3D por material e trecho. `settings[material]` = [Material, sombra].
func commit(parent: Node3D, prefix: String, settings: Dictionary) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var keys := _tools.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = str(key).split("|")
		var mesh := (_tools[key] as SurfaceTool).commit()
		if mesh == null or mesh.get_surface_count() == 0: continue
		var instance := MeshInstance3D.new()
		instance.name = "%s_%s_%s" % [prefix, parts[0], parts[1]]
		instance.mesh = mesh
		instance.material_override = settings[parts[0]][0]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings[parts[0]][1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
		result.append(instance)
	_tools.clear()
	return result
