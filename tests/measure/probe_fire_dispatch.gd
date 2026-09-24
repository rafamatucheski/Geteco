extends SceneTree
## Sonda: acompanha a viatura de bombeiro despachada para um incêndio perto do
## jogador (estado, distância, velocidade, eventos do despacho). Não é teste de
## aceitação; imprime uma linha a cada 2 s. Rodar com --no-save.
var world

func _initialize() -> void: run.call_deferred()

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.controller.set_population(0)
	var dispatch = world.dispatch
	dispatch.dispatch_event.connect(func(kind, data): print("EVENT ", kind, " ", data)) if dispatch.has_signal("dispatch_event") else null
	var far: Vector3 = world.player.global_position + Vector3(-12, 0, 8)
	var blaze = world.gameplay.emergency.ignite(far, null, 1.2)
	blaze.age = -300.0
	var shots := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/fire-dispatch-0924/"))
	for i in 140 * 60:
		await physics_frame
		if shots < 2:
			for unit in dispatch.units:
				if unit.service == "fire" and unit.state == "working" and is_instance_valid(unit.vehicle):
					if shots == 0: world.player.teleport(unit.vehicle.global_position + Vector3(3, .1, 5))
					shots += 1
					for k in 40: await process_frame
					for c in world.find_children("*", "CharacterBody3D", true, false):
						if c.get("cannon") != null and is_instance_valid(c.cannon):
							print("FIRES ", world.gameplay.emergency.fires.map(func(f): return f.global_position if is_instance_valid(f) else null), " crew_pos ", c.global_position, " mode ", c.mode, " incident ", c.incident_id)
							print("CANNON life=%.2f dir=%s vmin=%.1f from=%s to=%s visible=%s" % [c.cannon.drops.lifetime, c.cannon._drop_process.direction, c.cannon._drop_process.initial_velocity_min, c.cannon.drops.global_position, c.cannon.end_point, c.cannon.visible])
					root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/fire-dispatch-0924/trabalho_%d.png" % shots))
					break
			if shots >= 2: quit(0)
		if i % 120 != 0: continue
		for unit in dispatch.units:
			if unit.service != "fire": continue
			var car: Node3D = unit.vehicle
			var gap := Vector2(car.global_position.x - far.x, car.global_position.z - far.z).length() if is_instance_valid(car) else -1.0
			print("T%3d estado=%s gap=%.1f speed=%.1f at_end=%s pos=%s fim=%s" % [i / 60, unit.state, gap, car.speed if is_instance_valid(car) else 0.0, unit.driver.at_route_end(), car.global_position if is_instance_valid(car) else Vector3.ZERO, unit.end_reason])
	quit(0)
