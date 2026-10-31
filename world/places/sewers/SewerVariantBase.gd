extends Node3D
## Base dos esgotos novos. A sala fica centrada na origem, em metros (o Esgoto da V1 usa pixels de origem).
## `solid_rects` (id -> Rect2 no plano XZ) vira colisão no `NativePlace`; cada peça com `solid` entra ali.
## Subclasses definem REWARDS e RESIDENTS (lidos por `SewerNetwork.decorate`) e implementam `_build()`.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
var solid_rects: Dictionary = {}
var half := Vector2(8, 5)
var _palette: Dictionary = {}
var _solid_counter := 0
## Luzes da sala, para as capturas e testes de revisão.
var lights: Array[OmniLight3D] = []
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const DARKNESS := preload("res://world/places/sewers/SewerDarkness.gd")
## Humor da sala (escuridão por cima do 3D, `SewerDarkness`): tint, base/edge = opacidade no centro e nas bordas.
var mood := {"tint": Color(0.012, 0.02, 0.02), "base": 0.6, "edge": 0.88, "halo": 3.2, "halo_strength": 0.5}
var _rng := RandomNumberGenerator.new()
var _floor_base: MeshInstance3D
var _floor_tiles: MultiMeshInstance3D
var _floor_area := Rect2()
var _floor_pieces: Array[Dictionary] = []

func room_size() -> Vector2:
	return half * 2.0

func _ready() -> void:
	_rng.seed = hash(str(get_script().resource_path))
	_build()
	var avoid_rects: Array = solid_rects.values()
	# NativePlace consumes tagged, transformed bounds. Keep the authored footprints
	# during dressing, then remove their duplicate bodies before room admission.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("source_solid_rect"): solid_rects.erase(mesh.get_meta("source_solid_rect"))
	add_child(preload("res://audio/sewers/SewerAmbience.gd").new())
	var darkness := DARKNESS.new()
	add_child(darkness)
	darkness.configure(self, mood)
	# Ratos e baratas correndo pela sala (só se mexem com o jogador dentro dela).
	var critters := preload("res://world/places/sewers/SewerCritters.gd").new()
	add_child(critters)
	critters.configure(half, avoid_rects)

func _build() -> void:
	pass

func _mat(color: String, metal := false, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color, metal, glow]
	if not _palette.has(key):
		var material: StandardMaterial3D
		if glow > 0.0:
			# Lâmpadas e brasas continuam chapadas: textura apagaria o brilho.
			material = StandardMaterial3D.new()
			material.albedo_color = Color(color)
			material.roughness = 0.62 if metal else 0.93
			material.metallic = 0.45 if metal else 0.0
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = glow
		else:
			material = SURFACES.material("sewer_" + key, "metal" if metal else "concrete", Color(color),
				0.62 if metal else 0.9, 0.45 if metal else 0.0, 1.0 if metal else 2.0, 1.3)
		_palette[key] = material
	return _palette[key]

func _add_solid(center: Vector3, size: Vector3, solid: String) -> void:
	_solid_counter += 1
	solid_rects["%s_%d" % [solid, _solid_counter]] = Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)

func box(center: Vector3, size: Vector3, color: String, metal := false, solid := "", glow := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, metal, glow)
	instance.position = center
	add_child(instance)
	if solid != "":
		_add_solid(center, size, solid)
		instance.set_meta("interior_solid_id", "%sMesh_%d" % [solid, _solid_counter])
		instance.set_meta("source_solid_rect", "%s_%d" % [solid, _solid_counter])
	return instance

func cyl(center: Vector3, radius: float, height: float, color: String, metal := false, solid := "", glow := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, metal, glow)
	instance.position = center
	add_child(instance)
	if solid != "":
		_add_solid(center, Vector3(radius * 2.0, height, radius * 2.0), solid)
		instance.set_meta("interior_solid_id", "%sMesh_%d" % [solid, _solid_counter])
		instance.set_meta("source_solid_rect", "%s_%d" % [solid, _solid_counter])
	return instance

