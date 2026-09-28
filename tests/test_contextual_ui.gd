extends SceneTree
## Integrated presentation acceptance. Run rendered for screenshots, always --no-save.
const OUT := "res://evidence/ui-refactor-20260928/acceptance"
var world
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1; print("CONTEXTUAL_UI ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count := 6) -> void:
	for i in count: await process_frame
func wait_seconds(seconds: float) -> void: await create_timer(seconds).timeout
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(label+".png"))==OK,"capture "+label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("UI acceptance timed out"); quit(3))
	DirAccess.make_dir_recursive_absolute(OUT)
	seed(28092026)
	var settings = root.get_node("V2Settings")
	settings.window_mode=0; settings.resolution=0; settings.show_fps=false; settings.apply_settings()
	world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true); world.set_meta("skip_dispatch",true); root.add_child(world); current_scene=world
	for i in 2400:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"real session ready")
	if not failures.is_empty(): finish(); return
	check(world.production.no_save,"personal saves disabled")
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.player.teleport(Vector3(132,.15,72)); world.production.region.set_focus(world.player.global_position)
	world.session.weather.set_process(false); world.session.weather.time_of_day=.4; world.session.weather.weather_state=0; world.session.weather._update()
	await wait_seconds(3)
	var hud=world.hud; var state=world.session.state; var controls=root.get_node("GameInput")
	state.grant_weapon("pistol"); state.add_ammo("pistol",80); state.equip_weapon("pistol"); world.gameplay.armor=60
	hud.refresh_from_state(); await wait_seconds(.3)
	check(hud.health_bar.value==world.gameplay.health and hud.armor_bar.value==60,"status reads combat authority")
	check(not hud.health_bar.show_percentage and not hud.armor_bar.show_percentage,"vitals have no numeric percentages")
	check(not hud.player_status.cold_row.visible,"warm area omits cold row")
	check(hud.money_label.text=="$ "+preload("res://ui/GameStyle.gd").amount(state.economy.balance),"isolated wallet uses balance and thousands separator")
	check(hud.weapon_icon.weapon_id==state.equipped_weapon and " | " in hud.ammo_label.text,"current weapon and real magazine/reserve")
	await wait_seconds(3)
	check(not hud.objective_card.visible and not hud.weapon.carousel.visible,"objective and weapon switch expire")
	check(not hud.minimap.caption.visible,"minimap has no permanent distance caption")
	check(hud.get_node_or_null("GameplayHUDRoot/WeatherReadout")==null,"no clock/weather HUD component")
	var economy_before: Dictionary=state.economy.snapshot()
	for dims in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1680,720)]:
		root.content_scale_size=dims; root.size=dims; await frames(12); hud.refresh_from_state(); await frames()
		var rect := root.get_visible_rect()
		for node in [hud.player_status,hud.money,hud.weapon,hud.backpack,hud.minimap]:
			check(rect.encloses(node.get_global_rect()),"safe bounds "+node.name+" "+str(dims))
		check(hud.player_status.get_global_rect().position.x<rect.size.x*.2 and hud.player_status.get_global_rect().position.y<50,"status top left")
		check(hud.money.get_global_rect().position.x>rect.size.x*.7,"money top right")
		check(hud.weapon.get_global_rect().position.x>rect.size.x*.65,"weapon bottom right")
		await shot("hud-"+str(dims.x)+"x"+str(dims.y))
	check(state.economy.snapshot()==economy_before,"HUD/resizing never mutates inventory or economy")
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720); await frames()
	state.economy.grant_reward("ui_refactor_wallet",150); hud.refresh_from_state(); await frames()
	check(hud.money.change.visible and hud.money.change.text=="+ $ 150","small wallet delta")
	await wait_seconds(2); check(not hud.money.change.visible and hud.money_label.is_visible_in_tree(),"delta expires; balance remains")
	var pad := InputEventJoypadButton.new(); pad.button_index=JOY_BUTTON_GUIDE; pad.pressed=true; Input.parse_input_event(pad); await frames()
	check(controls.using_gamepad and hud.backpack_hint.text==controls.prompt("inventory"),"last gamepad input updates backpack binding")
	hud.interaction_row.update_prompt("E  Conversar","interact",controls)
	check(hud.interaction_key.text==controls.prompt("interact") and hud.interaction_label.text=="Conversar","only current controller prompt")
	var mouse := InputEventMouseMotion.new(); mouse.relative=Vector2(8,0); Input.parse_input_event(mouse); await frames()
	check(not controls.using_gamepad and hud.backpack_hint.text==controls.prompt("inventory"),"mouse restores keyboard prompts")
	var bindings: Dictionary=controls.export_bindings(); controls.import_bindings({"interact":[{"key":KEY_P}]})
	hud.interaction_row.update_prompt("E  Conversar","interact",controls)
	check(hud.interaction_key.text=="P","remapped keyboard prompt")
	controls.import_bindings(bindings)
	hud.player_status.update_status(100,60,{"visible":true,"temperature":43,"key":"exposed"},.1); await wait_seconds(.3)
	check(hud.player_status.cold_row.visible,"cold exposure reveals third bar")
	hud.player_status.update_status(100,60,{"visible":false,"temperature":100},3.1); await wait_seconds(.3)
	check(not hud.player_status.cold_row.visible,"normal temperature retires cold row")
	state.economy.grid_equip_bag("backpack"); state.economy.grant_item("apple",3); state.economy.grant_item("water",2)
	pad.button_index=JOY_BUTTON_DPAD_LEFT; pad.pressed=true; Input.parse_input_event(pad); await frames(12)
	var bag=world.session.field_inventory.ui
	check(bag.visible,"mapped gamepad button opens real backpack")
	pad.button_index=JOY_BUTTON_B; Input.parse_input_event(pad); await frames()
	check(not bag.visible and not world.session.modal,"gamepad cancel closes real backpack")
	var tab := InputEventKey.new(); tab.physical_keycode=KEY_TAB; tab.pressed=true; Input.parse_input_event(tab); await frames(12)
	check(world.session.modal and bag.visible and not hud.root_control.visible,"backpack owns modal input and hides HUD")
	check(absf(bag.card.get_global_rect().get_center().x-root.get_visible_rect().size.x*.5)<3,"backpack centered")
	await shot("backpack")
	bag.wardrobe_visible=true; bag.refresh(); bag.selected_outfit="dante_classic"; bag._details(); await frames()
	check(bag.details.visible,"owned clothes have selected protection details")
	check(root.get_visible_rect().encloses(bag.card.get_global_rect()),"clothes and actions stay within 720p")
	await shot("clothes")
	check(state.economy.grant_outfit("dante_arctic"),"owned thermal clothing fixture uses economy API")
	bag.selected_outfit="dante_arctic"; bag._details(); await frames()
	bag.details.get_child(bag.details.get_child_count()-1).pressed.emit(); await frames()
	check(state.economy.outfit=="dante_arctic" and world.player.outfit_id=="dante_arctic","equip clothes updates economy and existing character visual")
	for dims in [Vector2i(1280,800),Vector2i(1680,720)]:
		root.content_scale_size=dims; root.size=dims; await frames(12)
		check(root.get_visible_rect().encloses(bag.card.get_global_rect()),"backpack responsive "+str(dims))
	world.session.close_menu(); await frames()
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720); await frames()
	world.session.show_map(); await frames(12)
	var map=world.hud.get_node("MapUI")
	check(map.has_method("change_zoom") and map.size.x>1000,"full map fills available screen")
	var old_zoom: float=map.target_zoom; map.change_zoom(1.25); await wait_seconds(.5)
	check(map.zoom>old_zoom,"map zoom interpolates")
	map.select_marker(0); await frames(); check(map.sidebar.visible,"selected marker opens sidebar")
	await shot("map")
	for dims in [Vector2i(1280,800),Vector2i(1680,720)]:
		root.content_scale_size=dims; root.size=dims; await frames(12)
		check(root.get_visible_rect().encloses(map.get_global_rect()) and root.get_visible_rect().encloses(map.sidebar.get_global_rect()),"full map responsive "+str(dims))
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720); await frames()
	world.session.close_menu(); world.session.show_journal(); await frames()
	check(world.session.panel.size.x<800,"normal modal size restored after map")
	world.session.close_menu(); await frames()
	state.equip_weapon("pistol")
	check(await world.session.enter_place("maciota",false,"maciota"),"real garage transition")
	await frames(20); hud.refresh_from_state()
	check(not state.weapons_allowed() and state.equipped_weapon=="fists" and hud.weapon_icon.weapon_id=="fists","garage holsters immediately in authoritative state and HUD")
	check(not state.equip_weapon("pistol") and not state.can_attack(),"garage still blocks equip and attacks")
	check(not hud.minimap.visible,"outdoor map hidden inside garage")
	finish()
func finish() -> void:
	print("CONTEXTUAL_UI_RESULT checks=",checks," failures=",failures.size())
	FileAccess.open(OUT.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
