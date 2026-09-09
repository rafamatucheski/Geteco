extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Boxrunner: Caminhão leve de distribuição urbana com cabine avançada (Cab-Over).
## Identidade: Cabine frontal vertical com defletor aerodinâmico, baú com cantoneiras e porta de enrolar.

func build() -> void:
	paint = mat("paint", "ffffff", 0.25, 0.35)
	var aluminum := mat("aluminum_trim", "bdc3c7", 0.78, 0.25)
	var black := mat("industrial_black", "1e272e", 0.1, 0.8)
	var rollup_door := mat("rollup_metal", "95a5a6", 0.65, 0.40)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)

	# 1. Chassi Longo
	box(Vector3(0.0, 0.35, 0.0), Vector3(2.05, 0.16, 6.50), black)
	# Para-choque frontal com degrau
	box(Vector3(0.0, 0.45, -3.35), Vector3(2.20, 0.22, 0.18), black)

	# 2. Cabine Avançada Vertical (Cab-Over)
	box(Vector3(0.0, 1.25, -2.45), Vector3(2.15, 1.45, 1.65), paint)
	# Para-brisa frontal amplo e quase vertical
	var w_front := box(Vector3(0.0, 1.52, -3.22), Vector3(2.02, 0.82, 0.04), glass)
	w_front.rotation.x = deg_to_rad(8.0)
	# Vidros das portas da cabine
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.08, 1.48, -2.45), Vector3(0.02, 0.62, 1.05), glass)
		# Retrovisores verticais de caminhão
		box(Vector3(s * 1.26, 1.42, -3.05), Vector3(0.20, 0.36, 0.08), black)
		tube([Vector3(s * 1.10, 1.54, -3.05), Vector3(s * 1.22, 1.54, -3.05)], 0.018, black)
		tube([Vector3(s * 1.10, 1.30, -3.05), Vector3(s * 1.22, 1.30, -3.05)], 0.018, black)

	# 3. Identidade Visual 1: Defletor Aerodinâmico Angular de Teto (Wind Fairing)
	var deflector := box(Vector3(0.0, 2.30, -2.15), Vector3(2.05, 0.62, 1.05), paint)
	deflector.rotation.x = deg_to_rad(32.0)

	# 4. Baú Traseiro de Carga Fechado (Dry Cargo Box)
	box(Vector3(0.0, 1.70, 0.85), Vector3(2.22, 2.10, 4.85), paint)

	# 5. Identidade Visual 2: Cantoneiras de Reforço em Alumínio nos Cantos do Baú
	for s in [-1.08, 1.08]:
		# Cantoneiras verticais
		box(Vector3(s, 1.70, -1.55), Vector3(0.06, 2.10, 0.06), aluminum)
		box(Vector3(s, 1.70, 3.25), Vector3(0.06, 2.10, 0.06), aluminum)
		# Cantoneiras horizontais superiores
		box(Vector3(s, 2.72, 0.85), Vector3(0.06, 0.06, 4.85), aluminum)
	# Cantoneira transversal superior dianteira e traseira
	box(Vector3(0.0, 2.72, -1.55), Vector3(2.20, 0.06, 0.06), aluminum)
	box(Vector3(0.0, 2.72, 3.25), Vector3(2.20, 0.06, 0.06), aluminum)

	# 6. Identidade Visual 3: Porta Traseira Corrediça de Enrolar (Roll-up Door)
	box(Vector3(0.0, 1.65, 3.28), Vector3(1.95, 1.85, 0.02), rollup_door)
	# Frisos horizontais das lâminas da porta de enrolar
	for f in 9:
		box(Vector3(0.0, 0.85 + float(f) * 0.18, 3.285), Vector3(1.92, 0.015, 0.02), black)
	# Puxador / Trava de piso central
	box(Vector3(0.0, 0.76, 3.295), Vector3(0.16, 0.04, 0.03), aluminum)

	# 7. Proteção Lateral Ciclista sob o Baú (Side Underrun Protection)
	for s in [-1.02, 1.02]:
		tube([Vector3(s, 0.42, -1.10), Vector3(s, 0.42, 1.20)], 0.025, aluminum)
		tube([Vector3(s, 0.30, -1.10), Vector3(s, 0.30, 1.20)], 0.025, aluminum)

	# 8. Luzes de Posição Delimitadoras Superiores (Clearance Lights)
	for s in [-1.05, 1.05]:
		box(Vector3(s, 2.72, -1.56), Vector3(0.06, 0.04, 0.03), lens_amber)
		box(Vector3(s, 2.72, 3.26), Vector3(0.06, 0.04, 0.03), lens_tail)

	# 9. Faróis Dianteiros e Lanternas Traseiras
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.82, 0.72, -3.26), Vector3(0.28, 0.20, 0.04), lens_head)
		box(Vector3(s * 0.98, 0.72, -3.25), Vector3(0.08, 0.20, 0.04), lens_amber)
		# Lanternas traseiras sob o baú
		box(Vector3(s * 0.88, 0.48, 3.28), Vector3(0.22, 0.14, 0.04), lens_tail)
		box(Vector3(s * 0.72, 0.48, 3.28), Vector3(0.08, 0.14, 0.04), lens_amber)

	# 10. Quatro Rodas Pesadas de Distribuição
	for s in [-0.96, 0.96]:
		add_wheel(s, 0.44, -2.10, 0.44, 0.26, 0.24, 6, "7f8c8d")
		add_wheel(s, 0.44, 1.80, 0.44, 0.32, 0.24, 6, "7f8c8d")
