extends "res://tests/test_vehicle_glass_damage.gd"
## Regressão: tiro no vidro não seca a pintura nem reinicia as gotas dos outros vidros.
## Exercita o caminho de bala e dano real; headless cobre contratos, não aparência/FPS.
const BODY_RAIN := preload("res://gameplay/vehicle_effects/VehicleRain.gd")
const GLASS_RAIN := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")

class RainCombat extends "res://gameplay/Gameplay.gd":
	func _ready() -> void: set_process(false); set_physics_process(false)
	func _damage(actor: Object, amount: float, source: Node, _continuous: bool = false) -> void:
		actor.receive_damage(amount, source)
	func _play_glass_break(_point: Vector3, _volume: float = 0.0, _pitch: float = 1.0) -> void: pass

class RainWeather extends RefCounted:
	var _covered := false
	func rain_strength_at(_point: Vector3) -> float: return .8

class NoShelter extends RefCounted:
	func sheltered(_point: Vector3) -> bool: return false

class BodyWeather extends Node:
	var strength := .1
	var atmosphere := {"SHELTER": NoShelter.new()}
	func rain_strength_at(_point: Vector3) -> float: return strength

func make_car(id: String, point: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "rain_damage_" + id
	car.paint_color = Color("3d718f")
	root.add_child(car)
	car.set_physics_process(false)
	car.position = point
	return car

func colors(car: Node3D) -> Array[Color]:
	var result: Array[Color] = []
	for material: StandardMaterial3D in car._paint.materials: result.append(material.albedo_color)
	return result

func same_colors(car: Node3D, expected: Array[Color]) -> bool:
	if car._paint.materials.size() != expected.size(): return false
	for i in expected.size():
		if not car._paint.materials[i].albedo_color.is_equal_approx(expected[i]): return false
	return true

func has_body_drops(car: Node3D) -> bool:
	for material: StandardMaterial3D in car._paint.materials:
		if not BODY_RAIN.has_beads(material): return false
	return not car._paint.materials.is_empty()

func active_paint_surfaces(car: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface)
			if material is StandardMaterial3D and material in car._paint.materials:
				result.append({"part": part, "surface": surface, "material": material, "color": material.albedo_color})
	return result

func active_paint_unchanged(surfaces: Array[Dictionary]) -> bool:
	var retained := not surfaces.is_empty()
	for entry in surfaces:
		var part: MeshInstance3D = entry.part
		if not is_instance_valid(part) or not part.is_visible_in_tree() or part.mesh == null or part.mesh.get_surface_count() <= entry.surface:
			retained = false
			print("ACTIVE_PAINT missing original visible surface ", entry.surface)
			continue
		var material := part.get_active_material(entry.surface) as StandardMaterial3D
		if material != entry.material or not material.albedo_color.is_equal_approx(entry.color) or not BODY_RAIN.has_beads(material):
			retained = false
			print("ACTIVE_PAINT lost reference/color/drops ", part.get_path(), " surface=", entry.surface)
	return retained

func run() -> void:
	var combat := RainCombat.new()
	root.add_child(combat)
	var body_weather := BodyWeather.new()
	root.add_child(body_weather)
	var weather_driver := BODY_RAIN.new()
	weather_driver.weather = body_weather
	for id in ["union_sedan", "monaliza", "courier_van"]:
		var car := make_car(id, Vector3.ZERO)
		var dry := make_car(id, Vector3(24, 0, 0))
		car.controlled = true
		for tick in 3: await physics_frame
		var dry_colors := colors(car)
		car.set_meta("rain_wet", 1.0)
		car.set_meta("rain_level", BODY_RAIN.LEVELS)
		BODY_RAIN.apply(car, 1.0)
		var wet_colors := colors(car)
		check(not same_colors(car, dry_colors) and has_body_drops(car), id + " begins wet with body droplets")
		car.finish_doors()
		var rain := GLASS_RAIN.new(car)
		rain.weather_override = RainWeather.new()
		car.effects.windshield_rain = rain
		for tick in 30: rain.tick(.1)
		check(rain._glass_material.shader.get_shader_uniform_list().any(func(uniform): return uniform.name == "falling"), id + " rain shader compiles with rainfall control")
		var rain_level: float = rain.level()
		var visible_paint := active_paint_surfaces(car)
		var ray := ray_for(car, 0)
		check(not ray.is_empty(), id + " exposes a real window shot")
		if ray.is_empty(): car.free(); dry.free(); continue
		# Impactos reais mantêm o mesmo caminho pelo vidro e pela vida do veículo.
		for shot in 3:
			combat._damage_bullet(car, 25.0, null, ray[0], ray[1])
			dry.receive_damage(25.0 * .15, null)
			check(car.snapshot_glass().size() == shot + 1, id + " bullet %d reaches glass and damage" % (shot + 1))
			check(same_colors(car, wet_colors), id + " shot %d preserves wet body color immediately" % (shot + 1))
			check(has_body_drops(car), id + " shot %d preserves body droplets immediately" % (shot + 1))
			check(rain.is_active() and is_equal_approx(rain.level(), rain_level), id + " shot %d preserves water on surviving glazing" % (shot + 1))
			# O controlador de clima reaplica um material quando a umidade muda ou o dano o invalida.
			BODY_RAIN.apply(car, 1.0)
			check(same_colors(car, wet_colors), id + " shot %d cannot multiply wet tint on refresh" % (shot + 1))
			rain.tick(.1)
		check(active_paint_unchanged(visible_paint), id + " all %d active paint surfaces retain references, color and droplets after three shots" % visible_paint.size())
		car.body_dents.impact(18.0, Vector3(.6, .6, -car.half_length))
		car.body_dents._rebuild()
		check(not car.body_dents.snapshot().is_empty() and active_paint_unchanged(visible_paint), id + " dent mesh rebuild and glass reapply retain active wet materials")
		car.animate_driver_door(-1, true, 0.0)
		var left_door: Node3D = car.door_presentation.hinges.get(-1)
		check(left_door != null and absf(left_door.rotation.y) > .1 and active_paint_unchanged(visible_paint), id + " opening actual door retains its wet paint materials")
		car.animate_driver_door(-1, false, 0.0)
		check(is_equal_approx(car.health, dry.health), id + " fixture keeps actual vehicle damage")
		BODY_RAIN.apply(car, 0.0)
		check(same_colors(car, dry_colors), id + " drying after damage restores the original paint color")
		var same_finish := true
		for i in car._paint.materials.size():
			same_finish = same_finish and is_equal_approx(car._paint.materials[i].roughness, dry._paint.materials[i].roughness)
		check(same_finish, id + " drying preserves wear finish instead of a wet baseline")
		# Repair cannot erase moisture or permanently retain wet darkening.
		BODY_RAIN.apply(car, 1.0)
		car.repair()
		BODY_RAIN.apply(car, 1.0)
		check(same_colors(car, wet_colors) and has_body_drops(car), id + " repair during rain preserves water and paint color")
		# Uma operação real de pintura com o carro molhado vira a base usada depois de secar.
		car.paint_color = Color("a94435")
		dry.paint_color = Color("a94435")
		var repainted := colors(dry)
		BODY_RAIN.apply(car, 1.0)
		car.receive_damage(1.0)
		BODY_RAIN.apply(car, 1.0)
		BODY_RAIN.apply(car, 0.0)
		check(same_colors(car, repainted), id + " repaint survives rain, subsequent damage and drying")
		# As normais da chuva e do amassado são independentes; nenhuma pode apagar a outra.
		BODY_RAIN.apply(car, 1.0)
		car.restore_health(car.max_health * .45)
		BODY_RAIN.apply(car, 1.0)
		check(has_body_drops(car), id + " heavy wear retains rain droplets")
		var dent_normals: Array[Texture2D] = []
		for material: StandardMaterial3D in car._paint.materials: dent_normals.append(material.normal_texture)
		BODY_RAIN.apply(car, 0.0)
		var preserved_dents := true
		for i in dent_normals.size():
			preserved_dents = preserved_dents and car._paint.materials[i].normal_texture == dent_normals[i]
		check(preserved_dents, id + " drying keeps damage normals")
		# Um carro todo molhado pode sair do alcance de apresentação durante uma transição de chuva.
		# A volta precisa usar a chuva atual mesmo que a umidade dele nunca tenha mudado.
		car.set_meta("rain_wet", 1.0)
		car.set_meta("rain_level", BODY_RAIN.LEVELS)
		car.set_meta("rain_falling", .9)
		BODY_RAIN.apply(car, 1.0)
		weather_driver._step(car, Vector3(1000, 0, 0), .25)
		weather_driver._step(car, Vector3(100, 0, 0), .25)
		var current_intensity := true
		for material: StandardMaterial3D in car._paint.materials:
			current_intensity = current_intensity and is_equal_approx(float(material.get_meta("rain_drops").get_shader_parameter("falling")), .1)
		check(current_intensity, id + " reentering range updates rainfall on already wet paint")
		car.free()
		dry.free()
		await process_frame
	combat.free()
	body_weather.free()
	weather_driver.free()
	print("VEHICLE_RAIN_DAMAGE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
