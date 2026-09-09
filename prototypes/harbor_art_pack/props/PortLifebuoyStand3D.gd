class_name PortLifebuoyStand3D
extends Node3D

## Suporte e pedestal quayside com boia salva-vidas marítima regulamentar.
## Boia toroidal em laranja de segurança internacional, faixas retrorrefletivas brancas e cabo flutuante.
## Dimensões: 0.50m largura x 1.45m altura x 0.35m profundidade.
## Origem no piso Y=0, centrado em X e Z.

const WIDTH: float = 0.50
const HEIGHT: float = 1.45
const DEPTH: float = 0.35

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(WIDTH, HEIGHT, DEPTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-WIDTH * 0.5, 0.0, -DEPTH * 0.5), Vector3(WIDTH, HEIGHT, DEPTH)))

	var mat_post := PortArtMaterials.steel_dark()
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_buoy := PortArtMaterials.safety_orange()
	var mat_white := PortArtMaterials.reflective_white()
	var mat_rope := PortArtMaterials.rope_hemp()

	# 1. Base flange aparafusada no piso
	_box(Vector3(0.0, 0.015, 0.0), Vector3(0.32, 0.03, 0.32), mat_post)
	for cx in [-0.12, 0.12]:
		for cz in [-0.12, 0.12]:
			_cyl(Vector3(cx, 0.035, cz), 0.015, 0.02, mat_hardware)

	# 2. Pedestal tubular vertical
	_cyl(Vector3(0.0, 0.70, 0.0), 0.03, 1.35, mat_post)

	# 3. Gancho / Suporte em berço da boia
	_box(Vector3(0.0, 1.05, 0.06), Vector3(0.24, 0.04, 0.12), mat_post)
	_cyl(Vector3(0.0, 1.15, 0.12), 0.015, 0.20, mat_hardware)

	# 4. Boia salva-vidas toroidal (Raio externo 0.35m, tubo 0.07m)
	var buoy_y := 1.05
	var buoy_z := 0.12
	var buoy_outer_r := 0.35
	var buoy_tube_r := 0.07

	var tm := TorusMesh.new()
	tm.inner_radius = buoy_outer_r - buoy_tube_r * 2.0
	tm.outer_radius = buoy_outer_r
	tm.rings = 24
	tm.ring_segments = 14

	var mi_buoy := MeshInstance3D.new()
	mi_buoy.mesh = tm
	mi_buoy.rotation_degrees.x = 90.0
	mi_buoy.position = Vector3(0.0, buoy_y, buoy_z)
	mi_buoy.material_override = mat_buoy
	add_child(mi_buoy)

	# 5. Quatro faixas retrorrefletivas brancas (top, bottom, left, right)
	_box(Vector3(0.0, buoy_y + buoy_outer_r - buoy_tube_r, buoy_z), Vector3(0.08, 0.04, 0.16), mat_white)
	_box(Vector3(0.0, buoy_y - buoy_outer_r + buoy_tube_r, buoy_z), Vector3(0.08, 0.04, 0.16), mat_white)
	_box(Vector3(-buoy_outer_r + buoy_tube_r, buoy_y, buoy_z), Vector3(0.04, 0.08, 0.16), mat_white)
	_box(Vector3(buoy_outer_r - buoy_tube_r, buoy_y, buoy_z), Vector3(0.04, 0.08, 0.16), mat_white)

	# 6. Cabo de resgate enrolado na haste inferior
	_cyl(Vector3(0.0, 0.50, 0.0), 0.065, 0.22, mat_rope)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
