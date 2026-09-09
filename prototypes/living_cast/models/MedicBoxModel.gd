extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Medic Box: Ambulância de suporte avançado tipo baú médico (SAMU / Resgate).
## Identidade: Módulo cúbico traseiro alargado, cruzes médicas em relevo, giroflex azul/vermelho e degrau de maca.

func build() -> void:
	paint = mat("paint", "f5f6fa", 0.20, 0.35)
	var orange_stripe := mat("medic_orange", "e67e22", 0.1, 0.4)
	var red_cross := mat("medic_red", "d63031", 0.1, 0.4)
	var blue_cross := mat("medic_blue", "0984e3", 0.1, 0.4)
	var chrome := mat("chrome", "ecf0f1", 0.85, 0.20)
	var black := mat("black_trim", "1e272e", 0.1, 0.7)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)

	# 1. Assoalho e Chassi da Ambulância
	box(Vector3(0.0, 0.30, 0.0), Vector3(2.00, 0.12, 5.30), rubber)

	# 2. Cabine Dianteira
	# Capô frontal
	box(Vector3(0.0, 0.78, -1.95), Vector3(1.92, 0.46, 1.40), paint)
	# Cabine do motorista/paramédico
	box(Vector3(0.0, 1.45, -1.05), Vector3(1.86, 0.90, 1.25), paint)
	# Para-brisa frontal inclinado
	var w_front := box(Vector3(0.0, 1.35, -1.48), Vector3(1.72, 0.72, 0.04), glass)
	w_front.rotation.x = deg_to_rad(24.0)
	# Vidros laterais da cabine
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.935, 1.38, -0.98), Vector3(0.02, 0.52, 0.92), glass)
		# Retrovisores com espelho de ponto cego
		box(Vector3(s * 1.08, 1.25, -1.35), Vector3(0.20, 0.34, 0.08), black)
		tube([Vector3(s * 0.95, 1.32, -1.35), Vector3(s * 1.06, 1.32, -1.35)], 0.018, black)
		tube([Vector3(s * 0.95, 1.18, -1.35), Vector3(s * 1.06, 1.18, -1.35)], 0.018, black)

	# 3. Módulo Traseiro Cúbico de Resgate (Box Module - mais largo e mais alto)
	box(Vector3(0.0, 1.45, 0.95), Vector3(2.14, 1.55, 3.25), paint)
	# Teto do módulo médico
	box(Vector3(0.0, 2.25, 0.95), Vector3(2.12, 0.08, 3.20), paint)

	# 4. Identidade Visual 1: Faixa Laranja / Vermelha Reflexiva de Resgate
	for s in [-1.0, 1.0]:
		# Faixa horizontal contínua
		box(Vector3(s * 1.075, 0.92, 0.95), Vector3(0.02, 0.22, 3.24), orange_stripe)
		# Faixa na cabine
		box(Vector3(s * 0.965, 0.92, -1.45), Vector3(0.02, 0.22, 2.10), orange_stripe)

	# 5. Identidade Visual 2: Cruzes Médicas / Estrela da Vida em Relevo nas Laterais e Teto
	for s in [-1.0, 1.0]:
		# Cruz Médica Lateral (haste vertical + horizontal)
		box(Vector3(s * 1.076, 1.52, 0.95), Vector3(0.025, 0.52, 0.16), red_cross)
		box(Vector3(s * 1.076, 1.52, 0.95), Vector3(0.025, 0.16, 0.52), red_cross)

	# Cruz Médica no Teto (visível por helicópteros e câmera top-down)
	box(Vector3(0.0, 2.30, 0.95), Vector3(0.65, 0.025, 0.20), red_cross)
	box(Vector3(0.0, 2.30, 0.95), Vector3(0.20, 0.025, 0.65), red_cross)

	# 6. Identidade Visual 3: Portas Traseiras de Maca com Janelas Quadradas Fumê e Degrau
	# Divisão central das portas traseiras
	box(Vector3(0.0, 1.25, 2.58), Vector3(0.02, 1.60, 0.02), black)
	# Janelas quadradas fumê nas duas portas traseiras
	for s in [-0.45, 0.45]:
		box(Vector3(s, 1.55, 2.585), Vector3(0.38, 0.48, 0.02), glass)
		# Maçanetas pretas
		box(Vector3(s * 0.25, 1.15, 2.59), Vector3(0.03, 0.14, 0.03), black)

	# Degrau traseiro antiderrapante de acesso à maca
	box(Vector3(0.0, 0.38, 2.65), Vector3(1.65, 0.08, 0.24), chrome)

	# 7. Identidade Visual 4: Barra de Giroflex Estroboscópico Azul/Vermelho e Estrobos de Quina
	add_lightbar(2.05, -1.25, Color("#e74c3c"), Color("#0984e3"), 1.65)
	# Estrobos de quina superiores do módulo traseiro
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.04, 2.22, -0.62), Vector3(0.08, 0.08, 0.08), red_cross if s < 0 else blue_cross)
		box(Vector3(s * 1.04, 2.22, 2.52), Vector3(0.08, 0.08, 0.08), red_cross if s < 0 else blue_cross)

	# 8. Frente, Faróis, Grade e Lanternas
	box(Vector3(0.0, 0.72, -2.66), Vector3(1.15, 0.28, 0.04), chrome)
	for s in [-1.0, 1.0]:
		# Faróis dianteiros duplos
		box(Vector3(s * 0.76, 0.76, -2.66), Vector3(0.28, 0.22, 0.04), lens_head)
		box(Vector3(s * 0.90, 0.76, -2.65), Vector3(0.06, 0.22, 0.04), lens_amber)
		# Lanternas traseiras verticais
		box(Vector3(s * 1.02, 1.05, 2.58), Vector3(0.08, 0.55, 0.03), lens_tail)

	# Para-choque dianteiro
	box(Vector3(0.0, 0.42, -2.68), Vector3(1.96, 0.16, 0.12), chrome)

	# 9. Quatro Rodas Reforçadas
	for s in [-0.94, 0.94]:
		add_wheel(s, 0.40, -1.65, 0.38, 0.24, 0.22, 5, "dcdde1")
		add_wheel(s, 0.40, 1.55, 0.38, 0.30, 0.22, 5, "dcdde1") # Rodagem traseira mais larga
