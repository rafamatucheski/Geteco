extends RefCounted
## Continuous visible escarpments owned by surface chunks, never teleport triggers.
const DESERT := preload("res://world/desert/DesertLayout.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const COLLISION_FACES := preload("res://world/chunk_bake/CollisionFaces.gd")
const GROUP := "scenario_boundary"
const WIDTH := 10.0
const INSET := 4.0

static func build_desert(parent: Node3D, rect: Rect2, height: Callable) -> void:
	var bounds := DESERT.BOUNDS
	var west := bounds.position.x + INSET
	var east := bounds.end.x - INSET
	# Leave the north road's existing terminal (-1945) and guardrail accessible.
	var north := bounds.position.y + 1.0
	var south := bounds.end.y - INSET
	_strip(parent, rect, Vector2(west,north), Vector2(west,south), height, false)
	_strip(parent, rect, Vector2(east,north), Vector2(east,south), height, false)
	# The only southern route is the campaign bridge. Its physical deck and
	# shoulders fit inside this opening; the old scattered rocks left 156 m open.
	var bridge_x := DESERT.BRIDGE_END.x
	_strip(parent, rect, Vector2(west,south), Vector2(bridge_x-14,south), height, false)
	_strip(parent, rect, Vector2(bridge_x+14,south), Vector2(east,south), height, false)
	# The mission opens the pass, not an unbuilt next map. A ridge behind its
	# terminal also stops a pedestrian jumping over the existing low guardrail.
	_strip(parent, rect, Vector2(west,north), Vector2(east,north), height, false, 2.0)

static func build_mountain(parent: Node3D, rect: Rect2, height: Callable, blocked: Callable = Callable()) -> void:
	if preload("res://world/regions/MountainTerrain3D.gd").island_enabled():
		build_mountain_coast(parent, rect, height, blocked)
		return
	# Stay on the supported side of the logical seam. The bridge void row
	# (-320..-256) already has its authored shore, rails and tunnel opening.
	var west := CONNECTION.SEAM.x + INSET
	_strip(parent, rect, Vector2(west,-1000000), Vector2(west,-320), height, true)
	_strip(parent, rect, Vector2(west,-256), Vector2(west,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), height, true)
	_strip(parent, rect, Vector2(west,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), Vector2(1000000,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), height, true)

static func _strip(parent: Node3D, rect: Rect2, a: Vector2, b: Vector2, height: Callable, snow: bool, width := WIDTH) -> void:
	var vertical := is_equal_approx(a.x,b.x)
	var fixed := a.x if vertical else a.y
	var low := maxf(a.y if vertical else a.x, rect.position.y if vertical else rect.position.x)
	var high := minf(b.y if vertical else b.x, rect.end.y if vertical else rect.end.x)
	# The wall has one owner, including when a boundary aligns to the grid.
	if high <= low or fixed < (rect.position.x if vertical else rect.position.y) or fixed >= (rect.end.x if vertical else rect.end.y): return
	var cuts: Array[float] = [low]
	var cut := (floorf(low/8.0)+1)*8.0
	while cut < high:
		cuts.append(cut)
		cut += 8.0
	cuts.append(high)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color("939e9f") if snow else Color("ad8c64"))
	for index in range(cuts.size()-1):
		var first := _section(fixed,cuts[index],vertical,height,width)
		var last := _section(fixed,cuts[index+1],vertical,height,width)
		for side in first.size():
			var next := (side+1)%first.size()
			var face: Array=[first[side],first[next],last[next],first[side],last[next],last[side]]
			# Swapping the extrusion axis reverses handedness. Horizontal strips
			# previously rendered their inside, exposing sky through the rock.
			if not vertical: face.reverse()
			for vertex in face:
				surface.set_color(_color(vertex, snow))
				surface.add_vertex(vertex)
		for side in range(1,first.size()-1):
			var caps: Array=[]
			if index==0: caps.append_array([first[0],first[side+1],first[side]])
			if index==cuts.size()-2: caps.append_array([last[0],last[side],last[side+1]])
			if not vertical: caps.reverse()
			for vertex in caps:
				surface.set_color(_color(vertex, snow))
				surface.add_vertex(vertex)
	surface.generate_normals()
	# Malha e colisão das mesmas arrays da CPU: create_trimesh_shape lia a malha de volta da GPU no streaming.
	var built: Array = COLLISION_FACES.commit_with_shape(surface, true)
	var mesh: ArrayMesh = built[0]
	var ridge := MeshInstance3D.new()
	ridge.name = "ScenarioBoundaryRidge"
	ridge.mesh = mesh
	ridge.material_override = preload("res://world/desert/DesertHorizonRelief.gd").material()
	parent.add_child(ridge)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(GROUP)
	var collider := CollisionShape3D.new()
	collider.shape = built[1]
	body.add_child(collider)
	ridge.add_child(body)

