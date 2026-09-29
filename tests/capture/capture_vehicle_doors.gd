extends SceneTree
## Captura renderizada (Vulkan, não headless) das portas de cada veículo.
## Uso: --script res://tests/capture/capture_vehicle_doors.gd -- <modo> [id ...]
##   grid  : vista lateral ortográfica com grade métrica (para medir onde fica a porta)
##   open  : portas abertas em vista lateral, 3/4 frente, 3/4 trás e de cima
##   shut  : portas fechadas nas mesmas vistas (comparação: nada pode mudar ao fechar)
##   base  : sem criar as portas (imagem original do modelo, para comparar com `shut`)
## Saída em res://evidence/vehicle-doors/. Só visual; nada aqui altera o jogo.
const OUTPUT := "res://evidence/vehicle-doors/"
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")

var stage: Node3D
var grid_size := 4.2
var camera: Camera3D

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 640)
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55, .6, .66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7, .72, .78)
	env.environment.ambient_light_energy = .7
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(.32, .32, .33)
	ground.material_override = ground_material
	stage.add_child(ground)
	camera = Camera3D.new()
	stage.add_child(camera)

	var args: Array = Array(OS.get_cmdline_user_args())
	var mode: String = args.pop_front() if not args.is_empty() else "grid"
	var ids: Array = []
	for argument in args:
		if str(argument).begins_with("size="): grid_size = float(str(argument).substr(5))
		else: ids.append(argument)
	if ids.is_empty():
		for id in FLEET.all().keys():
			if str(id).begins_with("bike_") or id in ["army_tank", "route_city"]: continue
			ids.append(id)
	for id in ids:
		var car := VEHICLE.new()
		car.archetype = id
		# Tinta fixa: sem isto cada execução sorteia uma cor e `base` × `shut` não se comparam.
		car.paint_color = Color("b04a3c")
		car.name = "Car"
		stage.add_child(car)
		car.set_physics_process(false)
		await process_frame
		match mode:
			"grid": await _grid(car)
			"open": await _open(car, true)
			"shut": await _open(car, false)
			"base": await _open(car, false, false)
		car.queue_free()
		await process_frame
		print("CAPTURE ", mode, " ", id)
	quit(0)

func _save(label: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))

## Lateral ortográfica: +Z (traseira) à direita da imagem, frente à esquerda. Escala fixa
## (px/m igual para todos os modelos) e números na régua, para ler z e y direto da imagem.
const GLYPHS := {
	"0": ["111","101","101","101","111"], "1": ["010","110","010","010","111"], "2": ["111","001","111","100","111"],
	"3": ["111","001","111","001","111"], "4": ["101","101","111","001","001"], "5": ["111","100","111","001","111"],
	"6": ["111","100","111","101","111"], "7": ["111","001","010","010","010"], "8": ["111","101","111","101","111"],
	"9": ["111","101","111","001","111"], "-": ["000","000","111","000","000"], ".": ["000","000","000","000","010"],
}

func _text(image: Image, text: String, at: Vector2i, color: Color) -> void:
	var cursor := at.x
	for character in text:
		var rows: Array = GLYPHS.get(character, GLYPHS["0"])
		for row in 5:
			for column in 3:
				if str(rows[row])[column] == "1":
					image.fill_rect(Rect2i(cursor + column * 2, at.y + row * 2, 2, 2), color)
		cursor += 8

func _grid(car: Node3D) -> void:
	var center := Vector3(0, grid_size * .26, 0)
	var height := grid_size
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = height
	camera.position = center + Vector3(-12, 0, 0)
	camera.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var scale := image.get_height() / height
	var mid := Vector2(image.get_width() * .5, image.get_height() * .5)
	# z (metros) vira coluna; y vira linha (o chão fica em center.y abaixo do meio).
	for step in range(-64, 65):
		var z := step * .25
		var x := int(mid.x + z * scale)
		if x < 0 or x >= image.get_width(): continue
		var color := Color(1, 0, 0) if step == 0 else (Color(1, 1, 0) if step % 4 == 0 else (Color(1, 1, 1) if step % 2 == 0 else Color(0, 0, 0)))
		for y in image.get_height():
			if step % 2 == 0 or y % 3 == 0: image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, .75 if step % 2 == 0 else .35))
		if step % 2 == 0: _text(image, "%.1f" % z, Vector2i(x + 2, 4), color)
	for step in range(0, 32):
		var y_m := step * .25
		var row := int(mid.y - (y_m - center.y) * scale)
		if row < 0 or row >= image.get_height(): continue
		var line := Color(1, 1, 0) if step % 4 == 0 else (Color(1, 1, 1) if step % 2 == 0 else Color(0, 0, 0))
		for x in image.get_width():
			if step % 2 == 0 or x % 3 == 0: image.set_pixel(x, row, image.get_pixel(x, row).lerp(line, .75 if step % 2 == 0 else .35))
		if step % 2 == 0: _text(image, "%.1f" % y_m, Vector2i(4, row - 12), line)
	image.save_png(ProjectSettings.globalize_path(OUTPUT + "grid_" + car.archetype + ".png"))

func _open(car: Node3D, opened: bool, touch_doors := true) -> void:
	# `base` nunca cria a apresentação de portas: é a imagem original, para comparar com `shut`.
	if touch_doors:
		car.animate_driver_door(-1, opened, 0.0)
		car.animate_driver_door(1, opened, 0.0)
	var center := Vector3(0, car.body_height * .5, 0)
	var reach := maxf(car.half_length * 2.0, car.body_height * 1.6) * .95
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 40
	var views := {"side": Vector3(-1, .12, 0), "fl": Vector3(-1, .5, -.9), "rr": Vector3(1, .5, 1.0), "top": Vector3(-.35, 1.7, -.2)}
	for label in views:
		camera.position = center + (views[label] as Vector3).normalized() * reach
		camera.look_at(center, Vector3.UP)
		await _save(("open_" if opened else ("shut_" if touch_doors else "base_")) + car.archetype + "_" + label)
