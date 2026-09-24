extends SceneTree
## Poças de chuva (RainPuddles3D) e água do chafariz da Union Plaza.
## Cenário falso e isolado: uma rua reta, chão com colisão e um corpo que atravessa
## uma poça. Não mede aparência nem desempenho, só o ciclo encher/respingar/secar.

var failures: Array[String] = []

class FakeAtmosphere extends RefCounted:
	func focus_position(controller) -> Vector3: return controller.world.player.global_position
	func weights_at(_point: Vector3) -> Dictionary: return {"mountain": 0.0}

class FakeWeather extends Node:
	var weather_state := 0
	var atmosphere := FakeAtmosphere.new()

class FakeSession extends Node:
	var weather: FakeWeather

class FakeRegion extends Node3D:
	var roads: Array[Dictionary] = []

class FakeWorld extends Node3D:
	var player: Node3D

class FakeController extends Node:
	var world: FakeWorld
	var session: FakeSession
	var regions: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	var stage := FakeWorld.new()
	root.add_child(stage)
	stage.player = Node3D.new()
	stage.add_child(stage.player)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	ground_shape.shape = box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	stage.add_child(ground)
	var controller := FakeController.new()
	stage.add_child(controller)
	controller.world = stage
	controller.session = FakeSession.new()
	controller.session.weather = FakeWeather.new()
	stage.add_child(controller.session)
	var harbor := FakeRegion.new()
	harbor.roads.append({"id":"test_avenue", "points":PackedVector3Array([Vector3(-200,0,0), Vector3(200,0,0)]), "width":12.0, "surface":"asphalt"})
	controller.regions["harbor"] = harbor
	var puddles = preload("res://world/rain/RainPuddles3D.gd").new()
	puddles.controller = controller
	stage.add_child(puddles)
	await frames(10)
	check(puddles.wetness == 0.0 and not puddles.visible, "tempo seco não deveria ter poça")

	controller.session.weather.weather_state = 1
	# Acelera o enchimento: 45 s de chuva simulados em passos de _process.
	for i in 60: puddles._process(1.0)
	check(puddles.wetness >= 1.0, "a chuva deveria encher as poças (wetness=%.2f)" % puddles.wetness)
	check(puddles._active.size() > 0, "a chuva deveria criar poças perto do foco")
	check(puddles._active.size() <= puddles.MAX_PUDDLES, "limite de poças excedido")
	var first_layout: Array = puddles._active.keys()
	await frames(4)

	var puddle: Area3D = puddles._active.values()[0]
	check(absf(puddle.global_position.z) < 6.0, "poça fora da largura da rua: z=%.2f" % puddle.global_position.z)
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	var walker_shape := CollisionShape3D.new()
	walker_shape.shape = CapsuleShape3D.new()
	walker_shape.position.y = 1.0
	walker.add_child(walker_shape)
	stage.add_child(walker)
	walker.global_position = puddle.global_position + Vector3(0, 0, 8)
	walker.velocity = Vector3(0, 0, -3)
	await frames(4)
	for i in 30:
		walker.global_position += Vector3(0, 0, -0.4)
		await physics_frame
	check(puddles.splash_count > 0, "atravessar a poça a 3 m/s deveria respingar")

	# Mesma chuva: sair e voltar mostra o mesmo desenho.
	stage.player.global_position = Vector3(180, 0, 0)
	puddles._clock = 1.0
	puddles._process(0.0)
	stage.player.global_position = Vector3.ZERO
	puddles._clock = 1.0
	puddles._process(0.0)
	var same := true
	for key in first_layout: if not puddles._active.has(key): same = false
	check(same, "a mesma chuva deveria manter as mesmas poças na mesma rua")

	controller.session.weather.weather_state = 0
	for i in 130: puddles._process(1.0)
	check(puddles.wetness == 0.0 and puddles._active.is_empty(), "sem chuva as poças deveriam secar e sumir")
	var generation: int = puddles.generation
	controller.session.weather.weather_state = 2
	puddles._process(0.1)
	check(puddles.generation == generation + 1, "chuva nova deveria sortear desenho novo")

	var fountain = preload("res://world/urban_detail/fountain/UnionFountain3D.gd").new()
	stage.add_child(fountain)
	await frames(3)
	for label in ["FountainBasinWater", "FountainBowlWater", "FountainCurtain", "FountainJet", "FountainLandingSplash", "FountainSound"]:
		check(fountain.get_node_or_null(label) != null, "chafariz sem " + label)
	var jet: GPUParticles3D = fountain.get_node_or_null("FountainJet")
	check(jet != null and jet.emitting, "o jato do chafariz deveria estar ligado")

	if failures.is_empty():
		print("PASS test_rain_puddles")
		quit(0)
	else:
		print("FAIL test_rain_puddles: %d falha(s)" % failures.size())
		quit(1)
