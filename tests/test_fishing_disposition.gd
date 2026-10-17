extends "res://tests/test_fishing_redesign_edges.gd"
## Real Main integration; fixture shortens the fight, not the choice/transactions.
const ITEMS := preload("res://activities/fishing/FishingCatchItems.gd")
const SAVE := preload("res://runtime/SaveStore.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")
var save_path := ""

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(480).timeout.connect(func():
		if not _finishing: check(false, "disposition timeout"); finish.call_deferred()
	)
	folder = FIXTURE.output_dir("fishing-disposition")
	var data := FIXTURE.full_snapshot(LOCATION.ENTRY + Vector3.UP * .1, false)
	data.campaign.active_id = ""
	data.campaign.step = 0
	data.economy.balance = 500
	save_path = FIXTURE.write_fixture(folder, "isolated-save.json", data)
	check(not save_path.is_empty(), "valid isolated save")
	if save_path.is_empty(): await finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled:
		await physics_frame
		if _finishing: return
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size = Vector2i(1280,720)
	Engine.max_fps = 30 # Frame capture only, not a performance measurement.
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.production.region.set_focus(LOCATION.ENTRY)
	world.session.fishing_runtime.refresh()
	await create_timer(1).timeout
	fishing = world.session.fishing
	touch = world.find_child("AndroidControls", true, false)
	var site = world.session.fishing_runtime.site
	check(is_instance_valid(site), "real lake mounted")
	if not is_instance_valid(site): await finish(); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "C# native router loaded")
	var point: Vector3 = site.fishing_spots()[0].position + Vector3.UP * .03
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	for frame in 12: await physics_frame
	if not (await start_attempt(-1)): await finish(); return
	var raw := "fish:pirarara:14000"
	for index in 3:
		if not (await hook_large_fish()) or not (await reach_landing()) or not (await until_phase("caught")):
			check(false, "catch fixture reaches choice"); await finish(); return
		press("interact", false)
		if index == 0:
			await create_timer(4).timeout
			check(fishing.phase == "caught" and fishing._rod._fish.visible, "choice keeps fish visible beyond old timeout")
			await capture("01-choice")
		if index < 2:
			var button: Button = fishing._hud.get_node("KeepFish")
			await click_button(button)
			check(fishing.phase == "storing", "real GUI Guardar enters storing")
			check(not fishing.choose_catch("keep"), "repeated keep cannot duplicate catch")
			check(world.session.state.economy.inventory.get(raw,0) == index + 1, "kept fish preserves species and weight")
			check(await until_phase("ready"), "store animation returns to fishing")
		else:
			check(not fishing._hud.state.keep_enabled, "full pockets disable Guardar")
			var before: Dictionary = world.session.state.economy.snapshot()
			check(not fishing.choose_catch("keep") and fishing.phase == "caught", "failed keep leaves choice available")
			await capture("02-bag-full")
			var model_id: int = fishing._rod._fish.get_instance_id()
			await click_button(fishing._hud.get_node("ReleaseFish"))
			check(fishing.phase == "releasing", "real GUI Soltar enters release")
			await record_release(model_id)
			check(fishing.phase == "ready" and world.session.state.economy.snapshot() == before, "release neither grants nor consumes inventory")
			check(int(fishing.snapshot().catches) == 3, "released fish keeps its catch record")
	press("exit_vehicle")
	expect_released("choice session exit")
	check(world.session.save_game(), "catch record and items save together")
	var saved := SAVE.read_valid(save_path)
	check(not saved.is_empty() and saved.economy.inventory.get(raw,0) == 2 and GAME_STATE.new().restore_snapshot(saved), "real disk save restores both kept fish")
	if not (await start_attempt(0)) or not (await hook_large_fish()) or not (await reach_landing()):
		await finish(); return
	fishing.remaining = .04
	check(await until_phase("caught"), "zero tournament clock allows landing to finish")
	var prize_balance: int = world.session.state.economy.balance
	await create_timer(3.7).timeout
	check(fishing.active and fishing.phase == "caught" and world.session.state.economy.balance == prize_balance, "zero clock still waits for catch decision without premature prize")
	fishing._hud.get_node("ReleaseFish").grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	root.push_input(accept,true)
	await physics_frame
	check(fishing.phase == "releasing" and not fishing._exit_after_choice, "Enter confirms focused Soltar instead of exiting")
	var deadline := Time.get_ticks_msec() + 4000
	while fishing.active and Time.get_ticks_msec() < deadline: await physics_frame
	check(not fishing.active and fishing.last_result.get("won",false) and world.session.state.economy.balance == prize_balance + 100, "prize settles once after release animation")
	check(FISH_STATE.claim(world.session.state.world_state,world.session.state.economy) == 0, "prize cannot be claimed twice")
	check(not ITEMS.sell(world.session,raw,"fishing_sale_1"), "sale rejected away from reception")
	world.player.teleport(site.entry_position() + Vector3.UP * .03)
	for frame in 12: await physics_frame
	check(fishing.open_menu(), "reception menu opens")
	var sell_menu := find_button("Vender peixes")
	check(sell_menu != null, "reception exposes fish sale")
	if sell_menu != null: sell_menu.pressed.emit()
	var balance: int = world.session.state.economy.balance
	var sale := find_button("Vender ·")
	check(sale != null, "carried fish appears with sale price")
	await capture("03-sale")
	if sale != null: sale.pressed.emit()
	check(world.session.state.economy.balance == balance + ITEMS.sale_price(raw) and world.session.state.economy.inventory.get(raw,0) == 1, "sale pays and consumes exactly one fish")
	world.session.close_menu()
	# The production residence API supplies the real Kitchen and menu guards.
	world.session.activities.residence.data.active_home = "westgate_garden"
	check(await world.session.enter_place("westgate_garden", false), "enter owned home for cooking")
	if world.session.room == null: await finish(); return
	world.player.teleport(world.session.room.interaction_points.food + Vector3.UP * .08)
	for frame in 12: await physics_frame
	check(world.session.interact(), "physical Kitchen opens fridge")
	await create_timer(.7).timeout
	var cook_button := find_button("Cozinhar ·")
	check(cook_button != null, "Kitchen lists the kept fish")
	await capture("04-cook")
	if cook_button != null: cook_button.pressed.emit()
	check(world.session.state.economy.inventory.get(raw,0) == 0 and world.session.state.economy.inventory.get("cooked_fish",0) == 1, "Kitchen replaces raw fish with prepared food")
	world.session.close_menu()
	world.gameplay.health = 50
	var grid: Dictionary = world.session.state.economy.grid_snapshot()
	for container in ["pockets","storage"]:
		for index in grid[container].size():
			if grid[container][index].id == "cooked_fish": world.session.field_inventory.consume(container,index)
	check(world.gameplay.health == 85 and world.session.state.economy.inventory.get("cooked_fish",0) == 0, "cooked fish uses real inventory consume and heals 35")
	check(world.session.save_game() and not SAVE.read_valid(save_path).is_empty(), "sale cooking and consumption remain saveable")
	await finish()

func find_button(prefix: String) -> Button:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix) and not child.is_queued_for_deletion(): return child
	return null

func click_button(button: Button) -> void:
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 91
		event.position = button.get_global_rect().get_center()
		event.pressed = down
		root.push_input(event,true)
		await process_frame

func record_release(model_id: int) -> void:
	var directory := folder.path_join("release")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var frames: Array = []
	var splash := false
	var same := true
	var start := Time.get_ticks_msec()
	while fishing.phase == "releasing" and Time.get_ticks_msec() - start < 5000:
		await RenderingServer.frame_post_draw
		var rod = fishing._rod
		same = same and rod._fish.get_instance_id() == model_id
		splash = splash or rod._release_splashed
		root.get_texture().get_image().save_jpg(directory.path_join("%05d.jpg" % frames.size()),.88)
		frames.append({"ms":Time.get_ticks_msec()-start,"phase":fishing.phase,"position":str(rod._fish.global_position),"visible":rod._fish.visible})
	FileAccess.open(directory.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(frames,"\t"))
	check(same and splash and frames.size() > 20, "release preserves same fish through splash and swimming")
