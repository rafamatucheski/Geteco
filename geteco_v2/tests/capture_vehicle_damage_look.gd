extends SceneTree
## Captura renderizada dos estágios de dano: intacto, desgastado, pegando fogo e carcaça,
## sob luz neutra e sob luz de poste amarela (onde a carcaça antiga lia como marrom).
## Precisa de janela real (não --headless). Saída em res://evidence/vehicle-damage-0922/.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const OUTPUT := "res://evidence/vehicle-damage-0922/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Captura de dano precisa de renderização real")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 700)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.33, .38, .45)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.55, .58, .62)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 30)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(.22, .22, .23)
	asphalt.roughness = .95
	ground.material_override = asphalt
	world.add_child(ground)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	body.add_child(collision)
	world.add_child(body)
	var cars: Array = []
	for index in 4:
		var car := VEHICLE.new()
		car.archetype = "sport_coupe"
		car.paint_color = Color("d5a544")
		world.add_child(car)
		car.place(Vector3(-8.25 + index * 5.5, .12, 0), deg_to_rad(35))
		cars.append(car)
	for frame in 10: await physics_frame
	for car in cars: car.set_physics_process(false)
	cars[1].receive_damage(cars[1].max_health * .7)
	cars[2].receive_damage(cars[2].max_health * .86)
	cars[2].damage_look.set_physics_process(false)
	cars[3].receive_damage(cars[3].max_health * 2)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 7.5, 13), Vector3(0, .6, 0))
	camera.fov = 52
	for frame in 30:
		cars[2].damage_look._update_fire()
		await process_frame
	await _save("01_luz_neutra_logo_apos_explodir")
	# Brasa já fria e luz de poste de sódio: a condição em que a carcaça antiga virava marrom.
	for frame in 600: await process_frame
	sun.light_color = Color(1, .72, .4)
	sun.light_energy = .55
	environment.environment.ambient_light_color = Color(.35, .28, .2)
	environment.environment.background_color = Color(.08, .08, .12)
	for index in 4:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1, .7, .32)
		lamp.light_energy = 3.0
		lamp.omni_range = 9.0
		lamp.position = Vector3(-8.25 + index * 5.5, 5, 2)
		world.add_child(lamp)
	for frame in 20:
		cars[2].damage_look._update_fire()
		await process_frame
	await _save("02_luz_de_poste_brasa_fria")
	print("VEHICLE_DAMAGE_CAPTURE ok ", ProjectSettings.globalize_path(OUTPUT))
	quit(0)

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
