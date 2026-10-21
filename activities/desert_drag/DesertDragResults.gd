extends Control
## A finished attempt remains inspectable until the player chooses where to go.
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const REGULAR := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const INK := Color("11161c")
const TEXT := Color("f5f2ea")
const MUTED := Color("9ba7b0")
const ACCENT := Color("ff633b")
signal action_requested(action: String)
var result: Dictionary = {}
var rival_name := ""
var message := ""
var buttons: Array[Button] = []
var telemetry_button: Button
var telemetry_open := false

func _ready() -> void:
	custom_minimum_size=Vector2(740,480)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_STOP
	for item in [["rematch","REVANCHE"],["entry","VOLTAR À ENTRADA"],["stay","FICAR AQUI"]]:
		var button := Button.new()
		button.name=str(item[0])
		button.text=str(item[1])
		button.position=Vector2(32+buttons.size()*228,366)
		button.size=Vector2(220,62)
		button.add_theme_font_override("font",FONT)
		button.add_theme_font_size_override("font_size",20)
		button.add_theme_color_override("font_color",INK if buttons.is_empty() else TEXT)
		button.add_theme_color_override("font_hover_color",INK)
		button.add_theme_color_override("font_focus_color",INK if buttons.is_empty() else TEXT)
		button.add_theme_color_override("font_pressed_color",INK)
		for state in ["normal","hover","pressed","disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color=ACCENT if buttons.is_empty() or state in ["hover","pressed"] else Color("222b34")
			if state=="disabled": style.bg_color=Color("222b34")
			style.set_corner_radius_all(3)
			button.add_theme_stylebox_override(state,style)
		var focus := StyleBoxFlat.new()
		focus.bg_color=Color.TRANSPARENT
		focus.border_color=TEXT
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(3)
		button.add_theme_stylebox_override("focus",focus)
		button.pressed.connect(func(): _activate(str(item[0])))
		add_child(button)
		buttons.append(button)
	for i in buttons.size():
		var next := buttons[(i+1)%buttons.size()]
		var previous := buttons[(i+buttons.size()-1)%buttons.size()]
		buttons[i].focus_neighbor_right=buttons[i].get_path_to(next)
		buttons[i].focus_next=buttons[i].get_path_to(next)
		buttons[i].focus_neighbor_left=buttons[i].get_path_to(previous)
		buttons[i].focus_previous=buttons[i].get_path_to(previous)
	telemetry_button=Button.new()
	telemetry_button.name="Telemetry"
	telemetry_button.text="VER PASSAGEM"
	telemetry_button.position=Vector2(558,22)
	telemetry_button.size=Vector2(150,30)
	telemetry_button.add_theme_font_override("font",FONT)
	telemetry_button.add_theme_font_size_override("font_size",15)
	telemetry_button.pressed.connect(func(): telemetry_open=not telemetry_open; telemetry_button.text="VER RESULTADO" if telemetry_open else "VER PASSAGEM"; queue_redraw())
	add_child(telemetry_button)
	buttons[2].focus_next=buttons[2].get_path_to(telemetry_button)
	buttons[0].focus_previous=buttons[0].get_path_to(telemetry_button)
	telemetry_button.focus_next=telemetry_button.get_path_to(buttons[0])
	telemetry_button.focus_previous=telemetry_button.get_path_to(buttons[2])
	telemetry_button.focus_neighbor_bottom=telemetry_button.get_path_to(buttons[1])

func show_result(value: Dictionary, opponent: String) -> void:
	result=value.duplicate(true)
	rival_name=opponent
	message=""
	telemetry_open=false
	telemetry_button.text="VER PASSAGEM"
	telemetry_button.visible=not result.get("telemetry",{}).is_empty()
	buttons[2].focus_next=buttons[2].get_path_to(telemetry_button if telemetry_button.visible else buttons[0])
	buttons[0].focus_previous=buttons[0].get_path_to(telemetry_button if telemetry_button.visible else buttons[2])
	buttons[0].text=("REPETIR NOITE" if result.get("night_done",false) else "CONTINUAR") if result.get("night",false) else "REVANCHE"
	buttons[1].text="VER A NOITE" if result.get("night",false) else "VOLTAR À ENTRADA"
	if result.get("challenge",false):
		buttons[0].text="PRÓXIMA PROVA" if int(result.get("challenge_step",0))==0 and result.get("challenge_success",false) else "REPETIR PROVA"
		buttons[1].text="VER DESAFIOS"
	set_busy(false)
	queue_redraw()
	_focus_primary.call_deferred()

func _activate(action: String) -> void:
	if result.get("challenge",false):
		if action=="rematch": action="challenge_continue"
		elif action=="entry": action="challenge_overview"
	elif result.get("night",false):
		if action=="rematch": action="night_repeat" if result.get("night_done",false) else "night_continue"
		elif action=="entry": action="night_overview"
	action_requested.emit(action)

func _focus_primary() -> void:
	if is_visible_in_tree() and not buttons.is_empty(): buttons[0].grab_focus()

func set_busy(busy: bool) -> void:
	for button in buttons: button.disabled=busy
	if is_instance_valid(telemetry_button): telemetry_button.disabled=busy
	message="Preparando a entrada…" if busy else ""
	queue_redraw()

func set_message(value: String) -> void:
	message=value
	queue_redraw()

func _label(at: Vector2, value: String, height: int, color := TEXT, strong := true) -> void:
	draw_string(FONT if strong else REGULAR,at,tr(value),HORIZONTAL_ALIGNMENT_LEFT,-1,height,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	draw_rect(Rect2(0,0,size.x,4),ACCENT)
	draw_rect(Rect2(0,0,size.x,size.y),Color("35424d"),false,1)
	var night: bool=bool(result.get("night",false))
	var challenge: bool=bool(result.get("challenge",false))
	var heading := "BATERIA LIVRE   /   #27   /   800 M" if result.get("casual",false) else "ARRANCADA   /   800 M"
	if night: heading="NOITE DE ACERTO   /   %d DE 3   /   %d M"%[int(result.get("night_round",1)),int(result.get("distance",800))]
	if challenge: heading="DESAFIO   /   PROVA %d   /   %d M"%[int(result.get("challenge_step",0))+1,int(result.get("distance",800))]
	if result.get("return_mode",false): heading="IDA E VOLTA   /   %d M"%ceili(float(result.get("distance",0)))
	_label(Vector2(32,40),heading,16,MUTED)
	var verdict := "VITÓRIA" if result.get("won",false) else "DERROTA"
	if night:
		verdict=("NOITE VENCIDA" if result.get("night_won",false) else "NOITE CONCLUÍDA") if result.get("night_done",false) else ("PASSAGEM VENCIDA" if result.get("won",false) else "PASSAGEM CONCLUÍDA")
	if challenge: verdict="PEÇA CONQUISTADA" if result.get("challenge_new_mastery",false) else ("PROVA CUMPRIDA" if result.get("challenge_success",false) else "TENTE OUTRO ACERTO")
	_label(Vector2(32,109),verdict,42 if night or challenge else 60)
	var player_time := float(result.get("seconds",0.0))
	var opponent_time := float(result.get("rival_seconds",-1.0))
	var gap := absf(player_time-opponent_time)
	# Modelos de tradução não casam texto que começa por número: a palavra é
	# traduzida antes de se juntar ao número.
	var detail := "%.3f s %s"%[gap,tr("À FRENTE" if result.get("won",false) else "ATRÁS")] if opponent_time>0 else "RIVAL NÃO COMPLETOU"
	if challenge: detail=str(result.get("challenge_detail",detail))
	_label(Vector2(34,144),detail,17 if challenge else 20,ACCENT)
	draw_line(Vector2(32,170),Vector2(708,170),Color("35424d"),1)
	if telemetry_open:
		_draw_telemetry()
		_label(Vector2(32,457),message if not message.is_empty() else "Esc / B  Ficar aqui",16,MUTED,false)
		return
	_label(Vector2(32,202),"DANTE",18,MUTED)
	_label(Vector2(394,202),rival_name.to_upper(),18,MUTED)
	_label(Vector2(32,257),"%.3f"%player_time,46)
	_label(Vector2(394,257),"%.3f"%opponent_time if opponent_time>0 else "DNF",46)
	# A unidade segue a largura do tempo; a coluna fixa deixava ~70 px de vão.
	_label(Vector2(40+FONT.get_string_size("%.3f"%player_time,HORIZONTAL_ALIGNMENT_LEFT,-1,46).x,254),"s",22,MUTED)
	if opponent_time>0: _label(Vector2(402+FONT.get_string_size("%.3f"%opponent_time,HORIZONTAL_ALIGNMENT_LEFT,-1,46).x,254),"s",22,MUTED)
	var telemetry: Dictionary=result.get("telemetry",{})
	if not telemetry.is_empty():
		_label(Vector2(32,281),"%s · %s · nitro %.1f s"%[str(telemetry.get("launch","")),String(tr("%d boas trocas"))%int(telemetry.get("good_shifts",0)),float(telemetry.get("nitro_seconds",0.0))],15,MUTED,false)
	draw_line(Vector2(364,190),Vector2(364,268),Color("35424d"),1)
	var record_label := "SEM PONTOS NO RANKING" if result.get("casual",false) else String(TranslationServer.translate("SEU RECORDE   %.3f s")) %float(result.get("best_seconds",player_time))
	if night: record_label="%s   %.3f s"%["NOVO RECORDE" if result.get("record_improved",false) else "RECORDE DO ACERTO",float(result.get("best_seconds",player_time))]
	if challenge: record_label=("NOVO RECORDE   %.3f s"%float(result.get("best_seconds",player_time))) if result.get("record_improved",false) else "PROVA %02d · %s"%[int(result.get("challenge_step",0))+1,"CUMPRIDA" if result.get("challenge_success",false) else "OBJETIVO PENDENTE"]
	_label(Vector2(32,307),record_label,19,MUTED)
	if challenge:
		var note := "Ajuste o carro e tente novamente. Seus carimbos conquistados continuam salvos."
		if result.get("challenge_done",false): note=str(result.get("challenge_reward","Peça"))+" · disponível para instalar"
		elif result.get("challenge_success",false): note="1 / 2 provas. Complete a próxima para conquistar a peça."
		if int(result.get("reward_paid",0))>0: _label(Vector2(478,307),"+ R$ %d"%int(result.reward_paid),20,ACCENT)
		elif int(result.get("reward_pending",0))>0: _label(Vector2(478,307),"R$ %d PENDENTES"%int(result.reward_pending),17,ACCENT)
		_label(Vector2(32,340),note,16,MUTED,false)
	elif night:
		_label(Vector2(394,307),"%d / 3 PONTOS"%int(result.get("night_points",0)),23,ACCENT)
		var note := "Mesmo carro. Prepare o próximo trecho no quadro da noite."
		if int(result.get("night_pass",1))==2: note="Outra passagem de 402 m com o mesmo acerto. Vale seu melhor tempo."
		elif result.get("night_done",false):
			note="R$ %d recebidos"%int(result.get("reward_paid",0))
			var pending: int=int(result.get("reward_pending",0))
			if pending>0: note+=" · R$ %d pendentes na próxima visita"%pending
			if result.get("night_merit",false): note+=" · +1 prova distinta na oficina"
		elif float(result.get("night_consistency",-1.0))>=0.0: note="Diferença entre as passagens: %.3f s. Agora, o desafio de 800 m."%float(result.night_consistency)
		_label(Vector2(32,340),note,16,MUTED,false)
	elif result.get("first_win",false):
		_label(Vector2(394,307),"RIVAL SUPERADO",19,ACCENT)
	elif result.get("won",false) and not result.get("casual",false):
		_label(Vector2(394,307),"REVANCHE VENCIDA",19,ACCENT)
	if not night and not challenge and not telemetry.is_empty() and str(result.get("instrument_unlock","")).is_empty(): _label(Vector2(32,340),str(telemetry.get("advice","")),16,MUTED,false)
	if not str(result.get("instrument_unlock","")).is_empty():
		_label(Vector2(32,340),"NOVO PAINEL DISPONÍVEL: "+str(result.instrument_unlock).to_upper(),16,ACCENT)
	_label(Vector2(32,457),message if not message.is_empty() else "Esc / B  Ficar aqui",16,MUTED,false)

func _draw_telemetry() -> void:
	var data: Dictionary=result.get("telemetry",{})
	_label(Vector2(32,202),"SUA PASSAGEM",18,MUTED)
	_label(Vector2(32,230),"%s · %s"%[str(data.get("launch","")),String(tr("%d boas / %d erros"))%[int(data.get("good_shifts",0)),int(data.get("bad_shifts",0))]],20)
	_label(Vector2(32,260),"Limitador %.2f s · nitro %.2f s · máxima %.0f km/h"%[float(data.get("limiter_seconds",0)),float(data.get("nitro_seconds",0)),float(data.get("top_kmh",0))],18,MUTED,false)
	var splits: Dictionary=data.get("splits",{})
	var labels: Array[String]=[]
	for metres in ["60","201","402","800"]:
		if splits.has(metres): labels.append("%s m  %.3f s"%[metres,float(splits[metres])])
	_label(Vector2(32,296),"   ·   ".join(labels),17,ACCENT)
	_label(Vector2(32,340),str(data.get("advice","")),16,MUTED,false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED: queue_redraw()
