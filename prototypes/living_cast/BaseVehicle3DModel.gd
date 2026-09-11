extends "res://prototypes/living_cast/CoupeDamageModel.gd"

## Classe base para todos os modelos de veículos 3D procedurais da Frota Viva.
## Herda os contratos de deformação e dano de lataria (CoupeDamageModel.gd).
## Fornece helpers especializados para carrocerias, vidros, rodas esterçáveis e equipamentos.

var vehicle_id: String = ""

func _init() -> void:
	if get_child_count() == 0:
		if not preload("res://VehicleGeometryCache.gd").restore(self):
			build()
			preload("res://VehicleGeometryCache.gd").capture(self)

func _enter_tree() -> void:
	if get_child_count() == 0:
		build()

func _ready() -> void:
	if get_child_count() == 0:
		build()
	super._ready()

func add_wheel(
	side: float,
	wheel_y: float,
	wheel_z: float,
	tire_radius: float = 0.35,
	tire_width: float = 0.22,
	rim_radius: float = 0.22,
	spoke_count: int = 5,
	rim_color: String = "b5bdc3"
) -> void:
	var black := mat("rubber", "15191d", 0.0, 0.92)
	var trim := mat("trim", "282f36", 0.2, 0.45)
	var rim_mat := mat("rim_" + rim_color, rim_color, 0.75, 0.25)
	var brake_mat := mat("caliper", "cd382b", 0.3, 0.4)
	var rotor_mat := mat("rotor", "555d64", 0.6, 0.5)

	var first_idx := get_child_count()
	var center := Vector3(side, wheel_y, wheel_z)

	# 1. Pneu de borracha
	var tire := cylinder(center, tire_radius, tire_width, black)
	tire.rotation.z = PI / 2.0

	# 2. Roda / Aro metálico
	var rim_mesh := cylinder(Vector3(side * (absf(side) + 0.02) / absf(side), wheel_y, wheel_z), rim_radius, tire_width * 0.95, rim_mat)
	rim_mesh.rotation.z = PI / 2.0

	# 3. Disco de freio ventilado
	var disc := cylinder(Vector3(side * (absf(side) - 0.03) / absf(side), wheel_y, wheel_z), rim_radius * 0.85, 0.02, rotor_mat)
	disc.rotation.z = PI / 2.0

	# 4. Pinça de freio (caliper - não gira com a roda)
	var caliper := box(Vector3(side * (absf(side) + 0.01) / absf(side), wheel_y + tire_radius * 0.4, wheel_z + 0.06), Vector3(0.04, 0.10, 0.06), brake_mat)

	# 5. Raios da roda
	for i in spoke_count:
		var ang: float = float(i) * TAU / float(spoke_count)
		var p1 := Vector3(side * (absf(side) + 0.03) / absf(side), wheel_y + cos(ang) * 0.05, wheel_z + sin(ang) * 0.05)
		var p2 := Vector3(side * (absf(side) + 0.03) / absf(side), wheel_y + cos(ang) * (rim_radius * 0.88), wheel_z + sin(ang) * (rim_radius * 0.88))
		tube([p1, p2], 0.018, rim_mat)

	# 6. Cubo central
	var hub := cylinder(Vector3(side * (absf(side) + 0.035) / absf(side), wheel_y, wheel_z), 0.055, 0.025, trim)
	hub.rotation.z = PI / 2.0

	# Marcação de metadados para direção de HarborCoupe
	for idx in range(first_idx, get_child_count()):
		var part := get_child(idx)
		part.set_meta("wheel_center", center)
		part.set_meta("wheel_spins", part != caliper)
		# O rig precisa do raio real para rolar o pneu na velocidade certa: um
		# caminhão de 0.50 m girava com a cadência de um sedã de 0.355 m.
		part.set_meta("wheel_radius", tire_radius)

func add_lightbar(
	y_pos: float,
	z_pos: float,
	color_left: Color = Color.RED,
	color_right: Color = Color.BLUE,
	width: float = 1.10
) -> void:
	var bar_base := box(Vector3(0.0, y_pos, z_pos), Vector3(width, 0.05, 0.22), mat("lightbar_mount", "1a1d20", 0.5, 0.4))
	var glass_left := box(Vector3(-width * 0.26, y_pos + 0.05, z_pos), Vector3(width * 0.44, 0.07, 0.18), mat("bar_left", color_left.to_html(false), 0.1, 0.1, 0.95))
	var glass_right := box(Vector3(width * 0.26, y_pos + 0.05, z_pos), Vector3(width * 0.44, 0.07, 0.18), mat("bar_right", color_right.to_html(false), 0.1, 0.1, 0.95))
	var center_siren := cylinder(Vector3(0.0, y_pos + 0.04, z_pos), 0.08, 0.10, mat("siren_speaker", "2f3640", 0.6, 0.3))
	center_siren.rotation.x = PI / 2.0

func add_roof_sign(y_pos: float, z_pos: float, text_label: String, bg_color: Color = Color("#f1c40f"), fg_color: Color = Color("#111111")) -> void:
	var base := box(Vector3(0.0, y_pos + 0.015, z_pos), Vector3(0.48, 0.025, 0.16), mat("sign_base", "2d3436", 0.4, 0.5))
	var sign_box := box(Vector3(0.0, y_pos + 0.08, z_pos), Vector3(0.44, 0.10, 0.12), mat("sign_glow", bg_color.to_html(false), 0.1, 0.2, 0.55))
	# Letras ou símbolos contrastantes
	var mark := box(Vector3(0.0, y_pos + 0.08, z_pos), Vector3(0.36, 0.05, 0.125), mat("sign_text", fg_color.to_html(false), 0.1, 0.4))

func add_exhaust_dual(x_offset: float, y_pos: float, z_pos: float, radius: float = 0.065) -> void:
	var rim_mat := mat("chrome_exhaust", "dcdde1", 0.85, 0.2)
	var black := mat("exhaust_hole", "000000", 0.0, 1.0)
	for s in [-1.0, 1.0]:
		var pipe := cylinder(Vector3(s * x_offset, y_pos, z_pos), radius, 0.14, rim_mat)
		pipe.rotation.x = PI / 2.0
		var hole := cylinder(Vector3(s * x_offset, y_pos, z_pos + 0.06), radius * 0.78, 0.02, black)
		hole.rotation.x = PI / 2.0
