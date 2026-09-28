extends SceneTree
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const RESIDENCE := preload("res://activities/Residence.gd")
const STORAGE := preload("res://runtime/ResidenceStorage.gd")
var world
var checks := 0
var failures: Array[String] = []

class BackpackFixture extends RefCounted:
	var unlocked := false
	var full := false
	var stock := {"sandwich":2,"water":1}
	func is_backpack_unlocked() -> bool: return unlocked
	func storage_items() -> Dictionary:
		var result := {}
		for id in stock: result[id] = {"label":id,"count":stock[id]}
		return result
	func remove_storage_item(id: String, count: int) -> bool:
		if int(stock.get(id,0)) < count: return false
		stock[id] -= count
		return true
	func add_storage_item(id: String, count: int) -> bool:
		if full: return false
		stock[id] = int(stock.get(id,0))+count
		return true

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("RESIDENCE timeout"); quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("HOME ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(count := 4) -> void:
	for _i in count: await physics_frame

func until(predicate: Callable, count := 900) -> bool:
	for _i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	_storage_contract()
	if "--storage-only" in OS.get_cmdline_user_args():
		print("STORAGE_RESULT checks=",checks," failures=",failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	world = load("res://Main.tscn").instantiate()
	if world.get_script() == null:
		world.free()
		push_error("Main could not compile; integration not executed")
		quit(2)
		return
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	if not await until(func(): return world.session != null and world.session.ready_for_play,2400): quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.session.state.economy.grant_reward("residence_test_funds",100000)
	if not "--parking-only" in OS.get_cmdline_user_args():
		for id in ["westgate_garden","quayside_house","canal_north"]: await _home(id)
	for id in ["westgate_garden","quayside_house","canal_north"]:
		world.session.activities.residence.data.active_home = id
		world.production.region.set_focus(PLACES.get_definition(id).entry_position)
		world.player.teleport(PLACES.get_definition(id).entry_position+Vector3.UP*.08)
		await frames(60)
		await _parking()
		var home = world.session.activities.residence
		for car in [home.deployed,home.deployed_motorcycle]:
			if is_instance_valid(car):
				if world.driving.car == car: world.driving.car = null
				world.production.vehicles.erase(car)
				car.queue_free()
		home.data.stored_vehicle = {}
		home.data.stored_motorcycle = {}
		home.deployed = null
		home.deployed_motorcycle = null
		await frames()
	print("RESIDENCE_RESULT checks=",checks," failures=",failures.size()," ",failures)
	world.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)

func _storage_contract() -> void:
	var bridge := STORAGE.new()
	var bag := BackpackFixture.new()
	var chest := {}
	check(not bridge.unlocked() and not bridge.deposit(chest,"sandwich"),"missing backpack keeps chest locked")
	check(bridge.bind_inventory(bag) and not bridge.deposit(chest,"sandwich"),"locked backpack cannot deposit")
	bag.unlocked = true
	check(bridge.deposit(chest,"sandwich") and bag.stock.sandwich == 1 and chest.sandwich == 1,"deposit conserves food")
	bag.full = true
	check(not bridge.withdraw(chest,"sandwich") and chest.sandwich == 1,"full backpack preserves chest contents")
	bag.full = false
	check(bridge.withdraw(chest,"sandwich") and chest.is_empty() and bag.stock.sandwich == 2,"withdraw conserves food")
	check(not bridge.deposit(chest,"missing"),"unknown item cannot be manufactured")
	var home := RESIDENCE.new()
	var old := home.snapshot()
	old.erase("stored_motorcycle")
	old.erase("chest")
	check(home.restore_snapshot(old) and home.data.stored_motorcycle.is_empty() and home.data.chest.is_empty(),"old saves migrate empty slots")
	home.data.active_home = "westgate_garden"
	home.data.chest = {"sandwich":2}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(home.snapshot()))
	check(home.restore_snapshot(saved) and home.data.chest.sandwich == 2,"chest survives JSON restore")
	saved.chest.sandwich = -1
	check(not home.restore_snapshot(saved) and home.data.chest.sandwich == 2,"invalid chest rejected atomically")
	var legacy_bike := home.snapshot()
	legacy_bike.stored_vehicle = {"archetype_id":"bike_urban","health":45,"color":"779999ff","status":"stored"}
	legacy_bike.erase("stored_motorcycle")
	check(home.restore_snapshot(legacy_bike) and home.data.stored_vehicle.is_empty() and home.data.stored_motorcycle.archetype_id == "bike_urban","legacy bike migrates into motorcycle bay")
	var invalid_slot := home.snapshot()
	invalid_slot.stored_motorcycle.archetype_id = "sport_coupe"
	check(not home.restore_snapshot(invalid_slot) and home.data.stored_motorcycle.archetype_id == "bike_urban","car cannot occupy motorcycle save slot")

