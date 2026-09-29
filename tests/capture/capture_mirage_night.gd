extends SceneTree
## Revisão visual à noite: faróis e luz de freio do carro preparado (Mirage) usando o
## `VehicleEquipment` real, ao lado de modelos da frota. NÃO é benchmark.
## Uso: Godot --path . --script res://tests/capture/capture_mirage_night.gd
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CATALOG := preload("res://runtime/FleetCatalog.gd")
var camera: Camera3D
var cars: Array = []

func _initialize() -> void: run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/mirage-test/%s.png" % name)
	print("MIRAGE_NIGHT ", name)

func frame(focus: Vector3, size: float, offset: Vector3) -> void:
	camera.size = size
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.make_current()
	for i in 10: await physics_frame

func spawn(world: Node3D, id: String, at: Vector3, braking: bool, paint: Color) -> Node3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "night_" + id + str(at.x)
	car._paint_requested = true
	car.paint_color = paint
	world.add_child(car)
	car.position = at
	# Motorista humano (não IA): senão o sistema trata como trânsito e usa outra regra de farol.
	car.controlled = true
	car.input_locked = braking
	car.brake_input = braking
	car.ensure_equipment(world)
	cars.append(car)
	return car

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("precisa do jogo renderizado"); quit(2); return
	var spec: Dictionary = CATALOG.spec("metro_hatch").duplicate(true)
	spec.merge({"id": "mirage_test", "scene": "res://assets/fleet/incoming/mirage_test.scn", "bounds_size": [1.9, 1.23, 4.2], "bounds_center": [0, 0.62, 0], "colors": ["ffffffff"], "roof_prop": "none"}, true)
	CATALOG.all()["mirage_test"] = spec
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("06090e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("3a4a66")
	env.environment.ambient_light_energy = .35
	world.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 30, 0)
	moon.light_color = Color("9fb6e6")
	moon.light_energy = .35
	moon.shadow_enabled = true
	world.add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("43484b")
	ground_material.roughness = .9
	ground.material_override = ground_material
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
	# Frente de cada carro para -Z; a câmera do jogo fica atrás e acima (offset +Z).
	spawn(world, "mirage_test", Vector3(-9, .1, 0), false, Color("e9e9ec"))
	spawn(world, "mirage_test", Vector3(-4.5, .1, 0), true, Color("b3372d"))
	spawn(world, "sport_coupe", Vector3(0, .1, 0), false, Color("31577a"))
	spawn(world, "metro_hatch", Vector3(4.5, .1, 0), true, Color("e74c3c"))
	for i in 20: await physics_frame
	for car in cars:
		car.equipment.headlights_on = true
	for i in 20: await physics_frame
	print("MIRAGE_NIGHT_EQUIPMENT ", cars.map(func(c): return [c.archetype, is_instance_valid(c.equipment), c.equipment.lens_materials.size() if is_instance_valid(c.equipment) else -1, c.equipment.tail_materials.size() if is_instance_valid(c.equipment) else -1, c.brake_input]))
	await frame(Vector3(-2.2, .4, -3), 30, Vector3(0, 25.3, 25.3))
	await shot("night-gameplay")
	await frame(Vector3(-6.7, .5, 0), 13, Vector3(0, 9, 10.5))
	await shot("night-rear-closer")
	await frame(Vector3(-6.7, .5, 0), 10, Vector3(0, 7.5, -9.5))
	await shot("night-front-closer")
	print("MIRAGE_NIGHT_COMPLETE")
	quit()
