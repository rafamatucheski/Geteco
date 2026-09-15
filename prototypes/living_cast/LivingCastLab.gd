extends Node2D

const CIVIL := preload("res://prototypes/living_cast/LivingCivil.gd")
const VEHICLE := preload("res://prototypes/living_cast/LivingVehicle.gd")
var people: Array[Node2D] = []
var cars: Array[Node2D] = []
var player: CharacterBody2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("394047"))
	for i in 6:
		var civil := CIVIL.new()
		civil.name = "Civil_%d" % i
		civil.appearance = i
		civil.response = 1 if i == 4 else (2 if i == 5 else 0)
		civil.roam = false
		civil.position = Vector2(140 + i * 135, 210)
		add_child(civil)
		people.append(civil)
		var caption := Label.new()
		caption.text = CIVIL.NAMES[i]
		caption.position = civil.position + Vector2(-30, 28)
		add_child(caption)
		var car := make_car(i)
		car.position = Vector2(140 + i * 135, 425)
		add_child(car)
		cars.append(car)
	# Actual Player controls and damage contract, isolated from the city scene.
	player = load("res://characters/Player.gd").new()
	player.name = "Player"
	player.position = Vector2(400, 310)
	player.collision_layer = 4
	player.collision_mask = 7
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.zoom = Vector2.ONE * 1.5
	player.add_child(camera)
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6
	collision.shape = circle
	player.add_child(collision)
	add_child(player)
	camera.make_current()
	player.equip_weapon("fists")
	# Solid test barrier: drive into it to exercise the inherited collision path.
	var wall := StaticBody2D.new()
	wall.position = Vector2(985, 425)
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 180)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	var art := Polygon2D.new()
	art.polygon = PackedVector2Array([Vector2(-14,-90),Vector2(14,-90),Vector2(14,90),Vector2(-14,90)])
	art.color = Color("baaa83")
	wall.add_child(art)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(18, 16)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "LABORATORIO ISOLADO — elenco e veiculos (nao integrado a cidade)"
	panel.add_child(title)
	var help := Label.new()
	help.text = "WASD / Shift: andar e correr | E: carro | F: desembarcar | Clique: atacar\nMoradores fogem. Brigador e vigia revidam somente se provocados. Barreira a direita dos carros."
	panel.add_child(help)
	var run_button := Button.new()
	run_button.text = "Demonstrar corrida dos moradores"
	run_button.pressed.connect(func():
		for person in people:
			if is_instance_valid(person) and person.response == 0: person.panic()
	)
	panel.add_child(run_button)
	var reset := Button.new()
	reset.text = "Recriar laboratorio"
	reset.pressed.connect(func(): get_tree().reload_current_scene())
	panel.add_child(reset)

static func make_car(index: int) -> CharacterBody2D:
	var car := VEHICLE.new()
	car.name = "Vehicle_%d" % index
	car.body_variant = index
	car.collision_layer = 2
	car.collision_mask = 23
	var shape := CollisionShape2D.new()
	shape.name = "Collision"
	car.add_child(shape)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2.ONE * 1.5
	car.add_child(camera)
	var area := Area2D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 4
	var trigger := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48
	trigger.shape = circle
	area.add_child(trigger)
	car.add_child(area)
	return car
