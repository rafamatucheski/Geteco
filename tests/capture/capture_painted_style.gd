extends SceneTree
## Revisão de estilos do PaintedFacadeKit no tamanho natural (style.json), lado a
## lado, vistos de 3/4 pela frente e pelos fundos, de dia e de noite, com a porta
## da frente do primeiro estilo meio aberta.
## Uso: "$GODOT" --path . --script res://tests/capture/capture_painted_style.gd -- --styles=a,b,c --label=x [--no-snow]
## PNG em evidence/painted-facades-20261015/style_<label>_<vista>_<dia|noite>.png.
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var styles: Array = []
	var label := "review"
	var snow := true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--styles="): styles = Array(argument.trim_prefix("--styles=").split(","))
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument == "--no-snow": snow = false
	if styles.is_empty(): styles = PaintedFacadeKit.all_styles()
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
	ground.mesh.size = Vector2(300, 300)
	ground.material_override = UrbanMaterials.sidewalk_stone()
	stage.add_child(ground)
	var collisions := Node3D.new()
	stage.add_child(collisions)
	var x := 0.0
	var span := 0.0
	var tallest := 0.0
	var pieces := []
	var first_door: Variant = null
	for style in styles:
		var natural := PaintedFacadeKit.natural_size(style)
		var house := Node3D.new()
		house.position = Vector3(x + natural.x * 0.5, 0, 0)
		stage.add_child(house)
		var built := PaintedFacadeKit.build(house, style, natural, collisions, NAN, {"snow": snow})
		pieces.append("%s=%d" % [style, built.find_children("*", "MeshInstance3D", true, false).size()])
		if first_door == null:
			var doors := built.find_children("Door", "", true, false)
			if not doors.is_empty(): first_door = doors[0]
		tallest = maxf(tallest, PaintedFacadeKit.ridge_height(style, natural.y))
		x += natural.x + 3.0
		span = x - 3.0
	if first_door != null: first_door.set_open_amount(0.6)
	print("PAINTED_STYLE label=", label, " pieces=", pieces)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	var mid := span * 0.5
	var distance := maxf(12.0, span * 0.75)
	var look_y := tallest * 0.45
	var shots := [
		["front", Vector3(mid - distance * 0.35, tallest * 0.7 + 2.0, distance), Vector3(mid, look_y, 0)],
		["back", Vector3(mid + distance * 0.35, tallest * 0.7 + 2.0, -distance), Vector3(mid, look_y, 0)],
		["close", Vector3(PaintedFacadeKit.natural_size(styles[0]).x * 0.5 - 3.0, 2.0, 7.0), Vector3(PaintedFacadeKit.natural_size(styles[0]).x * 0.5, 1.8, 0)]]
	for night in [false, true]:
		MATERIALS.set_night(1.0 if night else 0.0)
		sun.light_energy = 0.05 if night else 1.0
		env.environment.background_energy_multiplier = 0.08 if night else 1.0
		env.environment.ambient_light_energy = 0.15 if night else 1.0
		for shot in shots:
			if night and shot[0] != "front": continue
			cam.look_at_from_position(shot[1], shot[2])
			for i in 8: await process_frame
			var path := "%s/style_%s_%s_%s.png" % [out, label, shot[0], "night" if night else "day"]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit(0)
