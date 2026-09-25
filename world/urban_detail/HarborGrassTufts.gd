extends RefCounted
## Tufos de grama 3D para os gramados do Harbor (pátio do Neco, cemitério). Os gramados
## eram caixas de cor lisa herdadas do desenho 2D da V1 e liam como chão chapado
## (feedback de 25/09/2026). Um MultiMesh por gramado, sem sombra: o custo é uma
## chamada de desenho por área.
##
## Os tufos evitam retângulos informados (pátio, túmulos, caminhos) e o asfalto e as
## calçadas da região (`NativeRegion.roads`), para não atravessar rua.

const MAX_TUFTS := 3200
static var _mesh: ArrayMesh
static var _material: StandardMaterial3D
static var _grounds: Dictionary = {}

## Chão de gramado e de cascalho: ruído suave, projetado no mundo. O ladrilho
## genérico do UrbanGround mostrava um padrão repetido de manchas nessas áreas.
static func ground_material(kind := "grass") -> StandardMaterial3D:
	if _grounds.has(kind): return _grounds[kind]
	var gravel := kind == "gravel"
	var noise := FastNoiseLite.new()
	noise.seed = 3107 if not gravel else 5519
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR if gravel else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05 if gravel else 0.012
	noise.fractal_octaves = 3 if gravel else 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color("6f6a5c") if gravel else Color("3f5234"))
	ramp.set_color(1, Color("b1a88f") if gravel else Color("6e8450"))
	ramp.add_point(0.55, Color("958d77") if gravel else Color("56693f"))
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	texture.generate_mipmaps = true
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * (0.12 if gravel else 0.06)
	material.roughness = 0.95
	_grounds[kind] = material
	return material

## `area` e `exclude` em XZ local de `parent`. `density` em tufos por m².
static func scatter(parent: Node3D, area: Rect2, exclude: Array, density: float, seed_value: int, top_y := 0.012) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var segments := _road_segments(parent, area)
	var wanted := mini(MAX_TUFTS, int(area.get_area() * density))
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for attempt in wanted * 2:
		if transforms.size() >= wanted: break
		var point := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		# Manchas: a grama fica mais densa em umas partes e rala em outras.
		if noise.get_noise_2d(point.x, point.y) < -0.25 and rng.randf() < 0.7: continue
		if _excluded(point, exclude): continue
		var world := parent.to_global(Vector3(point.x, 0, point.y))
		if _on_road(Vector2(world.x, world.z), segments): continue
		var scale := rng.randf_range(0.7, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.25), scale))
		transforms.append(Transform3D(basis, Vector3(point.x, top_y, point.y)))
		var shade := rng.randf_range(-0.06, 0.08)
		tints.append(Color(0.85 + shade, 0.95 + shade, 0.8 + shade * 0.5))
	if transforms.is_empty(): return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _tuft_mesh()
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, tints[index])
	var display := MultiMeshInstance3D.new()
	display.name = "GrassTufts"
	display.multimesh = multimesh
	display.material_override = _tuft_material()
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(display)
	return display

static func _excluded(point: Vector2, exclude: Array) -> bool:
	for rect in exclude:
		if (rect as Rect2).has_point(point): return true
	return false

## Trechos de rua/calçada que passam perto da área, em XZ do mundo: [a, b, meia largura].
static func _road_segments(parent: Node3D, area: Rect2) -> Array:
	var region: Node = parent
	while region != null and not ("roads" in region): region = region.get_parent()
	if region == null: return []
	var first := parent.to_global(Vector3(area.position.x, 0, area.position.y))
	var bounds := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for corner in [area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
		var world := parent.to_global(Vector3(corner.x, 0, corner.y))
		bounds = bounds.expand(Vector2(world.x, world.z))
	var result := []
	var sources: Array = region.roads.duplicate()
	if "walkways" in region: sources.append_array(region.walkways)
	for road in sources:
		var points: PackedVector3Array = road.points
		var half := float(road.width) * 0.5 + 0.8
		for index in points.size() - 1:
			var a := Vector2(points[index].x, points[index].z)
			var b := Vector2(points[index + 1].x, points[index + 1].z)
			if not Rect2(a, Vector2.ZERO).expand(b).grow(half).intersects(bounds): continue
			result.append([a, b, half])
	return result

static func _on_road(point: Vector2, segments: Array) -> bool:
	for segment in segments:
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		if closest.distance_to(point) < float(segment[2]): return true
	return false

## Tufo: sete folhas finas em leque, base escura e ponta clara (cor por vértice).
static func _tuft_mesh() -> ArrayMesh:
	if _mesh != null: return _mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for blade in 7:
		var yaw := TAU * float(blade) / 7.0 + rng.randf_range(-0.3, 0.3)
		var lean := rng.randf_range(0.05, 0.14)
		var height := rng.randf_range(0.18, 0.34)
		var width := rng.randf_range(0.025, 0.04)
		var direction := Vector3(sin(yaw), 0, cos(yaw))
		var side := Vector3(cos(yaw), 0, -sin(yaw)) * width
		var base := direction * rng.randf_range(0.0, 0.05)
		var tip := base + direction * lean + Vector3.UP * height
		var normal := (direction * -0.3 + Vector3.UP).normalized()
		for vertex in [[base - side, Color("2f4a25")], [base + side, Color("2f4a25")], [tip, Color("7f9a4f")]]:
			tool.set_color(vertex[1])
			tool.set_normal(normal)
			tool.add_vertex(vertex[0])
	_mesh = tool.commit()
	return _mesh

static func _tuft_material() -> StandardMaterial3D:
	if _material != null: return _material
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.roughness = 0.95
	return _material
