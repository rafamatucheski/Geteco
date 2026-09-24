extends SceneTree
## Faróis do trânsito à noite (V1 `DayNightWeatherManager.set_headlights`) com
## caráter por modelo (`gameplay/VehicleLightProfiles.gd`).
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PROFILES := preload("res://gameplay/VehicleLightProfiles.gd")
const TRAFFIC := ["sport_coupe", "union_sedan", "courier_van", "ranch_single", "arctic_jeep", "nimbus_minivan", "sedan_classic", "taxi_yellow", "route_city", "aurora_executive", "vertice_midengine", "bike_sport"]
var failures: Array[String] = []
var checks := 0

class FakeState extends RefCounted:
	var world_state := {"time": .5, "weather": 0}
class FakeProduction extends RefCounted:
	var state := FakeState.new()
class FakeWorld extends Node3D:
	var production := FakeProduction.new()
	var player := Node3D.new()

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures.append(label)

func spawn(world: FakeWorld, id: String, point: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.position = point
	world.add_child(car)
	car.set_physics_process(false)
	car.traffic = true
	car.ensure_equipment(world)
	return car

func lens_on(car) -> bool:
	return not car.equipment.lens_materials.is_empty() and car.equipment.lens_materials[0].emission_enabled

func run() -> void:
	var world := FakeWorld.new()
	root.add_child(world)
	world.add_child(world.player)
	var cars := {}
	for index in TRAFFIC.size():
		cars[TRAFFIC[index]] = spawn(world, TRAFFIC[index], Vector3(index * 6.0, 0, 0))
	for id in TRAFFIC:
		var equipment = cars[id].equipment
		check(not equipment.lens_materials.is_empty(), id + ": lente do farol encontrada no modelo")
		# O cupê anima a própria lanterna (Vehicle.tail_material); o Arctic Trail
		# não tem lente traseira emissiva no modelo original.
		if id not in ["sport_coupe", "arctic_jeep"]: check(not equipment.tail_materials.is_empty(), id + ": lanterna traseira encontrada")
	check(cars.taxi_yellow.equipment.lens_materials.size() == 1, "Luminoso do táxi no teto não vira farol")
	check(cars.bike_sport.equipment.lamps.size() == 1, "Moto tem um farol só")
	check(cars.route_city.equipment.lamps.size() == 2 and cars.union_sedan.equipment.lamps.size() == 2, "Carros e ônibus têm par de projetores")

	# Caráter por modelo: cor, alcance e abertura diferentes entre famílias.
	var classic = cars.sedan_classic.equipment.npc_beam
	var xenon = cars.aurora_executive.equipment.npc_beam
	var led = cars.vertice_midengine.equipment.npc_beam
	var heavy = cars.route_city.equipment.npc_beam
	check(classic.light_color.b < xenon.light_color.b - .3, "Clássico amarelado, executivo branco-azulado")
	check(xenon.spot_range > classic.spot_range + 8, "Xenônio alcança mais longe que halógeno antigo")
	check(led.spot_angle > xenon.spot_angle, "LED abre mais que xenônio")
	check(heavy.light_energy > classic.light_energy, "Ônibus ilumina mais forte que sedã clássico")
	var families := {}
	for id in TRAFFIC: families[PROFILES.family(id)] = true
	check(families.size() >= 5, "Trânsito cobre pelo menos cinco famílias de farol")
	check(cars.sedan_classic.equipment.lens_materials[0].emission.is_equal_approx(PROFILES.FAMILIES.classic.color), "Lente do clássico brilha na cor do perfil")

	await process_frame
	check(not lens_on(cars.union_sedan) and not cars.union_sedan.equipment.npc_beam.visible, "De dia o trânsito anda apagado")
	check(not cars.union_sedan.equipment.tail_materials[0].emission_enabled, "De dia a lanterna traseira fica apagada")
	cars.union_sedan.blocked = true
	await process_frame
	check(cars.union_sedan.equipment.tail_materials[0].emission_energy_multiplier > 2, "Luz de freio acende quando o trânsito para")
	cars.union_sedan.blocked = false

	world.production.state.world_state.time = .9
	# A ordenação do orçamento usa o estado do quadro anterior: um quadro de atraso.
	await process_frame
	await process_frame
	check(lens_on(cars.union_sedan) and lens_on(cars.bike_sport), "À noite o trânsito acende os faróis")
	check(cars.union_sedan.equipment.tail_materials[0].emission_enabled and cars.union_sedan.equipment.tail_materials[0].emission_energy_multiplier < 1.5, "À noite a lanterna fica acesa fraca")
	var beams := 0
	var nearest_lit := true
	for index in TRAFFIC.size():
		var beam = cars[TRAFFIC[index]].equipment.npc_beam
		if beam.visible: beams += 1
		if index < EQUIPMENT.npc_beam_budget and not beam.visible: nearest_lit = false
	check(beams == EQUIPMENT.npc_beam_budget, "Só %d fachos reais de NPC (%d acesos)" % [EQUIPMENT.npc_beam_budget, beams])
	check(nearest_lit, "Os fachos ficam com os carros mais próximos do jogador")
	check(not cars.union_sedan.equipment.lamps[0].visible, "NPC usa o facho central, não o par do jogador")
	world.player.position = Vector3(66, 0, 0)
	await process_frame
	await process_frame
	check(cars.bike_sport.equipment.npc_beam.visible and not cars.sport_coupe.equipment.npc_beam.visible, "Orçamento segue o jogador")

	world.production.state.world_state.time = .5
	world.production.state.world_state.weather = 2
	await process_frame
	check(lens_on(cars.union_sedan), "Tempestade acende os faróis de dia (V1)")
	world.production.state.world_state.weather = 0
	world.production.state.world_state.time = .1

	var parked := VEHICLE.new()
	parked.archetype = "union_sedan"
	world.add_child(parked)
	parked.set_physics_process(false)
	parked.ensure_equipment(world)
	parked.brake_input = true
	await process_frame
	check(not lens_on(parked) and not parked.equipment.tail_materials[0].emission_enabled, "Carro estacionado não acende nem freia")

	var service := spawn(world, "police_cruiser", Vector3(0, 0, 12))
	service.traffic = false
	service.controlled = true
	service.external_input = true
	await process_frame
	check(service.equipment.auto_lit and lens_on(service), "Viatura com motorista NPC acende à noite")

	# Carjack à noite: quem tomou o carro aceso continua com o farol ligado.
	var taken = cars.nimbus_minivan
	check(taken.equipment.auto_lit, "Minivan acesa antes do roubo")
	taken.traffic = false
	taken.controlled = true
	await process_frame
	check(taken.equipment.headlights_on and taken.equipment.lamps[0].visible and not taken.equipment.npc_beam.visible, "Carro roubado aceso segue com os faróis do jogador")

	world.free()
	await process_frame
	print("TRAFFIC_HEADLIGHTS ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
