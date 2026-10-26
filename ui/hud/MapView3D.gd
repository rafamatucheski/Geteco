extends SubViewportContainer
## Mapa da tecla M em maquete 3D (mundo orgânico, etapa 5, 26/10/2026; visual aprovado em
## docs/design/mapa-3d-tecla-m-20261026.html). Fica por baixo da camada de ícones do MapUI: o MapUI
## continua dono de filtros, seleção, rota e destino e só troca project()/unproject() pelos daqui.
##
## O que aparece é o mundo físico: o mar e o chão-base são as mesmas malhas do WorldSea, as cordilheiras
## do deserto são a geometria do DesertHorizonRelief e o relevo da serra vem do próprio terreno (com a altura
## exagerada para ler como maquete). Estradas e prédios saem do WorldMapData. Só materiais que o jogo já
## compila (oceano, chão-base de cor por vértice, arenito): abrir o mapa não compila shader.
## As malhas ficam guardadas no mundo (meta "map3d_cache") e só os nós são recriados a cada abertura.
const SEA := preload("res://world/shape/WorldSea.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const RELIEF := preload("res://world/desert/DesertHorizonRelief.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const FOV := 34.0
const PITCH := 0.88
## Altura da serra no mapa: o chão real tem poucos metros; multiplicado lê como montanha.
const MOUNTAIN_EXAGGERATION := 6.0
const MARKER_LIFT := 3.0
var viewport: SubViewport
var camera: Camera3D
var scene: Node3D
var mountain_sampler: Callable
var yaw := 0.0

func configure(controller, atlas) -> void:
	name = "MapView3D"
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.handle_input_locally = false
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0b161b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cfdbe0")
	environment.environment.ambient_light_energy = .55
	environment.environment.fog_enabled = true
	environment.environment.fog_light_color = Color("0b161b")
	environment.environment.fog_density = .00018
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -125, 0)
	sun.light_energy = 1.15
	viewport.add_child(sun)
	camera = Camera3D.new()
	# Sem interpolação de física: com o jogo pausado no mapa não há tique de física, e a câmera interpolada
	# ficaria parada na posição antiga (a projeção dos ícones também).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = FOV
	camera.near = 5.0
	camera.far = 9000.0
	viewport.add_child(camera)
	camera.current = true
	mountain_sampler = _mountain_sampler(controller)
	scene = Node3D.new()
	scene.name = "MapScene"
	viewport.add_child(scene)
	var cache: Dictionary = _cache(controller, atlas)
	for item in cache.pieces:
		var node := MeshInstance3D.new()
		node.mesh = item[0]
		node.material_override = item[1]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(node)

## Câmera olhando o ponto `center` do chão, girada por `yaw`, numa distância que mantém a escala do mapa
## 2D (px por metro) no centro da tela.
func sync(center: Vector2, pixels_per_metre: float, rotation_yaw: float) -> void:
	yaw = rotation_yaw
	var height_px := maxf(1.0, size.y)
	var visible_metres := height_px / maxf(pixels_per_metre, .0001)
	var distance := visible_metres * .5 / tan(deg_to_rad(FOV) * .5)
	var target := Vector3(center.x, 0.0, center.y)
	var horizontal := distance * sin(PITCH)
	camera.position = target + Vector3(sin(yaw) * horizontal, distance * cos(PITCH), cos(yaw) * horizontal)
	camera.look_at(target, Vector3.UP)

func height_at(point: Vector2) -> float:
	if mountain_sampler.is_valid() and SHAPE.field_distance("mountain", point) > -2.0:
		return maxf(0.0, float(mountain_sampler.call(point))) * MOUNTAIN_EXAGGERATION + .3
	return .3

func project(point: Vector2) -> Vector2:
	var at := Vector3(point.x, height_at(point) + MARKER_LIFT, point.y)
	if camera.is_position_behind(at): return Vector2(-99999, -99999)
	return camera.unproject_position(at)

