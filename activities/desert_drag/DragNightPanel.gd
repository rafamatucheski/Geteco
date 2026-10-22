extends Control
## Static event card: no per-frame work or extra render target.
signal action_requested(action: String)
const BOLD := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const PROGRESS := preload("res://activities/desert_drag/DragNightProgress.gd")
const CATALOG := preload("res://activities/desert_drag/DragNightCatalog.gd")
const AMBER := Color("ffbd5d")
const INK := Color("11171d")
const PAPER := Color("f1eee6")
const MUTED := Color("9ea8af")
var state: Dictionary = {}
var opponent := ""
var car_name := ""
var message := ""
var buttons: Dictionary = {}

func _ready() -> void:
	custom_minimum_size=Vector2(900,640)
	size=custom_minimum_size
	_button("back","VOLTAR",Vector2(748,24),Vector2(120,40))
	_button("continue","COMEÇAR A NOITE",Vector2(32,522),Vector2(400,58),true)
	_button("prepare","PREPARAR CARRO",Vector2(448,522),Vector2(252,58))
	_button("abandon","ENCERRAR",Vector2(716,522),Vector2(152,58))
	for i in 3:
		var preset: String=["rua","drag","terra"][i]
		_button("preset:"+preset,preset.to_upper(),Vector2(500+i*122,402),Vector2(112,38))
	for i in 3:
		var category: String=["livre","street","prepared"][i]
		_button("category:"+category,["LIVRE","R$ 6 MIL","R$ 12 MIL"][i],Vector2(500+i*122,338),Vector2(112,32))

func _button(id: String, label: String, point: Vector2, extent: Vector2, primary := false) -> void:
	var button := Button.new()
	button.name=id.replace(":","_")
	button.text=label
	button.position=point
	button.size=extent
	button.add_theme_font_override("font",BOLD)
	button.add_theme_font_size_override("font_size",20 if primary else 17)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,INK if primary else PAPER)
	button.add_theme_color_override("font_disabled_color",Color("64717a"))
	for name in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color=AMBER if primary and name!="disabled" else Color("27323b")
		if name=="hover": style.bg_color=Color("ffd28d") if primary else Color("3a4853")
		if name=="focus":
			style.bg_color=Color.TRANSPARENT
			style.border_color=PAPER
			style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(name,style)
	button.pressed.connect(func(): action_requested.emit(id))
	add_child(button)
	buttons[id]=button

func show_state(value: Dictionary, rival_name: String, vehicle_name: String, presets: Dictionary) -> void:
	state=value.duplicate(true)
	opponent=rival_name
	car_name=vehicle_name
	message=""
	set_busy(false)
	var step: int=int(state.get("step",0))
	buttons["continue"].text="CONTINUAR · %d M"%int(PROGRESS.DISTANCES[step]) if state.get("has_episode",false) else "COMEÇAR A NOITE"
	buttons.abandon.disabled=not state.get("has_episode",false)
	buttons.prepare.disabled=step==2
	for preset in ["rua","drag","terra"]:
		buttons["preset:"+preset].disabled=step==2 or not presets.has(preset)
	for category in ["livre","street","prepared"]:
		buttons["category:"+category].disabled=state.get("has_episode",false)
		buttons["category:"+category].text=("✓ " if state.get("category","livre")==category else "")+{"livre":"LIVRE","street":"R$ 6 MIL","prepared":"R$ 12 MIL"}[category]
	queue_redraw()
	buttons["continue"].grab_focus()

func set_message(value: String) -> void:
	message=value
	queue_redraw()

func set_busy(busy: bool) -> void:
	for button in buttons.values(): button.disabled=busy
	if busy: set_message("Preparando a concentração…")

func _label(point: Vector2, value: String, height: int, color := PAPER, strong := true, width := -1.0) -> void:
	draw_string(BOLD if strong else FONT,point,tr(value),HORIZONTAL_ALIGNMENT_LEFT,width,height,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	draw_rect(Rect2(0,0,900,4),AMBER)
	_label(Vector2(32,39),"ENCONTRO DO DESERTO",15,MUTED)
	_label(Vector2(32,85),"NOITE DE ACERTO",40)
	_label(Vector2(500,85),opponent.to_upper(),29,AMBER)
	draw_line(Vector2(32,105),Vector2(868,105),Color("35424c"),1)
	var step: int=int(state.get("step",0))
	var runs: Array=state.get("results",[])
	for i in 4:
		var y := 126.0+i*80.0
		draw_rect(Rect2(32,y,430,68),Color("2c353c") if i==step else Color("192229"))
		if i==step: draw_rect(Rect2(32,y,3,68),AMBER)
		_label(Vector2(48,y+27),"%02d  %s"%[PROGRESS.ROUNDS[i],str(PROGRESS.LABELS[i]).to_upper()],18,AMBER if i==step else PAPER)
		_label(Vector2(48,y+52),"%d M"%int(PROGRESS.DISTANCES[i]),17,MUTED)
		if runs.size()>i:
			_label(Vector2(230,y+52),"%.3f s  /  %.3f s"%[runs[i].seconds,runs[i].rival_seconds],17)
		elif i==step: _label(Vector2(293,y+52),"PRÓXIMA",16,AMBER)
	_label(Vector2(500,137),car_name.to_upper(),19,PAPER,true,365)
	_label(Vector2(500,165),"MESMO CARRO NAS QUATRO PASSADAS",14,MUTED)
	var spec := CATALOG.get_rival(str(state.get("rival_id","digo")))
	_label(Vector2(500,209),str(spec.specialty).to_upper(),21,AMBER)
	draw_multiline_string(FONT,Vector2(500,237),tr(str(spec.advice)),HORIZONTAL_ALIGNMENT_LEFT,358,20,2,PAPER)
	_label(Vector2(500,301),"MELHOR DE 2 × 402 M DECIDE A MARCA",15,MUTED)
	_label(Vector2(500,328),"CATEGORIA · ACERTO ATUAL R$ %d"%int(state.get("preparation_value",0)),14,MUTED)
	_label(Vector2(500,382),"APLICAR AJUSTE SALVO",14,MUTED)
	_label(Vector2(32,479),String(TranslationServer.translate("%d / 3 PONTOS"))%int(state.get("points",0)),25,AMBER)
	_label(Vector2(500,479),"R$ 600 + R$ 300 PELA VITÓRIA",19,PAPER)
	var footer := "A primeira noite vencida conta como uma prova distinta na oficina."
	if str(state.get("category","livre"))!="livre": footer="Teto das peças instaladas para ambos. Peças conquistadas têm valor de referência."
	if step==2: footer="Mantenha o acerto nas duas passagens de 402 m para comparar seus tempos."
	_label(Vector2(32,612),message if not message.is_empty() else footer,17,AMBER if not message.is_empty() else MUTED,false,836)
