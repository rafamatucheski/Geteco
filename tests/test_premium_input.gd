extends SceneTree
## Verifica a entrada independente de dispositivo sem acessar saves pessoais.
const OUT := "res://docs/measurements/premium-ui-0910/"
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n: await process_frame
func key(code: Key,pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func load_done() -> void:
	while root.get_node("GameLoading").active: await process_frame
func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	var temp := OS.get_temp_dir().path_join("geteco_input_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(temp)
	root.get_node("SaveManager")._save_dir = temp+"/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SettingsManager")._settings_path = temp.path_join("settings.cfg")
	var sm := root.get_node("SettingsManager")
	sm.window_mode = 0
	sm.resolution = Vector2i(1280,720)
	sm.text_scale = 1.0
	sm.apply_all_settings()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete"]: campaign.set_campaign_flag(flag,true)
	root.get_node("GameLoading").begin("res://world/harbor/HarborGame.tscn")
	await load_done()
	await frames(8)
	var player: Node2D = current_scene.get_node("Player")
	var controls := root.get_node("GameInput")
	var remap := InputEventKey.new()
	remap.keycode = KEY_I
	remap.physical_keycode = KEY_I
	check(controls.rebind("move_up",remap).is_empty(),"movimento aceita remapeamento")
	key(KEY_I,true)
	await frames(3)
	check(controls.movement().y < -0.9,"nova tecla produz movimento")
	key(KEY_I,false)
	await frames(2)
	key(KEY_W,true)
	await frames(2)
	check(controls.movement().is_zero_approx(),"W não mantém atalho escondido após remapear")
	key(KEY_W,false)
	await frames(2)
	sm.save_settings()
	controls.reset_bindings()
	sm.load_settings()
	check(controls.hint("move_up",true) == "I","remapeamento persiste em disco")
	controls.reset_bindings()
	var pad := InputEventJoypadMotion.new()
	pad.axis = JOY_AXIS_LEFT_X
	pad.axis_value = 0.8
	Input.parse_input_event(pad)
	await frames(3)
	check(controls.using_gamepad and controls.movement().x>0.5,"analógico gera movimento e troca dicas")
	var release_pad := pad.duplicate() as InputEventJoypadMotion
	release_pad.axis_value = 0
	Input.parse_input_event(release_pad)
	await frames(2)
	controls.using_gamepad = false
	await shot("14_touch_preview")
	check(current_scene.get_node("Minimap").panel.get_global_rect().position.y<400,"mapa libera canto de movimento no perfil de toque")
	# Confere a troca real pelo loader para a cena destinada aos saves anteriores.
	root.get_node("GameLoading").begin("res://legacy/Main.tscn")
	await load_done()
	check(current_scene.scene_file_path == "res://legacy/Main.tscn" and not paused,"loader também libera a cena legada")
	change_scene_to_file("res://ui/MainMenu.tscn")
	await frames(10)
	root.size = Vector2i(1920,810)
	root.content_scale_size = root.size
	await shot("15_menu_ultrawide_final")
	print("PREMIUM INPUT: ",failures," falha(s)")
	quit(0 if failures == 0 else 1)
