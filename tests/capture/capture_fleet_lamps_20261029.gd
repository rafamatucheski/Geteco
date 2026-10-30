extends SceneTree
## Antes/depois do detalhe de lanternas, faróis e pneus da frota (29/10/2026), com o Vehicle e o equipamento
## de verdade (farol, freio). Só imagens; NÃO é benchmark de FPS nem prova de ausência de piscada.
## Um carro por vez (RAM). Com --dir=, as cenas das cópias tomam o caminho real no cache do ResourceLoader
## (take_over_path), então o RedesignedFleet carrega a cópia sem tocar no .scn real.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/capture/capture_fleet_lamps_20261029.gd -- \
##   --ids=raijin_gt,union_sedan --dir=res://artifacts/fleet-lamps-20261029/scn   (antes e depois na mesma ida)
const VEHICLE := preload("res://scripts/Vehicle.gd")
const REDESIGNED := preload("res://runtime/RedesignedFleet.gd")
const OUT := "res://evidence/fleet-lamps-20261029"
var camera: Camera3D
var world: Node3D
var sun: DirectionalLight3D
var env: Environment
var label := "antes"
var copy_dir := ""
var held: Array = []

func _initialize() -> void: run.call_deferred()

func shot(id: String, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s-%s-%s.png" % [OUT, id, label, name])

func frame(focus: Vector3, size: float, offset: Vector3) -> void:
	camera.size = size
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.make_current()
	for i in 6: await physics_frame

func spawn(id: String, at: Vector3, braking: bool, paint: Color) -> Node3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "lamps_%s_%d" % [id, int(at.x)]
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
	env.background_color = Color("06090e") if night else Color("829da6")
	env.ambient_light_color = Color("3a4a66") if night else Color("c4d4de")
	env.ambient_light_energy = .35 if night else .65
	sun.light_color = Color("9fb6e6") if night else Color("ffe2b8")
	sun.light_energy = .35 if night else 1.6

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("precisa do jogo renderizado"); quit(2); return
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids = Array(arg.trim_prefix("--ids=").split(",", false))
		elif arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		elif arg.begins_with("--dir="): copy_dir = arg.trim_prefix("--dir=").trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("545859")
	gm.roughness = .9
	ground.material_override = gm
	world.add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	floor_shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 200
	world.add_child(camera)
	for id: String in ids:
		# Antes = cena real; depois = cópia tomando o caminho real no cache (mesma janela, mesma luz, mesmo dia).
		label = "antes"
		await capture(id)
		if copy_dir.is_empty(): continue
		var copy := ResourceLoader.load(copy_dir + "/" + id + ".scn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if copy == null:
			push_error("cópia ausente: " + id)
			continue
		copy.take_over_path(REDESIGNED.scene_path(id))
		held = [copy]
		label = "depois"
		await capture(id)
		held = []
	print("FLEET_LAMPS_CAPTURE_COMPLETE")
	quit()

func capture(id: String) -> void:
	set_time(false)
	var colors: Array = preload("res://runtime/FleetCatalog.gd").spec(id).get("colors", ["ffffffff"])
	var a := spawn(id, Vector3(-3.5, .1, 0), false, Color.html(str(colors[0])))
	var b := spawn(id, Vector3(3.5, .1, 0), true, Color.html(str(colors[mini(1, colors.size() - 1)])))
	for i in 20: await physics_frame
	var hl: float = a.half_length
	var hw: float = a.half_width
	# Traseira e frente de perto (3/4), roda dianteira esquerda de lado, e câmera de jogo (45°, ortho 30).
	await frame(a.position + Vector3(0, .75, hl), 3.4, Vector3(1.8, 1.5, 4.6))
	await shot(id, "tras")
	await frame(a.position + Vector3(0, .75, -hl), 3.4, Vector3(1.8, 1.5, -4.6))
	await shot(id, "frente")
	var wheel := a.position + Vector3(-hw, .38, -hl * .58)
	if not a.wheels.is_empty():
		var front: Node3D = null
		for pivot: Node3D in a.wheels:
			if pivot.global_position.x >= a.global_position.x: continue
			if front == null or pivot.global_position.z < front.global_position.z: front = pivot
		if front != null: wheel = front.global_position
	await frame(wheel, 1.25, Vector3(-4.0, .9, 0))
	await shot(id, "roda")
	await frame(Vector3(0, .5, 0), 30, Vector3(0, 25.3, 25.3))
	await shot(id, "jogo-30")
	set_time(true)
	for car in [a, b]: car.equipment.headlights_on = true
	for i in 10: await physics_frame
	await frame(Vector3(0, .75, hl), 9.5, Vector3(0, 6.5, 9.0))
	await shot(id, "noite-tras")
	await frame(Vector3(0, .75, -hl), 9.5, Vector3(0, 6.5, -9.0))
	await shot(id, "noite-frente")
	a.free()
	b.free()
	# Libera a cena do carro antes do próximo (RedesignedFleet guarda por id; a RAM fica com um carro).
	REDESIGNED._scenes.erase(id)
	for i in 4: await process_frame
	print("FLEET_LAMPS_CAPTURE ", id, " ", label)
