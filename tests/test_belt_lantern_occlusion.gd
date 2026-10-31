extends SceneTree
## Contrato renderizado para a lanterna de corpo real: alcance radial e oclusão sólida.
class Actor extends Node3D:
	var visual: Node3D
class Game extends Node3D:
	var player
	var world: Node3D
	var health := 100.0
var camera: Camera3D
var failures := 0

func _initialize() -> void: run.call_deferred()

func box(parent: Node3D, point: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.6,.6,.6)
	material.roughness = 1.0
	instance.material_override = material
	parent.add_child(instance)
	return instance

func picture() -> Image:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func brightness(frame: Image, point: Vector3) -> float:
	var scale_factor := Vector2(frame.get_size()) / root.get_visible_rect().size
	var pixel := Vector2i(camera.unproject_position(point) * scale_factor)
	var sum := 0.0
	for y in range(-2,3):
		for x in range(-2,3):
			var color := frame.get_pixel(pixel.x+x,pixel.y+y)
			sum += color.get_luminance()
	return sum / 25.0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(960,720)
	var game := Game.new()
	game.world = game
	root.add_child(game)
	game.player = Actor.new()
	game.add_child(game.player)
	game.player.visual = Node3D.new()
	game.player.add_child(game.player.visual)
	camera = Camera3D.new()
	game.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	camera.position = Vector3(8,14,12)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .01
	camera.environment = environment
	box(game,Vector3(0,-.1,0),Vector3(16,.2,16))
	var belt := preload("res://gameplay/BeltFlashlight.gd").new()
	belt.gameplay = game
	game.add_child(belt)
	belt.restore({"owned":true,"enabled":false})
	var dark := await picture()
	belt.toggle()
	var lit := await picture()
	var center := Vector3(belt.global_position.x,.02,belt.global_position.z)
	for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
		var point: Vector3 = center + direction*3.0
		var gain := brightness(lit,point)-brightness(dark,point)
		print("RADIAL_GAIN ",direction," ",gain)
		check(gain > .08,"lamp lights floor in direction " + str(direction))
	box(game,center+Vector3(0,1,1.5),Vector3(3,2,.25))
	var blocked := await picture()
	var behind := center+Vector3(0,0,3)
	check(brightness(blocked,behind)-brightness(dark,behind) < .025,"solid wall blocks radial light")
	var folder := "res://evidence/mobile-lights-20261015"
	DirAccess.make_dir_recursive_absolute(folder)
	lit.save_png(folder.path_join("radial-open.png"))
	blocked.save_png(folder.path_join("radial-blocked.png"))
	game.free()
	quit(1 if failures else 0)
