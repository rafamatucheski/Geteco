extends "res://tests/test_door_push_access.gd"
## Regressão: compra na porta, travessia, volta e reentrada.
func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240).timeout.connect(func(): push_error("CANAL_ACCESS timeout"); quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 10800):
		check(false,"Main ready"); quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var session = world.session
	var definition: Dictionary = PLACES.get_definition("canal_north")
	session.controller.region.set_focus(definition.entry_position)
	world.player.teleport(definition.entry_position + Vector3(0,.08,1))
	await frames(120)
	var markers := get_nodes_in_group("residence_sale_marker").filter(func(node): return node.property_id == "canal_north")
	check(markers.size() == 1 and markers[0].visible,"Canal North shows dollar before purchase")
	session.state.economy.grant_reward("canal_access_fixture",100000)
	check(session.activities.residence.buy("canal_north"),"purchase through real residence controller")
	for visit in 2:
		if not await push_access("canal_north"): break
	var runtime = session.building_entrance
	var grocery: Dictionary = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").find("harbor_building_north_grocer")
	check(not grocery.is_empty(),"Canal Grocery has accessible building definition")
	if not grocery.is_empty() and session.state.place_id.is_empty():
		session.controller.region.set_focus(grocery.entry_position)
		world.player.teleport(grocery.return_position + Vector3.UP*.08)
		check(await wait_until(func(): return is_instance_valid(runtime.staged) and runtime.staged.definition.id == grocery.id and not runtime.preparing,900),"Canal Grocery prepares on approach")
		if is_instance_valid(runtime.staged) and runtime.staged.definition.id == grocery.id:
			world.player.automatic_direction = -runtime.staged.global_basis.z
			check(await wait_until(func(): return session.state.place_id == grocery.id,300),"walk into Canal Grocery")
			world.player.automatic_direction = Vector3.ZERO
			check(not world.player.input_locked,"grocery restores control")
	print("CANAL_ACCESS_RESULT checks=",checks," failures=",failures)
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)