func pipe(a: Vector3, b: Vector3, radius: float, color: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color, true)
	add_child(instance)
	instance.position = (a + b) * 0.5
	var axis := (b - a).normalized()
	instance.basis = Basis(Quaternion(Vector3.UP, axis)) if absf(axis.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	# Thin fishing rods, ropes and secret pipe curtains remain passable.
	if radius >= .08 and minf(a.y, b.y) - radius < 2.1:
		_solid_counter += 1
		instance.set_meta("interior_solid_id", "PipeMesh_%d" % _solid_counter)
	return instance

## Piso de pedra com ladrilhos de tons variados (um MultiMesh) e a laje escura por baixo.
func floor_slab(rect: Rect2, base := "#151b1b", tone_set := ["#3b403a", "#40443a", "#34403b", "#443f2f"]) -> void:
	_floor_area = rect
	_floor_base = box(Vector3(rect.get_center().x, -0.16, rect.get_center().y), Vector3(rect.size.x, 0.3, rect.size.y), base)
	var tile := Vector2(1.9, 1.4)
	var columns := int(rect.size.x / tile.x)
	var rows := int(rect.size.y / tile.y)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile.x - 0.08, 0.03, tile.y - 0.08)
	multi.mesh = mesh
	multi.instance_count = columns * rows
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.size.x * 31.0 + rect.size.y * 17.0)
	var tones: Array = []
	for tone in tone_set: tones.append(Color(tone))
	var index := 0
	var origin_x := rect.get_center().x - columns * tile.x * 0.5
	var origin_z := rect.get_center().y - rows * tile.y * 0.5
	for row in rows:
		for column in columns:
			var origin := Vector3(origin_x + tile.x * (column + 0.5), -0.005, origin_z + tile.y * (row + 0.5))
			multi.set_instance_transform(index, Transform3D(Basis(), origin))
			multi.set_instance_color(index, (tones[rng.randi_range(0, 3)] as Color).srgb_to_linear())
			_floor_pieces.append({"rect": Rect2(origin.x - (tile.x-.08)*.5, origin.z - (tile.y-.08)*.5, tile.x-.08, tile.y-.08), "color": multi.get_instance_color(index)})
			index += 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	SURFACES.detail(material, "paving", 2.0, 1.2)
	instance.material_override = material
	add_child(instance)
	_floor_tiles = instance

func _subtract_rect(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var hit := rect.intersection(cut)
	if not hit.has_area(): return [rect]
	var parts: Array[Rect2] = []
	for part in [Rect2(rect.position, Vector2(rect.size.x, hit.position.y-rect.position.y)),
		Rect2(Vector2(rect.position.x, hit.end.y), Vector2(rect.size.x, rect.end.y-hit.end.y)),
		Rect2(Vector2(rect.position.x, hit.position.y), Vector2(hit.position.x-rect.position.x, hit.size.y)),
		Rect2(Vector2(hit.end.x, hit.position.y), Vector2(rect.end.x-hit.end.x, hit.size.y))]:
		if part.has_area(): parts.append(part)
	return parts

func _open_channel(rect: Rect2) -> void:
	if not is_instance_valid(_floor_base): return
	var material := _floor_base.material_override
	_floor_base.hide()
	# Basin bed below the water, dry banks at the original walking height.
	var basin := box(Vector3(rect.get_center().x, -.46, rect.get_center().y), Vector3(rect.size.x,.12,rect.size.y), "#0b1412")
	basin.name = "ChannelBed"
	for part in _subtract_rect(_floor_area, rect):
		var bank := box(Vector3(part.get_center().x, -.16, part.get_center().y), Vector3(part.size.x,.3,part.size.y), "#151b1b")
		bank.material_override = material
	var pieces: Array[Dictionary] = []
	for tile in _floor_pieces:
		for part in _subtract_rect(tile.rect, rect): pieces.append({"rect":part,"color":tile.color})
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	multi.mesh = mesh
	multi.instance_count = pieces.size()
	for i in pieces.size():
		var part: Rect2 = pieces[i].rect
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(part.size.x,.03,part.size.y)), Vector3(part.get_center().x,-.005,part.get_center().y)))
		multi.set_instance_color(i, pieces[i].color)
	_floor_tiles.multimesh = multi

