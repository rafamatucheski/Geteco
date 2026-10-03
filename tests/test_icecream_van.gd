extends SceneTree
const VAN := preload("res://gameplay/icecream/IceCreamVan.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0
class TestWorld extends Node3D:
	var player: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,.2,200)
	floor_shape.shape = box
	floor_shape.position.y = -.1
	ground.add_child(floor_shape)
	world.add_child(ground)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(6,3.4,-6)
	camera.look_at(Vector3(0,1.4,0))
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("506577")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40,-35,0)
	world.add_child(sun)
	var car := VEHICLE.new()
	car.archetype = "courier_van"
	car.paint_color = Color("fff0dd")
	world.add_child(car)
	check(not car.has_node("IceCreamVan"),"ordinary courier van remains ordinary")
	car.vehicle_id = VAN.PREFIX+"test"
	car.traffic = true
	var rig := car.get_node("IceCreamVan")
	VAN.attach(car)
	check(car.find_children("IceCreamVan","",false,false).size()==1,"idempotent attachment")
	check(car.shape.shape.size.is_equal_approx(Vector3(2.32,2.21,5.02)),"original van collision dimensions retained")
	check(car.has_node("IceCreamRoofCollision"),"roof ornament has collision")
	check(rig.crew.get_child_count()==2,"two seated clowns")
	check(VAN.livery_mesh().get_surface_count()==1,"batched livery")
	check(VAN.clown_mesh().get_surface_count()==1,"batched clown")
	check(rig.song.stream.get_length()>10 and rig.song.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"original jingle loops")
	check(rig.song.stream.loop_end==roundi(rig.song.stream.get_length()*rig.song.stream.mix_rate),"compressed audio loop covers every sample frame")
	check(rig.song.bus==&"Ambient" and rig.song.max_distance==48,"ambient volume and finite range")
	await create_timer(.4).timeout
	check(rig.song.playing and rig.crew.visible,"near traffic van plays and shows crew")
	var ray := PhysicsRayQueryParameters3D.create(car.global_position+Vector3(0,4,.5),car.global_position+Vector3(0,2.3,.5),4)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider==car and hit.position.y>car.global_position.y+2.9,"roof ornament physically blocks a ray above original hull")
	car.controlled = true
	rig._update_ambience()
	check(not rig.crew.visible,"clowns do not overlap player after taking the van")
	car.controlled = false
	var saved: Dictionary = preload("res://runtime/FleetState.gd").capture(car,"harbor")
	check(preload("res://runtime/FleetState.gd").validate(saved),"normal fleet record accepts variant")
	var restored := VEHICLE.new()
	restored.archetype = saved.archetype
	restored.vehicle_id = saved.vehicle_id
	restored.paint_color = Color.html(saved.paint)
	restored.position.x = 7
	world.add_child(restored)
	restored.traffic = true
	check(restored.has_node("IceCreamVan"),"saved identity reconstructs variant in ready")
	check(not VAN.choose([car,restored]),"two ambient vans cap new spawns")
	var third := VEHICLE.new()
	third.archetype = "courier_van"
	third.vehicle_id = VAN.PREFIX+"third"
	third.position.x = 14
	world.add_child(third)
	await create_timer(.4).timeout
	var playing := 0
	for node in get_nodes_in_group(VAN.GROUP):
		if node.song.playing: playing += 1
	check(playing==2,"at most two nearby jingles even with extra saved vans")
	car.health = 0
	rig._update_ambience()
	check(not rig.song.playing and not rig.crew.visible,"wreck is silent and has no seated crew")
	car.health = car.max_health
	car.engine_disabled = true
	rig._update_ambience()
	check(not rig.song.playing,"disabled engine is silent")
	car.engine_disabled = false
	car.hide()
	rig._update_ambience()
	check(not rig.song.playing,"hidden region is silent")
	car.show()
	car.set_physics_process(false)
	rig._update_ambience()
	check(not rig.song.playing,"suspended vehicle is silent")
	car.set_physics_process(true)
	world.player.position.x = 100
	await create_timer(.4).timeout
	check(not rig.song.playing,"distant listener is silent")
	world.player.position.x = 0
	await create_timer(.4).timeout
	check(rig.song.playing,"return to range resumes jingle")
	# Keep screenshots focused on one vehicle; the others only exercise the voice cap.
	restored.hide()
	third.hide()
	camera.global_position = car.global_position+Vector3(6,3.4,-6)
	camera.look_at(car.global_position+Vector3.UP*1.4)
	if DisplayServer.get_name() != "headless":
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/icecream/fixture.png")
		camera.global_position = car.global_position+Vector3(2.6,2.1,-4.3)
		camera.look_at(car.global_position+Vector3(0,1.45,-.9))
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/icecream/clowns.png")
	world.free()
	await process_frame
	check(get_nodes_in_group(VAN.GROUP).is_empty(),"despawn frees all variant nodes and sound players")
	print("ICECREAM_TEST checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
