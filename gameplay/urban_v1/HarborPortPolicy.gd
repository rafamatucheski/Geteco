extends RefCounted
## Limites entre a via pública e a área de operação do Porto Sul.
const LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const SCALE := 16.0

static func is_private_road(road: Dictionary) -> bool:
	var id := str(road.get("id", ""))
	# O acesso de oficina/serviço e o pátio sem saída do Neco são destinos do jogador,
	# não rotas de passagem para a população ambiente.
	return id.begins_with("south_port_") or id in ["salvage_access", "westgate_service_lane"]

static func ambient_roads(roads: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road in roads:
		if not road is Dictionary or is_private_road(road): continue
		var points: PackedVector3Array = road.get("points", PackedVector3Array())
		var width := float(road.get("width", 7.5))
		var enters_port := false
		for index in range(points.size() - 1):
			if segment_enters_private_area(points[index], points[index + 1], width * 0.5 + 0.85):
				enters_port = true
				break
		if not enters_port: result.append(road)
	return result

## Casco e seu retângulo calculados uma vez: contains_private_area roda milhares de vezes por
## rota em route_is_ambient_safe, e ship_hull() aloca um PackedVector2Array a cada chamada.
static var _hull: PackedVector2Array = PackedVector2Array()
static var _hull_bounds := Rect2()

static func contains_private_area(point: Vector3) -> bool:
	if not point.is_finite(): return false
	var authored := Vector2(point.x * SCALE, point.z * SCALE)
	if LAYOUT.LAND.has_point(authored) or LAYOUT.WALKWAY.has_point(authored): return true
	if _hull.is_empty():
		_hull = LAYOUT.ship_hull()
		_hull_bounds = Rect2(_hull[0], Vector2.ZERO)
		for vertex in _hull: _hull_bounds = _hull_bounds.expand(vertex)
		# Folga: Rect2.has_point exclui a borda máxima, que o polígono inclui.
		_hull_bounds = _hull_bounds.grow(1.0)
	if _hull_bounds.has_point(authored) and Geometry2D.is_point_in_polygon(authored, _hull): return true
	for pier in LAYOUT.PIERS:
		if pier.has_point(authored): return true
	return false

static func segment_enters_private_area(start: Vector3, finish: Vector3, margin: float = 0.0) -> bool:
	var direction := finish - start
	direction.y = 0.0
	var length := direction.length()
	var side := direction.normalized().cross(Vector3.UP) * margin if length > 0.001 else Vector3.ZERO
	var steps := maxi(1, ceili(length / 1.0))
	for index in range(steps + 1):
		var point := start.lerp(finish, float(index) / float(steps))
		if contains_private_area(point): return true
		if margin > 0.0 and (contains_private_area(point + side) or contains_private_area(point - side)): return true
	return false

static func route_is_ambient_safe(route: Curve3D) -> bool:
	if route == null or route.get_baked_length() < 0.1: return false
	# Rotas de NativeTrafficRoutes.route_near (com "traffic_nodes") são compartilhadas e nunca
	# alteradas depois de montadas: o veredito da varredura de 1 m vale para sempre.
	if route.has_meta("ambient_safe_verdict"): return bool(route.get_meta("ambient_safe_verdict"))
	var safe := _scan_ambient_safe(route)
	if route.has_meta("traffic_nodes"): route.set_meta("ambient_safe_verdict", safe)
	return safe

## Amostras a cada <= 1 m. Cada trecho entre amostras tem <= 1 m, então segment_enters_private_area
## só testava as duas pontas: testar cada amostra uma vez dá o mesmo veredito pela metade do custo.
## Antes disso, uma rota cujo envoltório (pontos e alças de Bézier: a curva fica dentro dele) não
## toca nenhuma área privada é pública sem amostrar: quase todas as ruas da cidade.
static func _scan_ambient_safe(route: Curve3D) -> bool:
	if not _route_bounds(route).intersects(_private_bounds()): return true
	var length := route.get_baked_length()
	var steps := maxi(1, ceili(length / 1.0))
	for index in range(steps + 1):
		if contains_private_area(route.sample_baked(length * float(index) / float(steps), true)): return false
	return true

static func _route_bounds(route: Curve3D) -> Rect2:
	var bounds := Rect2(Vector2(route.get_point_position(0).x, route.get_point_position(0).z) * SCALE, Vector2.ZERO)
	for i in route.point_count:
		var at := route.get_point_position(i)
		for point: Vector3 in [at, at + route.get_point_in(i), at + route.get_point_out(i)]:
			bounds = bounds.expand(Vector2(point.x, point.z) * SCALE)
	# Folga de 1 m (16 unidades autorais) para o arredondamento do bake e bordas inclusivas.
	return bounds.grow(SCALE)

static var _private_union := Rect2()

static func _private_bounds() -> Rect2:
	if _private_union.has_area(): return _private_union
	contains_private_area(Vector3.ZERO) # inicializa o casco em cache
	var union := LAYOUT.LAND.merge(LAYOUT.WALKWAY).merge(_hull_bounds)
	for pier in LAYOUT.PIERS: union = union.merge(pier)
	_private_union = union
	return union