## Paredes: fundo alto e frente baixa mantêm a leitura da câmera fixa.
func walls(back_height := 2.8, side_height := 1.0, front_height := 0.35, color := "#3b4237") -> void:
	var t := 0.5
	# Camera cutaways retain their complete light-blocking silhouette.
	for bounds in [AABB(Vector3(-half.x-t,0,half.y),Vector3(half.x*2.0+t*2.0,2.8,t)), AABB(Vector3(-half.x-t,0,-half.y),Vector3(t,2.8,half.y*2.0)), AABB(Vector3(half.x,0,-half.y),Vector3(t,2.8,half.y*2.0))]:
		var blocker := box(bounds.get_center(), bounds.size, color)
		var shadow_mesh := ArrayMesh.new()
		shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, MESH_ARRAYS.arrays_of(blocker.mesh, 0))
		blocker.mesh = shadow_mesh
		blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	box(Vector3(0, back_height * 0.5, -half.y - t * 0.5), Vector3(half.x * 2.0 + t * 2.0, back_height, t), color, false, "BackWall")
	box(Vector3(0, front_height * 0.5, half.y + t * 0.5), Vector3(half.x * 2.0 + t * 2.0, front_height, t), color, false, "FrontWall")
	for side in [-1.0, 1.0]:
		box(Vector3(side * (half.x + t * 0.5), side_height * 0.5, 0), Vector3(t, side_height, half.y * 2.0), color, false, "SideWall")
	# Faixas de tijolo mais claro no fundo, para o muro não ser um bloco liso.
	for course in 3:
		box(Vector3(0, 0.45 + course * 0.8, -half.y + 0.02), Vector3(half.x * 2.0, 0.06, 0.05), "#4a5143")
	# Staggered masonry has actual relief, batched into one draw per room.
	var masonry := MultiMesh.new()
	masonry.transform_format = MultiMesh.TRANSFORM_3D
	masonry.use_colors = true
	var brick := BoxMesh.new()
	brick.size = Vector3(.68,.24,.09)
	masonry.mesh = brick
	var columns := int(half.x * 2.0 / .72)
	var courses := int(back_height / .28)
	masonry.instance_count = columns * courses
	for row in courses:
		for column in columns:
			var index := row * columns + column
			masonry.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(-half.x+.4+column*.72+(row%2)*.16,.14+row*.28,-half.y+.035)))
			masonry.set_instance_color(index, (Color(color) * _rng.randf_range(.9,1.22)).srgb_to_linear())
	var bricks := MultiMeshInstance3D.new()
	bricks.multimesh = masonry
	var surface := StandardMaterial3D.new()
	surface.vertex_color_use_as_albedo = true
	surface.roughness = .95
	SURFACES.detail(surface, "brick", 2.0, 1.3)
	bricks.material_override = surface
	add_child(bricks)

func ladder(at: Vector3, rail_color := "#b0a276", rung_color := "#c6b37f", base_color := "#182728") -> void:
	box(at + Vector3(0, 0.03, 0), Vector3(1.0, 0.04, 0.9), base_color)
	for x in [-0.27, 0.27]: cyl(at + Vector3(x, 1.0, 0), 0.035, 2.0, rail_color, true)
	for rung in 7: box(at + Vector3(0, 0.17 + rung * 0.29, 0), Vector3(0.56, 0.05, 0.05), rung_color, true)