func _home(id: String) -> void:
	var session = world.session
	var home = session.activities.residence
	var entrance = session.weapon_shop_entrance
	var definition := PLACES.get_definition(id)
	var door: Vector3 = entrance._door_position(id,definition)
	world.production.region.set_focus(door)
	world.player.teleport(door+Vector3(0,.08,1.7))
	await frames(80)
	var facade: Node3D
	for node in get_nodes_in_group("v2_walkin_facade"):
		if node.get_meta("place_id","") == id: facade = node
	check(is_instance_valid(facade),id+" facade streamed")
	if not is_instance_valid(facade): return
	check(is_zero_approx(facade.open_amount),id+" unowned door stays closed nearby")
	check(not await session.enter_place(id,false),id+" unowned interior refused")
	var blocked: bool = world.player.test_move(Transform3D(Basis.IDENTITY,door+Vector3(0,.1,.8)),Vector3(0,0,-1.5))
	check(blocked,id+" closed door blocks full player")
	world.player.teleport(door+Vector3(0,.08,.8))
	world.player.automatic_direction = Vector3.FORWARD
	await frames(18)
	world.player.automatic_direction = Vector3.ZERO
	check(session.state.place_id.is_empty() and facade.open_amount == 0,id+" walking cannot open unowned door")
	check(home.buy(id),id+" purchase succeeds at door")
	await frames(25)
	check(facade.open_amount > .95,id+" owned door opens")
	world.player.automatic_direction = Vector3.FORWARD
	check(await until(func(): return session.state.place_id == id,300),id+" walking enters")
	world.player.automatic_direction = Vector3.ZERO
	await until(func(): return not entrance._entering and not session.is_transition_blocked())
	if session.state.place_id != id: return
	check(session.position_clear(world.player.position+Vector3.UP*.05),id+" entry spawn fits")
	var services = session.residence_services
	for station in ["wardrobe","chest","food","save","time","arsenal"]:
		var point: Vector3 = session.room.interaction_points[station]
		check(session.room.is_floor_clear(session.room.to_local(point),.34),id+" "+station+" approach fits body")
		world.player.teleport(point+Vector3.UP*.08)
		await frames()
		var action: Dictionary = services.nearest_action()
		check(action.get("station","") == station,id+" physical "+station+" interaction")
		if action.get("station","") != station: continue
		check(services.perform("residence_services"),id+" opens "+station)
		if DisplayServer.get_name() != "headless" and station in ["wardrobe","food","chest"]:
			await frames(12)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/residence-living/menu-"+id+"-"+station+".png")
		if station == "food":
			session.close_menu()
			world.gameplay.health = 40
			services.perform("residence_services")
			services._consume("meal")
			check(world.gameplay.health == 75,id+" meal restores health")
			services.perform("residence_services")
			services._consume("drink")
			check(world.gameplay.health == 90,id+" drink restores health")
		elif station == "wardrobe":
			var before: String = world.player.outfit_id
			services._wear("dante_arctic")
			check(world.player.outfit_id == before,id+" wardrobe rejects unowned clothes")
			session.state.economy.grant_outfit("dante_suit")
			services._wear("dante_suit")
			check(world.player.outfit_id == "dante_suit",id+" wardrobe applies owned clothing")
		elif station == "chest":
			check(not services.storage.unlocked(),id+" chest waits for backpack integration")
		session.close_menu()
	await _physical(id)
	# Save through the same manual service action to a test-only file.
	world.player.teleport(session.room.interaction_points.save+Vector3.UP*.08)
	await frames()
	var previous_path: String = session.controller.store.path
	session.controller.store.path = "res://evidence/residence-living/manual-"+id+".json"
	session.controller.no_save = false
	check(services.perform("residence_services"),id+" manual save action available")
	var loaded = load("res://runtime/GameState.gd").new()
	check(session.controller.store.load_into(loaded).get("ok",false) and loaded.place_id == id,id+" manual save reloads house")
	session.controller.no_save = true
	session.controller.store.path = previous_path
	session.close_menu()
	world.player.teleport(session.room.exit_position+Vector3(0,.08,-1))
	world.player.automatic_direction = Vector3.BACK
	check(await until(func(): return session.state.place_id.is_empty(),300),id+" walking exits")
	world.player.automatic_direction = Vector3.ZERO
	await until(func(): return not entrance._leaving)
	check(not world.player.input_locked,id+" exit restores controls")

