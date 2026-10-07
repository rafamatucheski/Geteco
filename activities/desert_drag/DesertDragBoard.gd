extends Control
## Static NPC photos and handwritten chalk. Race progress stays in the save ledger.
signal closed
signal race_requested(identity: String)
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const NAMES := ["Digo","Lívia","Raul","Jessica","Nadir"]
var handwriting: Font
var photos: Dictionary = {}
var wins: Array = []
var selected := "digo"
var current := "digo"
var strike: Dictionary = {}
var rows: Array[Button] = []
var race_button: Button
var message := ""
var _animation: Tween

func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/caveat/Caveat.ttf"):
		handwriting=load("res://assets/fonts/caveat/Caveat.ttf")
	else:
		handwriting=FontFile.new()
		handwriting.load_dynamic_font("res://assets/fonts/caveat/Caveat.ttf")
	for id in PROGRESS.RIVALS:
		# Loading PNG bytes also supports first-run capture before editor imports.
		var path: String="res://assets/desert_drag/portraits/"+id+".png"
		photos[id]=load(path) if ResourceLoader.exists(path) else ImageTexture.create_from_image(Image.load_from_file(path))
	custom_minimum_size=Vector2(900,640)
	size=custom_minimum_size
	resized.connect(queue_redraw)
	for i in PROGRESS.RIVALS.size():
		var row := Button.new()
		row.name=PROGRESS.RIVALS[i]
		row.position=Vector2(40,112+i*86)
		row.size=Vector2(470,80)
		row.flat=true
		row.tooltip_text=NAMES[i]
		row.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		row.add_theme_stylebox_override("hover",_style(Color(1,1,1,.06)))
		row.add_theme_stylebox_override("pressed",_style(Color(1,1,1,.10)))
		row.add_theme_stylebox_override("focus",_style(Color(1,1,1,.08)))
		row.pressed.connect(select_rival.bind(str(PROGRESS.RIVALS[i])))
		add_child(row)
		rows.append(row)
	var close := Button.new()
	close.text="Fechar  ×"
	close.position=Vector2(741,27)
	close.size=Vector2(125,42)
	close.pressed.connect(func(): closed.emit())
	add_child(close)
	race_button=Button.new()
	race_button.position=Vector2(561,510)
	race_button.size=Vector2(286,50)
	race_button.add_theme_stylebox_override("normal",_style(Color("e0c892")))
	race_button.add_theme_stylebox_override("hover",_style(Color("f3dfa9")))
	race_button.add_theme_color_override("font_color",Color("263830"))
	race_button.add_theme_font_override("font",handwriting)
	race_button.add_theme_font_size_override("font_size",30)
	race_button.pressed.connect(func(): race_requested.emit(selected))
	add_child(race_button)
	_update_button()

func show_progress(state: Dictionary, newly_won := "") -> void:
	wins=state.get("wins",[]).duplicate()
	current=PROGRESS.RIVALS.back()
	for id in PROGRESS.RIVALS:
		if id not in wins: current=id; break
	selected=current
	message=""
	if _animation: _animation.kill()
	strike.clear()
	for id in wins: strike[id]=0.0 if id==newly_won else 1.0
	if newly_won in wins:
		selected=newly_won
		_animation=create_tween()
		_animation.tween_method(func(value: float): strike[newly_won]=value; queue_redraw(),0.0,1.0,.65).set_delay(.25)
	_update_button()
	rows[PROGRESS.RIVALS.find(selected)].grab_focus()
	queue_redraw()

func select_rival(id: String) -> void:
	if id not in PROGRESS.RIVALS: return
	selected=id
	message=""
	_update_button()
	queue_redraw()

func set_message(text: String) -> void:
	message=text
	queue_redraw()

func _update_button() -> void:
	if race_button==null: return
	race_button.disabled=selected!=current
	race_button.text="Correr" if selected==current else ("Vencido" if selected in wins else "Vença "+NAMES[PROGRESS.RIVALS.find(current)])

