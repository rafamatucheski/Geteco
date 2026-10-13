extends SceneTree
## Contratos da P4 com veículos reais e mundo mínimo; não certifica visual nem FPS.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
var checks := 0
var failures: Array[String] = []

class FakeState extends RefCounted:
	var world_state := {"time": .95, "weather": 0}
class FakeProduction extends RefCounted:
	var state := FakeState.new()
class FakeWorld extends Node3D:
	var production := FakeProduction.new()
	var player := Node3D.new()
	var camera := Camera3D.new()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures.append(label)

func fixture() -> FakeWorld:
	var world := FakeWorld.new()
	root.add_child(world)
	world.add_child(world.player)
	world.add_child(world.camera)
	world.camera.position = Vector3(0, 3, 0)
	world.camera.current = true
	return world

func spawn(world: FakeWorld, point: Vector3, traffic: bool = true, id: String = "union_sedan") -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.position = point
	car.traffic = traffic
	world.add_child(car)
	car.set_physics_process(false)
	car.ensure_equipment(world)
	return car

func equipment_lights(car: CharacterBody3D) -> Array[Light3D]:
	var result: Array[Light3D] = []
	var equipment: Node = car.equipment
	for item: Dictionary in equipment.lamps: result.append(item.lamp)
	if is_instance_valid(equipment.npc_beam): result.append(equipment.npc_beam)
	if is_instance_valid(equipment.halo): result.append(equipment.halo)
	return result

func active_count(cars: Array[CharacterBody3D]) -> int:
	var count := 0
	for car in cars:
		if not is_instance_valid(car): continue
		for light in equipment_lights(car):
			if light.is_visible_in_tree() and light.light_energy > 0: count += 1
	return count

func settle() -> void:
	# O SceneTree emite process_frame antes de executar os _process dos nós.
	for index in 3: await process_frame

func refresh_all(cars: Array[CharacterBody3D]) -> void:
	for car in cars:
		if is_instance_valid(car):
			car.equipment._refresh()
			if BUDGET.enabled: check(active_count(cars) <= 8, "teto global durante atualização individual")

