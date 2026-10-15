extends SceneTree
## Captura renderizada (NÃO headless) das gotas e do limpador no para-brisa, com chuva simulada
## por um clima falso (sem Main). Uso: --script res://tests/capture/capture_windshield_rain.gd -- [arquetipo]
## Saída em res://evidence/windshield-rain/ (PNG fica fora do Git).
const OUTPUT := "res://evidence/windshield-rain/"
const VEHICLE := preload("res://scripts/Vehicle.gd")
const RAIN := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd")

class FakeWeather extends RefCounted:
	var _covered := false
	var strength := .85
	func rain_strength_at(_point: Vector3) -> float: return strength

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(900, 600)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.38, .42, .47)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.62, .66, .72)
	env.environment.ambient_light_energy = .9
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -135, 0)
	sun.light_energy = .8
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(.2, .2, .22)
	ground.material_override = ground_material
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	var id := "union_sedan"
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"): id = argument
	var car = VEHICLE.new()
	car.archetype = id
	stage.add_child(car)
	car.set_physics_process(false)
	car.controlled = true
	for i in 3: await process_frame
	var weather := FakeWeather.new()
	var rain = RAIN.new(car)
	rain.weather_override = weather
	var center: Vector3 = car.global_position + Vector3(0, float(car.body_height) * .5, 0)
	var views := {"game": [Vector3(sin(.55) * 25.3, 25.3, cos(.55) * 25.3), 4.2], "close": [Vector3(sin(-2.6) * 12, 14, cos(-2.6) * 12), 2.6], "front": [Vector3(0, 6, -26), 3.2]}
	for k in 240:
		rain.tick(1.0 / 30.0)
		await process_frame
	print("ativo=", rain.is_active(), " nivel=", rain.level(), " limpador=", rain.wiper_amplitude())
	var shot := 0
	for view in views:
		camera.size = views[view][1]
		camera.global_position = center + views[view][0]
		camera.look_at(center, Vector3.UP)
		for frame in 4:
			# Passos de ~0,35 s de relógio real para pegar o limpador em fases diferentes.
			await create_timer(.35).timeout
			rain.tick(.35)
			await process_frame
			get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + id + "_" + view + "_" + str(frame) + ".png"))
			shot += 1
	print("capturas=", shot)
	quit(0)