func _physical(id: String) -> void:
	var room = world.session.room
	var npc = preload("res://scripts/Actor.gd").new()
	npc.controlled_automatically = true
	world.add_child(npc)
	# Sweep bodies through every authored furniture footprint from each side.
	for key in room.model.solid_rects:
		if key in ["BackWall","LeftWall","RightCutaway","SouthLeft","SouthRight","DoorBoundary"]: continue
		var rect: Rect2 = room.model.solid_rects[key]
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var distance: float = (rect.size.x if direction.x != 0 else rect.size.y)*.5+.7
			var start: Vector2 = rect.get_center()+direction*distance
			if not room.is_floor_clear(Vector3(start.x,0,start.y),.34): continue
			var transform := Transform3D(Basis.IDENTITY,room.to_global(Vector3(start.x,.08,start.y)))
			var motion := Vector3(-direction.x,0,-direction.y)*distance*2
			check(world.player.test_move(transform,motion),id+" player blocked by "+key)
			check(npc.test_move(transform,motion),id+" NPC blocked by "+key)
	npc.queue_free()
	await frames()
	if DisplayServer.get_name() != "headless": await _depth_photos(id)

func _depth_photos(id: String) -> void:
	var room = world.session.room
	var npc = preload("res://scripts/Actor.gd").new()
	npc.controlled_automatically = true
	world.add_child(npc)
	for key in ["StorageChest","SaveDesk","Wardrobe","Kitchen"]:
		var rect: Rect2 = room.model.solid_rects[key]
		for side in ["front","behind","side"]:
			var point := rect.get_center()
			if side == "front": point.y = rect.end.y+.42
			elif side == "behind": point.y = rect.position.y-.42
			else: point.x = rect.position.x-.42
			var local := Vector3(point.x,.06,point.y)
			# Wall-backed furniture has no physical rear passage: don't invent one.
			if not room.is_floor_clear(local,.33): continue
			world.player.teleport(room.to_global(local))
			npc.teleport(room.to_global(Vector3(0,.06,2.4)))
			await frames(12)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/residence-living/depth-"+id+"-"+key+"-"+side+".png")
			check(world.player.visible and npc.visible,id+" depth positive control "+key+" "+side)
	# Then swap player/NPC roles; both use native depth in the same room.
	world.player.teleport(room.to_global(Vector3(0,.06,2.4)))
	var chest: Rect2 = room.model.solid_rects.StorageChest
	npc.teleport(room.to_global(Vector3(chest.get_center().x,.06,chest.end.y+.42)))
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/residence-living/depth-"+id+"-npc.png")
	npc.queue_free()
	await frames()

