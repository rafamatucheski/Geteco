extends "res://tests/measure/measure.gd"
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var output := "res://artifacts/hud-layout-20261027/before"
var final_check := false
var issues: Array[String] = []

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg=="--after": output="res://artifacts/hud-layout-20261027/after"; final_check=true
	DirAccess.make_dir_recursive_absolute(output)
	seed(27102026)
	var settings = root.get_node("V2Settings")
	settings.window_mode=0; settings.resolution=0; settings.vsync=true; settings.fps_limit=1; settings.apply_settings()
	world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene=world
	if not await STARTUP.wait_for_startup(world): push_error("HUD_LAYOUT startup"); quit(2); return
	world.player.teleport(Vector3(132,.15,72)); world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.camera.target_size=38
	world.session.weather.set_process(false); world.session.weather.time_of_day=.4; world.session.weather.weather_state=0; world.session.weather._update()
	print("HUD_LAYOUT_READY")
	var warm: Array[float]=[]
	var frames_ms: Array[float]=[]
	var begin:=Time.get_ticks_usec(); var last:=begin; var total:=0.0
	while total<30000:
		await process_frame
		var now:=Time.get_ticks_usec(); var ms:=(now-last)/1000.0; last=now
		if now-begin<8000000: warm.append(ms)
		else: frames_ms.append(ms); total+=ms
	var report:={"summary":stats(frames_ms),"warmup":stats(warm),"frames_ms":frames_ms,"warmup_ms":warm,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"resolution":str(root.size),"population":world.people.size()}
	FileAccess.open(output.path_join("timing.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("HUD_LAYOUT_TIMING ",JSON.stringify(report.summary))
	# Directed presentation combinations, after measuring normal Main gameplay.
	var hud=world.hud
	hud.set_process(false)
	var audio=world.production.world_audio
	audio.set_process(false); audio.radio_index=1; audio._show_station(); audio.radio_notice.modulate.a=1
	hud.radio_label.text="Rádio · Todas as unidades, o suspeito segue pela rodoviária em direção ao porto."
	hud.radio_label.show()
	hud.stars_label.text="[right]★★★★  Busca[/right]"; hud.stars_label.show(); hud.search_progress.show()
	hud.current_objective_label.text="Converse com Maciota na garagem."; hud.current_objective.show()
	hud.player_status.update_status(82,65,{"visible":true,"temperature":42,"text":"Protegido do frio","key":"protected"},1)
	hud.objective_card.present("Encontre a pista de Vicente na garagem.","Novo objetivo",60)
	hud.feedback_card.present("O veículo está pronto para retirada.","",60)
	hud.interaction_row.update_prompt("Pedir o malote pelo rádio da cooperativa","interact",root.get_node("GameInput"))
	for extent in [Vector2i(1280,720),Vector2i(800,600),Vector2i(1920,1080)]:
		root.content_scale_size=extent; root.size=extent
		await settle(hud)
		await capture_layout("busy-"+str(extent.x),hud,audio)
	root.content_scale_size=Vector2i(800,600); root.size=Vector2i(800,600)
	world.session.show_speech("Maciota","Dante, o carro está pronto. Passe na garagem antes de seguir para o porto.",20)
	await settle(hud)
	await capture_layout("speech-800",hud,audio)
	var caption=world.session.speech_caption
	for node in [hud.interaction_row,hud.minimap,hud.current_objective,hud._lower_right]:
		if node.is_visible_in_tree() and node.get_global_rect().intersects(caption.get_global_rect()): issues.append("speech-800: caption overlaps "+node.name)
	world.session.clear_speech()
	hud.set_process(true)
	await settle(hud)
	if world.session.equipment_wheel.open():
		await settle(hud)
		if hud.root_control.is_visible_in_tree(): issues.append("wheel: gameplay HUD remains visible beneath wheel")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("wheel-800.png"))
		world.session.equipment_wheel.cancel()
	await settle(hud)
	if not hud.root_control.is_visible_in_tree(): issues.append("wheel: gameplay HUD did not return")
	FileAccess.open(output.path_join("layout-issues.json"),FileAccess.WRITE).store_string(JSON.stringify(issues,"\t"))
	print("HUD_LAYOUT_ISSUES ",JSON.stringify(issues))
	world.queue_free(); await process_frame
	quit(1 if final_check and not issues.is_empty() else 0)

func settle(hud) -> void:
	for i in 12:
		await process_frame
		hud._layout()
		if not hud.interaction_row.has_method("layout_in_rect"): hud.interaction_row.follow_actor(world.player,world.camera,Vector2(root.size))

func capture_layout(id: String,hud,audio) -> void:
	var nodes: Array=[hud.player_status,hud._upper_right,hud.minimap,hud.current_objective,hud._notifications,hud.radio_label,audio.radio_notice,hud.interaction_row,hud._lower_right]
	var rects:={}
	for node in nodes:
		if not node.is_visible_in_tree(): continue
		var rect: Rect2=node.get_global_rect()
		rects[str(node.name)]={"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y}
		if not Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect): issues.append(id+": out of bounds "+node.name)
	for i in nodes.size():
		for j in range(i+1,nodes.size()):
			var a: Control=nodes[i]; var b: Control=nodes[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a) or not a.is_visible_in_tree() or not b.is_visible_in_tree(): continue
			if a.get_global_rect().intersects(b.get_global_rect()): issues.append(id+": "+a.name+" overlaps "+b.name)
	FileAccess.open(output.path_join(id+".json"),FileAccess.WRITE).store_string(JSON.stringify(rects,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))