static func _section(fixed: float, along: float, vertical: bool, height: Callable, width: float) -> PackedVector3Array:
	var center := Vector2(fixed,along) if vertical else Vector2(along,fixed)
	var floor_y: float = height.call(center)
	var crest := floor_y+9.0+1.2*sin(along*.037)+.6*sin(along*.113)
	var profile := [Vector2(-width*.5,floor_y-18),Vector2(-width*.5,floor_y+.6),Vector2(-width*.43,crest-3),Vector2(-width*.2,crest-.4),Vector2(width*.07,crest),Vector2(width*.43,crest-2.5),Vector2(width*.5,floor_y+.6),Vector2(width*.5,floor_y-18)]
	var points := PackedVector3Array()
	for point: Vector2 in profile:
		var plan := center+(Vector2(point.x,0) if vertical else Vector2(0,point.x))
		points.append(Vector3(plan.x,point.y,plan.y))
	return points

static func _color(point: Vector3, snow: bool) -> Color:
	var variation := .06*sin(point.y*.8+point.x*.07+point.z*.04)
	return (Color("939e9f") if snow else Color("ad8c64")).lightened(variation)

# --- Serra ilha (etapa 4 do mundo orgânico, 26/10/2026) ------------------------------------------------

## O muro da serra acompanha a costa da forma do mundo COAST_INSET m para dentro, em vez das duas retas
## (emenda a oeste e limite norte de Harbor ao sul). Abre onde há estrada ou trilha (`blocked`): pelos
## contratos de test_world_shape só a ponte leste chega à costa; o resto fica a 14 m ou mais dela.
const COAST_INSET := 5.0
const COAST_STEP := 8.0
## Borda de pedra baixa (26/10/2026): o muro usava o perfil dos limites antigos (9 m de altura, 10 m de
## largura) com o material de arenito do deserto e virava uma "montanha de areia" na beira da serra, tapando
## a vista do mar. Agora a pedra fica em COAST_WALL_HEIGHT m; a colisão continua alta (COAST_BLOCK_HEIGHT,
## invisível) para ninguém cair no mar.
const COAST_WALL_WIDTH := 1.8
const COAST_WALL_HEIGHT := 1.1
const COAST_BLOCK_HEIGHT := 3.0
const COAST_ROCK := Color("8a9293")
static var _coast_material: StandardMaterial3D
static var _coast_line := PackedVector2Array()

static func mountain_coast_line() -> PackedVector2Array:
	if not _coast_line.is_empty(): return _coast_line
	var best := 0.0
	for island in preload("res://world/shape/WorldShape.gd").islands():
		if str(island.id) != "mountain": continue
		for polygon in Geometry2D.offset_polygon(island.polygon, -COAST_INSET):
			var area := absf(_area(polygon))
			if area > best:
				best = area
				_coast_line = polygon
	return _coast_line

static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total * .5

