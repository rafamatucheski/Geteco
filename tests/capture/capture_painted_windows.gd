extends SceneTree
## Captura de antes/depois das janelas pintadas (PaintedWindow) num sobrado
## e num terraço isolados, de dia e de noite. Rodar duas vezes:
##   GETECO_PAINTED_WINDOWS=0 → "boxes" (antes); sem a variável → "painted".
## Também conta nós de malha por prédio, para comparar o peso das duas versões.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var tag := "painted" if PaintedWindow.enabled() else "boxes"
	var out := ProjectSettings.globalize_path("res://evidence/painted-windows-20261015")
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
	ground.mesh.size = Vector2(120, 120)
	ground.material_override = UrbanMaterials.sidewalk_stone()
	stage.add_child(ground)
	var chunk := Node3D.new()
	stage.add_child(chunk)
	var cases := [
		{"id":"NorthbankHomes1","kind":"brownstone","position":Vector3(-8,0,0),"size":Vector2(12,10)},
		{"id":"FoundryTerraceWest","kind":"rowhouse_terrace","position":Vector3(8,0,0),"size":Vector2(12,10)}]
	for source in cases: FACTORY.populate_chunk(chunk, source)
	DRESSING._night_pass(chunk, {"lamps":[]})
	var meshes := chunk.find_children("*", "MeshInstance3D", true, false).size()
	print("PAINTED_WINDOWS tag=", tag, " mesh_nodes=", meshes)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	var shots := [["wide", Vector3(0, 4.5, 22), Vector3(0, 3.8, 0)], ["close", Vector3(-5, 4.0, 9.5), Vector3(-8, 3.8, 5)], ["terrace", Vector3(10, 4.0, 10.5), Vector3(10, 4.0, 5)]]
	for night in [false, true]:
		MATERIALS.set_night(1.0 if night else 0.0)
		sun.light_energy = 0.05 if night else 1.0
		env.environment.background_energy_multiplier = 0.08 if night else 1.0
		env.environment.ambient_light_energy = 0.15 if night else 1.0
		for shot in shots:
			cam.look_at_from_position(shot[1], shot[2])
			for i in 8: await process_frame
			var path := "%s/%s_%s_%s.png" % [out, tag, shot[0], "night" if night else "day"]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit(0)