## Fogueira de acampamento: anel de pedras, lenha e chama com luz que pisca.
func campfire(at: Vector3, energy := 2.0) -> void:
	for index in 8:
		var angle := TAU * float(index) / 8.0
		box(at + Vector3(cos(angle) * 0.32, 0.07, sin(angle) * 0.32), Vector3(0.18, 0.14, 0.14), "#4a4237", false, "").rotation.y = angle
	box(at + Vector3(0, 0.08, 0), Vector3(0.5, 0.1, 0.08), "#2a1c10").rotation.y = 0.5
	box(at + Vector3(0, 0.08, 0), Vector3(0.5, 0.1, 0.08), "#2a1c10").rotation.y = -0.5
	_solid_counter += 1
	solid_rects["Campfire_%d" % _solid_counter] = Rect2(at.x - 0.4, at.z - 0.4, 0.8, 0.8)
	var flames := CPUParticles3D.new()
	flames.position = at + Vector3(0, 0.2, 0)
	flames.amount = 12
	flames.lifetime = 0.6
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.8
	flames.gravity = Vector3(0, 0.6, 0)
	var spark := SphereMesh.new()
	spark.radius = 0.05
	spark.height = 0.1
	flames.mesh = spark
	flames.material_override = _mat("#ffa24a", false, 3.5)
	add_child(flames)
	lamp(at + Vector3(0, 0.9, 0.2), "#ffa24a", energy, 6.0, true)

