extends "res://tools/capture_promo_20261007.gd"
## Tomadas adicionais de gameplay real para a edição promocional ampliada.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const BUILDINGS = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const NETWORK = preload("res://world/railway/RailwayNetwork.gd")

func extra_scene() -> void:
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 1.8
	world.gameplay.god_mode = true
	world.session.state.equip_weapon("fists")
	match scene_id:
		"city": await city()
		"mining": await mining()
		"train": await train()
		"cabin": await cabin()

func position_at(point: Vector3) -> void:
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.initialized = false
	await frames(100)

func unlock_fixture() -> void:
	var fixture: Dictionary = preload("res://tests/fixtures/NorthGatewayFixtures.gd").full_snapshot(world.player.global_position,true,true)
	fixture.campaign.aftermath = {"call_complete":true}
	require(world.session.state.campaign.restore_snapshot(fixture.campaign),"Completed campaign filming fixture")

func walk_to(point: Vector3, limit := 180) -> bool:
	for i in limit:
		var direction: Vector3 = point-world.player.global_position
		direction.y=0
		if direction.length()<.2: break
		world.player.automatic_direction=direction.normalized()
		await process_frame
	world.player.automatic_direction=Vector3.ZERO
	return world.player.global_position.distance_to(point)<.5

func walk_take(label: String, count := 150) -> void:
	var start: Vector3 = world.player.global_position
	var goal := start
	# Escolhe um caminho curto realmente livre na sala atual ou na rua.
	for direction in [Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT,Vector3.BACK]:
		var candidate: Vector3 = start+direction*3.2
		if not world.session.position_clear(candidate): continue
		if world.player.test_move(world.player.global_transform,candidate-start): continue
		if is_instance_valid(world.session.room) and world.session.room.has_method("is_floor_clear"):
			if not world.session.room.is_floor_clear(world.session.room.to_local(candidate),.34): continue
		goal=candidate
		break
	print("PROMO_WALK ",label," from=",start," to=",goal)
	await take(label,count,func(_i):
		var direction: Vector3=goal-world.player.global_position
		direction.y=0
		world.player.automatic_direction=direction.normalized() if direction.length()>.15 else Vector3.ZERO
	)
	world.player.automatic_direction=Vector3.ZERO

func city() -> void:
	world.session.activities.residence.data.active_home="westgate_garden"
	if not require(await world.session.enter_place("westgate_garden",false),"Residence admitted"): return
	await frames(80)
	await walk_take("home")
	if not require(await world.session.leave_place(),"Residence exit"): return
	var definition: Dictionary = BUILDINGS.find("harbor_customs_house")
	await position_at(definition.return_position+Vector3.UP*.08)
	await walk_take("street")
	await position_at(definition.return_position+Vector3.UP*.08)
	var runtime=world.session.building_entrance
	for i in 600:
		await process_frame
		if is_instance_valid(runtime.staged) and runtime.staged.definition.id==definition.id and not runtime.preparing: break
	if not require(is_instance_valid(runtime.staged) and runtime.staged.definition.id==definition.id,"Building staged"): return
	if not require(await walk_to(runtime.staged.spawn_position+Vector3.UP*.04),"Walked through building entrance"): return
	await frames(35)
	var room=world.session.room
	if not require(is_instance_valid(room) and world.session.state.place_id==definition.id,"Building interior admitted"): return
	await walk_take("building")
	for level in range(1,int(definition.floor_count)+1):
		world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
		await frames(4)
		if not require(await room.change_floor(level),"Stairs floor "+str(level)): return
		await frames(20)
	await frames(80)
	await walk_take("rooftop",180)

func mining() -> void:
	unlock_fixture()
	if not await travel("desert",Vector3(-180,.12,-1645)): return
	await frames(90)
	await position_at(Vector3(-173,-27.9,-1782))
	make_camera(145)
	var focus := Vector3(-180,-16,-1775)
	await take("quarry",150,func(i):
		aim_camera(focus,Vector3(105-float(i)*.10,145,115+float(i)*.1))
	)
	camera.queue_free()
	camera=null
	world.camera.make_current()
	var entry: Vector3=preload("res://world/mining/MiningLayout.gd").SECRET_ENTRY+Vector3.UP*.08
	await position_at(entry)
	if not require(await world.session.enter_place("remote_coal_mine",false),"Coal gallery admitted"): return
	await frames(90)
	var room=world.session.room
	world.player.teleport(room.to_global(Vector3(8,0,-4))+Vector3.UP*.08)
	await frames(40)
	await walk_take("gallery",180)

func train() -> void:
	await position_at(Vector3(173.75,.12,32))
	await walk_take("city_walk",150)
	var origin: Dictionary=NETWORK.get_station("harbor_central")
	await position_at(origin.arrival)
	var railway=world.session.railway
	if not require(railway.perform("harbor_central"),"Station menu"): return
	if not require(railway.travel_to("mountain_pines",false),"Ordinary train trip"): return
	for i in 300:
		await process_frame
		if railway.is_riding(): break
	if not require(railway.is_riding(),"Train moving with passenger"): return
	railway.set_camera_mode(0)
	await frames(110)
	await take("inside",180,func(_i): pass)
	railway.set_camera_mode(1)
	await frames(25)
	await take("outside",360,func(_i): pass)

func cabin() -> void:
	var definition: Dictionary=PLACES.get_definition("mountain_cabin")
	if not await travel("mountain",definition.entry_position+Vector3.UP*.08): return
	if not require(await world.session.enter_place("mountain_cabin",false),"Mountain cabin admitted"): return
	await frames(90)
	await walk_take("cabin",180)