func _parking() -> void:
	var home = world.session.activities.residence
	var id: String = home.data.active_home
	for slot in ["car","motorcycle"]:
		var model := "sport_coupe" if slot == "car" else "bike_urban"
		var point: Vector3 = home.parking(id,slot)+Vector3.UP*.12
		world.player.teleport(point+Vector3(0,0,4))
		await frames(20)
		check(home._clear(model,point),slot+" bay supports full hull")
		if not home._clear(model,point):
			var query := PhysicsShapeQueryParameters3D.new()
			var shape := BoxShape3D.new()
			var bounds: Array = home.Fleet.spec(model).bounds_size
			shape.size = Vector3(maxf(.65,bounds[0])+.1,maxf(1.1,bounds[1]),bounds[2]+.1)
			query.shape = shape
			query.transform.origin = point+Vector3.UP*shape.size.y*.5
			query.collision_mask = 7
			for hit in world.get_world_3d().direct_space_state.intersect_shape(query,20): print("BAY_OBSTACLE ",slot," ",hit.collider.get_path())
		var car = world.production.spawn_vehicle(model,point,0)
		check(is_instance_valid(car),slot+" vehicle spawned")
		if not is_instance_valid(car): continue
		await frames()
		check(await world.session.restore_garage_driver(car),slot+" driver enters physically")
		car.speed = 0
		check(world.session.interact(),slot+" store action dispatches through gameplay")
		check(await until(func(): return home._record(slot).get("status","") == "stored",300),slot+" stores vehicle after exit animation")
		check(not world.driving.occupied and not world.driving.is_body_transition_active(),slot+" stored only after safe dismount")
		world.player.teleport(point+Vector3(0,0,4))
		await frames()
	check(home.data.stored_vehicle.get("status","") == "stored" and home.data.stored_motorcycle.get("status","") == "stored","car and motorcycle coexist")
	check(RESIDENCE.validate_snapshot(JSON.parse_string(JSON.stringify(home.snapshot()))),"both bays persist in valid save")
	var session = world.session
	var save_path: String = session.controller.store.path
	session.controller.store.path = "res://evidence/residence-living/parking-"+id+".json"
	session.controller.no_save = false
	check(session.save_game(true),id+" both stored vehicles publish in complete save")
	var loaded = load("res://runtime/GameState.gd").new()
	var loaded_ok: bool = session.controller.store.load_into(loaded).get("ok",false)
	check(loaded_ok and loaded.world_state.activities.home.stored_vehicle.get("status","") == "stored" and loaded.world_state.activities.home.stored_motorcycle.get("status","") == "stored",id+" both bays reload together")
	session.controller.no_save = true
	session.controller.store.path = save_path
	for slot in ["car","motorcycle"]:
		world.player.teleport(home.parking(id,slot)+Vector3(0,.08,4))
		await frames()
		check(home.retrieve_vehicle(slot),slot+" retrieves independently")
		check(not home.retrieve_vehicle(slot),slot+" cannot duplicate deployed vehicle")
	var garage: Node3D
	for facade in get_nodes_in_group("v2_walkin_facade"):
		if facade.get_meta("place_id","") == id: garage = facade.get_parent().get_node("ResidentialGarage")
	await frames()
	check(is_instance_valid(garage) and not garage._roof.visible,id+" garage cutaway reveals parked vehicles")
	if DisplayServer.get_name() != "headless":
		await frames(20)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/residence-living/parked-"+id+".png")
	var deployed_snapshot: Dictionary = JSON.parse_string(JSON.stringify(home.snapshot()))
	for car in [home.deployed,home.deployed_motorcycle]:
		if is_instance_valid(car):
			if world.driving.car == car: world.driving.car = null
			world.production.vehicles.erase(car)
			car.queue_free()
	await frames()
	check(home.restore_snapshot(deployed_snapshot),id+" deployed state restores")
	home.restore_deployed()
	check(is_instance_valid(home.deployed) and is_instance_valid(home.deployed_motorcycle),id+" both deployed vehicles reconstruct")
