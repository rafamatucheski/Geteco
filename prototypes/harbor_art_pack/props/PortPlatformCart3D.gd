class_name PortPlatformCart3D
extends Node3D

## Carrinho plataforma industrial de 4 rodas (1.25m x 0.75m x 0.95m).
## Plataforma de aço com revestimento antiderrapante, 4 rodízios reforçados e alça tubular de empurrar.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 1.25
const WIDTH: float = 0.75
const HEIGHT: float = 0.95

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(LENGTH, HEIGHT, WIDTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-LENGTH * 0.5, 0.0, -WIDTH * 0.5), Vector3(LENGTH, HEIGHT, WIDTH)))

	var mat_deck := PortArtMaterials.plastic_blue()
	var mat_frame := PortArtMaterials.steel_dark()
	var mat_handle := PortArtMaterials.steel_galvanized()
	var mat_wheel := PortArtMaterials.rubber_black()
	var mat_hub := PortArtMaterials.steel_galvanized()

	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var deck_y := 0.20
	var wheel_r := 0.08

	# 1. Estrutura de aço do chassi inferior
	_box(Vector3(0.0, deck_y - 0.03, 0.0), Vector3(LENGTH, 0.04, WIDTH), mat_frame)

	# 2. Deck superior com textura e borda de borracha protetora
	_box(Vector3(0.0, deck_y, 0.0), Vector3(LENGTH - 0.04, 0.02, WIDTH - 0.04), mat_deck)
	# Borda perimetral contra impactos
	_box(Vector3(0.0, deck_y + 0.005, 0.0), Vector3(LENGTH + 0.02, 0.03, WIDTH + 0.02), mat_wheel)

	# 3. Quatro rodízios industriais (Casters)
	for cx in [-half_l + 0.18, half_l - 0.18]:
		for cz in [-half_w + 0.12, half_w - 0.12]:
			# Garfo/Suporte de aço do rodízio
			_box(Vector3(cx, deck_y * 0.55, cz), Vector3(0.06, deck_y * 0.7, 0.06), mat_frame)
			# Roda de borracha
			_cyl(Vector3(cx, wheel_r, cz), wheel_r, 0.045, mat_wheel, Vector3(0, 0, 90))
			# Cubo
			_cyl(Vector3(cx, wheel_r, cz), 0.03, 0.05, mat_hub, Vector3(0, 0, 90))

	# 4. Alça tubular de empurrar traseira (-X)
	var handle_x := -half_l + 0.06
	# Hastes verticais
	for hz in [-half_w + 0.08, half_w - 0.08]:
		_cyl(Vector3(handle_x, deck_y + (HEIGHT - deck_y) * 0.5, hz), 0.018, HEIGHT - deck_y, mat_handle)

	# Barra transversal superior de empurrar
	_cyl(Vector3(handle_x, HEIGHT - 0.015, 0.0), 0.02, WIDTH - 0.16, mat_handle, Vector3(90, 0, 0))

	# Travessa intermediária de reforço
	_cyl(Vector3(handle_x, deck_y + 0.35, 0.0), 0.016, WIDTH - 0.16, mat_handle, Vector3(90, 0, 0))

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
