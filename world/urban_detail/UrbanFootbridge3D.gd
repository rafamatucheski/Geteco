@tool
extends Node3D
## Passarela de pedestres sobre a rua. Eixo local Z = travessia (a rua corre em
## X). `length` é o comprimento total com as escadas, para o retângulo do editor
## mostrar a área real ocupada; o vão livre é o que sobra das duas escadas.
## Peças repetidas vão em MultiMesh por material; sem luzes nem processamento.

const DECK_HEIGHT := 5.6
# Degraus de 18 cm por 29 cm: escada de 32°, abaixo dos 45° de piso do CharacterBody.
const STEPS := 30
const TREAD := 0.29
const LANDING := 1.6
const DECK_THICKNESS := 0.35
const GIRDER_DEPTH := 0.7
const RAIL_HEIGHT := 1.15
const MIN_SPAN := 8.0

var width := 2.6
var length := 34.6
var accent := Color("3f6e8c")
var _batches: Dictionary = {}
var _body: StaticBody3D

static func run_length() -> float:
	return STEPS * TREAD

static func span_for(total_length: float) -> float:
	return maxf(MIN_SPAN, total_length - 2.0 * (run_length() + LANDING))

const GROUP := "footbridges"

func build() -> void:
	# Grupo: `FootbridgeCrossers` acha passarelas carregadas sem varrer a região.
	add_to_group(GROUP)
	for child in get_children(): child.free()
	_batches.clear()
	_body = StaticBody3D.new()
	_body.name = "FootbridgeCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var concrete := _mat(Color("a7a397"))
	var paving := _mat(Color("5c5f5c"))
	var steel := _mat(Color("7d8488"), 0.45)
	var paint := _mat(accent, 0.6)
	var mesh_screen := _mat(Color(0.18, 0.2, 0.21, 0.55))
	mesh_screen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var span := span_for(length)
	var half_deck := span * 0.5 + LANDING
	var rise := DECK_HEIGHT / float(STEPS + 1)

	# Tabuleiro: laje de concreto, piso escuro e vigas laterais pintadas.
	_box(Vector3(0, DECK_HEIGHT - DECK_THICKNESS * 0.5, 0), Vector3(width, DECK_THICKNESS, half_deck * 2.0), concrete)
	_box(Vector3(0, DECK_HEIGHT + 0.01, 0), Vector3(width - 0.3, 0.02, half_deck * 2.0 - 0.1), paving)
	_solid(Vector3(0, DECK_HEIGHT - DECK_THICKNESS * 0.5, 0), Vector3(width, DECK_THICKNESS, half_deck * 2.0))
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 + 0.1)
		_box(Vector3(x, DECK_HEIGHT - GIRDER_DEPTH * 0.5, 0), Vector3(0.22, GIRDER_DEPTH, half_deck * 2.0), paint)
		# Treliça leve na viga: montantes e diagonais alternadas lêem como estrutura metálica.
		var bays := maxi(2, int(half_deck * 2.0 / 1.6))
		var bay := half_deck * 2.0 / float(bays)
		for i in bays + 1:
			var z := -half_deck + i * bay
			_box(Vector3(x + side * 0.04, DECK_HEIGHT - GIRDER_DEPTH * 0.5, z), Vector3(0.08, GIRDER_DEPTH, 0.08), steel)
		_railing(Vector3(side * (width * 0.5 - 0.05), DECK_HEIGHT, -half_deck), Vector3(side * (width * 0.5 - 0.05), DECK_HEIGHT, half_deck), steel, paint, mesh_screen)

	# Pilares na borda do vão, fora da calçada, com travessa sob o tabuleiro.
	for end in [-1.0, 1.0]:
		var z: float = end * (span * 0.5 + LANDING * 0.5)
		for side in [-1.0, 1.0]:
			var column := Vector3(side * (width * 0.5 - 0.25), (DECK_HEIGHT - DECK_THICKNESS) * 0.5, z)
			_box(column, Vector3(0.42, DECK_HEIGHT - DECK_THICKNESS, 0.42), concrete)
			_solid(column, Vector3(0.42, DECK_HEIGHT - DECK_THICKNESS, 0.42))
			_box(Vector3(column.x, 0.12, z), Vector3(0.7, 0.24, 0.7), concrete)
		_box(Vector3(0, DECK_HEIGHT - DECK_THICKNESS - 0.25, z), Vector3(width + 0.3, 0.5, 0.5), concrete)

	# Escadas: degraus visuais, laje inclinada por baixo e rampa de colisão lisa.
	for end in [-1.0, 1.0]:
		var top_z: float = end * half_deck
		var bottom_z: float = end * (half_deck + run_length())
		for i in STEPS:
			var top := DECK_HEIGHT - (i + 1) * rise
			var z: float = top_z + end * (i + 0.5) * TREAD
			_box(Vector3(0, top - 0.09, z), Vector3(width - 0.2, 0.18, TREAD + 0.01), concrete)
		var slope_length := Vector2(run_length(), DECK_HEIGHT).length()
		var angle := atan2(DECK_HEIGHT, run_length())
		var mid := Vector3(0.0, DECK_HEIGHT * 0.5, (top_z + bottom_z) * 0.5)
		# Laje inclinada sob os degraus.
		var soffit := Basis(Vector3.RIGHT, float(end) * angle)
		_box_basis(Transform3D(soffit.scaled_local(Vector3(width - 0.1, 0.3, slope_length)), mid - soffit.y * 0.35), concrete)
		# Colisão: rampa cujo topo passa pelas quinas dos degraus (anda liso, sem tropeço).
		# Topo da rampa na linha tabuleiro-chão: os degraus ficam a menos de meio espelho dela.
		var shape_center := mid - soffit.y * 0.15
		_solid_basis(Transform3D(soffit, shape_center), Vector3(width - 0.2, 0.3, slope_length + 0.3))
		# Apoio no meio do lance.
		_box(Vector3(0, DECK_HEIGHT * 0.25, (top_z + bottom_z) * 0.5), Vector3(0.35, DECK_HEIGHT * 0.5 - 0.3, 0.35), concrete)
		for side in [-1.0, 1.0]:
			var x: float = side * (width * 0.5 - 0.05)
			_box_basis(Transform3D(soffit.scaled_local(Vector3(0.2, 0.5, slope_length)), mid + Vector3(side * (width * 0.5 + 0.02), 0, 0) - soffit.y * 0.15), paint)
			_railing(Vector3(x, DECK_HEIGHT, top_z), Vector3(x, rise, bottom_z), steel, paint, mesh_screen)
	_flush()

