extends "res://tests/test_belt_lantern_occlusion.gd"
## Os projetores reais da frota precisam nascer nos faróis da frente e parar em sólidos.

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280,720)
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
	camera.size = 18
	camera.position = Vector3(10,16,-20)
	camera.look_at(Vector3(0,0,-6))
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .01
	camera.environment = environment
	box(game,Vector3(0,-.1,-8),Vector3(30,.2,40))
	var car := preload("res://scripts/Vehicle.gd").new()
	car.archetype = "union_sedan"
	car.position.y = .1
	game.add_child(car)
	car.set_physics_process(false)
	car.controlled = true
	var kit = car.ensure_equipment(game)
	kit.headlights_on = false
	kit._refresh()
	var dark := await picture()
	kit.headlights_on = true
	kit._refresh()
	var lit := await picture()
	for item in kit.lamps:
		check(item.lamp.position.y > .3 and item.lamp.position.z < -1.0,"projector originates above ground at front lens")
		check(item.lamp.is_visible_in_tree() and item.lamp.shadow_enabled,"real headlight source active with occlusion")
	check(kit._budget_request().decal == null,"no luminous floor decal")
	var target := Vector3(0,.02,-7)
	var gain := brightness(lit,target)-brightness(dark,target)
	print("HEADLIGHT_OPEN_GAIN ",gain)
	check(gain > .08,"headlights illuminate road ahead")
	box(game,Vector3(0,1.5,-4),Vector3(8,3,.3))
	var blocked := await picture()
	var blocked_gain := brightness(blocked,target)-brightness(dark,target)
	print("HEADLIGHT_BLOCKED_GAIN ",blocked_gain)
	check(blocked_gain < .025,"wall blocks beam instead of leaving a glowing road patch")
	var folder := "res://evidence/mobile-lights-20261015"
	DirAccess.make_dir_recursive_absolute(folder)
	lit.save_png(folder.path_join("headlight-open.png"))
	blocked.save_png(folder.path_join("headlight-blocked.png"))
	game.free()
	quit(1 if failures else 0)
