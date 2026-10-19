extends Control
## Static workshop card, keyboard/controller navigable without live viewports.
signal action_requested(action: String)
const CATALOG := preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd")
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const BOLD := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const INK := Color("11171d")
const PAPER := Color("f1eee6")
const AMBER := Color("ffbd5d")
const MUTED := Color("9ea8af")
var state: Dictionary = {}
var message := ""
var buttons: Dictionary = {}

func _ready() -> void:
	size=Vector2(900,640)
	custom_minimum_size=size
	_button("back","VOLTAR",Vector2(748,24),Vector2(120,40))
	for i in CATALOG.IDS.size():
		var id := str(CATALOG.IDS[i])
		_button("rival:"+id,str(CATALOG.RIVALS[id].name).to_upper(),Vector2(32+i*140,116),Vector2(132,38))
	for step in 2:
		_button("step:"+str(step),"",Vector2(32,186+step*112),Vector2(528,100))
	_button("start","CORRER PROVA",Vector2(32,522),Vector2(300,58),true)
	_button("prepare","AJUSTAR CARRO",Vector2(348,522),Vector2(252,58))
	_button("install","RECEBER PEÇA",Vector2(616,522),Vector2(252,58))

func _button(id: String, label: String, at: Vector2, extent: Vector2, primary := false) -> void:
	var button := Button.new()
	button.name=id.replace(":","_")
	button.position=at
	button.size=extent
	button.text=label
	button.add_theme_font_override("font",BOLD)
	button.add_theme_font_size_override("font_size",19 if primary else 17)
	for property in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(property,INK if primary else PAPER)
	for mode in ["normal","hover","pressed","disabled","focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color=AMBER if primary and mode!="disabled" else Color("26323b")
		if id.begins_with("step:"): box.bg_color=Color.TRANSPARENT
		if mode=="hover": box.bg_color=Color("ffd28d") if primary else Color("394a57")
		if mode=="focus": box.bg_color=Color.TRANSPARENT; box.border_color=PAPER; box.set_border_width_all(2)
		box.set_corner_radius_all(3)
		button.add_theme_stylebox_override(mode,box)
	button.pressed.connect(func(): action_requested.emit(id))
	add_child(button)
	buttons[id]=button

func show_state(value: Dictionary) -> void:
	state=value.duplicate(true)
	message=""
	set_busy(false)
	var available: bool=state.get("available",false)
	var proofs: Array=state.get("proofs",[{},{}])
	buttons.start.disabled=not available or not state.get("has_car",false) or (int(state.get("step",0))==1 and proofs[0].is_empty())
	buttons.prepare.disabled=not state.get("has_car",false)
	buttons.install.disabled=not state.get("mastered",false) or not state.get("has_car",false)
	buttons.install.text="INSTALAR PEÇA" if state.get("owned",false) else "RECEBER PEÇA"
	buttons["step:1"].disabled=proofs[0].is_empty()
	buttons.start.text=("REPETIR · " if not proofs[int(state.get("step",0))].is_empty() else "CORRER · ")+"%d M"%int(state.get("distance",201))
	queue_redraw()

func set_busy(busy: bool) -> void:
	for button in buttons.values(): button.disabled=busy
	if busy: set_message("Preparando a concentração…")

func set_message(value: String) -> void:
	message=value
	queue_redraw()

func _label(at: Vector2, text: String, height: int, color := PAPER, strong := true, width := -1.0) -> void:
	draw_string(BOLD if strong else FONT,at,tr(text),HORIZONTAL_ALIGNMENT_LEFT,width,height,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	draw_rect(Rect2(0,0,900,4),AMBER)
	_label(Vector2(32,39),"OFICINA DA RETA",15,MUTED)
	_label(Vector2(32,85),"DESAFIOS DOS RIVAIS",39)
	if state.is_empty(): return
	var rival := str(state.rival_id)
	var proofs: Array=state.get("proofs",[{},{}])
	for i in 6:
		if CATALOG.IDS[i]==rival: draw_rect(Rect2(32+i*140,157,132,3),AMBER)
	for step in 2:
		var y := 186.0+step*112.0
		draw_rect(Rect2(32,y,528,100),Color("2d3740") if step==int(state.step) else Color("192229"))
		if step==int(state.step): draw_rect(Rect2(32,y,3,100),AMBER)
		var goal := CATALOG.goal(rival,step)
		_label(Vector2(48,y+26),"%02d · %s"%[step+1,str(goal.name).to_upper()],20,AMBER if step==int(state.step) else PAPER)
		_label(Vector2(465,y+26),"FEITO" if not proofs[step].is_empty() else "%d M"%int(goal.distance),15,MUTED)
		draw_multiline_string(FONT,Vector2(48,y+53),tr(str(goal.objective)),HORIZONTAL_ALIGNMENT_LEFT,492,18,2,PAPER)
	_label(Vector2(590,205),"%d / 2 PROVAS"%int(state.stamps),24,AMBER)
	_label(Vector2(590,235),"PEÇA CONQUISTADA" if state.mastered else "PRÓXIMA RECOMPENSA",14,MUTED)
	draw_multiline_string(BOLD,Vector2(590,267),str(state.reward_label),HORIZONTAL_ALIGNMENT_LEFT,278,24,2,PAPER)
	draw_multiline_string(FONT,Vector2(590,335),tr(str(state.reward_effect)),HORIZONTAL_ALIGNMENT_LEFT,278,17,4,MUTED)
	var vehicle := str(state.get("car_name","Entre em um carro para correr"))
	_label(Vector2(32,431),vehicle.to_upper(),19,PAPER,true,836)
	var tip := "Seu objetivo vale mesmo se o rival chegar antes. Os dois carimbos liberam a peça."
	if not state.available:
		var index := CATALOG.IDS.find(rival)
		tip="Conclua os dois desafios de "+str(CATALOG.RIVALS[CATALOG.IDS[index-1]].name)+" para liberar."
	elif rival=="jessica" and not state.get("reference",{}).is_empty():
		tip="Referência: %.3f s. Para mudar carro ou acerto, corra a prova 01 de novo."%float(state.reference.seconds)
	_label(Vector2(32,461),tip,17,MUTED,false,836)
	_label(Vector2(32,491),tr("Melhore seu recorde em mais de 0,01 s: R$ 200 · %d bônus restantes")%int(state.bonuses_left),17,AMBER,false,836)
	_label(Vector2(32,613),message if not message.is_empty() else "Dois desafios liberam a peça. Retire cópias para outros carros aqui, sem custo.",17,AMBER if not message.is_empty() else MUTED,false,836)
