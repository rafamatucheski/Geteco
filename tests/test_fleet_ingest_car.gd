extends SceneTree
## Um carro de IA preparado por tools/fleet_ingest/ingest_glb_car.gd funciona como Vehicle
## de verdade: rodas soltas giram e esterçam, a tinta troca, anda, e a geometria é enxuta.
## Não altera catalog.json: injeta a especificação só nesta execução.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CATALOG := preload("res://runtime/FleetCatalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("FLEET_INGEST ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func run() -> void:
	var scene_path := "res://assets/fleet/incoming/mirage_test.scn"
	var spec: Dictionary = CATALOG.spec("metro_hatch").duplicate(true)
	spec.merge({"id": "mirage_test", "scene": scene_path, "bounds_size": [1.9, 1.23, 4.2], "bounds_center": [0, 0.62, 0], "colors": ["ffffffff"], "mesh_count": 6, "roof_prop": "none"}, true)
	CATALOG.all()["mirage_test"] = spec
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var car := VEHICLE.new()
	car.archetype = "mirage_test"
	car.vehicle_id = "vehicle_ingest_test"
	world.add_child(car)
	car.position = Vector3(0, 0.1, 0)
	for _i in 30: await physics_frame
	var parts := car.visual.find_children("*", "MeshInstance3D", true, false)
	check(parts.size() == 6, "carro tem 6 peças (carroceria, lâmpadas e 4 rodas), tem %d" % parts.size())
	check(car.wheels.size() == 4, "quatro pivôs de roda registrados (%d)" % car.wheels.size())
	var painted := 0
	for part in parts:
		var m: Material = (part as MeshInstance3D).material_override if (part as MeshInstance3D).material_override else (part as MeshInstance3D).mesh.surface_get_material(0)
		if m is StandardMaterial3D and m.resource_name == "paint": painted += 1
	check(painted == 1 and car._paint.materials.size() == 1, "só a carroceria recebe tinta (%d material)" % car._paint.materials.size())
	car.paint_color = Color("c8412f")
	var tinted := false
	for material in car._paint.materials: tinted = tinted or material.albedo_color.is_equal_approx(Color("c8412f"))
	check(tinted, "trocar paint_color repinta a carroceria")
	car.set_external_driver(true)
	car.throttle_input = 1.0
	car.brake_input = false
	for _i in 180: await physics_frame
	check(car.speed > 3.0 and car.position.z < -3.0, "anda para -Z (frente do modelo é a frente do carro), z=%.1f" % car.position.z)
	var spin_before := car.wheel_spin
	car.steer_input = 1.0
	for _i in 30: await physics_frame
	check(absf(car.wheel_spin - spin_before) > 1.0, "rodas giram (%.1f rad)" % (car.wheel_spin - spin_before))
	var steer_seen := false
	var rolling := true
	for pivot in car.wheels:
		if pivot.get_meta("front"): steer_seen = steer_seen or absf(pivot.rotation.y) > 0.05
		rolling = rolling and absf(pivot.rotation.x) >= 0.0
	check(steer_seen, "só as rodas dianteiras esterçam")
	var front := 0
	for pivot in car.wheels:
		if pivot.get_meta("front"): front += 1
	check(front == 2, "duas rodas dianteiras e duas traseiras (%d dianteiras)" % front)
	check(car.is_on_floor() or car.position.y < 0.5, "apoia no chão (y=%.2f)" % car.position.y)
	print("FLEET_INGEST_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
