extends "res://tests/test_police_walkin.gd"
const DATA := preload("res://world/editing/WorldEditData.gd")
const SERVICES := preload("res://world/editing/WorldServiceBuildings.gd")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var official := DATA.disk_hash()
	var previous: Variant = Engine.get_meta("geteco_world_edit_document") if Engine.has_meta("geteco_world_edit_document") else null
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var original := PLACES.get_definition("harbor_hospital")
	var roofs := preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")
	var original_roof := roofs.find("harbor_hospital").duplicate(true)
	var game_state := preload("res://runtime/GameState.gd")
	var reward_contracts := game_state._world_reward_contracts()
	var region: Variant = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var catalog := DATA.catalog(region)
	var row: Dictionary = catalog["building/Clinic"].duplicate(true)
	region.free()
	var initial_room := PLACES.create_place("harbor_hospital")
	check(not original.is_empty() and initial_room!=null,"Existing service can create an interior")
	if initial_room!=null: initial_room.free()
	# Move a fachada real e a entrada dela antes de removê-la.
	row.position = [float(row.position[0])+3,float(row.position[1])+2]
	row.rotation = 15.0
	var doc := DATA.empty_document()
	doc.regions.harbor[row.id] = row
	Engine.set_meta("geteco_world_edit_document",doc)
	var moved := PLACES.get_definition("harbor_hospital")
	check(moved.entry_position.is_equal_approx(SERVICES.transform_for(row)*original.entry_position),"Moving the service moves its live entrance")
	check(not roofs.find("harbor_hospital").exterior_position.is_equal_approx(original_roof.exterior_position),"Moving the service invalidates its cached roof access")
	row.deleted = true
	check(DATA.validate_document(doc).is_empty(),"Deleted service remains a valid authored edit")
	check(not PLACES.definitions().any(func(value): return value.id=="harbor_hospital"),"Deleted service has no active place definition")
	check(not PLACES.access_points().any(func(value): return value.place_id=="harbor_hospital"),"Deleted service leaves no entrance or transfer trigger")
	var deleted := PLACES.get_definition("harbor_hospital")
	check(deleted.get("editor_deleted",false) and deleted.return_position.is_equal_approx(moved.return_position),"Mission and restore references keep the moved exterior return")
	check(PLACES.create_place("harbor_hospital")==null,"A deleted service cannot create a hidden interior")
	check(roofs.find("harbor_hospital").is_empty(),"Deleting the service removes its roof stair access")
	var roof_snapshot := {"id":"harbor_hospital","place":"harbor_hospital","return":[0,0,0]}
	check(roofs.valid_snapshot(roof_snapshot),"A historical rooftop save remains recoverable")
	check(game_state._location_is_compatible("harbor","harbor_hospital"),"A save inside the removed service retains a valid recoverable location identity")
	check(game_state._world_reward_contracts()==reward_contracts,"Removal preserves historical reward contracts and receipts")
	var entrance := preload("res://runtime/WeaponShopEntrance.gd").new()
	check(entrance._definition_for("harbor_hospital").is_empty(),"Walking entrance excludes the deleted service")
	entrance.free()
	# Exercise real admission and save-location recovery, including physical support.
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	world.set_meta("skip_traffic_yield",true)
	root.add_child(world)
	var ready := await wait_until(func(): return world.session!=null and world.session.ready_for_play and world.production.ready_for_play,1800)
	check(ready,"Runtime with a deleted service reaches normal play")
	if ready:
		var session: Variant = world.session
		check(not await session.enter_place("harbor_hospital",false),"Direct admission into a deleted service is rejected")
		var campaign: Dictionary = session.state.campaign.snapshot().duplicate(true)
		session.state.place_id = "harbor_hospital"
		session.state.world_state["pedestrian"] = {"region":"harbor","position":[9999,0,9999]}
		session.state.world_state["harbor_service_roof"] = roof_snapshot
		await session.restore_location()
		check(session.state.place_id.is_empty() and not is_instance_valid(session.room),"An old interior save recovers outside the deleted service")
		check(world.player.global_position.distance_to(deleted.return_position+Vector3.UP*.08)<4,"Recovery uses the service return rather than stale interior coordinates")
		check(session.position_clear(world.player.global_position),"Recovered player has physical ground and no solid overlap")
		check(not world.production.save_invalid,"Removing a service does not invalidate the rest of the save")
		check(not session.state.world_state.has("harbor_service_roof"),"Recovery retires the removed rooftop state")
		check(session.state.campaign.snapshot()==campaign,"Recovery preserves campaign progression")
	world.free()
	world = null
	doc.regions.harbor.erase(row.id)
	check(PLACES.definitions().any(func(value): return value.id=="harbor_hospital"),"Restoring the original service restores its active definition")
	var restored := PLACES.create_place("harbor_hospital")
	check(restored!=null,"Restored service can create its interior again")
	if restored!=null: restored.free()
	if previous==null: Engine.remove_meta("geteco_world_edit_document")
	else: Engine.set_meta("geteco_world_edit_document",previous)
	check(DATA.disk_hash()==official,"Lifecycle validation never saves the user's world")
	print("WORLD_EDITOR_SERVICE_LIFECYCLE failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
