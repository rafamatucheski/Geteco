extends Node2D

const MODULAR_CAR := preload("res://prototypes/living_cast/Modular3DCar.gd")

const VEHICLE_LIST := [
	"union_sedan",
	"metro_hatch",
	"courier_van",
	"ranch_single",
	"route_city",
	"rescue_pumper",
	"medic_box",
	"towmaster",
	"boxrunner"
]

var spawned_vehicles: Array[CharacterBody2D] = []
var player: CharacterBody2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#2c3e50"))

	# 1. Chão de asfalto do pátio
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([
		Vector2(-400, -200),
		Vector2(2600, -200),
		Vector2(2600, 1600),
		Vector2(-400, 1600)
	])
	ground.color = Color("#222f3e")
	add_child(ground)

	# 2. Vagas e Linhas demarcadas
	for i in VEHICLE_LIST.size():
		var x_pos := 160.0 + float(i) * 220.0
		var line := Polygon2D.new()
		line.polygon = PackedVector2Array([
			Vector2(x_pos - 90, 180),
			Vector2(x_pos - 90, 520),
			Vector2(x_pos - 85, 520),
			Vector2(x_pos - 85, 180)
		])
		line.color = Color("#f1c40f")
		add_child(line)

	# 3. Instanciar os 9 Veículos 3D da Fase 2
	for i in VEHICLE_LIST.size():
		var id: String = VEHICLE_LIST[i]
		var x_pos := 160.0 + float(i) * 220.0

		var car := MODULAR_CAR.new()
		car.name = "Vehicle_" + id
		car.archetype_id = id
		car.position = Vector2(x_pos, 350.0)
		car.rotation = -PI / 2.0 # Apontado para cima / norte
		add_child(car)
		spawned_vehicles.append(car)

		# Placa / Rótulo de Identificação
		var label := Label.new()
		var spec := VehicleCatalog.get_vehicle_spec(id)
		label.text = spec.get("label", id)
		label.position = Vector2(x_pos - 80, 530)
		label.modulate = Color("#ecf0f1")
		add_child(label)

	# 4. Instanciar o Dante (Player) com Câmera e Controles
	player = load("res://Player.gd").new()
	player.name = "Player"
	player.position = Vector2(160, 620)
	player.collision_layer = 4
	player.collision_mask = 7

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.zoom = Vector2.ONE * 1.3
	player.add_child(camera)

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8
	collision.shape = circle
	player.add_child(collision)

	add_child(player)
	camera.make_current()

	# 5. Painel de Instruções na UI
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui_label := Label.new()
	ui_label.text = "VITRINE DA FROTA 3D - FASE 2 (9 NOVOS VEÍCULOS)\n[W, A, S, D / Setas]: Andar / Correr\n[E]: Entrar / Sair do Veículo mais próximo\n[Espaço]: Freio de mão / Drift\n[K]: Ligar / Desligar Farol Alto"
	ui_label.position = Vector2(25, 25)
	ui_label.modulate = Color("#f5f6fa")
	canvas.add_child(ui_label)
