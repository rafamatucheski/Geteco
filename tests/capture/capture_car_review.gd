extends SceneTree
## Revisão visual de um carro da frota (dia e noite) com o equipamento real (faróis, freio).
## Só imagens e contagens; NÃO é benchmark de FPS.
## Uso: Godot --path . --script res://tests/capture/capture_car_review.gd -- --id=aurora_executive --label=antes
const VEHICLE := preload("res://scripts/Vehicle.gd")
var camera: Camera3D
var car_id := "aurora_executive"
var label := "antes"
var world: Node3D
var sun: DirectionalLight3D
var env: Environment

func _initialize() -> void: run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/car-review/%s-%s-%s.png" % [car_id, label, name])
	print("CAR_REVIEW ", name)

func frame(focus: Vector3, size: float, offset: Vector3) -> void:
	camera.size = size
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.make_current()
	for i in 8: await physics_frame

func spawn(at: Vector3, braking: bool, paint: Color) -> Node3D:
	var car := VEHICLE.new()
	car.archetype = car_id
	car.vehicle_id = "review_%s_%d" % [car_id, int(at.x)]
	car._paint_requested = true
	car.paint_color = paint
	world.add_child(car)
	car.position = at
	car.controlled = true
	car.input_locked = braking
	car.brake_input = braking
	car.ensure_equipment(world)
	return car

func set_time(night: bool) -> void:
	# Dia = ajustes de scripts/World.gd; noite = luar fraco.
	env.background_color = Color("06090e") if night else Color("829da6")
	env.ambient_light_color = Color("3a4a66") if night else Color("c4d4de")
	env.ambient_light_energy = .35 if night else .65
	sun.light_color = Color("9fb6e6") if night else Color("ffe2b8")
	sun.light_energy = .35 if night else 1.6

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("precisa do jogo renderizado"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): car_id = arg.trim_prefix("--id=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/car-review"))
	world = Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("545859")
	gm.roughness = .9
	ground.material_override = gm
	world.add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	floor_shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 400
	world.add_child(camera)
	set_time(false)
	# Tinta de fábrica do catálogo e duas cores extras; a do meio freia.
	var colors: Array = preload("res://runtime/FleetCatalog.gd").spec(car_id).get("colors", ["ffffffff"])
	var a := spawn(Vector3(-6, .1, 0), false, Color.html(str(colors[0])))
	var b := spawn(Vector3(0, .1, 0), false, Color.html(str(colors[mini(3, colors.size() - 1)])))
	var c := spawn(Vector3(6, .1, 0), true, Color.html(str(colors[mini(1, colors.size() - 1)])))
	for i in 25: await physics_frame
	# Câmera de jogo (45°): tamanho de jogo e de perto.
	await frame(Vector3(0, .5, 0), 30, Vector3(0, 25.3, 25.3))
	await shot("jogo-30")
	await frame(Vector3(0, .5, 0), 9, Vector3(0, 8, 9.5))
	await shot("tras-3q")
	await frame(Vector3(0, .5, 0), 9, Vector3(0, 8, -9.5))
	await shot("frente-3q")
	await frame(Vector3(0, .6, 0), 8, Vector3(11, 2.8, 0))
	await shot("lado")
	await frame(Vector3(0, .6, 0), 8, Vector3(-11, 2.8, 0))
	await shot("lado-luz")
	await frame(Vector3(0, .9, -2.3), 3.4, Vector3(1.6, 1.8, -4.3))
	await shot("detalhe-frente")
	await frame(Vector3(0, 1.0, 0.2), 4.6, Vector3(0, 7.5, 0.5))
	await shot("teto")
	# Noite: faróis ligados nos três (o da direita também freia).
	set_time(true)
	for car in [a, b, c]: car.equipment.headlights_on = true
	for i in 12: await physics_frame
	await frame(Vector3(0, .5, -2), 24, Vector3(0, 25.3, 25.3))
	await shot("noite-jogo")
	await frame(Vector3(0, .5, 0), 9, Vector3(0, 8, 9.5))
	await shot("noite-tras")
	await frame(Vector3(0, .5, 0), 9, Vector3(0, 8, -9.5))
	await shot("noite-frente")
	print("CAR_REVIEW_COMPLETE")
	quit()
