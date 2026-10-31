extends SceneTree
## Cena de produção e luz de cinto real; nunca lê nem grava saves do jogador.
var world
var failures := 0
const OUT := "res://artifacts/flashlight-fix-20261017/integration"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func settle(count := 12) -> void:
	for i in count: await physics_frame
func press_light() -> void:
	var event := InputEventAction.new()
	event.action = "weapon_flashlight"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = "weapon_flashlight"
	event.pressed = false
	Input.parse_input_event(event)
	await settle()
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
	world.gameplay.state.equip_weapon("fists")
	world.gameplay.belt_flashlight.purchase()
	world.gameplay.belt_flashlight.enabled = false
	world.gameplay.flashlight_enabled = false
	world.gameplay._update_visual()
	var previous_env: Environment = world.camera.environment
	var previous_sun: int = world.production.sun.light_cull_mask
	var previous_shadows: bool = world.gameplay.belt_flashlight.lamp.shadow_enabled
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
		check(world.gameplay.belt_flashlight.lamp.shadow_enabled,"wall shadows " + id)
		await capture(id + "-off")
		check(world.gameplay.belt_flashlight.toggle(),"switch light on " + id)
		await settle()
		check(world.gameplay.belt_flashlight.lamp.is_visible_in_tree(),"actual belt light active " + id)
		await capture(id + "-on")
		world.gameplay.state.equip_weapon("pistol")
		await settle()
		check(world.gameplay.belt_flashlight.lamp.is_visible_in_tree(), "light remains with pistol " + id)
		world.session._toggle_weapon_flashlight()
		check(not world.gameplay.belt_flashlight.enabled, "session input switches belt off " + id)
		world.session._toggle_weapon_flashlight()
		world.gameplay.state.equip_weapon("fists")
		# Ambas possuídas: o comando compartilhado precisa chegar também ao acessório da arma.
		world.gameplay.state.equip_weapon("pistol")
		world.gameplay.buy_attachment("pistol", "flashlight")
		world.gameplay.flashlight_enabled = false
		await press_light()
		check(not world.gameplay.belt_flashlight.enabled and not world.gameplay.flashlight_enabled, "shared command switches available lights off " + id)
		await press_light()
		await settle()
		check(world.gameplay.belt_flashlight.lamp.is_visible_in_tree() and world.gameplay.flashlight.is_visible_in_tree(), "shared command lights both belt and weapon " + id)
		world.gameplay.state.equip_weapon("fists")
		await settle()
		check(not world.gameplay.flashlight.is_visible_in_tree() and world.gameplay.belt_flashlight.lamp.is_visible_in_tree(), "unarmed keeps belt and hides weapon light " + id)
		if DisplayServer.get_name() != "headless" and "--temporal" in OS.get_cmdline_user_args():
			world.gameplay.state.equip_weapon("pistol")
			var started := Time.get_ticks_msec()
			var timestamps: Array[int] = []
			var folder := OUT.path_join(id + "-temporal")
			DirAccess.make_dir_recursive_absolute(folder)
			while Time.get_ticks_msec()-started < 30000:
				var elapsed := Time.get_ticks_msec()-started
				# Each source alone, then together, while aiming through a full turn.
				world.gameplay.belt_flashlight.enabled = elapsed < 10000 or elapsed >= 20000
				world.gameplay.flashlight_enabled = elapsed >= 10000
				root.get_node("GameInput").touch_aim = Vector2.from_angle(float(elapsed)*.00065)
				await RenderingServer.frame_post_draw
				timestamps.append(Time.get_ticks_msec()-started)
				root.get_texture().get_image().save_jpg(folder.path_join("%05d.jpg" % timestamps.size()),.85)
			FileAccess.open(folder.path_join("timestamps.json"),FileAccess.WRITE).store_string(JSON.stringify(timestamps))
		check(world.gameplay.belt_flashlight.toggle(),"switch light off " + id)
		check(await world.session.leave_place(),"leave " + id)
		await settle()
		check(world.camera.environment == previous_env,"restore exterior environment " + id)
		check(world.production.sun.light_cull_mask == previous_sun,"restore sunlight " + id)
		check(world.gameplay.belt_flashlight.lamp.shadow_enabled == previous_shadows,"restore exterior shadow policy " + id)
	# A entrada compartilhada não pode sacar nem ativar uma arma dentro da garagem do Maciota.
	check(await world.session.enter_place("maciota",false), "enter weapon-free garage")
	await settle()
	check(not world.gameplay.state.equip_weapon("pistol"), "garage blocks equipping firearm")
	await press_light()
	check(not world.gameplay.attack_allowed() and not world.gameplay.gun.visible and not world.gameplay.flashlight.is_visible_in_tree(), "light command preserves garage weapon restrictions")
	check(await world.session.leave_place(), "leave garage")
	check(world.gameplay.state.equip_weapon("pistol"), "firearm inventory and use restored outside")
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
