extends SceneTree
## Production scene and actual weapon light; never reads or writes player saves.
var world
var failures := 0
const OUT := "res://evidence/sewer-flashlight-20261012"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func settle(count := 12) -> void:
	for i in count: await physics_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.state.economy.cheat_infinite_money = true
	world.gameplay.state.grant_weapon("pistol")
	world.gameplay.state.equip_weapon("pistol")
	world.gameplay.buy_attachment("pistol","flashlight")
	world.gameplay.flashlight_enabled = false
	world.gameplay._update_visual()
	var previous_env: Environment = world.camera.environment
	var previous_sun: int = world.production.sun.light_cull_mask
	var previous_shadows: bool = world.gameplay.flashlight.shadow_enabled
	var places := ["harbor_sewer","sewer_market"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--place="): places = [arg.trim_prefix("--place=")]
	for id in places:
		var definition := preload("res://world/places/PlaceCatalog.gd").get_definition(id)
		world.session.controller.region.set_focus(definition.entry_position)
		world.player.teleport(definition.entry_position+Vector3(-1.2,.08,1.0))
		await settle(60)
		var hatch: Node3D = world.session._find_sewer_hatch(id)
		if is_instance_valid(hatch):
			world.player.teleport(hatch.to_global(Vector3(0,.08,1.1)))
			await settle(3)
		var entered: bool = await world.session.enter_place(id,false)
		check(entered, "enter " + id)
		if not entered:
			print("ENTRY_DIAGNOSTIC ",id," notice=",world.session.notice.text," locked=",world.player.input_locked," transition=",world.session.transition_kind," region=",world.session.state.region_id," place=",world.session.state.place_id," air=",world.player.get_meta("player_air_busy",false)," blocked=",world.session.is_transition_blocked()," occupied=",world.driving.occupied)
			world.queue_free(); quit(1); return
		await settle()
		check(is_equal_approx(world.camera.environment.ambient_light_energy,.025),"dark ambient " + id)
		check(world.production.sun.light_cull_mask == 0,"no sunlight " + id)
		check(world.gameplay.flashlight.shadow_enabled,"wall shadows " + id)
		await capture(id + "-off")
		check(world.gameplay.toggle_flashlight(),"switch light on " + id)
		await settle()
		check(world.gameplay.flashlight.is_visible_in_tree(),"actual weapon light active " + id)
		await capture(id + "-on")
		if DisplayServer.get_name() != "headless" and "--temporal" in OS.get_cmdline_user_args():
			var started := Time.get_ticks_msec()
			var timestamps: Array[int] = []
			var folder := OUT.path_join(id + "-temporal")
			DirAccess.make_dir_recursive_absolute(folder)
			while Time.get_ticks_msec()-started < 30000:
				root.get_node("GameInput").touch_aim = Vector2.from_angle(float(Time.get_ticks_msec()-started)*.00025)
				await RenderingServer.frame_post_draw
				timestamps.append(Time.get_ticks_msec()-started)
				root.get_texture().get_image().save_jpg(folder.path_join("%05d.jpg" % timestamps.size()),.85)
			FileAccess.open(folder.path_join("timestamps.json"),FileAccess.WRITE).store_string(JSON.stringify(timestamps))
		check(world.gameplay.toggle_flashlight(),"switch light off " + id)
		check(await world.session.leave_place(),"leave " + id)
		await settle()
		check(world.camera.environment == previous_env,"restore exterior environment " + id)
		check(world.production.sun.light_cull_mask == previous_sun,"restore sunlight " + id)
		check(world.gameplay.flashlight.shadow_enabled == previous_shadows,"restore exterior shadow policy " + id)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
