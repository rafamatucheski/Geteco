extends "res://tests/test_harbor_building_walkthrough.gd"
const CELLAR := preload("res://world/places/curitiba_cellar/CuritibaCellarPlace.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")

func run() -> void:
	create_timer(240).timeout.connect(func(): check(false,"bounded shop safety session"); finish(3))
	rendered = DisplayServer.get_name() != "headless"
	folder = FIXTURE.output_dir("shop-safety-session")
	var definition := CELLAR.definition_data()
	var snapshot := FIXTURE.full_snapshot(definition.return_position + Vector3.UP * .08, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder, "save.json", snapshot)
	await boot()
	world.gameplay.stars = 2
	check(not await world.session.enter_place(CELLAR.ID, false), "wanted admission refused by real session")
	check(not world.session.weapon_shop_entrance._entry_available(CELLAR.ID), "walking access also refuses wanted player")
	check(world.session.state.place_id.is_empty() and not is_instance_valid(world.session.room), "refusal creates no shop or interior transition")
	world.gameplay.stars = 0
	world.gameplay.crime_points = 0
	check(await world.session.enter_place(CELLAR.ID, false), "shop opens after losing police")
	check(world.session.room_npcs.size() == 2, "Luisa and Nelson installed")
	check(not world.session.state.can_attack() and not world.session.state.equip_weapon("pistol"), "real interior refuses attack and drawing")
	for actor in world.session.room_npcs:
		var before: float = actor.health
		actor.receive_damage(10000.0, world.player)
		world.gameplay._damage(actor, 10000.0, world.player)
		check(PROTECTION.is_protected(actor) and actor.health == before and not actor.dead, str(actor.get_meta("interior_npc_id")) + " survives real lethal damage paths")
	await photo("protected-luisa-nelson")
	# --no-save protects the user's default slot; this fixture explicitly owns
	# the separate file and must enable writes to exercise disk restoration.
	world.production.no_save = false
	check(world.production.store.path == save_path, "save store owns only isolated fixture")
	check(world.session.save_game(), "safe shop saves to isolated disk")
	check(STORE.read_valid(save_path).get("place_id", "") == CELLAR.ID, "disk checkpoint actually records shop")
	world.free()
	await process_frame
	await boot()
	check(world.session.state.place_id == CELLAR.ID and not world.session.state.can_attack(), "cold disk restore preserves shop restriction")
	check(world.session.room_npcs.all(func(actor): return PROTECTION.is_protected(actor) and not actor.dead), "cold restore preserves invulnerability")
	check(await world.session.leave_place(), "exit remains available")
	check(world.session.state.weapons_allowed(), "exterior restores combat permission")
	finish()
