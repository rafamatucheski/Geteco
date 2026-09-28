extends Node3D
## Beira de estrada de Mountain: trilha de pedestre e postes de luz.
##
## Os pedestres da V2 nascem a 0,85 m da borda do asfalto e andam paralelos a ele
## (ProductionWorld._create_citizen). Em Harbor isso cai na calçada; em Mountain
## caía no mato, e a serra parecia sem vida (relato do jogador em 2026-09-24).
## Aqui cada estrada de asfalto de Mountain ganha, dos dois lados, uma trilha de
## cascalho e neve pisada exatamente nessa faixa, e postes rústicos de madeira com
## lampião a cada LAMP_SPACING, alternando lados. Só os LIT_LAMPS postes mais
## perto do jogador têm luz de verdade à noite; os outros só brilham o vidro.
##
## Nó próprio (não entra no chunk de NativeRegion): a malha é montada uma vez para
## a região inteira quando Mountain está montada, e some junto com ela.

const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const ROUTE_GEOMETRY := preload("res://world/mountain_detail/MountainRouteGeometry.gd")
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const PATH_INNER := 0.05
const PATH_OUTER := 1.65
const PATH_Y := 0.014
const LAMP_OFFSET := 2.3
const LAMP_SPACING := 50.0
const LIT_LAMPS := 8

var controller
var _region: Node3D
var _paths: MeshInstance3D
var _lamp_points: Array[Vector3] = []
var _lamp_transforms: Array[Transform3D] = []
var _lamp_glass: MultiMeshInstance3D
var _glass_material: StandardMaterial3D
var _lights: Array[OmniLight3D] = []
var _clock := 0.0

func _ready() -> void:
	name = "MountainRoadside"
	for i in LIT_LAMPS:
		var light := OmniLight3D.new()
		light.light_color = Color("ffc98a")
		light.omni_range = 11.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.5: return
	_clock = 0.0
	var region = controller.regions.get("mountain") if controller != null else null
	if not is_instance_valid(region):
		visible = false
		return
	if region != _region:
		_region = region
		_build(region)
	visible = true
	_update_lights()

func _in_crossing(point: Vector3) -> bool:
	# Ponte e túnel têm guarda-corpo e parede próprios; trilha ali atravessaria o vão.
	return point.x < CONNECTION.TUNNEL_END_X + 4.0 and absf(point.z - CONNECTION.CENTER_Z) < 16.0

func _build(region) -> void:
	for child in get_children():
		if child != null and not (child is OmniLight3D): child.queue_free()
	_lamp_points.clear()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lamp_side := 1.0
	var since_lamp := LAMP_SPACING * 0.5
	for road: Dictionary in region.roads:
		if String(road.get("surface", "asphalt")) != "asphalt": continue
		var points: PackedVector3Array = road.points
		var half: float = float(road.width) * 0.5
		# Faixa contínua com emenda em ângulo (miter) em cada vértice: quadriláteros
		# soltos por trecho se sobrepunham nas curvas e pareciam remendos (relato do
		# jogador em 2026-09-24).
		for s in [-1.0, 1.0]: _add_strip(points, half, s, vertices, uvs)
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var along := (b - a) / length
			var side := Vector3(along.z, 0, -along.x)
			var skip := _in_crossing(a) or _in_crossing(b)
			var travelled := 0.0
			while travelled + (LAMP_SPACING - since_lamp) < length:
				travelled += LAMP_SPACING - since_lamp
				since_lamp = 0.0
				var at := a + along * travelled
				if skip or _in_crossing(at): continue
				var lamp_point := at + side * lamp_side * (half + LAMP_OFFSET)
				if region.route_geometry.contains(lamp_point,.7): continue
				_lamp_points.append(lamp_point)
				lamp_side = -lamp_side
			since_lamp += length - travelled
	_paths = MeshInstance3D.new()
	_paths.name = "MountainFootpaths"
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_paths.mesh = mesh
	var path_material := ShaderMaterial.new()
	path_material.shader = preload("res://world/mountain_detail/mountain_footpath.gdshader")
	CONNECTION.configure_ground_material(path_material)
	_paths.material_override = path_material
	_paths.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paths)
	_build_lamps()