## Inverso de project(): cruza o raio da tela com a mesma altura em que os ícones são desenhados
## (relevo + MARKER_LIFT), refinando três vezes pelo relevo da serra. Clique e destino caem no lugar certo.
func unproject(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < .0001: return Vector2(origin.x, origin.z)
	var level := .3 + MARKER_LIFT
	var hit := Vector2.ZERO
	for i in 3:
		var t := (level - origin.y) / direction.y
		var at := origin + direction * t
		hit = Vector2(at.x, at.z)
		level = height_at(hit) + MARKER_LIFT
	return hit

## Arrasto na tela vira deslocamento no chão, seguindo a rotação.
func pan_delta(relative: Vector2, pixels_per_metre: float) -> Vector2:
	return relative.rotated(-yaw) / maxf(pixels_per_metre, .0001)

# --- Malhas (guardadas no mundo entre aberturas) ---------------------------------------------------

static func _mountain_sampler(controller) -> Callable:
	if not controller.world is Node: return Callable()
	var production = controller.world.get("production")
	if production == null: return Callable()
	var regions: Dictionary = {}
	regions.merge(production.get("_region_cache") if production.get("_region_cache") is Dictionary else {})
	regions.merge(production.get("regions") if production.get("regions") is Dictionary else {}, true)
	var mountain = regions.get("mountain")
	if mountain == null or mountain.get("terrain") == null: return Callable()
	# _calculate_height é o amostrador só de leitura (não mexe no cache de alturas do jogo).
	return mountain.terrain._calculate_height

func _cache(controller, atlas) -> Dictionary:
	var owner_node: Node = controller.world if controller.world is Node else null
	if owner_node != null and owner_node.has_meta("map3d_cache"): return owner_node.get_meta("map3d_cache")
	var began := STALL_WORK.begin()
	var pieces: Array = []
	var base_material: Material = null
	var production = owner_node.get("production") if owner_node != null else null
	var sea = production.get("world_sea") if production != null else null
	if sea is Node and is_instance_valid(sea):
		base_material = sea.get("base_material")
		for child in sea.get_children():
			if child is MeshInstance3D and child.mesh != null: pieces.append([child.mesh, child.material_override])
	if base_material == null:
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		fallback.vertex_color_is_srgb = true
		fallback.roughness = 1.0
		base_material = fallback
	var relief: Node3D = RELIEF.build()
	for child in relief.get_children():
		if child is MeshInstance3D: pieces.append([child.mesh, child.material_override])
	relief.free()
	var mountain := _mountain_mesh()
	if mountain != null: pieces.append([mountain, base_material])
	var roads := _road_mesh(atlas)
	if roads != null: pieces.append([roads, base_material])
	var buildings := _building_mesh(atlas)
	if buildings != null: pieces.append([buildings, base_material])
	var cache := {"pieces": pieces}
	if owner_node != null: owner_node.set_meta("map3d_cache", cache)
	STALL_WORK.finish("map3d.cache", began)
	return cache

func _mountain_mesh() -> ArrayMesh:
	if not mountain_sampler.is_valid(): return null
	var bounds := Rect2()
	for island in SHAPE.islands():
		if str(island.id) == "mountain": bounds = (island.bounds as Rect2).grow(8.0)
	if not bounds.has_area(): return null
	var step := 8.0
	var columns := ceili(bounds.size.x / step)
	var rows := ceili(bounds.size.y / step)
	var heights := PackedFloat32Array()
	for z in rows + 1:
		for x in columns + 1:
			var p := bounds.position + Vector2(x, z) * step
			var coast := SHAPE.field_distance("mountain", p)
			heights.append(height_at(p) if coast > 0.0 else -3.0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in rows:
		for x in columns:
			var quad: Array = []
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var cx: int = x + corner.x
				var cz: int = z + corner.y
				quad.append(Vector3(bounds.position.x + cx * step, heights[cz * (columns + 1) + cx], bounds.position.y + cz * step))
			if quad.all(func(v: Vector3) -> bool: return v.y < -1.0): continue
			for index in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[index]
				surface.set_color(_mountain_color(v.y))
				surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()

static func _mountain_color(y: float) -> Color:
	if y < .6: return Color("7a8382")
	return Color("6f7a70").lerp(Color("eef3f5"), smoothstep(6.0, 26.0, y))

func _road_mesh(atlas) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for road in atlas.roads:
		var points: PackedVector2Array = road.points
		if points.size() < 2: continue
		var kind := str(road.surface)
		var color := Color("e9e6da")
		var width := maxf(float(road.width), 4.0)
		if kind in ["earth", "footpath", "dirt"]: color = Color("c9b48c"); width = maxf(float(road.width), 2.5)
		elif kind == "railway": color = Color("3a3d40"); width = 3.0
		elif kind in ["ski", "cable"]: color = Color("9edcff") if kind == "ski" else Color("2a2d30"); width = 1.6
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var direction := (b - a).normalized()
			var side := Vector2(-direction.y, direction.x) * width * .5
			var lift := 12.0 if kind == "railway" else 24.0 if kind == "cable" else .5
			var ya := height_at(a) + lift
			var yb := height_at(b) + lift
			var quad := [Vector3(a.x + side.x, ya, a.y + side.y), Vector3(b.x + side.x, yb, b.y + side.y), Vector3(b.x - side.x, yb, b.y - side.y), Vector3(a.x - side.x, ya, a.y - side.y)]
			_double(surface, quad[0], quad[1], quad[2], Vector3.UP, color)
			_double(surface, quad[0], quad[2], quad[3], Vector3.UP, color)
			any = true
	return surface.commit() if any else null

func _building_mesh(atlas) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tones := [Color("9a9d97"), Color("b0a899"), Color("8a9294"), Color("c0b6a4"), Color("b5654d")]
	var k := 0
	for polygon: PackedVector2Array in atlas.buildings:
		if polygon.size() < 3: continue
		k += 1
		var center := Vector2.ZERO
		for p in polygon: center += p
		center /= polygon.size()
		var desert := SHAPE.island_at(center) == "desert"
		var downtown := smoothstep(280.0, 40.0, center.distance_to(Vector2(90, 60)))
		var seed_value := absi(hash(center.round()))
		var height := 5.0 if desert else 7.0 + float(seed_value % 13) + downtown * float(seed_value % 37)
		var base := height_at(center)
		var color: Color = Color("d8b98b") if desert else tones[k % tones.size()]
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var wall := [Vector3(a.x, base, a.y), Vector3(b.x, base, b.y), Vector3(b.x, base + height, b.y), Vector3(a.x, base + height, a.y)]
			var mid := (a + b) * .5 - center
			var outward := Vector3(mid.x, 0, mid.y).normalized()
			_double(surface, wall[0], wall[1], wall[2], outward, color.darkened(.12))
			_double(surface, wall[0], wall[2], wall[3], outward, color.darkened(.12))
		var roof := Geometry2D.triangulate_polygon(polygon)
		for i in range(0, roof.size(), 3):
			var top := func(index: int) -> Vector3: return Vector3(polygon[roof[index]].x, base + height, polygon[roof[index]].y)
			_double(surface, top.call(i), top.call(i + 1), top.call(i + 2), Vector3.UP, color.lightened(.08))
	if k == 0: return null
	return surface.commit()

## Triângulo dos dois lados com a mesma normal: estradas e prédios não dependem do sentido do polígono e o
## material do chão-base corta o verso.
static func _double(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	for triangle in [[a, b, c], [a, c, b]]:
		for vertex in triangle:
			surface.set_color(color)
			surface.set_normal(normal)
			surface.add_vertex(vertex)
