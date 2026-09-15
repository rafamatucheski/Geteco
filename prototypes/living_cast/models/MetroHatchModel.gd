extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Metro Hatchback Sport: Hatch urbano compacto de 3 portas.
## Identidade: Traseira curta 2 volumes, aerofólio com brake-light, lanternas verticais e antena esportiva.

func build() -> void:
	paint = mat("paint", "e74c3c", 0.28, 0.25)
	var black := mat("black_trim", "1e272e", 0.1, 0.6)
	var rubber := mat("rubber", "15191d", 0.0, 0.92)
	var glass := mat("glass", "222f3e", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.65)
	var lens_brake := mat("brake_light", "e74c3c", 0.1, 0.2, 0.8)
	var lens_tail := mat("taillight_vert", "c0392b", 0.1, 0.2, 0.6)
	var alloy := mat("alloy_gunmetal", "718093", 0.75, 0.25)

	# 1. Assoalho
	box(Vector3(0.0, 0.20, 0.0), Vector3(1.58, 0.08, 3.65), rubber)

	# 2. Carroceria Inferior (Frente curta e traseira hatch)
	# Capô compacto
	box(Vector3(0.0, 0.58, -1.18), Vector3(1.64, 0.34, 1.35), paint)
	# Cabine inferior ampla
	box(Vector3(0.0, 0.58, 0.6325), Vector3(1.68, 0.35, 2.415), paint)

	# 3. Cabine Superior (Greenhouse Hatchback)
	# Teto arqueado
	box(Vector3(0.0, 1.34, 0.325), Vector3(1.28, 0.05, 2.05), paint)
	# Para-brisa dianteiro com boa inclinação aerodinâmica
	var w_front := box(Vector3(0.0, 1.02, -0.62), Vector3(1.26, 0.55, 0.04), glass)
	w_front.rotation.x = deg_to_rad(36.0)
	# Vidro traseiro da tampa do hatch (quase vertical, levemente inclinado)
	var w_rear := box(Vector3(0.0, 1.05, 1.32), Vector3(1.22, 0.52, 0.04), glass)
	w_rear.rotation.x = deg_to_rad(-22.0)
	# Vidros laterais de porta única ampla (estilo 3 portas)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.65, 1.04, 0.38), Vector3(0.02, 0.46, 2.08), glass)
		# Coluna de porta
		box(Vector3(s * 0.655, 1.04, -0.05), Vector3(0.03, 0.46, 0.06), black)
		# Maçaneta esportiva da porta
		box(Vector3(s * 0.85, 0.72, 0.10), Vector3(0.025, 0.025, 0.13), black)
		# Retrovisor aerodinâmico
		box(Vector3(s * 0.90, 0.85, -0.52), Vector3(0.16, 0.075, 0.09), paint)

	# 4. Identidade Visual 1: Aerofólio Traseiro com Terceira Luz de Freio (Brake Light)
	var spoiler := box(Vector3(0.0, 1.38, 1.30), Vector3(1.30, 0.05, 0.26), black)
	spoiler.rotation.x = deg_to_rad(8.0)
	box(Vector3(0.0, 1.385, 1.42), Vector3(0.38, 0.02, 0.03), lens_brake)

	# 5. Identidade Visual 2: Antena Esportiva de Teto
	var ant_base := cylinder(Vector3(0.0, 1.37, 0.95), 0.025, 0.02, black)
	var ant_rod := cylinder(Vector3(0.0, 1.48, 1.08), 0.006, 0.26, black)
	ant_rod.rotation.x = deg_to_rad(-35.0)

	# 6. Identidade Visual 3: Lanternas Traseiras Verticais em Coluna (C-Pillar)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.66, 1.08, 1.45), Vector3(0.05, 0.38, 0.04), lens_tail)
		# Lanterna inferior de para-choque
		box(Vector3(s * 0.68, 0.62, 1.84), Vector3(0.18, 0.08, 0.03), lens_tail)

	# 7. Frente Esportiva: Faróis em Gota & Grade Honeycomb
	box(Vector3(0.0, 0.52, -1.86), Vector3(0.96, 0.16, 0.03), black)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.62, 0.62, -1.84), Vector3(0.28, 0.14, 0.04), lens_head)
		# Farol de neblina inferior
		cylinder(Vector3(s * 0.58, 0.35, -1.87), 0.05, 0.03, lens_head)

	# 8. Para-choques Esportivos
	box(Vector3(0.0, 0.35, -1.86), Vector3(1.66, 0.14, 0.10), paint)
	# Difusor traseiro preto
	box(Vector3(0.0, 0.34, 1.86), Vector3(1.66, 0.14, 0.08), black)

	# 9. Rodas de Liga Leve Gunmetal
	for s in [-0.80, 0.80]:
		add_wheel(s, 0.34, -1.15, 0.32, 0.20, 0.20, 6, "718093")
		add_wheel(s, 0.34, 1.15, 0.32, 0.20, 0.20, 6, "718093")

	# 10. Saída de Escape Esportiva Única Cromada
	var pipe := cylinder(Vector3(0.52, 0.28, 1.88), 0.055, 0.14, mat("chrome", "ecf0f1", 0.9, 0.2))
	pipe.rotation.x = PI / 2.0
