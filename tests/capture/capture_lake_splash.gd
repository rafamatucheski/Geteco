extends SceneTree
## Viatura atravessando o lago alpino: confere respingo e gotas. Saída em res://evidence/lake-splash/.
const OUTPUT := "res://evidence/lake-splash/"
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather.time_of_day = .45
	var wet: Vector3 = CATALOG._at(Vector2(7000,100),"mountain")
	world.player.teleport(wet + Vector3(14, 0, 0))
	world.session.controller.region.set_focus(wet)
	await frames(240)
	var car = preload("res://scripts/Vehicle.gd").new()
	car.archetype = "police_cruiser"
	world.add_child(car)
	car.global_position = wet + Vector3(23, 1.0, -5)
	car.rotation.y = PI / 2.0
	car.set_external_driver(true)
	car.controlled = true
	car.brake_input = false
	await frames(30)
	for i in 240:
		car.speed = 9.0
		car.throttle_input = 1.0
		await physics_frame
		if i == 45:
			var tire = car.effects.tire_effects
			print("MODES ", tire.last_modes, " car=", car.global_position, " emitter0=", tire.droplets[0].global_position, " emitter1=", tire.droplets[1].global_position, " spray=", tire.emitters[0].global_position, " amount=", tire.droplets[0].amount, " ratio=", tire.droplets[0].amount_ratio, " water_y=", tire.last_contacts)
			await shot("a_splash")
		if i == 62: await shot("b_splash")
	quit(0)
