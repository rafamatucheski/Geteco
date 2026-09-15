extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Route City Ônibus Urbano: Ônibus de passageiros metropolitano de 2 portas.
## Identidade: Letreiro digital iluminado frontal, janelas panorâmicas, ar-condicionado de teto e portas de embarque.

func build() -> void:
	paint = mat("paint", "2980b9", 0.35, 0.30)
	var white := mat("roof_white", "ecf0f1", 0.2, 0.35)
	var black := mat("bus_black", "1e272e", 0.1, 0.8)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass_tinted", "1c2833", 0.38, 0.12)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.6)
	var sign_glow := mat("matrix_sign", "f1c40f", 0.1, 0.1, 1.2) # Letreiro âmbar LED luminoso
	var chrome := mat("chrome_trim", "dcdde1", 0.8, 0.2)

	# 1. Assoalho e Chassi Pesado de Ônibus
	box(Vector3(0.0, 0.35, 0.0), Vector3(2.32, 0.16, 9.40), rubber)

	# 2. Saia Inferior da Carroceria (Pintada)
	box(Vector3(0.0, 0.85, 0.0), Vector3(2.38, 0.84, 9.50), paint)

	# 3. Caixa Superior da Carroceria (Teto branco térmico)
	box(Vector3(0.0, 2.72, 0.0), Vector3(2.36, 0.22, 9.45), white)

	# 4. Vidros Panorâmicos Laterais e Colunas
	# Lado Esquerdo (janelas contínuas de ponta a ponta)
	box(Vector3(-1.19, 1.95, 0.0), Vector3(0.02, 1.35, 9.30), glass)
	# Colunas verticais estruturais pretas entre janelas
	for z_col in [-3.2, -1.6, 0.0, 1.6, 3.2]:
		box(Vector3(-1.195, 1.95, z_col), Vector3(0.03, 1.35, 0.10), black)

	# Lado Direito (com aberturas para as 2 portas sanfonadas)
	# Seção frontal de vidro
	box(Vector3(1.19, 1.95, -1.6), Vector3(0.02, 1.35, 3.00), glass)
	# Seção central de vidro
	box(Vector3(1.19, 1.95, 1.6), Vector3(0.02, 1.35, 3.00), glass)
	# Colunas do lado direito
	for z_col in [-1.6, 0.0, 1.6]:
		box(Vector3(1.195, 1.95, z_col), Vector3(0.03, 1.35, 0.10), black)

	# 5. Identidade Visual 1: Duas Portas Sanfonadas de Embarque e Desembarque (Lado Direito)
	for z_door in [-3.95, 3.65]:
		# Vão da porta (reentrância)
		box(Vector3(1.16, 1.45, z_door), Vector3(0.08, 2.25, 0.96), black)
		# Folhas da porta de vidro sanfonada
		box(Vector3(1.18, 1.55, z_door - 0.23), Vector3(0.02, 1.85, 0.42), glass)
		box(Vector3(1.18, 1.55, z_door + 0.23), Vector3(0.02, 1.85, 0.42), glass)
		# Degrau de entrada iluminado
		box(Vector3(1.14, 0.48, z_door), Vector3(0.12, 0.08, 0.90), chrome)

	# 6. Para-brisa Panorâmico Dianteiro e Traseiro
	var w_front := box(Vector3(0.0, 1.90, -4.68), Vector3(2.28, 1.38, 0.04), glass)
	w_front.rotation.x = deg_to_rad(10.0)
	# Vidro vigia traseiro
	box(Vector3(0.0, 2.10, 4.74), Vector3(2.20, 1.05, 0.04), glass)

	# 7. Identidade Visual 2: Grande Letreiro Digital de Rota LED Iluminado ("042 PORTO")
	var sign_box := box(Vector3(0.0, 2.76, -4.66), Vector3(1.85, 0.24, 0.10), black)
	sign_box.rotation.x = deg_to_rad(10.0)
	var sign_text := box(Vector3(0.0, 2.76, -4.71), Vector3(1.72, 0.18, 0.02), sign_glow)
	sign_text.rotation.x = deg_to_rad(10.0)

	# 8. Identidade Visual 3: Módulos de Ar-Condicionado de Teto e Luzes Delimitadoras
	for z_ac in [-1.2, 1.8]:
		box(Vector3(0.0, 2.96, z_ac), Vector3(1.65, 0.24, 1.80), white)
		# Grelhas de ventilação do ar-condicionado
		for g in 4:
			box(Vector3(0.0, 3.09, z_ac - 0.5 + float(g) * 0.32), Vector3(1.45, 0.02, 0.14), black)

	# Luzes de posição no topo do teto
	for s in [-1.05, -0.45, 0.45, 1.05]:
		box(Vector3(s, 2.86, -4.74), Vector3(0.08, 0.04, 0.03), lens_amber)
		box(Vector3(s, 2.86, 4.75), Vector3(0.08, 0.04, 0.03), lens_tail)

	# 9. Faróis Dianteiros, Lanternas Traseiras e Para-choques Pesados
	for s in [-1.0, 1.0]:
		# Faróis dianteiros duplos
		box(Vector3(s * 0.88, 0.82, -4.76), Vector3(0.24, 0.26, 0.04), lens_head)
		box(Vector3(s * 0.60, 0.82, -4.76), Vector3(0.18, 0.22, 0.04), lens_head)
		# Lanternas traseiras triplas verticais de ônibus
		for t in 3:
			var col: Material = lens_tail if t < 2 else lens_amber
			box(Vector3(s * 0.98, 0.72 + float(t) * 0.16, 4.76), Vector3(0.12, 0.12, 0.04), col)

	# Para-choques de borracha maciça
	box(Vector3(0.0, 0.48, -4.80), Vector3(2.42, 0.26, 0.18), black)
	box(Vector3(0.0, 0.52, 4.80), Vector3(2.42, 0.26, 0.18), black)

	# 10. Quatro Conjuntos de Rodas Pesadas de Ônibus (Eixo Dianteiro e Traseiro)
	for s in [-1.06, 1.06]:
		add_wheel(s, 0.48, -2.80, 0.48, 0.28, 0.28, 6, "7f8c8d")
		add_wheel(s, 0.48, 2.60, 0.48, 0.34, 0.28, 6, "7f8c8d") # Rodagem traseira mais larga
