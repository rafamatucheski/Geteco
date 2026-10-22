extends SceneTree
const OUT := "res://artifacts/interior-life-20261022/"
var label := "before"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(1600,1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("242c34")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e5e7ed")
	env.ambient_light_energy = .7
	environment.environment = env
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-20,0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	stage.add_child(camera)
	var shots := [] if "--trees-only" in OS.get_cmdline_user_args() else ["maciota","home0","home1","home2"]
	for id in shots:
		var room: Node3D
		if id == "maciota":
			room = load("res://world/maciota/MaciotaPlace.gd").new()
			room.interior_origin = Vector3.ZERO
			stage.add_child(room)
			room.set_interior_active(true)
		else:
			room = load("res://assets/regions/source/world/harbor/residences/ResidenceInterior3D.gd").new()
			room.variant_index = int(id.right(1))
			stage.add_child(room)
		camera.position = Vector3(-.8,18,14.34)
		camera.look_at(Vector3(-.8,.55,-.66))
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+label+"-"+id+".png")
		room.queue_free()
		await process_frame
	# Compare the production tree meshes at the same transform in this fixture.
	for modern in [false,true]:
		var tree := MeshInstance3D.new()
		tree.mesh = preload("res://world/places/ResidentialTreeVisual.gd").mesh() if modern else preload("res://world/city_look/CityPropKit.gd").mesh("street_tree")
		stage.add_child(tree)
		camera.size = 6
		camera.position = Vector3(0,5,9)
		camera.look_at(Vector3(0,2.2,0))
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+label+"-tree-"+("new" if modern else "previous")+".png")
		tree.queue_free()
		await process_frame
	quit()
