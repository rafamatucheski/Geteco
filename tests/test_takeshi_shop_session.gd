extends SceneTree
const HONOR := preload("res://runtime/TakeshiHonor.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var checks := 0
var failures := 0
var output := ""
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("TAKESHI_SHOP timeout"); quit(3))
	run.call_deferred()
func check(ok: bool, message: String) -> bool:
	checks += 1
	print("TAKESHI_SHOP ","PASS " if ok else "FAIL ",message)
	if not ok: failures += 1
	return ok
func frames(count: int) -> void:
	for i in count: await physics_frame
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	output = FIXTURE.output_dir("takeshi-shop")
	var place: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_ammunation")
	var door: Vector3 = place.exterior_position+Vector3(0,0,5.8)
	var data := FIXTURE.full_snapshot(door+Vector3(0,.08,1.12),true)
	var state = preload("res://runtime/GameState.gd").new()
	state.restore_snapshot(data)
	# This shop checkpoint is after the campaign epilogue phone call; leaving
	# it pending legitimately locks walking with an unrelated story dialogue.
	state.campaign.complete_aftermath_call()
	HONOR.record_finish(state.world_state,true,13.8)
	var car := {"vehicle_id":HONOR.CAR_ID,"archetype":"supra_a80","region":"desert","position":[-1000,.1,-1240],"yaw":PI,"health":200.0,"paint":"efeee8ff","equipment":{},"was_driven":false}
	if not check(HONOR.claim_state(state,"car",car).ok,"checkpoint contains genuine reward choice"): quit(1); return
	state.economy.grant_reward("takeshi_shop_fixture",450000)
	var path := FIXTURE.write_fixture(output,"checkpoint.json",state.snapshot())
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1280,720)
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play,"Main ready"): quit(1); return
	var session = world.session
	world.gameplay.god_mode = true
	world.production.region.prepare_collision_at(door)
	world.player.teleport(door+Vector3(0,.08,1.12))
	world.camera.heading = 0.0
	await frames(8)
	Input.action_press("move_up")
	for i in 150:
		await physics_frame
		if session.state.place_id=="harbor_ammunation": break
	Input.action_release("move_up")
	for i in 300:
		await physics_frame
		if session.state.place_id=="harbor_ammunation" and is_instance_valid(session.room) and not session.is_transition_blocked(): break
	if not check(session.state.place_id=="harbor_ammunation" and is_instance_valid(session.room),"walk through Ammu-Nation doorway"): quit(1); return
	world.player.teleport(session.room.interaction_points.service+Vector3.UP*.08)
	await frames(8)
	check(session.interact(),"counter interaction opens shop")
	await frames(2)
	var shop = session.storefronts.ammunation
	if not check(is_instance_valid(shop) and shop.active,"production weapon catalog active"): quit(1); return
	check(shop.stock.has("katana"),"Supra reward unlocks katana stock")
	shop.selection = shop.stock.find("katana")
	shop.change_selection(0)
	check(not shop.buy.disabled and shop.caption.text.contains("300000"),"actual purchase button shows 300000")
	await capture("katana-for-sale")
	var before_katana: int = session.state.economy.balance
	shop.buy.pressed.emit()
	await frames(2)
	check(session.state.owns_weapon("katana") and before_katana-session.state.economy.balance==300000,"catalog purchase charges 300000")
	shop.workbench_button.pressed.emit()
	await frames(2)
	var panel = shop.saber_panel
	if not check(is_instance_valid(panel) and not panel.apply_button.disabled,"saber color editor opens"): quit(1); return
	check(panel.get_viewport_rect().encloses(panel.get_global_rect()),"color editor and purchase controls fit the viewport")
	panel.picker.color = Color("d21dff")
	await capture("saber-color-picker")
	var before_saber: int = session.state.economy.balance
	panel.apply_button.pressed.emit()
	await frames(2)
	check(before_saber-session.state.economy.balance==150000 and HONOR.data(session.state.world_state).saber_color=="d21dffff","saber purchase and custom color committed")
	var after_saber: int = session.state.economy.balance
	panel.picker.color = Color("14ef88")
	panel.apply_button.pressed.emit()
	check(session.state.economy.balance==after_saber and HONOR.data(session.state.world_state).saber_color=="14ef88ff","color changes free after conversion")
	panel.closed.emit()
	panel.queue_free()
	await frames(2)
	check(shop.gun.find_child("EnergyBlade",true,false)!=null,"catalog previews upgraded energy blade")
	await capture("saber-preview")
	session.close_menu()
	await frames(4)
	check(not session.modal and is_equal_approx(Engine.time_scale,1.0),"shop closes restoring control and normal time")
	print("TAKESHI_SHOP_DONE checks=",checks," failures=",failures," evidence=",output)
	world.free()
	quit(0 if failures==0 else 1)
