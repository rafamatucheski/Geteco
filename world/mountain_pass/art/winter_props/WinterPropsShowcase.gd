class_name WinterPropsShowcase
extends Node3D

## Cena de Demonstração dos Modelos 3D de Inverno (Winter Props Showcase):
## Apresenta os 4 modelos procedurais em escala métrica 1:1, acompanhados de
## manequins de escala humana de 1,80 m ao lado de portas, janelas e bancos,
## além de demonstrar a customização de cores antes da inserção na árvore de cena.

const HUMAN_SCRIPT := preload("res://world/mountain_pass/art/winter_props/HumanScaleReference3D.gd")
const CABIN_SCRIPT := preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
const SHELTER_SCRIPT := preload("res://world/mountain_pass/art/winter_props/PatrolShelter3D.gd")
const WOODPILE_SCRIPT := preload("res://world/mountain_pass/art/winter_props/CoveredWoodpile3D.gd")
const SIGN_BENCH_SCRIPT := preload("res://world/mountain_pass/art/winter_props/TrailSignAndBench3D.gd")

func _ready() -> void:
	_setup_environment()
	_build_ground()
	_populate_showcase()

func _setup_environment() -> void:
	# Iluminação suave de inverno: sem excesso de luz nem shaders pesados
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	dir_light.light_color = Color(1.0, 0.96, 0.90)
	dir_light.light_energy = 1.25
	dir_light.shadow_enabled = true
	add_child(dir_light)

	var sky_fill := DirectionalLight3D.new()
	sky_fill.name = "SkyBounceFill"
	sky_fill.rotation_degrees = Vector3(50.0, -145.0, 0.0)
	sky_fill.light_color = Color(0.72, 0.85, 0.98)
	sky_fill.light_energy = 0.45
	add_child(sky_fill)

	# Câmera com ângulo de perspectiva isométrica cinematográfica
	var cam := Camera3D.new()
	cam.name = "ShowcaseCamera"
	cam.position = Vector3(0.0, 6.2, 14.5)
	cam.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	cam.current = true
	add_child(cam)

func _build_ground() -> void:
	# Terreno plano de neve compactada
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(36.0, 24.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e8edf2")
	mat.roughness = 0.95
	ground.material_override = mat
	add_child(ground)

func _populate_showcase() -> void:
	# ==============================================================================
	# FILEIRA 1: MODELOS PADRÃO COM REFERÊNCIA HUMANA DE 1,80 M (Z = 1.0)
	# ==============================================================================

	# 1. Microchalé de Lenhador (X = -7.0, Z = 1.0)
	var cabin = CABIN_SCRIPT.new()
	cabin.position = Vector3(-7.0, 0.0, 1.0)
	add_child(cabin)
	# Humano de 1,80 m ao lado do degrau/porta (X = -5.4, Z = 3.1)
	var human_cabin = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#c0392b"))
	human_cabin.position = Vector3(-5.4, 0.0, 3.1)
	add_child(human_cabin)

	# 2. Abrigo de Patrulha (X = -1.8, Z = 1.0)
	var shelter = SHELTER_SCRIPT.new()
	shelter.position = Vector3(-1.8, 0.0, 1.0)
	add_child(shelter)
	# Humano de 1,80 m ao lado do pórtico livre (X = -0.4, Z = 2.2)
	var human_shelter = HUMAN_SCRIPT.new(Color("#1a252f"), Color("#27ae60"))
	human_shelter.position = Vector3(-0.4, 0.0, 2.2)
	add_child(human_shelter)

	# 3. Pilha de Lenha Coberta (X = 2.8, Z = 1.0)
	var woodpile = WOODPILE_SCRIPT.new()
	woodpile.position = Vector3(2.8, 0.0, 1.0)
	add_child(woodpile)
	# Humano de 1,80 m ao lado da pilha retirando lenha (X = 4.2, Z = 1.7)
	var human_wood = HUMAN_SCRIPT.new(Color("#34495e"), Color("#d35400"))
	human_wood.position = Vector3(4.2, 0.0, 1.7)
	add_child(human_wood)

	# 4. Placa de Trilha e Banco de Madeira (X = 6.8, Z = 1.0)
	var sign_bench = SIGN_BENCH_SCRIPT.new()
	sign_bench.position = Vector3(6.8, 0.0, 1.0)
	add_child(sign_bench)
	# Humano de 1,80 m em pé ao lado da placa verificando a altura (X = 8.0, Z = 1.5)
	var human_sign = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#2980b9"))
	human_sign.position = Vector3(8.0, 0.0, 1.5)
	add_child(human_sign)

	# ==============================================================================
	# FILEIRA 2: DEMONSTRAÇÃO DE TROCA DE COR ANTES DE ADICIONAR À ÁRVORE (Z = -5.5)
	# ==============================================================================

	# Chalé Variante em Mogno Escuro / Cedro Nórdico
	var cabin_var = CABIN_SCRIPT.new(Color("#3d1f14"))
	cabin_var.position = Vector3(-7.0, 0.0, -5.5)
	add_child(cabin_var)

	# Abrigo Variante em Azul Ártico dos Lobos de Gelo
	var shelter_var = SHELTER_SCRIPT.new(Color("#2c3e50"))
	shelter_var.position = Vector3(-1.8, 0.0, -5.5)
	add_child(shelter_var)

	# Pilha de Lenha Variante em Madeira Envelhecida Acinzentada
	var wood_var = WOODPILE_SCRIPT.new(Color("#4f4b47"))
	wood_var.position = Vector3(2.8, 0.0, -5.5)
	add_child(wood_var)

	# Banco Variante em Pinheiro Dourado
	var bench_var = SIGN_BENCH_SCRIPT.new(Color("#8e5a2b"))
	bench_var.position = Vector3(6.8, 0.0, -5.5)
	add_child(bench_var)
