extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Union Sedan Premier: Sedã executivo/familiar clássico de 3 volumes.
## Proporções balanceadas: capô amplo, cabine de 4 portas e porta-malas traseiro destacado.

# Keep authored parts separate so damage and the live wheel rig retain their
# exact nodes, transforms and per-instance materials. Only the immutable
# primitive Mesh resources are shared; this removes repeated BoxMesh and
# CylinderMesh construction from the cold model that seeds VehicleGeometryCache.
static var _shared_box_meshes: Dictionary = {}
static var _shared_cylinder_meshes: Dictionary = {}


func box(pos: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := _shared_box_meshes.get(size_value) as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size_value
		_shared_box_meshes[size_value] = mesh
	return mesh_node(mesh, pos, material)


func cylinder(pos: Vector3, radius: float, depth: float, material: Material) -> MeshInstance3D:
	var key := Vector2(radius, depth)
	var mesh := _shared_cylinder_meshes.get(key) as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = depth
		mesh.radial_segments = 32
		_shared_cylinder_meshes[key] = mesh
	return mesh_node(mesh, pos, material)


func build() -> void:
	paint = mat("paint", "2c3e50", 0.35, 0.28)
	var chrome := mat("chrome", "ecf0f1", 0.88, 0.15)
	var rubber := mat("rubber", "191c20", 0.0, 0.90)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.4)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var dark_grille := mat("grille", "111418", 0.3, 0.7)

	# 1. Chassi e assoalho inferior
	box(Vector3(0.0, 0.22, 0.0), Vector3(1.70, 0.08, 4.40), rubber)

	# 2. Carroceria Inferior / Linha de Cintura (Capô, Portas, Porta-malas)
	# Capô frontal
	box(Vector3(0.0, 0.62, -1.45), Vector3(1.76, 0.36, 1.65), paint)
	# Cabine inferior
	box(Vector3(0.0, 0.60, 0.15), Vector3(1.78, 0.36, 1.70), paint)
	# Porta-malas traseiro
	box(Vector3(0.0, 0.64, 1.65), Vector3(1.74, 0.38, 1.30), paint)

	# 3. Cabine Superior Envidraçada (Greenhouse 3 volumes)
	# Teto
	box(Vector3(0.0, 1.35, 0.12), Vector3(1.36, 0.06, 1.60), paint)
	# Para-brisa dianteiro inclinado
	var w_front := box(Vector3(0.0, 1.05, -0.72), Vector3(1.34, 0.52, 0.04), glass)
	w_front.rotation.x = deg_to_rad(32.0)
	# Vidro traseiro inclinado
	var w_rear := box(Vector3(0.0, 1.05, 0.98), Vector3(1.34, 0.52, 0.04), glass)
	w_rear.rotation.x = deg_to_rad(-30.0)
	# Vidros laterais (janelas dianteiras e traseiras)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.69, 1.06, 0.12), Vector3(0.02, 0.48, 1.55), glass)
		# Colunas B e C da cabine
		box(Vector3(s * 0.70, 1.06, 0.12), Vector3(0.04, 0.48, 0.08), rubber)
		# Friso cromado de cintura
		box(Vector3(s * 0.90, 0.78, 0.0), Vector3(0.02, 0.025, 4.25), chrome)
		# Maçanetas cromadas das 4 portas
		box(Vector3(s * 0.905, 0.74, -0.22), Vector3(0.025, 0.03, 0.14), chrome)
		box(Vector3(s * 0.905, 0.74, 0.48), Vector3(0.025, 0.03, 0.14), chrome)
		# Retrovisores
		box(Vector3(s * 0.96, 0.88, -0.62), Vector3(0.18, 0.08, 0.10), paint)

	# 4. Frente / Identidade Visual do Union Sedan: Grade Cromada Horizontal & Emblema
	box(Vector3(0.0, 0.58, -2.28), Vector3(1.05, 0.22, 0.04), dark_grille)
	for g in 4:
		box(Vector3(0.0, 0.52 + float(g) * 0.045, -2.285), Vector3(1.02, 0.015, 0.03), chrome)
	# Emblema central cromado Union
	cylinder(Vector3(0.0, 0.58, -2.29), 0.045, 0.025, chrome)

	# 5. Faróis Dianteiros e Lanternas Traseiras
	for s in [-1.0, 1.0]:
		# Farol principal
		box(Vector3(s * 0.68, 0.62, -2.28), Vector3(0.32, 0.16, 0.04), lens_head)
		# Seta âmbar na quina
		box(Vector3(s * 0.84, 0.62, -2.26), Vector3(0.08, 0.15, 0.04), lens_amber)
		# Lanterna traseira dupla
		box(Vector3(s * 0.68, 0.66, 2.30), Vector3(0.34, 0.14, 0.04), lens_tail)
		box(Vector3(s * 0.82, 0.66, 2.29), Vector3(0.06, 0.13, 0.04), lens_amber)

	# Friso cromado do porta-malas na traseira
	box(Vector3(0.0, 0.68, 2.305), Vector3(0.92, 0.03, 0.02), chrome)

	# 6. Para-choques Dianteiro e Traseiro
	box(Vector3(0.0, 0.36, -2.32), Vector3(1.78, 0.14, 0.12), chrome)
	box(Vector3(0.0, 0.38, 2.34), Vector3(1.76, 0.14, 0.12), chrome)

	# 7. Quatro Rodas Esterçáveis
	for s in [-0.85, 0.85]:
		add_wheel(s, 0.36, -1.35, 0.35, 0.22, 0.22, 5, "dcdde1")
		add_wheel(s, 0.36, 1.35, 0.35, 0.22, 0.22, 5, "dcdde1")

	# 8. Escapamento
	add_exhaust_dual(0.55, 0.28, 2.32, 0.045)
