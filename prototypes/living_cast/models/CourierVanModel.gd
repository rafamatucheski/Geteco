extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Courier Van Express: Furgão de entrega urbana de carga e logística.
## Identidade: Carroceria de teto alto, baú traseiro fechado, rack de teto com travas de escada e portas traseiras 50/50.

func build() -> void:
	paint = mat("paint", "ffffff", 0.25, 0.30)
	var black := mat("industrial_black", "1e272e", 0.1, 0.7)
	var stripe_blue := mat("van_stripe", "0984e3", 0.2, 0.4)
	var chrome_rack := mat("galvanized_steel", "b2bec3", 0.75, 0.35)
	var rubber := mat("rubber", "15191d", 0.0, 0.92)
	var glass := mat("glass", "222f3e", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.65)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)

	# 1. Assoalho e Chassi Reforçado
	box(Vector3(0.0, 0.26, 0.0), Vector3(1.82, 0.10, 4.60), rubber)

	# 2. Carroceria Inferior
	# Capô inclinado curto frontal
	box(Vector3(0.0, 0.72, -1.75), Vector3(1.86, 0.44, 1.25), paint)
	# Área de carga inferior
	# Mantém a frente do compartimento e fecha a carroceria no plano das portas.
	box(Vector3(0.0, 0.72, 0.625), Vector3(1.92, 0.44, 3.50), paint)

	# 3. Baú Traseiro Alto Fechado (Sem janelas traseiras)
	box(Vector3(0.0, 1.5325, 0.70), Vector3(1.90, 1.185, 3.35), paint)

	# 4. Cabine Superior (Envidraçada apenas para motorista/passageiro)
	box(Vector3(0.0, 1.62, -1.05), Vector3(1.80, 0.95, 1.15), paint)
	# Para-brisa dianteiro amplo quase plano
	var w_front := box(Vector3(0.0, 1.25, -1.35), Vector3(1.68, 0.78, 0.04), glass)
	w_front.rotation.x = deg_to_rad(26.0)
	# Vidros das portas dianteiras
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.905, 1.30, -0.95), Vector3(0.02, 0.52, 0.95), glass)
		# Retrovisores grandes de haste dupla
		box(Vector3(s * 1.05, 1.20, -1.25), Vector3(0.22, 0.32, 0.10), black)
		tube([Vector3(s * 0.92, 1.28, -1.25), Vector3(s * 1.02, 1.28, -1.25)], 0.015, black)
		tube([Vector3(s * 0.92, 1.12, -1.25), Vector3(s * 1.02, 1.12, -1.25)], 0.015, black)

	# 5. Identidade Visual 1: Faixa Decorativa Lateral de Entrega Expressa
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.965, 0.92, 0.35), Vector3(0.015, 0.18, 3.10), stripe_blue)
		# Painéis de porta corrediça lateral marcada
		box(Vector3(s * 0.962, 1.05, 0.15), Vector3(0.01, 1.25, 0.02), black)
		box(Vector3(s * 0.962, 1.05, 1.35), Vector3(0.01, 1.25, 0.02), black)

	# 6. Identidade Visual 2: Rack de Teto Tubular com Travas
	for s in [-0.75, 0.75]:
		tube([Vector3(s, 2.18, -0.80), Vector3(s, 2.18, 1.85)], 0.022, chrome_rack)
		# Suportes verticais de teto
		for z_sup in [-0.60, 0.30, 1.20, 1.80]:
			tube([Vector3(s, 2.12, z_sup), Vector3(s, 2.18, z_sup)], 0.020, black)
	# Travessas transversais
	for z_bar in [-0.40, 0.50, 1.40]:
		tube([Vector3(-0.75, 2.20, z_bar), Vector3(0.75, 2.20, z_bar)], 0.020, chrome_rack)

	# 7. Identidade Visual 3: Portas Traseiras 50/50 com Trincos e Degrau Traseiro
	# Fresta central da divisão das portas
	box(Vector3(0.0, 1.25, 2.38), Vector3(0.02, 1.70, 0.02), black)
	# Maçanetas das portas traseiras
	box(Vector3(-0.06, 1.10, 2.39), Vector3(0.04, 0.14, 0.03), black)
	box(Vector3(0.06, 1.10, 2.39), Vector3(0.04, 0.14, 0.03), black)
	# Degrau traseiro antiderrapante de carga
	box(Vector3(0.0, 0.32, 2.45), Vector3(1.70, 0.08, 0.22), black)

	# 8. Lanternas Traseiras Verticais e Frente
	for s in [-1.0, 1.0]:
		# Lanternas traseiras altas
		box(Vector3(s * 0.88, 1.25, 2.38), Vector3(0.08, 0.65, 0.03), lens_tail)
		# Faróis dianteiros verticais utilitários
		box(Vector3(s * 0.75, 0.72, -2.38), Vector3(0.26, 0.22, 0.04), lens_head)
		box(Vector3(s * 0.89, 0.72, -2.37), Vector3(0.06, 0.22, 0.04), lens_amber)

	# Grade dianteira utilitária preta
	box(Vector3(0.0, 0.65, -2.38), Vector3(1.10, 0.24, 0.03), black)
	# Para-choque robusto
	box(Vector3(0.0, 0.38, -2.40), Vector3(1.88, 0.18, 0.12), black)

	# 9. Quatro Rodas Reforçadas de Carga
	for s in [-0.88, 0.88]:
		add_wheel(s, 0.38, -1.45, 0.37, 0.24, 0.21, 5, "7f8c8d")
		add_wheel(s, 0.38, 1.45, 0.37, 0.24, 0.21, 5, "7f8c8d")
