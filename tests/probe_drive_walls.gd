extends SceneTree
## Sonda: dirige o carro do jogador em linha reta a partir de vários pontos/rumos e lista quem o trava.
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	world.session.state.intro.stage = "complete"
	world.player.teleport(COURSE.ENTRY+Vector3.UP*.1)
	world.production.region.set_focus(COURSE.ENTRY)
	for i in 240: await physics_frame
	var car: CharacterBody3D = world.driving.car
	car.controlled = true
	car.external_input = true
	car.health = 1000.0
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	print('DBG process=',car.is_physics_processing(),' mode=',car.process_mode,' visible=',car.visible,' layer=',car.collision_layer,' mask=',car.collision_mask,' ctrl=',car.controlled,' ext=',car.external_input,' hp=',car.health,' traffic=',car.traffic,' lock=',car.input_locked,' disabled=',car.engine_disabled)
	var runs := 0
	for z in range(-140,45,20):
		for x in range(-260,-90,20):
			for k in 4:
				var yaw := k*PI*.5
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,60,z),Vector3(x,-20,z),1))
				if hit.is_empty(): continue
				car.place(Vector3(x,hit.position.y+.3,z),yaw)
				car.throttle_input = 1.0
				car.brake_input = false
				car.steer_input = 0.0
				for i in 30: await physics_frame
				var mid := car.global_position
				for i in 40: await physics_frame
				var moved := Vector2(car.global_position.x-mid.x,car.global_position.z-mid.z).length()
				runs += 1
				if moved < 4.0:
					var who := []
					for c in car.get_slide_collision_count():
						var cc := car.get_slide_collision(c)
						if absf(cc.get_normal().y) < .5 and cc.get_position().y - car.global_position.y < .06: who.append([str(cc.get_collider().get_path()).get_slice("World3D/",1),cc.get_normal().snapped(Vector3.ONE*.01),cc.get_position().snapped(Vector3.ONE*.1)])
					if not who.is_empty(): print("PARADO de=(%d,%d) yaw=%d moveu=%.1f em=(%.1f,%.1f) bateu=%s" % [x,z,k*90,moved,car.global_position.x,car.global_position.z,who])
	print("DRIVE_DONE runs=",runs)
	quit(0)