func lamp(at: Vector3, color := "#ffbd66", energy := 2.0, reach := 5.0, flicker := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = Color(color)
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	add_child(light)
	lights.append(light)
	if flicker:
		var tween := create_tween().set_loops()
		tween.tween_property(light, "light_energy", energy * 0.55, 0.11)
		tween.tween_property(light, "light_energy", energy * 1.1, 0.07)
		tween.tween_property(light, "light_energy", energy * 0.8, 0.16)
	return light

## Lâmpada de serviço: caixa de metal, bulbo que brilha e luz âmbar logo abaixo.
func service_lamp(at: Vector3, color := "#ffbd66", energy := 2.0, reach := 5.0, flicker := false) -> void:
	box(at + Vector3(0, 0.08, 0), Vector3(0.34, 0.14, 0.2), "#353f3f", true)
	box(at + Vector3(0, -0.02, 0), Vector3(0.22, 0.06, 0.12), "#ffd28a", false, "", 1.6)
	lamp(at + Vector3(0, -0.4, 0.5), color, energy, reach, flicker)

func water(rect: Rect2, y := -0.07, color := "#12484a") -> void:
	_open_channel(rect)
	var instance := box(Vector3(rect.get_center().x, y, rect.get_center().y), Vector3(rect.size.x, 0.04, rect.size.y), color, true)
	instance.name = "Water"
	var shader := Shader.new()
	shader.code = preload("res://world/places/SewerAtmosphere3D.gd").WATER_SHADER
	var surface := ShaderMaterial.new()
	surface.shader = shader
	surface.set_shader_parameter("size_m", rect.size)
	surface.set_shader_parameter("deep", Color(color).darkened(.3))
	surface.set_shader_parameter("shallow", Color(color).lightened(.13))
	surface.set_shader_parameter("foam", Color("58665a"))
	surface.set_shader_parameter("flow", .18)
	instance.material_override = surface

func puddle(at: Vector3, radius := 0.5) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat("#3e615b", true)
	instance.position = Vector3(at.x, 0.03, at.z)
	instance.scale.z = 0.45
	add_child(instance)

func drips(at: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.position = at
	particles.amount = 6
	particles.lifetime = 0.9
	particles.direction = Vector3.DOWN
	particles.spread = 2.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.4
	particles.gravity = Vector3(0, -6.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 0.8
	var mesh := SphereMesh.new()
	mesh.radius = 0.018
	mesh.height = 0.05
	particles.mesh = mesh
	particles.material_override = _mat("#7fb6b0", false, 0.6)
	add_child(particles)

func fire_barrel(at: Vector3) -> void:
	cyl(at + Vector3(0, 0.45, 0), 0.32, 0.9, "#6b3b2a", true, "FireBarrel")
	cyl(at + Vector3(0, 0.91, 0), 0.27, 0.04, "#ff8a2a", false, "", 3.0)
	for band in [0.2, 0.7]: cyl(at + Vector3(0, band, 0), 0.335, 0.05, "#3c2a22", true)
	var flames := CPUParticles3D.new()
	flames.position = at + Vector3(0, 0.95, 0)
	flames.amount = 14
	flames.lifetime = 0.7
	flames.direction = Vector3.UP
	flames.spread = 14.0
	flames.initial_velocity_min = 0.5
	flames.initial_velocity_max = 0.9
	flames.gravity = Vector3(0, 0.6, 0)
	flames.scale_amount_min = 0.5
	flames.scale_amount_max = 1.0
	var spark := SphereMesh.new()
	spark.radius = 0.06
	spark.height = 0.12
	flames.mesh = spark
	flames.material_override = _mat("#ff9a3a", false, 3.5)
	add_child(flames)
	lamp(at + Vector3(0, 1.3, 0.2), "#ff9d4a", 2.6, 6.0, true)

func crate(at: Vector3, size := Vector3(0.9, 0.7, 0.9), color := "#756347", yaw := 0.0) -> MeshInstance3D:
	var instance := box(at + Vector3(0, size.y * 0.5, 0), size, color, false, "Crate")
	instance.rotation.y = yaw
	box(at + Vector3(0, size.y + 0.01, 0), Vector3(size.x * 0.98, 0.03, size.z * 0.14), "#a58a5e").rotation.y = yaw
	return instance

func barrel(at: Vector3, color := "#4b655f") -> void:
	cyl(at + Vector3(0, 0.32, 0), 0.22, 0.64, color, true, "Barrel")
	for height in [0.12, 0.52]: cyl(at + Vector3(0, height, 0), 0.235, 0.04, "#8a9788", true)

func graffiti(at: Vector3, size: Vector2, color: String, yaw := 0.0) -> void:
	var instance := box(at, Vector3(size.x, size.y, 0.03), color, false, "", 0.15)
	instance.rotation.y = yaw

## Sacola de dinheiro para as recompensas em dinheiro; armas usam a arte padrão do `NativePlace`.
func create_reward_art(item: Dictionary) -> Node3D:
	if item.kind == "weapon": return null
	var bag := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.18, 0.24)
	body.mesh = mesh
	body.material_override = _mat("#3f4a3a")
	body.position.y = 0.2
	bag.add_child(body)
	var cash := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(0.28, 0.04, 0.18)
	cash.mesh = strip
	cash.material_override = _mat("#a7c58a", false, 0.4)
	cash.position.y = 0.32
	bag.add_child(cash)
	return bag

# --- Sujeira: tudo aqui é visual (sem colisão) salvo `rubble` e `heap(..., solid)`. ---

func stain(at: Vector3, radius := 0.6, color := "#1d2a24") -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat(color)
	instance.position = Vector3(at.x, 0.028, at.z)
	instance.scale.z = _rng.randf_range(0.4, 0.9)
	instance.rotation.y = _rng.randf() * TAU
	add_child(instance)

func moss(at: Vector3, radius := 0.5) -> void:
	stain(at, radius, ["#2c3a22", "#33401f", "#27351f"][_rng.randi() % 3])

## Monte de lixo: caixas, latas e trapos amassados. `solid` faz dele um obstáculo (monte grande).
func heap(at: Vector3, radius := 0.7, count := 9, solid := false) -> void:
	var colors := ["#4a4033", "#3a3d36", "#55483a", "#2f3a3a", "#5a4a30", "#2b2b28", "#4d3a38"]
	for index in count:
		var offset := Vector3(_rng.randf_range(-radius, radius), 0.0, _rng.randf_range(-radius, radius)) * 0.8
		var size := Vector3(_rng.randf_range(0.14, 0.42), _rng.randf_range(0.08, 0.3), _rng.randf_range(0.12, 0.38))
		var piece := box(at + offset + Vector3(0, size.y * 0.5 + _rng.randf() * 0.12, 0), size, colors[_rng.randi() % colors.size()])
		piece.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
		if solid:
			piece.set_meta("interior_solid_id", "HeapMesh_%d" % _solid_counter)
			piece.set_meta("source_solid_rect", "Heap_%d" % (_solid_counter+1))
	if solid: _add_solid(at + Vector3(0, 0.3, 0), Vector3(radius * 1.5, 0.6, radius * 1.5), "Heap")
	stain(at, radius * 1.2, "#1a1f1b")

func rust_streak(x: float, wall_z: float, length := 1.4, y_top := 2.4) -> void:
	box(Vector3(x, y_top - length * 0.5, wall_z), Vector3(_rng.randf_range(0.05, 0.12), length, 0.03), ["#5a3a22", "#4d3321", "#6a4526"][_rng.randi() % 3])

func skeleton(at: Vector3, yaw := 0.0) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.05, at.z)
	root.rotation.y = yaw
	add_child(root)
	var bone := _mat("#bdb8a4")
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.1
	skull_mesh.height = 0.2
	skull.mesh = skull_mesh
	skull.material_override = bone
	skull.position = Vector3(0.55, 0.1, 0)
	root.add_child(skull)
	for index in 5:
		var rib := MeshInstance3D.new()
		var rib_mesh := BoxMesh.new()
		rib_mesh.size = Vector3(0.03, 0.04, 0.34)
		rib.mesh = rib_mesh
		rib.material_override = bone
		rib.position = Vector3(0.28 - index * 0.08, 0.05, 0)
		rib.rotation.y = 0.0
		root.add_child(rib)
	for side in [-1.0, 1.0]:
		var limb := MeshInstance3D.new()
		var limb_mesh := BoxMesh.new()
		limb_mesh.size = Vector3(0.55, 0.05, 0.05)
		limb.mesh = limb_mesh
		limb.material_override = bone
		limb.position = Vector3(-0.35, 0.03, side * 0.16)
		limb.rotation.y = side * 0.25
		root.add_child(limb)

## Massa de entulho/tijolo que fecha um canto e dá à sala um contorno torto. Colide pelo retângulo.
func rubble(rect: Rect2, height := 1.8, color := "#2b312b") -> void:
	var cell := 0.9
	var columns := maxi(1, int(rect.size.x / cell))
	var rows := maxi(1, int(rect.size.y / cell))
	for row in rows:
		for column in columns:
			var h := height * _rng.randf_range(0.55, 1.0)
			var piece := box(Vector3(rect.position.x + (column + 0.5) * rect.size.x / columns, h * 0.5, rect.position.y + (row + 0.5) * rect.size.y / rows), Vector3(rect.size.x / columns * 1.1, h, rect.size.y / rows * 1.1), color)
			piece.rotation.y = _rng.randf_range(-0.3, 0.3)
			piece.set_meta("interior_solid_id", "RubbleMesh_%d" % solid_rects.size())
			piece.set_meta("source_solid_rect", "Rubble_%d" % solid_rects.size())
	solid_rects["Rubble_%d" % solid_rects.size()] = rect

## Espalha sujeira (manchas, musgo, lixo) numa área, fora dos retângulos de `avoid`.
func scatter_grime(area: Rect2, stains := 14, mosses := 6, heaps := 3, avoid: Array[Rect2] = []) -> void:
	for index in stains + mosses + heaps:
		var at := Vector3(area.position.x + _rng.randf() * area.size.x, 0, area.position.y + _rng.randf() * area.size.y)
		var blocked := false
		for rect in avoid:
			if rect.grow(0.4).has_point(Vector2(at.x, at.z)): blocked = true
		for rect in solid_rects.values():
			if (rect as Rect2).grow(0.4).has_point(Vector2(at.x, at.z)): blocked = true
		if blocked: continue
		if index < stains: stain(at, _rng.randf_range(0.3, 1.0))
		elif index < stains + mosses: moss(at, _rng.randf_range(0.3, 0.7))
		else: heap(at, _rng.randf_range(0.4, 0.7), 7)
