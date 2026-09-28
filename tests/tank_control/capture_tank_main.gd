extends SceneTree
## Rendered Main inspection of articulated cannon and actual crush collision.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var output := "res://evidence/tank-control-20260928/"
var world: Node3D

func _initialize() -> void: run.call_deferred()
func settle(frames: int) -> void:
	for index in frames: await physics_frame
func photo(file: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output+file+".png")
	print("TANK_CAPTURE ",file," result=",error)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-output="): output = argument.trim_prefix("--capture-output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	create_timer(180).timeout.connect(func(): push_error("TANK_CAPTURE timeout"); quit(2))
	root.size = Vector2i(1280,720)
	seed(28092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save: quit(3); return
	world.gameplay.set_physics_process(false)
	world.gameplay.police_air.set_physics_process(false)
	world.dispatch.set_physics_process(false)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.global_position)
	world.camera.set_physics_process(false)
	world.camera.set_process(false)
	var spot := Vector3.INF
	var yaw := 0.0
	for candidate in world.dispatch.router.spawn_candidates(world.player.global_position,5.0,95.0,14.0):
		if float(candidate.edge.width) < 7.5: continue
		world.production.region.prepare_collision_at(candidate.point)
		await settle(2)
		if not world.dispatch._space_clear(Vector3(6.5,3.5,22),candidate.point,candidate.yaw,world.dispatch.no_exclusions): continue
		spot = candidate.point
		yaw = candidate.yaw
		break
	if not spot.is_finite(): print("TANK_CAPTURE no clear street"); world.free(); quit(4); return
	var tank := VEHICLE.new()
	tank.archetype = "army_tank"
	world.add_child(tank)
	tank.place(spot,yaw)
	tank.controlled = true
	tank.get_node("TankDriverControls").set_physics_process(false)
	world.driving.car = tank
	world.driving.occupied = true
	world.player.hide()
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.teleport(spot)
	world.production.region.set_focus(spot)
	var target := VEHICLE.new()
	target.archetype = "sport_coupe"
	world.add_child(target)
	target.place(tank.to_global(Vector3(0,.02,-10)),yaw)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	camera.global_position = tank.to_global(Vector3(0,25,9))
	camera.look_at(tank.to_global(Vector3(0,1,-4)))
	camera.make_current()
	await settle(80)
	var cannon: Node3D = tank.tank_cannon
	cannon.aim_at(target.global_position+Vector3.UP*.9,3.0)
	await photo("tank-aim")
	if not cannon.fire(world.gameplay,false): print("TANK_CAPTURE cannon rejected"); world.free(); quit(5); return
	await settle(2)
	await photo("tank-fire")
	for index in 30:
		await physics_frame
		if cannon.impact_count > 0: break
	await photo("tank-impact")
	# Reset only the test target, then let real move_and_slide climb its hull.
	target.repair()
	target.place(tank.to_global(Vector3(0,.02,-7)),yaw)
	target.horizontal_velocity = Vector3.ZERO
	target.speed = 0
	tank.set_external_driver(true)
	tank.throttle_input = 1.0
	tank.brake_input = false
	var captured := false
	var blast_captured := false
	var max_rise := 0.0
	var initial_height := tank.global_position.y
	for index in 720:
		await physics_frame
		max_rise = maxf(max_rise,tank.global_position.y-initial_height)
		if target.has_meta("heavy_crush_ratio") and not blast_captured:
			await photo("tank-crush-explosion")
			blast_captured = true
		if target.has_meta("heavy_crush_ratio") and tank.global_position.y > initial_height+.32:
			await photo("tank-crush")
			camera.size = 11
			camera.global_position = tank.to_global(Vector3(-5,9,7))
			camera.look_at(tank.global_position+Vector3.UP*.8-tank.global_basis.z*1.8)
			await photo("tank-crush-side")
			captured = true
			break
	print("TANK_CAPTURE crush=",captured," rise=",max_rise," target_ratio=",target.get_meta("heavy_crush_ratio",1.0)," health=",target.health," wrecked=",target.damage_look.wrecked," exploded=",target.get_meta("heavy_crush_exploded",false)," speed=",tank.speed)
	world.queue_free()
	await process_frame
	quit(0 if captured else 1)
