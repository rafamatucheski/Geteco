extends SceneTree
## Captura renderizada (Vulkan, NÃO headless) do motorista sentado em cada veículo, com o
## interior e o vidro translúcido de `VehicleInterior`. Usa o mesmo caminho do jogo
## (`attach` + `seat_driver`), sem Main: só palco, luz, um Vehicle e o Actor do jogador.
## Uso: --script res://tests/capture/capture_seated_driver.gd -- [ids,separados,por,virgula] [--views=game,side,top,front]
## Saída em res://evidence/seated-driver/ (PNG fica fora do Git).
const OUTPUT := "res://evidence/seated-driver/"
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(720, 540)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55, .6, .66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.72, .74, .8)
	env.environment.ambient_light_energy = .85
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -135, 0)
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	var ids: Array = []
	var views: Array = ["game", "side"]
	var tag := ""
	var sheet := false
	var sheet_images: Dictionary = {}
	var sheet_ids: Array = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--views="): views = argument.substr(8).split(",")
		elif argument.begins_with("--tag="): tag = argument.substr(6)
		elif argument == "--sheet": sheet = true
		elif not argument.begins_with("--"): ids.append_array(argument.split(","))
	if ids.is_empty():
		ids = FLEET.all().keys()
		ids.sort()
	var actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	for id in ids:
		if id.begins_with("bike_") or id == "army_tank": continue
		var car = VEHICLE.new()
		car.archetype = id
		stage.add_child(car)
		car.set_physics_process(false)
		car.rotation.y = 0.0
		for i in 2: await process_frame
		INTERIOR.attach(car)
		INTERIOR.seat_driver(actor, car)
		actor.show()
		var size: float = maxf(float(car.half_length) * 2.0, 4.0) * (.72 if id != "route_city" else .5)
		var center: Vector3 = car.global_position + Vector3(0, float(car.body_height) * .5, 0)
		for view in views:
			match view:
				"game":
					camera.size = size * .75
					var heading := 0.55
					camera.global_position = center + Vector3(sin(heading) * 25.3, 25.3, cos(heading) * 25.3)
					camera.look_at(center, Vector3.UP)
				"game2":
					camera.size = size * .75
					var heading := 2.7
					camera.global_position = center + Vector3(sin(heading) * 25.3, 25.3, cos(heading) * 25.3)
					camera.look_at(center, Vector3.UP)
				"side":
					camera.size = size * .8
					camera.global_position = center + Vector3(-30, 0, 0)
					camera.look_at(center, Vector3.UP)
				"front":
					camera.size = maxf(float(car.body_height) * 1.9, 3.5)
					camera.global_position = center + Vector3(0, 0, -30)
					camera.look_at(center, Vector3.UP)
				"top":
					camera.size = size * .8
					camera.global_position = center + Vector3(0, 30, .01)
					camera.look_at(center, Vector3.BACK)
			for i in 4: await process_frame
			var image := root.get_texture().get_image()
			if sheet:
				image.convert(Image.FORMAT_RGBA8)
				image.resize(360, 270)
				if not sheet_images.has(view): sheet_images[view] = []
				sheet_images[view].append(image)
			else:
				image.save_png(ProjectSettings.globalize_path(OUTPUT + tag + id + "_" + view + ".png"))
		var s: Dictionary = INTERIOR.spec(car)
		var head: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones["Head"]).origin)
		sheet_ids.append(id)
		var view: Dictionary = car.get_meta("interior_view", {})
		print("CAPTURE ", id, " kind=", s.get("kind"), " roof=%.2f head=%.2f scale=%.2f" % [s.get("roof", 0.0), head.y, s.get("scale", 1.0)], " cortes=", view.get("roofs", []).size(), " placas=", view.get("slabs", []).size(), " alfa=", view.get("alpha_materials", []).size())
		actor.global_transform = Transform3D.IDENTITY
		actor.release_seated()
		car.queue_free()
		await process_frame
	if sheet:
		for view in sheet_images:
			var images: Array = sheet_images[view]
			for first in range(0, images.size(), 12):
				var page := Image.create(360 * 4, 270 * 3, false, Image.FORMAT_RGBA8)
				for i in range(first, mini(first + 12, images.size())):
					page.blit_rect(images[i], Rect2i(0, 0, 360, 270), Vector2i(((i - first) % 4) * 360, ((i - first) / 4) * 270))
				page.save_png(ProjectSettings.globalize_path(OUTPUT + tag + "sheet_" + view + "_" + str(first / 12) + ".png"))
				print("SHEET ", view, " ", first / 12, " = ", sheet_ids.slice(first, first + 12))
	quit(0)
