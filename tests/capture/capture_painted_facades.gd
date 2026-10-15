extends SceneTree
## Os 9 estilos de PaintedFacadeKit lado a lado (frente, lateral, fundos, telhado),
## portas alternadamente abertas, de dia e de noite. Conta peças por prédio.
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var out := ProjectSettings.globalize_path("res://evidence/painted-facades-20261015")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(200, 200)
	ground.material_override = UrbanMaterials.sidewalk_stone()
	stage.add_child(ground)
	var collisions := Node3D.new()
	stage.add_child(collisions)
	var x := -36.0
	var pieces := []
	var doors := []
	for index in PaintedFacadeKit.STYLES.size():
		var house := Node3D.new()
		house.position = Vector3(x + 3.0, 0, 0)
		stage.add_child(house)
		var built := PaintedFacadeKit.build(house, PaintedFacadeKit.STYLES[index], Vector3(6, 7, 8), collisions)
		pieces.append(built.find_children("*", "MeshInstance3D", true, false).size())
		for door in built.find_children("Door", "", true, false): doors.append(door)
		x += 8.0
	# Sobrado de 12 m: o módulo repete (duas portas, geminado).
	var wide := Node3D.new()
	wide.position = Vector3(0, 0, -20)
	stage.add_child(wide)
	PaintedFacadeKit.build(wide, "tijolo-londrino", Vector3(12, 7, 10), collisions)
	for index in doors.size():
		if index % 2 == 0: doors[index].set_open_amount(0.85)
	print("PAINTED_FACADES styles=", PaintedFacadeKit.STYLES.size(), " mesh_nodes_per_house=", pieces)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	var shots := [
		["street_left", Vector3(-24, 3.5, 17), Vector3(-24, 3.5, 0)],
		["street_right", Vector3(12, 3.5, 17), Vector3(12, 3.5, 0)],
		["door_close", Vector3(-30, 1.8, 5.5), Vector3(-31.2, 1.3, 3.5)],
		["corner_side", Vector3(-48, 4, 12), Vector3(-36, 3, 0)],
		["back", Vector3(-8, 4, -14), Vector3(-8, 3, 0)],
		["roofs", Vector3(-4, 30, 18), Vector3(-4, 0, -2)],
		["wide_12m", Vector3(0, 3.5, -4), Vector3(0, 3.5, -20)]]
	for night in [false, true]:
		MATERIALS.set_night(1.0 if night else 0.0)
		sun.light_energy = 0.05 if night else 1.0
		env.environment.background_energy_multiplier = 0.08 if night else 1.0
		env.environment.ambient_light_energy = 0.15 if night else 1.0
		for shot in shots:
			if night and shot[0] in ["roofs", "back", "corner_side"]: continue
			cam.look_at_from_position(shot[1], shot[2])
			for i in 8: await process_frame
			var path := "%s/%s_%s.png" % [out, shot[0], "night" if night else "day"]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit(0)