func _build_lamps() -> void:
	# Giro calculado uma vez: nearest_road percorre todas as estradas residentes.
	_lamp_transforms.clear()
	for i in _lamp_points.size(): _lamp_transforms.append(_lamp_transform(i))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("4a3526")
	wood.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("22262a")
	iron.roughness = 0.6
	iron.metallic = 0.4
	_glass_material = StandardMaterial3D.new()
	_glass_material.albedo_color = Color("f3d7a1")
	_glass_material.emission_enabled = true
	_glass_material.emission = Color("ffc47a")
	_glass_material.emission_energy_multiplier = 0.0
	var pole := BoxMesh.new()
	pole.size = Vector3(0.2, 3.6, 0.2)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.12, 0.12, 0.9)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.42, 0.1, 0.42)
	var glass := BoxMesh.new()
	glass.size = Vector3(0.3, 0.38, 0.3)
	var parts := [[pole, wood, Vector3(0, 1.8, 0)], [arm, wood, Vector3(0, 3.45, -0.4)], [cap, iron, Vector3(0, 3.3, -0.8)], [glass, _glass_material, Vector3(0, 3.06, -0.8)]]
	for part in parts:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part[0]
		multimesh.instance_count = _lamp_points.size()
		for i in _lamp_points.size():
			multimesh.set_instance_transform(i, _lamp_transforms[i].translated_local(part[2]))
		var instance := MultiMeshInstance3D.new()
		instance.name = "MountainLamp_" + str(parts.find(part))
		instance.multimesh = multimesh
		instance.material_override = part[1]
		add_child(instance)
		if part[1] == _glass_material:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_lamp_glass = instance

## O braço do poste aponta para a estrada (-Z local).
func _lamp_transform(index: int) -> Transform3D:
	var point := _lamp_points[index]
	var road_point: Vector3 = controller.nearest_road(point) if controller.has_method("nearest_road") else point
	var facing := Vector2(road_point.x - point.x, road_point.z - point.z)
	var yaw := atan2(-facing.x, -facing.y) if facing.length() > 0.1 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.0, point.z))

func _update_lights() -> void:
	var weather = controller.session.weather if controller.session != null else null
	var night := 0.0
	if weather != null: night = 1.0 - smoothstep(0.25, 0.70, ATMOSPHERE.daylight_at(float(weather.time_of_day)))
	if _glass_material != null: _glass_material.emission_energy_multiplier = night * 2.5
	var focus: Vector3 = controller.world.player.global_position
	var nearest: Array = []
	if night > 0.02:
		for i in _lamp_points.size():
			var gap := Vector2(_lamp_points[i].x - focus.x, _lamp_points[i].z - focus.z).length_squared()
			if gap < 70.0 * 70.0: nearest.append([gap, i])
		nearest.sort_custom(func(x, y): return x[0] < y[0])
	for k in _lights.size():
		var light := _lights[k]
		if k < nearest.size():
			light.global_transform = _lamp_transforms[nearest[k][1]].translated_local(Vector3(0, 2.9, -0.8))
			light.light_energy = night * 1.6
			light.visible = true
		else:
			light.visible = false

func _add_strip(points: PackedVector3Array, half: float, s: float, vertices: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var inner_edges := ROUTE_GEOMETRY.edges(points,2.0*(half+PATH_INNER))
	var outer_edges := ROUTE_GEOMETRY.edges(points,2.0*(half+PATH_OUTER))
	var inner_prev := Vector3.INF
	var outer_prev := Vector3.INF
	var dist_prev := 0.0
	var dist := 0.0
	for i in points.size():
		if i > 0: dist += points[i].distance_to(points[i - 1])
		var inner: Vector3 = inner_edges[i].left if s > 0 else inner_edges[i].right
		var outer: Vector3 = outer_edges[i].left if s > 0 else outer_edges[i].right
		var crossing := _in_crossing(points[i])
		if i > 0 and inner_prev != Vector3.INF and not crossing:
			var quad := [inner_prev, inner, outer, inner_prev, outer, outer_prev]
			# UV.y em metros, reiniciado a cada 64 m: distância de km perderia precisão no shader.
			var v0 := fmod(dist_prev, 64.0)
			var v1 := v0 + dist - dist_prev
			var quad_uv := [Vector2(0, v0), Vector2(0, v1), Vector2(1, v1), Vector2(0, v0), Vector2(1, v1), Vector2(1, v0)]
			for triangle in 2:
				var k := triangle*3
				_append_clipped_triangle(quad[k],quad[k+1],quad[k+2],quad_uv[k],quad_uv[k+1],quad_uv[k+2],vertices,uvs)
		inner_prev = Vector3.INF if crossing else inner
		outer_prev = outer
		dist_prev = dist

func _append_clipped_triangle(a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, vertices: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var origin := Vector2(a.x,a.z)
	var axis_b := Vector2(b.x,b.z)-origin
	var axis_c := Vector2(c.x,c.z)-origin
	var determinant := axis_b.cross(axis_c)
	if absf(determinant) < .000001: return
	var shape := PackedVector2Array([origin,origin+axis_b,origin+axis_c])
	if Geometry2D.is_polygon_clockwise(shape): shape.reverse()
	# Cut the actual polygons, including the main road shoulder at each branch.
	# No fragment overlay or raised curb remains across the carriageway.
	for piece in _region.route_geometry.outside_roads(shape):
		for index in Geometry2D.triangulate_polygon(piece):
			var point: Vector2 = piece[index]
			var delta := point-origin
			var weight_b := delta.cross(axis_c)/determinant
			var weight_c := axis_b.cross(delta)/determinant
			vertices.append(Vector3(point.x,PATH_Y,point.y))
			uvs.append(uv_a+(uv_b-uv_a)*weight_b+(uv_c-uv_a)*weight_c)
