extends SceneTree
## Gotas e limpador no para-brisa: inativo seco/abrigado/sem condutor, ativo na chuva, e libera
## tudo ao secar. Usa um Vehicle real (precisa de renderizador para medir o vidro? não: só malhas).
## Uso: --script res://tests/test_windshield_rain.gd
const VEHICLE := preload("res://scripts/Vehicle.gd")
const RAIN := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")
const GLASS := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
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
	car.finish_doors()
	var visual: Node3D = car.visual
	var baseline := visual.get_child_count()
	var weather := FakeWeather.new()
	var rain = RAIN.new(car)
	rain.weather_override = weather
	car.effects.windshield_rain = rain

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
	_check_glass_damage(car, rain, glass)

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

func _check_glass_damage(car: Node3D, rain: RefCounted, glass: MeshInstance3D) -> void:
	var owner := GLASS.owner_for(car, true)
	var original_mesh := glass.mesh
	var original_material := glass.material_override
	var original_level: float = rain.level()
	var original_amp: float = rain.wiper_amplitude()
	var original_phase: float = rain._wiper_phase
	var ray := _glass_ray(car, Vector3.LEFT)
	check(not ray.is_empty(), "regressão de chuva encontra vidro lateral alcançável")
	if ray.is_empty(): return
	for hit in GLASS.BREAK_HITS - 1:
		var impact: Dictionary = owner.shoot(ray[0], ray[1])
		check(not impact.is_empty() and not impact.shattered, "tiro %d só trinca o vidro lateral" % (hit + 1))
		check(rain.is_active() and glass.mesh == original_mesh and glass.material_override == original_material and rain.level() == original_level,
			"trinca preserva gotas, material e geometria da chuva")
	var broken: Dictionary = owner.shoot(ray[0], ray[1])
	check(not broken.is_empty() and broken.shattered, "impactos repetidos derrubam somente o painel atingido")
	check(rain.is_active() and _area(glass.mesh) < _area(original_mesh) and not _rain_covers(glass, broken.point, (ray[1] - ray[0]).normalized()), "chuva retira gotas da abertura e conserva fragmentos da borda")
	check(car.visual.find_children("*", "MeshInstance3D", true, false).any(func(part): return part.mesh != null and not part.mesh.get_meta("glass_remnant_starts", {}).is_empty()), "quebra conserva borda irregular de vidro presa à moldura")
	check(glass.material_override == original_material and rain.level() == original_level and rain.wiper_amplitude() == original_amp and rain._wiper_phase == original_phase,
		"quebrar vidro preserva umidade e limpador nos vidros restantes")
	var snapshot: Array = car.snapshot_glass()
	var remaining: int = glass.mesh.surface_get_array_len(0)
	car.restore_glass(snapshot)
	check(rain.is_active() and rain.level() == original_level and glass.mesh.surface_get_array_len(0) == remaining, "restaurar vidro quebrado conserva chuva existente")
	car.restore_glass([])
	check(rain.is_active() and rain.level() == original_level and glass.mesh.surface_get_array_len(0) == original_mesh.surface_get_array_len(0), "reparar vidro restaura gotas sem secar os demais painéis")
	var front := _glass_ray(car, Vector3.FORWARD)
	check(not front.is_empty(), "regressão de chuva encontra para-brisa alcançável")
	if front.is_empty(): return
	for hit in GLASS.BREAK_HITS: owner.shoot(front[0], front[1])
	check(rain.is_active() and rain._node.get_node_or_null("Wiper") == null, "para-brisa ausente não deixa limpador flutuando")
	car.restore_glass([])
	check(rain.is_active() and rain._node.get_node_or_null("Wiper") != null and rain.level() == original_level, "reparar para-brisa restaura limpador mantendo umidade")

func _glass_ray(car: Node3D, direction: Vector3) -> Array:
	var owner := GLASS.owner_for(car, true)
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part, surface) or not INTERIOR._is_glass(part, surface, part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh, surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := GLASS._indices(arrays)
			for i in range(0, indices.size() - 2, 3):
				var point := part.to_global((vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3.0)
				var from := point + direction * 5.0
				var to := point - direction * 5.0
				var hit: Dictionary = owner.contact(from, to)
				if not hit.is_empty() and hit.glass: return [from, to]
	return []

func _area(mesh: Mesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := GLASS._indices(arrays)
	var area := 0.0
	for i in range(0, indices.size() - 2, 3): area += (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]]).length() * .5
	return area

func _rain_covers(glass: MeshInstance3D, point: Vector3, direction: Vector3) -> bool:
	var arrays := glass.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var from := glass.to_local(point - direction * .08)
	var to := glass.to_local(point + direction * .08)
	for i in range(0, points.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(from, to, points[i], points[i + 1], points[i + 2]) != null: return true
	return false
