extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Ranch Single V8 4x4: Picape pesada de caçamba aberta e cabine simples.
## Identidade: Caçamba longa aberta, santantônio tubular com holofotes, estepe na caçamba e suspensão 4x4 elevada.

func build() -> void:
	paint = mat("paint", "8e44ad", 0.35, 0.30)
	var chrome := mat("chrome", "dcdde1", 0.85, 0.20)
	var bed_liner := mat("bed_liner", "2d3436", 0.1, 0.85)
	var black := mat("black_trim", "1e272e", 0.1, 0.7)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)
	var spot_lens := mat("spotlight_glow", "ffffaa", 0.1, 0.1, 0.9)

	# 1. Chassi Longo Elevado
	box(Vector3(0.0, 0.34, 0.0), Vector3(1.88, 0.14, 4.85), black)

	# 2. Frente / Capô e Para-lamas Altos
	box(Vector3(0.0, 0.82, -1.65), Vector3(1.96, 0.46, 1.60), paint)
	# Cabine simples
	box(Vector3(0.0, 0.80, -0.45), Vector3(1.94, 0.46, 1.10), paint)

	# 3. Cabine Superior (Envidraçada para 2/3 ocupantes)
	box(Vector3(0.0, 1.48, -0.42), Vector3(1.58, 0.06, 1.05), paint)
	# Para-brisa frontal
	var w_front := box(Vector3(0.0, 1.22, -0.92), Vector3(1.52, 0.62, 0.04), glass)
	w_front.rotation.x = deg_to_rad(24.0)
	# Vidro traseiro da cabine (vertical com abertura corrediça)
	box(Vector3(0.0, 1.25, 0.10), Vector3(1.48, 0.52, 0.03), glass)
	# Vidros das portas laterais
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.795, 1.24, -0.42), Vector3(0.02, 0.52, 0.95), glass)
		# Retrovisores quadrados de picape pesada
		box(Vector3(s * 1.06, 1.15, -0.82), Vector3(0.20, 0.24, 0.08), chrome)
		tube([Vector3(s * 0.95, 1.18, -0.82), Vector3(s * 1.04, 1.18, -0.82)], 0.018, chrome)

	# 4. Caçamba Traseira Aberta (Bed)
	# Piso da caçamba com protetor antiderrapante (bed liner)
	box(Vector3(0.0, 0.58, 1.35), Vector3(1.78, 0.05, 2.30), bed_liner)
	# Paredes laterais da caçamba
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.92, 0.82, 1.35), Vector3(0.12, 0.48, 2.30), paint)
		# Borda superior de proteção da caçamba
		box(Vector3(s * 0.92, 1.07, 1.35), Vector3(0.14, 0.03, 2.32), black)
	# Parede frontal da caçamba (atrás da cabine)
	box(Vector3(0.0, 0.82, 0.22), Vector3(1.76, 0.48, 0.08), paint)
	# Tampa traseira da caçamba (Tailgate com maçaneta cromada)
	box(Vector3(0.0, 0.82, 2.48), Vector3(1.76, 0.48, 0.08), paint)
	box(Vector3(0.0, 0.98, 2.53), Vector3(0.18, 0.04, 0.03), chrome)

	# 5. Identidade Visual 1: Santantônio Tubular Duplo de Aço com Holofotes
	for s in [-0.80, 0.80]:
		# Tubos principais do santantônio
		tube([Vector3(s, 1.06, 0.28), Vector3(s, 1.62, 0.28)], 0.035, black)
		# Braço inclinado de ancoragem na caçamba
		tube([Vector3(s, 1.58, 0.28), Vector3(s, 1.06, 1.05)], 0.030, black)
	# Barra transversal superior
	tube([Vector3(-0.80, 1.62, 0.28), Vector3(0.80, 1.62, 0.28)], 0.035, black)
	# Dois holofotes auxiliares de caçamba montados no santantônio
	for s in [-0.35, 0.35]:
		var spot_housing := cylinder(Vector3(s, 1.72, 0.28), 0.08, 0.08, black)
		spot_housing.rotation.x = deg_to_rad(12.0)
		var spot_face := cylinder(Vector3(s, 1.72, 0.23), 0.065, 0.02, spot_lens)
		spot_face.rotation.x = deg_to_rad(12.0)

	# 6. Identidade Visual 2: Estepe Off-Road Montado na Caçamba
	var spare := cylinder(Vector3(-0.68, 0.82, 1.15), 0.38, 0.26, rubber)
	spare.rotation.z = PI / 2.0
	var spare_rim := cylinder(Vector3(-0.66, 0.82, 1.15), 0.22, 0.28, chrome)
	spare_rim.rotation.z = PI / 2.0

	# 7. Frente Imponente: Grade Cromada Horizontal, Faróis Duplos e Quebra-Mato
	box(Vector3(0.0, 0.78, -2.48), Vector3(1.28, 0.34, 0.04), chrome)
	for g in 5:
		box(Vector3(0.0, 0.66 + float(g) * 0.055, -2.485), Vector3(1.22, 0.02, 0.03), black)
	# Faróis dianteiros duplos quadrados
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.78, 0.82, -2.48), Vector3(0.32, 0.24, 0.04), lens_head)
		box(Vector3(s * 0.78, 0.65, -2.48), Vector3(0.32, 0.06, 0.04), lens_amber)
		# Lanternas traseiras verticais de picape
		box(Vector3(s * 0.94, 0.82, 2.48), Vector3(0.08, 0.42, 0.04), lens_tail)

	# Para-choques reforçados
	box(Vector3(0.0, 0.46, -2.52), Vector3(1.98, 0.18, 0.14), chrome)
	# Para-choque traseiro tipo degrau com engate de reboque
	box(Vector3(0.0, 0.44, 2.54), Vector3(1.92, 0.14, 0.14), black)
	cylinder(Vector3(0.0, 0.40, 2.64), 0.045, 0.08, chrome)

	# 8. Quatro Rodas 4x4 Grandes Elevadas
	for s in [-0.94, 0.94]:
		add_wheel(s, 0.44, -1.45, 0.42, 0.28, 0.24, 5, "dcdde1")
		add_wheel(s, 0.44, 1.45, 0.42, 0.28, 0.24, 5, "dcdde1")

	# 9. Escapamento lateral saindo antes da roda traseira
	var exh := cylinder(Vector3(0.98, 0.32, 0.65), 0.055, 0.16, chrome)
	exh.rotation.z = deg_to_rad(75.0)
