extends SceneTree
## Comparação renderizada do piloto. Não mede FPS e não certifica a cena integrada.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const BAKE := preload("res://tools/building_bake/bake_commercial.gd")
const OUTPUT := "res://tools/building_bake/captures"
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var mode := ""

func _initialize() -> void: run.call_deferred()

func photo(record: Dictionary, use_bake: bool, distance_scale: float = 1.0) -> Image:
	FACTORY.baked_enabled = use_bake
	var building := FACTORY.build_building(record)
	assert(not use_bake or building.get_meta("baked_commercial", false), "A captura deve usar a cena assada, sem fallback.")
	stage.add_child(building)
	building.position = Vector3.ZERO
	var height: float = building.height
	camera.position = Vector3(18, 18, 24) * distance_scale
	camera.look_at(Vector3(0, height * .5, 0))
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	building.free()
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("A comparação visual exige renderização real e --no-save.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--shadows" in OS.get_cmdline_user_args(): mode = "_sombras_p5_off"
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("39414e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = "--shadows" in OS.get_cmdline_user_args()
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	stage.add_child(camera)
	var results := []
	var failures := 0
	for record in BAKE.records():
		var prefix := str(record.id) + ("_editado" if record.has("height_override") else "")
		var baseline := await photo(record, false)
		var optimized := await photo(record, true)
		baseline.save_png(OUTPUT + "/" + prefix + mode + "_original.png")
		optimized.save_png(OUTPUT + "/" + prefix + mode + "_assado.png")
		var left := baseline.get_data()
		var right := optimized.get_data()
		var different := 0
		for index in left.size():
			if left[index] != right[index]: different += 1
		if different > 0: failures += 1
		results.append({"id": prefix, "different_bytes": different, "total_bytes": left.size()})
		print("P6_VISUAL_PERTO ", prefix, " bytes diferentes=", different)
		if str(record.id) == "NorthFrontage5":
			var far := await photo(record, true, 2.1)
			far.save_png(OUTPUT + "/" + prefix + mode + "_lod.png")
	var file := FileAccess.open("res://tools/building_bake/visual" + mode + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "results": results,
		"sun_shadows": "--shadows" in OS.get_cmdline_user_args(),
		"scope": "Piloto isolado renderizado no renderer do projeto. Sem FPS e sem aprovação visual da cena integrada."}, "\t"))
	file.close()
	quit(0 if failures == 0 else 1)