## Guarda-corpo entre dois pontos do piso: postes, corrimão, travessa e tela.
func _railing(from: Vector3, to: Vector3, steel: Material, paint: Material, screen: Material) -> void:
	var run := to - from
	var count := maxi(2, int(ceil(run.length() / 1.5)) + 1)
	for i in count:
		var at := from.lerp(to, float(i) / float(count - 1))
		_box(at + Vector3(0, RAIL_HEIGHT * 0.5, 0), Vector3(0.07, RAIL_HEIGHT, 0.07), steel)
	var direction := run.normalized()
	var local_basis := Basis.looking_at(direction, Vector3.UP).orthonormalized()
	# `looking_at` aponta -Z para a direção; o comprimento vai no Z local.
	var middle := (from + to) * 0.5
	for level in [[RAIL_HEIGHT, 0.07, paint], [RAIL_HEIGHT * 0.5, 0.04, steel], [0.12, 0.04, steel]]:
		_box_basis(Transform3D(local_basis.scaled_local(Vector3(level[1], level[1], run.length())), middle + Vector3(0, level[0], 0)), level[2])
	_box_basis(Transform3D(local_basis.scaled_local(Vector3(0.02, RAIL_HEIGHT - 0.2, run.length())), middle + Vector3(0, RAIL_HEIGHT * 0.5 + 0.02, 0)), screen)
	# Parede invisível do guarda-corpo: ninguém cai nem atravessa a tela.
	_solid_basis(Transform3D(local_basis, middle + Vector3(0, RAIL_HEIGHT * 0.5 + 0.05, 0)), Vector3(0.12, RAIL_HEIGHT + 0.1, run.length()))

func _mat(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _box(center: Vector3, size: Vector3, material: Material) -> void:
	_box_basis(Transform3D(Basis.from_scale(size), center), material)

func _box_basis(transform_value: Transform3D, material: Material) -> void:
	var key := material.get_instance_id()
	if not _batches.has(key): _batches[key] = {"material": material, "transforms": []}
	_batches[key].transforms.append(transform_value)

func _solid(center: Vector3, size: Vector3) -> void:
	_solid_basis(Transform3D(Basis.IDENTITY, center), size)

func _solid_basis(transform_value: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = transform_value
	_body.add_child(collider)

func _flush() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for batch in _batches.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = cube
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size(): multimesh.set_instance_transform(index, batch.transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "FootbridgeBatch"
		instance.multimesh = multimesh
		instance.material_override = batch.material
		add_child(instance)
	_batches.clear()
