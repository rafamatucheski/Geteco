extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Summit SUV 4x4 Heavy (Veículo Assinatura dos Lobos de Gelo - Viktor Frost):
## SUV pesado blindado de tração integral permanente, suspensão elevada,
## quebra-mato frontal com guincho, bagageiro de teto com estepe e barra de LED auxiliar.

func build() -> void:
	paint = mat("paint", "2980b9", 0.35, 0.30) # Azul glacial / Lobos de Gelo
	var steel_bumper := mat("heavy_steel", "2c3e50", 0.75, 0.35)
	var black := mat("black_trim", "1e272e", 0.1, 0.75)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("tinted_glass", "1c2833", 0.35, 0.10)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.8)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var led_bar := mat("led_white", "ffffff", 0.1, 0.1, 1.0)
	var chrome := mat("chrome", "bdc3c7", 0.9, 0.15)

	# 1. Chassi 4x4 Elevado & Skidplates (Proteção Inferior)
	box(Vector3(0.0, 0.38, 0.0), Vector3(1.95, 0.16, 4.90), black)
	# Protetor de cárter de aço na frente
	box(Vector3(0.0, 0.32, -2.25), Vector3(1.30, 0.12, 0.50), steel_bumper)

	# 2. Carroceria Inferior / Linha de Cintura Muscular
	box(Vector3(0.0, 0.82, 0.0), Vector3(2.05, 0.55, 4.80), paint)
	# Para-lamas alargados (Fender Flares de plástico preto fosco)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.04, 0.78, -1.45), Vector3(0.12, 0.42, 1.10), black)
		box(Vector3(s * 1.04, 0.78, 1.45), Vector3(0.12, 0.42, 1.10), black)
		# Estribos laterais tubulares (Rock Sliders)
		box(Vector3(s * 1.02, 0.42, 0.0), Vector3(0.14, 0.08, 2.20), steel_bumper)

	# 3. Capô Elevado com Entrada de Ar e Snorkel Lateral
	box(Vector3(0.0, 1.14, -1.55), Vector3(1.75, 0.16, 1.65), paint)
	box(Vector3(0.0, 1.23, -1.40), Vector3(0.70, 0.06, 0.90), black) # Scoop
	# Snorkel de ar na coluna A direita para travessia de rio
	tube([Vector3(0.96, 0.90, -1.80), Vector3(0.96, 1.70, -0.90)], 0.045, black)
	box(Vector3(0.96, 1.74, -0.85), Vector3(0.12, 0.10, 0.16), black)

	# 4. Cabine Fechada de 3 Fileiras (Estilo SUV Expedição)
	box(Vector3(0.0, 1.62, 0.6125), Vector3(1.72, 0.08, 3.575), paint) # Teto até o vidro traseiro
	# Para-brisa dianteiro inclinado
	var w_front := box(Vector3(0.0, 1.36, -0.75), Vector3(1.68, 0.58, 0.04), glass)
	w_front.rotation.x = deg_to_rad(26.0)
	# Vidro traseiro vertical do porta-malas
	box(Vector3(0.0, 1.38, 2.38), Vector3(1.62, 0.54, 0.04), glass)
	# Vidros laterais (três janelas de cada lado)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.855, 1.38, 0.6375), Vector3(0.03, 0.52, 3.525), glass)
		# Retrovisores grandes de reboque
		box(Vector3(s * 1.12, 1.25, -0.70), Vector3(0.22, 0.26, 0.09), black)

	# 5. Bagageiro de Teto Tubular (Roof Rack) com Expedição & Barra de LED
	# Longarinas e travessas do bagageiro
	for s in [-0.78, 0.78]:
		tube([Vector3(s, 1.72, -0.90), Vector3(s, 1.72, 1.60)], 0.030, steel_bumper)
	for z_pos in [-0.80, -0.20, 0.40, 1.00, 1.55]:
		tube([Vector3(-0.76, 1.72, z_pos), Vector3(0.76, 1.72, z_pos)], 0.025, steel_bumper)
	# Estepe off-road amarrado no bagageiro de teto
	var roof_spare := cylinder(Vector3(0.0, 1.82, 0.35), 0.38, 0.22, rubber)
	roof_spare.rotation.x = PI / 2.0
	box(Vector3(0.0, 1.86, 0.35), Vector3(0.40, 0.04, 0.40), steel_bumper) # Cinta de fixação
	# Barra de LED auxiliar de alta potência no teto
	box(Vector3(0.0, 1.75, -0.92), Vector3(1.20, 0.07, 0.08), black)
	box(Vector3(0.0, 1.75, -0.96), Vector3(1.14, 0.05, 0.02), led_bar)

	# 6. Para-choque Dianteiro Tático de Aço com Quebra-Mato (Bullbar) e Guincho
	box(Vector3(0.0, 0.68, -2.48), Vector3(1.98, 0.32, 0.20), steel_bumper)
	# Quebra-mato tubular envolvente
	tube([Vector3(-0.55, 0.72, -2.52), Vector3(-0.55, 1.22, -2.50)], 0.035, steel_bumper)
	tube([Vector3(0.55, 0.72, -2.52), Vector3(0.55, 1.22, -2.50)], 0.035, steel_bumper)
	tube([Vector3(-0.55, 1.20, -2.50), Vector3(0.55, 1.20, -2.50)], 0.035, steel_bumper)
	# Guincho elétrico central com carretel de cabo de aço
	box(Vector3(0.0, 0.70, -2.58), Vector3(0.42, 0.18, 0.16), black)
	box(Vector3(0.0, 0.70, -2.66), Vector3(0.20, 0.08, 0.04), chrome)

	# 7. Faróis e Lanternas
	for s in [-1.0, 1.0]:
		# Faróis duplos de LED
		box(Vector3(s * 0.74, 0.88, -2.42), Vector3(0.38, 0.18, 0.04), lens_head)
		# Lanternas traseiras verticais
		box(Vector3(s * 0.92, 1.10, 2.41), Vector3(0.14, 0.44, 0.04), lens_tail)

	for side in [-1.0,1.0]:
		for axle in [-1.45,1.45]:
			add_wheel(side*0.98,0.36,axle,0.38,0.27,0.22,6)
