extends SceneTree
## Rendered regression: lit object, solid obstruction, then restored line of sight.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var failures := 0
var camera: Camera3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func box(parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.8,.8,.8)
	material.roughness = 1.0
	instance.material_override = material
	parent.add_child(instance)
	return instance
func picture() -> Image:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func brightness(image: Image, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point))
	var sum := 0.0
	for y in range(-2,3):
		for x in range(-2,3):
			var color := image.get_pixel(pixel.x+x,pixel.y+y)
			sum += color.r*.2126+color.g*.7152+color.b*.0722
	return sum/25.0
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280,720)
	var stage := Node3D.new()
	root.add_child(stage)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.position = Vector3(0,20,14)
	camera.look_at(Vector3(0,2.1,-3))
	camera.make_current()
	for id in ["harbor_sewer","sewer_market"]:
		var room = CATALOG.create_place(id)
		stage.add_child(room)
		for light in room.model.lights: light.hide()
		var target := Vector3(0,2.14,-4)
		var control := Vector3(-1.7,2.14,-4)
		box(room,target-Vector3.UP*.02,Vector3(.6,.04,.6))
		box(room,control-Vector3.UP*.02,Vector3(.6,.04,.6))
		var wall := box(room,Vector3(0,2.9,-2),Vector3(.9,1.6,.25))
		var light := SpotLight3D.new()
		room.add_child(light)
		light.position = Vector3(0,3.2,0)
		light.look_at(Vector3(0,2.14,-4))
		light.spot_range = 24
		light.spot_angle = 32
		light.spot_attenuation = .7
		light.spot_angle_attenuation = 2.2
		light.light_energy = 5
		light.shadow_enabled = true
		light.hide()
		var off := await picture()
		light.show()
		var blocked := await picture()
		wall.hide()
		var clear := await picture()
		var visible_gain := brightness(blocked,control)-brightness(off,control)
		var blocked_gain := brightness(blocked,target)-brightness(off,target)
		var clear_gain := brightness(clear,target)-brightness(off,target)
		print("LIGHT_PIXELS ",id," open=",visible_gain," blocked=",blocked_gain," clear=",clear_gain)
		check(visible_gain > .08,id+" beam illuminates object outside shadow")
		check(blocked_gain < .015,id+" wall blocks beam")
		check(clear_gain > .08,id+" removing wall restores illumination")
		var folder := "res://evidence/sewer-flashlight-20261012"
		DirAccess.make_dir_recursive_absolute(folder)
		blocked.save_png(folder.path_join(id+"-blocked.png"))
		clear.save_png(folder.path_join(id+"-clear.png"))
		room.free()
		await process_frame
	stage.free()
	quit(1 if failures else 0)
