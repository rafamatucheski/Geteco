extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Rescue Pumper: Caminhão pesado de combate a incêndio do Corpo de Bombeiros.
## Identidade: Vermelho bombeiro, giroflex estroboscópico, canhão d'água no teto, carretéis de mangueira e escadas.

var water_turret: Node3D
var water_muzzle: Marker3D

func build() -> void:
	paint = mat("paint", "c0392b", 0.35, 0.25)
	var white := mat("white_stripe", "f5f6fa", 0.2, 0.35)
	var chevron_yellow := mat("chevron_yellow", "f1c40f", 0.2, 0.4)
	var chrome := mat("chrome", "ecf0f1", 0.88, 0.15)
	var diamond_plate := mat("diamond_plate", "b2bec3", 0.70, 0.35)
	var black := mat("fire_black", "1e272e", 0.1, 0.8)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)
	var hose_yellow := mat("fire_hose", "f39c12", 0.1, 0.8)

	# 1. Chassi Pesado e Para-choque Frontal Reforçado
	box(Vector3(0.0, 0.36, 0.0), Vector3(2.36, 0.18, 8.30), black)
	# Para-choque frontal estendido de combate a incêndio com guincho embutido
	box(Vector3(0.0, 0.52, -4.32), Vector3(2.44, 0.32, 0.30), chrome)
	cylinder(Vector3(0.0, 0.56, -4.42), 0.12, 0.22, black) # Carretel do guincho

	# 2. Cabine Dupla Dianteira (Crew Cab)
	box(Vector3(0.0, 1.35, -2.75), Vector3(2.38, 1.48, 2.70), paint)
	# Faixa branca horizontal na cabine
	box(Vector3(0.0, 1.15, -2.75), Vector3(2.40, 0.24, 2.72), white)
	# Para-brisa frontal amplo
	var w_front := box(Vector3(0.0, 1.62, -4.10), Vector3(2.26, 0.85, 0.04), glass)
	w_front.rotation.x = deg_to_rad(12.0)
	# Vidros laterais da cabine dupla (4 portas de equipe)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.20, 1.65, -3.4), Vector3(0.02, 0.65, 1.05), glass)
		box(Vector3(s * 1.20, 1.65, -2.2), Vector3(0.02, 0.65, 1.05), glass)
		# Retrovisores grandes de caminhão
		box(Vector3(s * 1.38, 1.55, -3.95), Vector3(0.24, 0.38, 0.10), chrome)
		tube([Vector3(s * 1.22, 1.68, -3.95), Vector3(s * 1.32, 1.68, -3.95)], 0.020, chrome)
		tube([Vector3(s * 1.22, 1.42, -3.95), Vector3(s * 1.32, 1.42, -3.95)], 0.020, chrome)

	# 3. Módulo Traseiro de Bombas, Ferramentas e Tanque d'Água
	box(Vector3(0.0, 1.45, 0.95), Vector3(2.36, 1.65, 4.70), paint)
	# Teto com piso de chapa de aço diamantada antiderrapante
	box(Vector3(0.0, 2.30, 0.95), Vector3(2.34, 0.06, 4.65), diamond_plate)

	# 4. Identidade Visual 1: Painel de Controle de Bombas e Carretéis de Mangueira Laterais
	for s in [-1.0, 1.0]:
		# Painel de registros, manômetros e entradas/saídas de água
		box(Vector3(s * 1.19, 1.15, -1.05), Vector3(0.04, 0.85, 0.95), diamond_plate)
		for valve in [-0.25, 0.0, 0.25]:
			var conn := cylinder(Vector3(s * 1.22, 0.92, -1.05 + valve), 0.07, 0.06, chrome)
			conn.rotation.z = PI / 2.0
		# Carretel lateral de mangueira enrolada
		var reel := cylinder(Vector3(s * 1.20, 1.55, 0.15), 0.28, 0.22, hose_yellow)
		reel.rotation.z = PI / 2.0
		var reel_hub := cylinder(Vector3(s * 1.22, 1.55, 0.15), 0.32, 0.04, chrome)
		reel_hub.rotation.z = PI / 2.0
		# Portas de compartimento de ferramentas (persianas de alumínio rolantes)
		for z_comp in [1.15, 2.35]:
			box(Vector3(s * 1.19, 1.35, z_comp), Vector3(0.03, 1.20, 0.95), diamond_plate)

	# 5. Identidade Visual 2: Canhão Monitor de Água no Teto da Cabine (Deck Gun)
	cylinder(Vector3(0.0, 2.32, -1.55), 0.20, 0.20, red_metal_mat())
	water_turret = Node3D.new()
	water_turret.name = "WaterTurret"
	water_turret.position = Vector3(0.0, 2.48, -1.55)
	add_child(water_turret)
	var gun_barrel := cylinder(Vector3.ZERO, 0.085, 0.76, chrome)
	remove_child(gun_barrel)
	water_turret.add_child(gun_barrel)
	gun_barrel.position = Vector3(0, 0, -0.30)
	gun_barrel.rotation.x = PI * 0.5
	var gun_nozzle := cylinder(Vector3.ZERO, 0.11, 0.18, black)
	remove_child(gun_nozzle)
	water_turret.add_child(gun_nozzle)
	gun_nozzle.position = Vector3(0, 0, -0.72)
	gun_nozzle.rotation.x = PI * 0.5
	water_muzzle = Marker3D.new()
	water_muzzle.name = "WaterMuzzle"
	water_muzzle.position = Vector3(0, 0, -0.82)
	water_turret.add_child(water_muzzle)

	# 6. Identidade Visual 3: Escadas de Resgate em Alumínio no Teto
	for s in [-0.75, 0.75]:
		tube([Vector3(s - 0.12, 2.45, -0.8), Vector3(s - 0.12, 2.45, 3.1)], 0.020, chrome)
		tube([Vector3(s + 0.12, 2.45, -0.8), Vector3(s + 0.12, 2.45, 3.1)], 0.020, chrome)
		for r in 10:
			tube([Vector3(s - 0.12, 2.45, -0.6 + float(r) * 0.36), Vector3(s + 0.12, 2.45, -0.6 + float(r) * 0.36)], 0.015, chrome)

	# 7. Identidade Visual 4: Barra Dupla de Giroflex Estroboscópico de Emergência e Sirenes
	add_lightbar(2.18, -3.85, Color("#e74c3c"), Color("#f39c12"), 1.85)
	# Barra de giroflex secundária traseira
	add_lightbar(2.38, 3.25, Color("#e74c3c"), Color("#e74c3c"), 1.65)
	# Buzinas de ar cromadas no teto da cabine
	for s in [-0.45, 0.45]:
		var horn := cylinder(Vector3(s, 2.18, -3.20), 0.055, 0.48, chrome)
		horn.rotation.x = PI / 2.0

	# 8. Traseira com Faixas Chevron Amarelas/Vermelhas de Segurança Rodoviária
	box(Vector3(0.0, 1.35, 3.32), Vector3(2.32, 1.45, 0.04), paint)
	for c in 5:
		var chev := box(Vector3(-0.9 + float(c) * 0.45, 1.05 + float(c % 2) * 0.3, 3.33), Vector3(0.24, 0.55, 0.02), chevron_yellow)
		chev.rotation.z = deg_to_rad(45.0 if c % 2 == 0 else -45.0)

	# 9. Faróis Dianteiros, Lanternas Traseiras e Luzes de Cena
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.95, 0.82, -4.18), Vector3(0.26, 0.22, 0.04), lens_head)
		box(Vector3(s * 0.65, 0.82, -4.18), Vector3(0.20, 0.20, 0.04), lens_head)
		# Lanternas traseiras triplas verticais
		for t in 3:
			box(Vector3(s * 1.05, 0.75 + float(t) * 0.22, 3.34), Vector3(0.12, 0.16, 0.04), lens_tail if t < 2 else lens_amber)

	# 10. Quatro Rodas Pesadas de Bombeiro
	for s in [-1.06, 1.06]:
		add_wheel(s, 0.48, -2.50, 0.50, 0.30, 0.28, 6, "dcdde1")
		add_wheel(s, 0.48, 2.10, 0.50, 0.36, 0.28, 6, "dcdde1") # Dupla rodagem traseira

func red_metal_mat() -> StandardMaterial3D:
	return mat("fire_pumper_red", "a82020", 0.7, 0.3)