func run() -> void:
	var world := fixture()
	var cars: Array[CharacterBody3D] = []
	for index in 18:
		cars.append(spawn(world, Vector3((index % 6) * 3.0, 0, (index / 6) * 4.0)))
	await settle()
	if not BUDGET.enabled:
		var beams := 0
		for car in cars:
			var equipment: Node = car.equipment
			if equipment.npc_beam.is_visible_in_tree(): beams += 1
			check(equipment.glows.is_empty() and equipment.ground_pool is MeshInstance3D, "interruptor restaura mancha legada sem sprite/decal")
		check(beams == 2, "interruptor restaura dois fachos reais de NPC")
		var far := spawn(world, Vector3(36, 0, 0))
		cars.append(far)
		for car in cars:
			if car != far: car.position.x += 200
		await settle()
		check(far.equipment.npc_beam.is_visible_in_tree(), "legado mantém facho de NPC entre 25 e 45 m")
		world.free()
		await settle()
		finish()
		return

	check(active_count(cars) == 0, "18 veículos de trânsito não acendem fonte real")
	var decals := 0
	for car in cars:
		var equipment: Node = car.equipment
		check(equipment.ground_pool is Decal, "trânsito possui decal de farol")
		if equipment.ground_pool.is_visible_in_tree(): decals += 1
		check(equipment.glows.size() == 2 and equipment.glows.all(func(item): return item.sprite is Sprite3D and item.sprite.is_visible_in_tree()), "trânsito conserva o par de brilhos")
		check(equipment.lamps.size() == 2, "projetores latentes preservados para roubo")
	check(decals == 8, "decals ativos respeitam orçamento de oito no Mobile")
	check(BUDGET.counts().active_lights == 0 and BUDGET.counts().active_decals == decals, "contagem do registro coincide com fontes visíveis")

	# Sentinelas representam neons/incêndios, expressamente fora do novo escopo.
	var neon := OmniLight3D.new()
	neon.name = "UnregisteredNeon"
	neon.light_energy = 1.25
	cars[0].add_child(neon)
	var fire := OmniLight3D.new()
	fire.name = "UnregisteredFire"
	fire.light_energy = 2.0
	cars[1].add_child(fire)

	var player := spawn(world, Vector3.ZERO, false)
	cars.append(player)
	player.controlled = true
	check(player.equipment.toggle_headlights(), "jogador pode acender faróis")
	var services: Array[CharacterBody3D] = []
	for index in 9:
		var service := spawn(world, Vector3(4 + index * 1.5, 0, -5), false)
		service.controlled = true
		service.external_input = true
		services.append(service)
		cars.append(service)
	await settle()
	refresh_all(cars)
	check(active_count(cars) == 8, "jogador e serviços saturam oito fontes reais")
	check(player.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree()), "jogador conserva ambos os projetores sob saturação")
	check(neon.is_visible_in_tree() and fire.is_visible_in_tree() and is_equal_approx(neon.light_energy, 1.25) and is_equal_approx(fire.light_energy, 2.0), "neon e incêndio fora do registro permanecem intocados")
	var ranked := services.duplicate()
	ranked.sort_custom(func(a, b): return a.equipment.npc_beam.global_position.distance_squared_to(world.camera.global_position) < b.equipment.npc_beam.global_position.distance_squared_to(world.camera.global_position))
	for index in ranked.size():
		check(ranked[index].equipment.npc_beam.is_visible_in_tree() == (index < 6), "seis serviços mais próximos da câmera recebem as vagas restantes")
	# Remover apenas o componente mantém seus irmãos na árvore até o queue_free.
	# A limpeza precisa apagar essas fontes antes de entregar as vagas a outro carro.
	var removed_car: CharacterBody3D = ranked[0]
	var removed_equipment: Node = removed_car.equipment
	var removed_lights := equipment_lights(removed_car)
	removed_car.remove_child(removed_equipment)
	check(removed_lights.all(func(light): return not light.is_visible_in_tree()), "remoção de Equipment apaga fontes imediatamente, antes do descarte adiado")
	for car in cars:
		if car != removed_car: car.equipment._refresh()
	check(active_count(cars) == 8, "vaga de Equipment removido é reutilizada sem nove fontes simultâneas")
	check(not removed_equipment.ground_pool.is_visible_in_tree() and removed_equipment.glows.all(func(item): return not item.sprite.is_visible_in_tree()), "remoção do componente apaga decal e brilhos imediatamente")
	removed_equipment.free()
	await settle()
	removed_car.ensure_equipment(world)
	await settle()
	check(active_count(cars) == 8, "recriar Equipment restaura cadastro sem duplicação")

	world.camera.position = Vector3(18, 3, 0)
	await settle()
	refresh_all(cars)
	check(services[-1].equipment.npc_beam.is_visible_in_tree() and not services[0].equipment.npc_beam.is_visible_in_tree(), "seleção acompanha câmera sem mover jogador")

	world.camera.position = Vector3(0, 30.4, 19)
	await settle()
	refresh_all(cars)
	check(player.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree()), "câmera aérea a 36 m preserva par prioritário do jogador")
	check(player.equipment.lamps.all(func(item): return is_equal_approx(item.lamp.light_energy, float(player.equipment.profile.energy))), "câmera aérea conserva energia original dos faróis do jogador")
	check(services.all(func(car): return not car.equipment.npc_beam.is_visible_in_tree()), "fontes dos outros veículos fora de 25 m euclidianos apagam")

	# Isola uma fonte para testar o limite a partir de sua posição real.
	var boundary: CharacterBody3D = services[-1]
	for service in services:
		if service != boundary: service.position.x += 200
	world.camera.global_position = boundary.equipment.npc_beam.global_position + Vector3(24.99, 0, 0)
	await settle()
	check(boundary.equipment.npc_beam.is_visible_in_tree(), "fonte a 24,99 m entra no orçamento")
	check(boundary.equipment.npc_beam.light_energy > 0 and boundary.equipment.npc_beam.light_energy < .01, "fonte de NPC esmaece suavemente antes do limite")
	world.camera.global_position = boundary.equipment.npc_beam.global_position + Vector3(25.01, 0, 0)
	await settle()
	check(not boundary.equipment.npc_beam.is_visible_in_tree(), "fonte a 25,01 m fica fora do orçamento")
	world.camera.global_position = boundary.equipment.npc_beam.global_position + Vector3(10, 0, 0)
	await settle()
	check(boundary.equipment.npc_beam.is_visible_in_tree() and is_equal_approx(boundary.equipment.npc_beam.light_energy, float(boundary.equipment.profile.energy) * 1.6), "reaproximação recupera energia original sem perda acumulada")

	var police := spawn(world, Vector3(100, 0, 100), false, "police_cruiser")
	cars.append(police)
	police.controlled = true
	police.external_input = true
	check(police.equipment.toggle_siren(), "viatura NPC aciona sirene normalmente")
	await settle()
	check(not police.equipment.halo.is_visible_in_tree(), "giroflex fora do raio permanece sem fonte real")
	check(police.equipment.beacons.any(func(item): return item.material.emission_enabled), "giroflex fora do orçamento conserva brilho piscante")
	check(police.equipment.siren_audio.playing, "orçamento visual preserva áudio da sirene")

	var taken: CharacterBody3D = cars[2]
	check(taken.equipment.auto_lit, "trânsito aceso antes do roubo")
	player.controlled = false
	taken.traffic = false
	taken.controlled = true
	await settle()
	refresh_all(cars)
	check(taken.equipment.headlights_on and taken.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree()) and not taken.equipment.npc_beam.is_visible_in_tree(), "roubo transfere faróis acesos ao par do novo jogador")
	taken.equipment.receive_impact(Vector3(0, 0, -taken.half_length), 4)
	await settle()
	check(taken.equipment.lamps.all(func(item): return not item.lamp.is_visible_in_tree()) and not taken.equipment.ground_pool.is_visible_in_tree(), "dano nos dois lados apaga fontes e mancha")
	check(taken.equipment.glows.all(func(item): return not item.sprite.is_visible_in_tree()), "dano nos dois lados apaga brilhos")

	var service_bike := spawn(world, Vector3(40, 0, 0), false, "bike_sport")
	cars.append(service_bike)
	service_bike.controlled = true
	service_bike.external_input = true
	world.camera.global_position = service_bike.equipment.npc_beam.global_position + Vector3(10, 0, 0)
	await settle()
	check(service_bike.equipment.npc_beam.is_visible_in_tree() and service_bike.equipment.ground_pool.is_visible_in_tree(), "moto de serviço NPC acende seu farol único perto da câmera")
	service_bike.equipment.receive_impact(Vector3(-.3, 0, -service_bike.half_length), 4)
	await settle()
	check(service_bike.equipment.broken_left and not service_bike.equipment.broken_right, "impacto da moto danifica somente um lado")
	check(not service_bike.equipment.npc_beam.is_visible_in_tree(), "dano de um lado apaga fonte central do farol único da moto")
	check(not service_bike.equipment.ground_pool.is_visible_in_tree() and service_bike.equipment.glows.all(func(item): return not item.sprite.is_visible_in_tree()), "dano de um lado apaga brilho e decal do farol único da moto")
	check(not service_bike.equipment.lens_materials.is_empty() and service_bike.equipment.lens_materials.all(func(item): return not item.material.emission_enabled), "dano de um lado apaga também emissão da lente central da moto")

	world.production.state.world_state.time = .5
	await settle()
	check(not boundary.equipment.auto_lit and not boundary.equipment.ground_pool.is_visible_in_tree(), "transição ao dia apaga faróis automáticos")
	world.free()
	await settle()
	var counts: Dictionary = BUDGET.counts()
	check(counts.registered == 0 and counts.active_lights == 0 and counts.active_decals == 0, "descarregamento limpa registro e todas as vagas")
	world = fixture()
	var fresh := spawn(world, Vector3.ZERO, false)
	fresh.controlled = true
	fresh.equipment.toggle_headlights()
	await settle()
	check(fresh.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree()), "nova sessão reutiliza vagas sem estado residual")
	world.free()
	await settle()
	finish()

func finish() -> void:
	print("VEHICLE_LIGHT_BUDGET checks=", checks, " failures=", failures, " enabled=", BUDGET.enabled)
	quit(0 if failures.is_empty() else 1)
