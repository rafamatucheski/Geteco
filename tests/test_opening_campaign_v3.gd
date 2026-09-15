extends SceneTree
## Ponte real filme→desembarque. O filme completo é exercitado no teste runtime.
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures+=1
func run() -> void:
	root.size=Vector2i(1280,720)
	var state:=root.get_node("CampaignState")
	state.reset_campaign(); root.get_node("SaveManager").clear_pending_save()
	root.get_node("SaveManager").set("_save_dir",ProjectSettings.globalize_path("res://cutscenes/opening/v3/review/test_saves/"))
	var world: Node2D=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline:=Time.get_ticks_msec()+65000
	while world.get_node_or_null("ArrivalMission")==null and Time.get_ticks_msec()<deadline: await process_frame
	var arrival:=world.get_node_or_null("ArrivalMission")
	check(arrival!=null,"Missão real inicializada")
	if arrival==null: quit(1); return
	while not is_instance_valid(arrival._opening) and Time.get_ticks_msec()<deadline: await process_frame
	check(is_instance_valid(arrival._opening),"Nova abertura ligada à campanha")
	if not is_instance_valid(arrival._opening): quit(1); return
	check(arrival._opening.get_script().resource_path.ends_with("v3/opening_controller.gd"),"Campanha usa a V3")
	check(paused,"Simulação da cidade pausada durante o filme")
	arrival._opening.seek(arrival._opening.Timeline.TOTAL_DURATION_SECONDS-2)
	# Seek é intencional neste teste da ponte; término vem do relógio, nunca de skip.
	deadline=Time.get_ticks_msec()+18000
	while arrival.phase in ["arrival","disembark","arrival_wait"] and Time.get_ticks_msec()<deadline: await process_frame
	check(state.has_campaign_flag(&"harbor_arrival_seen"),"Término grava a chegada")
	check(not paused,"Controle de pausa devolvido ao mundo")
	check(world.weather.time_of_day>=.21 and world.weather.time_of_day<.24,"Amanhecer preservado no mundo")
	check(world.weather.is_dark and world.weather.weather_state==DayNightWeatherManager.WeatherState.DRIZZLE,"Amanhecer com garoa leve e sem tempestade")
	check(world.weather.get_rain_intensity()<=0.30,"Chegada nunca usa chuva pesada")
	check(arrival.phase=="phone","Desembarque conclui e libera a ligação de Maciota")
	check(world.get_node("Player").visible,"Dante visível após sair do ônibus")
	arrival.answer_phone()
	for i in 4: arrival.advance_dialogue()
	check(state.has_campaign_flag(&"harbor_arrival_call_complete"),"Ligação avança para o primeiro objetivo")
	check(arrival.phase=="meet_maciota","Primeiro objetivo continua disponível")
	var stream:=world.get_node_or_null("ContinuousWorld")
	deadline=Time.get_ticks_msec()+40000
	while stream!=null and stream.building and Time.get_ticks_msec()<deadline: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://cutscenes/opening/v3/review/gameplay_handoff.png")
	print("OPENING_CAMPAIGN_V3 failures=",failures)
	quit(1 if failures else 0)
