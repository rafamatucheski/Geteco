extends Node3D
## Base dos esgotos novos. A sala fica centrada na origem, em metros (o Esgoto da V1 usa pixels de origem).
## `solid_rects` (id -> Rect2 no plano XZ) vira colisão no `NativePlace`; cada peça com `solid` entra ali.
## Subclasses definem REWARDS e RESIDENTS (lidos por `SewerNetwork.decorate`) e implementam `_build()`.
var solid_rects: Dictionary = {}
var half := Vector2(8, 5)
var _palette: Dictionary = {}
var _solid_counter := 0
## Luzes da sala, para as capturas e testes de revisão.
var lights: Array[OmniLight3D] = []

func room_size() -> Vector2:
	return half * 2.0

func _ready() -> void:
	_build()

func _build() -> void:
	pass

func _mat(color: String, metal := false, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color, metal, glow]
	if not _palette.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = 0.62 if metal else 0.93
		material.metallic = 0.45 if metal else 0.0
		if glow > 0.0:
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = glow
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
	if solid != "": _add_solid(center, size, solid)
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
	if solid != "": _add_solid(center, Vector3(radius * 2.0, height, radius * 2.0), solid)
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
	return instance

## Piso de pedra com ladrilhos de tons variados (um MultiMesh) e a laje escura por baixo.
func floor_slab(rect: Rect2, base := "#252f30") -> void:
	box(Vector3(rect.get_center().x, -0.16, rect.get_center().y), Vector3(rect.size.x, 0.3, rect.size.y), base)
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
	var tones := [Color("566159"), Color("60665a"), Color("515d59"), Color("626958")]
	var index := 0
	var origin_x := rect.get_center().x - columns * tile.x * 0.5
	var origin_z := rect.get_center().y - rows * tile.y * 0.5
	for row in rows:
		for column in columns:
			var origin := Vector3(origin_x + tile.x * (column + 0.5), -0.005, origin_z + tile.y * (row + 0.5))
			multi.set_instance_transform(index, Transform3D(Basis(), origin))
			multi.set_instance_color(index, (tones[rng.randi_range(0, 3)] as Color).srgb_to_linear())
			index += 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	instance.material_override = material
	add_child(instance)

## Paredes: fundo alto e frente baixa mantêm a leitura da câmera fixa.
func walls(back_height := 2.8, side_height := 1.0, front_height := 0.35, color := "#626b59") -> void:
	var t := 0.5
	box(Vector3(0, back_height * 0.5, -half.y - t * 0.5), Vector3(half.x * 2.0 + t * 2.0, back_height, t), color, false, "BackWall")
	box(Vector3(0, front_height * 0.5, half.y + t * 0.5), Vector3(half.x * 2.0 + t * 2.0, front_height, t), color, false, "FrontWall")
	for side in [-1.0, 1.0]:
		box(Vector3(side * (half.x + t * 0.5), side_height * 0.5, 0), Vector3(t, side_height, half.y * 2.0), color, false, "SideWall")
	# Faixas de tijolo mais claro no fundo, para o muro não ser um bloco liso.
	for course in 3:
		box(Vector3(0, 0.45 + course * 0.8, -half.y + 0.02), Vector3(half.x * 2.0, 0.06, 0.05), "#747d68")

func ladder(at: Vector3) -> void:
	box(at + Vector3(0, 0.03, 0), Vector3(1.0, 0.04, 0.9), "#182728")
	for x in [-0.27, 0.27]: cyl(at + Vector3(x, 1.0, 0), 0.035, 2.0, "#b0a276", true)
	for rung in 7: box(at + Vector3(0, 0.17 + rung * 0.29, 0), Vector3(0.56, 0.05, 0.05), "#c6b37f", true)

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
	var instance := box(Vector3(rect.get_center().x, y, rect.get_center().y), Vector3(rect.size.x, 0.04, rect.size.y), color, true, "", 0.35)
	instance.name = "Water"

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
