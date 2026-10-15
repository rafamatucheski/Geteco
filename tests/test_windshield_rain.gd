extends SceneTree
## Gotas e limpador no para-brisa: inativo seco/abrigado/sem condutor, ativo na chuva, e libera
## tudo ao secar. Usa um Vehicle real (precisa de renderizador para medir o vidro? não: só malhas).
## Uso: --script res://tests/test_windshield_rain.gd
const VEHICLE := preload("res://scripts/Vehicle.gd")
const RAIN := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")
var failures := 0

class FakeWeather extends RefCounted:
	var _covered := false
	var strength := 0.0
	func rain_strength_at(_point: Vector3) -> float: return strength

func check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void: run.call_deferred()

func _drive(rain, seconds: float, step := .1) -> void:
	var t := 0.0
	while t < seconds:
		rain.tick(step)
		t += step

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var car = VEHICLE.new()
	car.archetype = "union_sedan"
	stage.add_child(car)
	car.set_physics_process(false)
	for i in 2: await process_frame
	var visual: Node3D = car.visual
	var baseline := visual.get_child_count()
	var weather := FakeWeather.new()
	var rain = RAIN.new(car)
	rain.weather_override = weather

	var geometry: Dictionary = RAIN.geometry_for(car)
	check(not geometry.is_empty() and geometry.glass.get_surface_count() == 1, "sedã tem malha de vidro")
	check(geometry.wiper != null and geometry.params.length > .2, "sedã tem limpador no para-brisa")

	car.controlled = true
	_drive(rain, 2.0)
	check(not rain.is_active() and visual.get_child_count() == baseline, "seco: inativo, sem nó novo")

	weather.strength = .8
	car.controlled = false
	_drive(rain, 2.0)
	check(not rain.is_active(), "chovendo mas sem condutor: inativo")

	car.controlled = true
	_drive(rain, 1.0)
	check(rain.is_active() and visual.get_child_count() == baseline + 1, "chovendo e conduzido: gotas ativas")
	_drive(rain, 4.0)
	check(rain.level() > .9, "gotas chegam ao máximo com chuva forte (%.2f)" % rain.level())
	check(rain.wiper_amplitude() > .99, "limpador varre com chuva forte (%.2f)" % rain.wiper_amplitude())
	var node: Node = visual.get_node_or_null(RAIN.NODE_NAME)
	var glass: MeshInstance3D = node.get_node("Glass") if node != null else null
	check(glass != null and glass.material_override is ShaderMaterial and is_equal_approx(float(glass.material_override.get_shader_parameter("rain")), rain.level()), "uniform de chuva segue o nível")
	check(node != null and node.get_node_or_null("Wiper") != null, "braços do limpador existem")
	check(glass != null and glass.mesh == geometry.glass, "malha do vidro vem do cache do arquétipo (não duplica)")

	# Garoa: gotas sem limpador.
	weather.strength = .1
	_drive(rain, 12.0)
	check(rain.is_active() and rain.wiper_amplitude() < .01, "garoa fraca: gotas ficam, limpador desliga (amp %.2f)" % rain.wiper_amplitude())

	# Abrigo (túnel, garagem): seca rápido e libera.
	weather.strength = .8
	_drive(rain, 3.0)
	weather._covered = true
	_drive(rain, 6.0)
	await process_frame
	check(not rain.is_active() and visual.get_child_count() == baseline, "abrigado: gotas secam e o nó é liberado")
	check(rain.level() == 0.0 and rain.wiper_amplitude() == 0.0, "estado zerado depois de liberar")

	# Volta a chover fora do abrigo e a chuva para: seca devagar e libera.
	weather._covered = false
	_drive(rain, 3.0)
	check(rain.is_active(), "saiu do abrigo na chuva: reativa")
	var kept: Node = visual.get_node_or_null(RAIN.NODE_NAME)
	weather.strength = 0.0
	_drive(rain, 4.0)
	check(rain.is_active(), "chuva parou: gotas ainda secando")
	_drive(rain, 12.0)
	await process_frame
	check(not rain.is_active() and not is_instance_valid(kept) and visual.get_child_count() == baseline, "seco de novo: nó liberado")

	# Descartar durante a chuva (veículo sai de cena / dispose) não deixa resíduo.
	weather.strength = .6
	_drive(rain, 2.0)
	check(rain.is_active(), "reativa para testar dispose")
	rain.dispose()
	await process_frame
	check(not rain.is_active() and visual.get_child_count() == baseline, "dispose libera o nó")

	var warm := RAIN.warm_materials()
	check(warm.size() == 2 and warm[0].shader != null and warm[1].shader != null, "materiais de pré-aquecimento")
	car.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
