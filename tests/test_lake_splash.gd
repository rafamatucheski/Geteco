extends SceneTree
## Dentro do lago alpino o veículo solta respingo grosso e gotas; fora dele, nenhuma gota.
const REGION := preload("res://world/regions/NativeRegion.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var wet_point: Vector3 = CATALOG._at(Vector2(7000,100),"mountain")
	var region = REGION.build_region("mountain",wet_point)
	root.add_child(region)
	region.prepare_collision_at(wet_point)
	var car := preload("res://scripts/Vehicle.gd").new()
	car.archetype = "police_cruiser"
	root.add_child(car)
	car.global_position = wet_point+Vector3.UP*.5
	car.set_external_driver(true)
	for i in 60: await physics_frame
	var effects = car.effects.tire_effects if car.effects != null else null
	check(effects != null,"veículo tem efeitos de pneu")
	if effects != null:
		car.horizontal_velocity = Vector3(0,0,-8)
		var seen_lake := false
		var seen_emitting := false
		for i in 30:
			effects.physics_tick(.05,true)
			if effects.last_modes[0] == "lake" or effects.last_modes[1] == "lake": seen_lake = true
			if effects.droplets.size() == 2 and (effects.droplets[0].emitting or effects.droplets[1].emitting): seen_emitting = true
			await physics_frame
		check(seen_lake,"modo lago ativo dentro d'água")
		check(effects.droplets.size() == 2,"gotas criadas na primeira vez na água")
		check(seen_emitting,"gotas emitindo")
	print("LAKE_SPLASH failures=",errors)
	quit(0 if errors.is_empty() else 1)
