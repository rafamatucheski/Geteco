extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Towmaster: Caminhão guincho com plataforma de reboque e torre hidráulica.
## Identidade: Amarelo serviço, giroflex âmbar, plataforma diamantada chanfrada e guincho com cabo de aço.

func build() -> void:
	paint = mat("paint", "f39c12", 0.35, 0.30) # Amarelo/Laranja de assistência rodoviária
	var diamond_plate := mat("diamond_plate", "7f8c8d", 0.75, 0.30)
	var chrome := mat("chrome", "dcdde1", 0.88, 0.15)
	var black := mat("industrial_black", "1e272e", 0.1, 0.8)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_beacon", "f1c40f", 0.1, 0.1, 1.2) # Âmbar luminoso
	var steel_cable := mat("steel_cable", "57606f", 0.65, 0.4)

	# 1. Chassi Longo Pesado de Reboque
	box(Vector3(0.0, 0.35, 0.0), Vector3(2.10, 0.18, 6.90), black)
	# Para-choque frontal resistente
	box(Vector3(0.0, 0.48, -3.55), Vector3(2.28, 0.24, 0.18), black)

	# 2. Cabine Dianteira
	box(Vector3(0.0, 1.28, -2.45), Vector3(2.20, 1.45, 1.85), paint)
	# Para-brisa dianteiro quase vertical
	var w_front := box(Vector3(0.0, 1.55, -3.28), Vector3(2.05, 0.78, 0.04), glass)
	w_front.rotation.x = deg_to_rad(14.0)
	# Vidros laterais da cabine
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.105, 1.52, -2.45), Vector3(0.02, 0.58, 1.10), glass)
		# Retrovisores com braço estendido de reboque
		box(Vector3(s * 1.30, 1.45, -3.10), Vector3(0.22, 0.35, 0.08), black)
		tube([Vector3(s * 1.12, 1.55, -3.10), Vector3(s * 1.25, 1.55, -3.10)], 0.020, black)
		tube([Vector3(s * 1.12, 1.35, -3.10), Vector3(s * 1.25, 1.35, -3.10)], 0.020, black)

	# 3. Identidade Visual 1: Barra de Giroflex Âmbar de Serviço Rodoviário no Teto
	add_lightbar(2.10, -2.45, Color("#f1c40f"), Color("#f39c12"), 1.45)

	# 4. Plataforma de Reboque Traseira Diamantada (Flatbed)
	# Base da plataforma
	box(Vector3(0.0, 0.85, 0.95), Vector3(2.25, 0.14, 4.85), diamond_plate)
	# Rampa de acesso chanfrada na extremidade traseira da plataforma
	var ramp := box(Vector3(0.0, 0.72, 3.42), Vector3(2.24, 0.12, 0.55), diamond_plate)
	ramp.rotation.x = deg_to_rad(-18.0)
	# Trilhos / Guias laterais de pneu na plataforma
	for s in [-1.05, 1.05]:
		box(Vector3(s, 0.96, 0.95), Vector3(0.08, 0.12, 4.80), black)
		# Caixas de ferramentas de aço sob a plataforma
		box(Vector3(s * 0.90, 0.45, 0.20), Vector3(0.24, 0.42, 1.20), diamond_plate)

	# 5. Identidade Visual 2: Torre de Guincho com Carretel e Cabo de Aço (Winch & Boom)
	# Estrutura tubular em A atrás da cabine
	for s in [-0.75, 0.75]:
		tube([Vector3(s, 0.95, -1.35), Vector3(s * 0.35, 1.95, -1.15)], 0.045, black)
		tube([Vector3(s, 0.95, -0.65), Vector3(s * 0.35, 1.95, -1.15)], 0.040, black)
	# Travessa superior da torre
	tube([Vector3(-0.35 * 0.75, 1.95, -1.15), Vector3(0.35 * 0.75, 1.95, -1.15)], 0.045, black)
	# Carretel hidráulico de guincho
	var drum := cylinder(Vector3(0.0, 1.15, -1.25), 0.18, 0.55, black)
	drum.rotation.z = PI / 2.0
	var cable_wrap := cylinder(Vector3(0.0, 1.15, -1.25), 0.14, 0.48, steel_cable)
	cable_wrap.rotation.z = PI / 2.0
	# Cabo de aço estendido da torre até o gancho
	tube([Vector3(0.0, 1.95, -1.15), Vector3(0.0, 1.05, -0.20)], 0.016, steel_cable)
	# Gancho de reboque amarelo de alta capacidade
	var hook := box(Vector3(0.0, 0.98, -0.18), Vector3(0.08, 0.16, 0.08), mat("tow_hook", "f1c40f", 0.3, 0.4))

	# 6. Sapatas Estabilizadoras Traseiras Hidráulicas
	for s in [-1.02, 1.02]:
		box(Vector3(s, 0.52, 3.25), Vector3(0.12, 0.35, 0.14), black)
		cylinder(Vector3(s, 0.32, 3.25), 0.09, 0.04, chrome)

	# 7. Faróis Dianteiros e Lanternas Traseiras
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.85, 0.78, -3.45), Vector3(0.28, 0.22, 0.04), lens_head)
		box(Vector3(s * 1.02, 0.78, -3.44), Vector3(0.08, 0.22, 0.04), lens_amber)
		# Lanternas traseiras embutidas sob a rampa
		box(Vector3(s * 0.92, 0.48, 3.55), Vector3(0.18, 0.12, 0.04), lens_tail)
		box(Vector3(s * 0.72, 0.48, 3.55), Vector3(0.12, 0.12, 0.04), lens_amber)

	# 8. Quatro Rodas Pesadas
	for s in [-0.98, 0.98]:
		add_wheel(s, 0.44, -2.15, 0.45, 0.26, 0.25, 6, "7f8c8d")
		add_wheel(s, 0.44, 1.85, 0.45, 0.34, 0.25, 6, "7f8c8d") # Dupla rodagem traseira de carga