static func build_mountain_coast(parent: Node3D, rect: Rect2, height: Callable, blocked: Callable = Callable()) -> void:
	var line := mountain_coast_line()
	if line.size() < 3: return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var block := SurfaceTool.new()
	block.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := false
	var center := GROUND_CUT_CENTER(line)
	for i in line.size():
		var a := line[i]
		var b := line[(i + 1) % line.size()]
		if not rect.grow(COAST_STEP).intersects(Rect2(a, Vector2.ZERO).expand(b), true): continue
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / COAST_STEP))
		var direction := (b - a) / maxf(length, .001)
		var across := Vector2(-direction.y, direction.x)
		# Para fora da ilha: o lado oposto ao centro do contorno.
		if across.dot((a + b) * .5 - center) < 0.0: across = -across
		for k in steps:
			var p := a.lerp(b, float(k) / steps)
			var q := a.lerp(b, float(k + 1) / steps)
			var mid := (p + q) * .5
			# Cada pedaço tem um dono: o trecho que contém o meio dele.
			if not rect.has_point(mid): continue
			if blocked.is_valid() and blocked.call(mid): continue
			_emit_piece(surface, _section_at(p, across, height, COAST_WALL_WIDTH, COAST_WALL_HEIGHT), _section_at(q, across, height, COAST_WALL_WIDTH, COAST_WALL_HEIGHT), mid, direction)
			_emit_piece(block, _section_at(p, across, height, COAST_WALL_WIDTH, COAST_BLOCK_HEIGHT), _section_at(q, across, height, COAST_WALL_WIDTH, COAST_BLOCK_HEIGHT), mid, direction)
			emitted = true
	if not emitted: return
	surface.generate_normals()
	var ridge := MeshInstance3D.new()
	ridge.name = "ScenarioBoundaryRidge"
	ridge.mesh = surface.commit()
	ridge.material_override = coast_material()
	parent.add_child(ridge)
	var built: Array = COLLISION_FACES.commit_with_shape(block, true)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(GROUP)
	var collider := CollisionShape3D.new()
	collider.shape = built[1]
	body.add_child(collider)
	ridge.add_child(body)

## Cor por vértice, opaco e fosco: as mesmas opções do chão-base do WorldSea (pré-aquecido sob a cortina),
## então o motor reaproveita aquele shader e nada compila no jogo.
static func coast_material() -> StandardMaterial3D:
	if _coast_material == null:
		_coast_material = StandardMaterial3D.new()
		_coast_material.vertex_color_use_as_albedo = true
		_coast_material.vertex_color_is_srgb = true
		_coast_material.roughness = 1.0
	return _coast_material

static func GROUND_CUT_CENTER(polygon: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / float(polygon.size())

## Pedra baixa e irregular atravessada ao longo de `across` (normal do trecho da costa), `rise` m acima do chão.
static func _section_at(center: Vector2, across: Vector2, height: Callable, width: float, rise: float) -> PackedVector3Array:
	var floor_y: float = height.call(center)
	var along := center.x * .7 + center.y * .3
	var crest := floor_y + rise + .12 * sin(along * .37) + .08 * sin(along * 1.13)
	var profile := [Vector2(-width*.5,floor_y-3),Vector2(-width*.5,floor_y+.15),Vector2(-width*.32,crest-.18),Vector2(width*.08,crest),Vector2(width*.38,crest-.28),Vector2(width*.5,floor_y+.15),Vector2(width*.5,floor_y-3)]
	var points := PackedVector3Array()
	for point: Vector2 in profile:
		var plan := center + across * point.x
		points.append(Vector3(plan.x, point.y, plan.y))
	return points

## Faces laterais entre duas seções e tampas nas pontas, sempre viradas para fora (o material corta o verso).
static func _emit_piece(surface: SurfaceTool, first: PackedVector3Array, last: PackedVector3Array, mid: Vector2, direction: Vector2) -> void:
	var axis := Vector3(mid.x, 0, mid.y)
	for side in first.size():
		var next := (side + 1) % first.size()
		_face(surface, [first[side], first[next], last[next]], axis)
		_face(surface, [first[side], last[next], last[side]], axis)
	for side in range(1, first.size() - 1):
		_face(surface, [first[0], first[side + 1], first[side]], axis - Vector3(direction.x, 0, direction.y) * 1000.0)
		_face(surface, [last[0], last[side], last[side + 1]], axis + Vector3(direction.x, 0, direction.y) * 1000.0)

static func _face(surface: SurfaceTool, triangle: Array, inside: Vector3) -> void:
	var a: Vector3 = triangle[0]
	var b: Vector3 = triangle[1]
	var c: Vector3 = triangle[2]
	var normal := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0
	var outward := center - Vector3(inside.x, center.y - 4.0, inside.z)
	# Godot desenha a frente no sentido horário: a normal (b-a)×(c-a) aponta para trás da frente.
	if normal.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for vertex in [a, b, c]:
		surface.set_color(COAST_ROCK.lightened(.08 * sin(vertex.x * .9 + vertex.z * .7)))
		surface.add_vertex(vertex)