func _style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	box.set_corner_radius_all(4)
	return box

func _draw() -> void:
	if handwriting==null: return
	draw_style_box(_style(Color(0,0,0,.35)),Rect2(9,12,900,640))
	draw_style_box(_style(Color("624936")),Rect2(0,0,900,640))
	draw_rect(Rect2(12,12,876,616),Color("283e37"))
	draw_rect(Rect2(18,18,864,604),Color("243a33"))
	# Deterministic faint chalk grain; no textures or per-frame background work.
	for i in 110:
		var x := 26.0+fmod(float(i*137),844.0)
		var y := 23.0+fmod(float(i*71),586.0)
		draw_line(Vector2(x,y),Vector2(minf(x+24,875),y+.4),Color(1,1,1,.025),1)
	var chalk := Color("ede8d3")
	draw_string(handwriting,Vector2(43,76),"Arrancadas",HORIZONTAL_ALIGNMENT_LEFT,-1,52,chalk)
	draw_string(handwriting,Vector2(535,69),"%d / 5"%wins.size(),HORIZONTAL_ALIGNMENT_LEFT,-1,31,Color("d5bf88"))
	draw_line(Vector2(42,92),Vector2(856,94),Color(chalk,.38),1.5,true)
	draw_line(Vector2(530,114),Vector2(527,562),Color(chalk,.2),1,true)
	for i in PROGRESS.RIVALS.size():
		var id: String=PROGRESS.RIVALS[i]
		var y := 118.0+float(i)*86
		if id==selected: draw_style_box(_style(Color(1,1,1,.07)),Rect2(40,y-6,470,80))
		draw_rect(Rect2(55,y,66,70),Color("e1d8c3"))
		draw_texture_rect(photos[id],Rect2(59,y+4,58,58),false)
		draw_string(handwriting,Vector2(140,y+45),"%02d"%(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("b6b8a0"))
		draw_string(handwriting,Vector2(192,y+47),NAMES[i],HORIZONTAL_ALIGNMENT_LEFT,-1,39,chalk if id==current or id in wins else Color("9ba797"))
		if id in wins: _draw_strike(Vector2(186,y+33),minf(handwriting.get_string_size(NAMES[i],HORIZONTAL_ALIGNMENT_LEFT,-1,39).x+24,275),float(strike.get(id,1.0)))
		elif id==current: draw_string(handwriting,Vector2(456,y+45),"←",HORIZONTAL_ALIGNMENT_LEFT,-1,32,Color("ddc58f"))
	var index := PROGRESS.RIVALS.find(selected)
	draw_rect(Rect2(583,120,240,269),Color("e8dfcb"))
	draw_texture_rect(photos[selected],Rect2(593,130,220,220),false)
	draw_string(handwriting,Vector2(603,380),NAMES[index],HORIZONTAL_ALIGNMENT_LEFT,204,32,Color("343c32"))
	draw_string(handwriting,Vector2(577,438),"800 m",HORIZONTAL_ALIGNMENT_LEFT,-1,33,chalk)
	draw_string(handwriting,Vector2(577,475),"R$ %d"%PROGRESS.reward_amount(selected),HORIZONTAL_ALIGNMENT_LEFT,-1,31,Color("d5bf88"))
	if not message.is_empty():
		draw_multiline_string(ThemeDB.fallback_font,Vector2(45,591),message,HORIZONTAL_ALIGNMENT_LEFT,808,16,2,Color("eed4b7"))

func _draw_strike(at: Vector2, width: float, fraction: float) -> void:
	var points := PackedVector2Array()
	for i in 29:
		var t := minf(float(i)/28.0,fraction)
		points.append(at+Vector2(width*t,sin(t*18.0)*1.5-t*5.0))
		if t>=fraction: break
	if points.size()>1: draw_polyline(points,Color("e8dfcb"),3.0,true)
	if fraction>.65: draw_line(at+Vector2(width*.1,6),at+Vector2(width*(fraction-.65)/.35,2),Color("e8dfcb"),1.5,true)
