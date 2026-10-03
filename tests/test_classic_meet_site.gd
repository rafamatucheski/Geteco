extends SceneTree
## Swept real player/NPC bodies, parking envelopes and the open street entrance.
const SITE := preload("res://world/places/classic_meet/ClassicMeetSite.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CLASSIC_SITE ","PASS " if ok else "FAIL ",label)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var site := SITE.new()
	stage.add_child(site)
	await physics_frame
	if "--lighting-only" in OS.get_cmdline_user_args():
		lighting_checks(site)
		stage.free()
		print("CLASSIC_SITE_LIGHTING checks=",checks," failures=",failures)
		quit(0 if failures.is_empty() else 1)
		return
	check(site.parking_slots().size()==6,"six separate parking spaces")
	check(site.pedestrian_spots().size()==6,"six gathering positions")
	check(site._body.get_child_count()>=15,"building, furniture, lamps and perimeter have solids")
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		await physics_frame
		var who := "player" if player else "npc"
		for spot in site.pedestrian_spots():
			actor.position = site.position+spot.position
			check(not actor.test_move(actor.global_transform,Vector3.UP*.01),who+" meeting spawn clear "+str(spot.position))
		for route in site.customer_routes():
			for i in route.size()-1:
				actor.position = site.position+route[i]
				check(not actor.test_move(actor.global_transform,route[i+1]-route[i]),who+" customer segment "+str(route[i]))
		actor.position = site.position+Vector3(0,.06,4)
		check(actor.test_move(actor.global_transform,Vector3(0,0,4)),who+" closed supermarket blocks swept body")
		actor.position = site.position+Vector3(-7.9,.06,3.5)
		check(actor.test_move(actor.global_transform,Vector3(0,0,2.5)),who+" produce display blocks swept body")
		actor.position = site.position+Vector3(7.5,.06,3.5)
		check(actor.test_move(actor.global_transform,Vector3(0,0,2.5)),who+" trolleys block swept body")
		actor.position = site.position+Vector3(0,.06,-17)
		check(not actor.test_move(actor.global_transform,Vector3(0,0,5)),who+" driveway has continuous free passage")
		actor.free()
	var vehicle := CharacterBody3D.new()
	vehicle.collision_layer = 4
	vehicle.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2,1.6,4.6)
	collision.shape = shape
	collision.position.y = .85
	vehicle.add_child(collision)
	stage.add_child(vehicle)
	await physics_frame
	for slot in site.parking_slots():
		vehicle.position = site.position+slot.position
		vehicle.rotation.y = slot.yaw
		check(not vehicle.test_move(vehicle.global_transform,Vector3.UP*.01),"full size parking envelope "+str(slot.position))
	vehicle.rotation.y = 0
	vehicle.position = site.position+Vector3(.7,.055,-18)
	check(not vehicle.test_move(vehicle.global_transform,Vector3(0,0,5)),"2m wide car passes entrance")
	vehicle.free()
	lighting_checks(site)
	stage.free()
	print("CLASSIC_SITE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func lighting_checks(site: Node3D) -> void:
	for lamp in site._lamps+site._event_lamps:
		check(lamp is SpotLight3D,"fitting illuminates through spot budget")
		check((-lamp.global_basis.z).dot(Vector3.DOWN)>.99,"fitting points toward ground")
		check(not lamp.shadow_enabled and not lamp.distance_fade_enabled,"stable fitting has no shadow/far-camera cutoff")
		check(not lamp.is_in_group(&"city_local_light_source"),"direct fitting is not duplicated in city pool")
	site.set_night_lighting(true,true)
	check(site._lamps.all(func(lamp): return lamp.visible),"night fittings enabled")
	check(site._event_lamps.all(func(lamp): return lamp.visible),"event fitting enabled")
	var event_energies: Array[float] = []
	for lamp in site._lamps+site._event_lamps: event_energies.append(lamp.light_energy)
	site.set_night_lighting(true,true)
	var repeated_energies: Array[float] = []
	for lamp in site._lamps+site._event_lamps: repeated_energies.append(lamp.light_energy)
	check(event_energies==repeated_energies,"repeated context scans never compound event brightness")
	site.set_night_lighting(true,false)
	for lamp in site._lamps+site._event_lamps:
		check(is_equal_approx(lamp.light_energy,float(lamp.get_meta("aurora_base_energy"))),"ordinary night restores authored base energy")
	site.set_night_lighting(false,false)
	check(site._lamps.all(func(lamp): return not lamp.visible),"day light sources disabled")
	check(site._event_lamps.all(func(lamp): return not lamp.visible),"day event source disabled")
