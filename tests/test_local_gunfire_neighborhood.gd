extends SceneTree

const DANGER := preload("res://PedestrianDanger.gd")
var failures := 0

class Witness extends Node2D:
	var alerts := 0
	func hear_gunfire(_origin: Vector2, _end: Vector2) -> void:
		alerts += 1

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func witness(world: Node2D, location: Vector2) -> Witness:
	var person := Witness.new()
	person.position = location
	person.add_to_group("pedestrian")
	world.add_child(person)
	return person

func wall(world: Node2D, location: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = location
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var projectile := Node2D.new()
	world.add_child(projectile)
	var nearby := witness(world, Vector2(100, -90))
	var next_block := witness(world, Vector2(280, -110))
	var firing_lane := witness(world, Vector2(620, -25))
	var beside_lane := witness(world, Vector2(620, 80))
	var close_cover := witness(world, Vector2(0, 110))
	var lateral_cover := witness(world, Vector2(500, 30))
	var behind_wall := witness(world, Vector2(800, 0))
	var terrace := witness(world, Vector2(120, -60))
	terrace.remove_from_group("pedestrian")
	terrace.add_to_group("restaurant_terrace")
	wall(world, Vector2(0, 60), Vector2(60, 12))
	wall(world, Vector2(490, 27), Vector2(12, 24))
	wall(world, Vector2(700, 0), Vector2(14, 90))
	await physics_frame
	await physics_frame
	DANGER.report(projectile, Vector2.ZERO, Vector2.RIGHT, null)
	check(nearby.alerts == 1, "Quem está perto reage ao tiro")
	check(next_block.alerts == 0, "Outro quarteirão mantém sua rotina")
	check(firing_lane.alerts == 1, "Quem está na trajetória continua protegido pela reação de perigo")
	check(beside_lane.alerts == 0, "Faixa lateral distante não espalha pânico")
	check(close_cover.alerts == 0, "Parede protege até quem está a menos de 140 pixels")
	check(lateral_cover.alerts == 0, "Cobertura lateral bloqueia ameaça da trajetória")
	check(behind_wall.alerts == 0, "Trajetória termina na primeira parede")
	check(terrace.alerts == 1, "Clientes das mesas recebem o mesmo alerta local")
	var shooter := Node2D.new()
	world.add_child(shooter)
	DANGER.report(projectile, Vector2.ZERO, Vector2.RIGHT, shooter)
	DANGER.report(projectile, Vector2.ZERO, Vector2.RIGHT, shooter)
	check(nearby.alerts == 2, "Rajada compartilha intervalo de alerta")
	var real_table := preload("res://world/harbor/restaurants/RestaurantTerraceView.gd").new()
	real_table.position = Vector2(2000, 0)
	world.add_child(real_table)
	await physics_frame
	await physics_frame
	DANGER.report(projectile, Vector2(2000, 60), Vector2.RIGHT, null)
	check(real_table.alarm_remaining > 0.0, "Colisão da própria mesa não bloqueia alerta aos clientes")
	print("LOCAL_GUNFIRE_NEIGHBORHOOD failures=", failures)
	quit(0 if failures == 0 else 1)
