extends CanvasLayer
## Native canvas with remappable gameplay actions and mouse/touch buttons.
var adapter
var game = preload("res://world/places/bars/BarGames.gd").new()
var root_control: Control
var board: Control
var heading: Label
var hint: Label
var panel: PanelContainer
var paused := false
var armed := false
var touch := Vector2.ZERO
var shot_button: Button
var clock := 0.0
var aim_hold := 0.0
const ART := "res://assets/places/bars/ui/"
var table_art: Texture2D
var cue_art: Texture2D
## Área de jogo da pintura da mesa (tools/build_bar_textures.py mede até a borda de fora da
## tabela); o recuo põe a tabela da física no nariz da almofada pintada, e as caçapas da física
## continuam dentro das pintadas.
const FELT := Rect2(Vector2(.031,.0643),Vector2(.9374,.8647))
const FELT_INSET := Vector2(.0117,.0234)
var ball_art: Array[Texture2D] = []
var dart_art: Texture2D

func _ready() -> void:
	layer = 86
	# load() e não preload: um preload de textura ainda não importada derruba a compilação
	# de toda a cadeia de scripts da sessão.
	table_art = load(ART+"pool_table.png")
	cue_art = load(ART+"pool_cue.png")
	for index in 7: ball_art.append(load(ART+"pool_ball_%d.png"%index))
	var place = adapter.get("definition") if adapter is Object else null
	var desert: bool = place is Dictionary and str(place.get("id","")) == "desert_bar"
	dart_art = load(ART+("dart_green.png" if desert else "dart_red.png"))
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	var shade := ColorRect.new()
	shade.color = Color(.012,.018,.015,.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(shade)
	panel = PanelContainer.new()
	root_control.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172720")
	style.border_color = Color("b8a16f")
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size",24)
	column.add_child(heading)
	board = Control.new()
	board.custom_minimum_size = Vector2(260,160)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.draw.connect(_draw_board)
	column.add_child(board)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var row := HBoxContainer.new()
	column.add_child(row)
	shot_button = _button("Jogar",_shoot,row)
	_button("Pausar",func(): paused = not paused,row)
	_button("Recomeçar",func(): game.reset(game.kind); paused = false,row)
	_button("Sair",adapter.close_game,row)
	var directions := HBoxContainer.new()
	column.add_child(directions)
	for item in [["←",Vector2.LEFT],["→",Vector2.RIGHT],["↑",Vector2.UP],["↓",Vector2.DOWN]]:
		var direction: Vector2 = item[1]
		var button := _button(item[0],Callable(),directions)
		button.button_down.connect(func(): touch = direction)
		button.button_up.connect(func(): touch = Vector2.ZERO)
	root_control.resized.connect(_layout)
	_layout()

func _button(text: String, action: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(64,38)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	if action.is_valid(): button.pressed.connect(action)
	parent.add_child(button)
	return button

func _layout() -> void:
	panel.size = Vector2(minf(960,root_control.size.x-20),minf(700,root_control.size.y-20))
	panel.position = (root_control.size-panel.size)*.5

func open_game(kind: String) -> void:
	game.reset(kind)
	paused = false
	armed = false
	clock = 0
	show()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: return false
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		adapter.close_game()
	elif armed and event.is_action_pressed("interact"):
		_shoot()
	return true

func _shoot() -> void:
	if not paused and armed: game.shoot()

func _process(delta: float) -> void:
	if not visible: return
	if not armed and not Input.is_action_pressed("interact"): armed = true
	if not paused and not get_tree().paused:
		clock += delta
		var direction := Input.get_vector("move_left","move_right","move_up","move_down")+touch
		if not game.moving and not game.finished:
			if game.kind == "bar_darts":
				game.aim = (game.aim+direction*delta*.7).limit_length(1.2)
				game.strength = .55+sin(clock*1.8)*.40
			else:
				# A tap nudges a fraction of a degree; holding ramps up to a fast sweep.
				aim_hold = aim_hold+delta if absf(direction.x) > .1 else 0.0
				game.angle += direction.x*delta*lerpf(.12,1.4,smoothstep(.15,.9,aim_hold))
				game.strength = clampf(game.strength-direction.y*delta*.55,.1,1)
		game.step(delta)
	var title := "Dardos" if game.kind == "bar_darts" else "Bilhar"
	heading.text = "%s · %d pontos · %d/%d%s"%[title,game.score,game.shots,9 if game.kind == "bar_darts" else 10," · Fim" if game.finished else (" · Pausado" if paused else "")]
	var controls := get_node_or_null("/root/GameInput")
	var action := "Ação"
	if controls != null: action = str(controls.prompt("interact"))
	hint.text = ("Mova a mira; a cruz sobe e desce sozinha, lance quando ela passar no ponto. %s: lançar. 9 dardos."%action if game.kind == "bar_darts" else "Esquerda/direita: mira (toque para ajuste fino) · cima/baixo: força · %s: tacada. 6 bolas, 10 tacadas, branca na caçapa tira %d."%[action,game.SCRATCH_PENALTY])+"  "+game.status
	shot_button.disabled = paused or game.finished or game.moving
	shot_button.text = "Lançar" if game.kind == "bar_darts" else "Tacada"
	board.queue_redraw()

func _draw_board() -> void:
	var area := board.size
	if game.kind == "bar_darts":
		var center := area*.5
		var radius := minf(area.x*.42,area.y*.40)
		for i in 20:
			var a := -PI*.5-PI/20+i*TAU/20
			var wedge := PackedVector2Array([center])
			for step in 5: wedge.append(center+Vector2.from_angle(a+step*TAU/80)*radius)
			board.draw_colored_polygon(wedge,Color("d9cda8") if i%2 else Color("272b29"))
		for ring in [[.96,.08],[.595,.07]]:
			for i in 20:
				board.draw_arc(center,radius*ring[0],-PI*.5-PI/20+i*TAU/20,-PI*.5+PI/20+i*TAU/20,8,Color("a43b31") if i%2 else Color("41836a"),radius*ring[1])
		board.draw_circle(center,radius*.094,Color("387a5e"))
		board.draw_circle(center,radius*.037,Color("b44130"))
		for i in 20:
			var p := center+Vector2.from_angle(-PI*.5+i*TAU/20)*radius*1.11
			board.draw_string(ThemeDB.fallback_font,p-Vector2(8,-5),str(game.SEGMENTS[i]),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ead9ac"))
		for point in game.marks:
			var hit: Vector2 = center+point*radius
			# Ponta no ponto do acerto e aletas para cima e à esquerda, como cravado no alvo.
			var length := radius*.32
			board.draw_set_transform(hit,PI*.25)
			board.draw_texture_rect(dart_art,Rect2(Vector2(-length,-length*.145),Vector2(length,length*.29)),false)
			board.draw_set_transform(Vector2.ZERO)
			board.draw_circle(hit,2.5,Color("ffba64"))
		var cross: Vector2 = center+(game.aim+Vector2(0,(.55-game.strength)*.65))*radius
		board.draw_line(cross-Vector2(12,0),cross+Vector2(12,0),Color.CYAN,2)
		board.draw_line(cross-Vector2(0,12),cross+Vector2(0,12),Color.CYAN,2)
	else:
		var play := Rect2(FELT.position+FELT_INSET,FELT.size-FELT_INSET*2)
		var scale_factor := minf((area.x-16)*play.size.x/640,(area.y-24)*play.size.y/320)
		var table_size := Vector2(640/play.size.x,320/play.size.y)*scale_factor
		var table_at := (area-table_size)*.5
		board.draw_texture_rect(table_art,Rect2(table_at,table_size),false)
		var origin := table_at+play.position*table_size
		for i in game.balls.size():
			var ball: Dictionary = game.balls[i]
			if ball.sunk: continue
			var at: Vector2 = origin+ball.position*scale_factor
			board.draw_texture_rect(ball_art[i],Rect2(at-Vector2.ONE*10*scale_factor,Vector2.ONE*20*scale_factor),false)
		if not game.moving and not game.finished:
			var cue: Vector2 = origin+game.balls[0].position*scale_factor
			var shot_dir := Vector2.from_angle(game.angle)
			board.draw_dashed_line(cue,cue+shot_dir*_guide_length()*scale_factor,Color("e9cf84",.7),2,8*scale_factor)
			# Stick pulls back with strength so the power reads on the table itself.
			var butt: Vector2 = cue-shot_dir*(14+game.strength*46)*scale_factor
			var stick := 300*scale_factor
			var thick: float = stick*cue_art.get_height()/cue_art.get_width()
			board.draw_set_transform(butt,game.angle)
			board.draw_texture_rect(cue_art,Rect2(Vector2(-stick,-thick*.5),Vector2(stick,thick)),false)
			board.draw_set_transform(Vector2.ZERO)
	board.draw_rect(Rect2(Vector2(8,area.y-8),Vector2((area.x-16)*game.strength,5)),Color("edbd69"))

# Guide stops at the first ball in the line of the shot, or at the cushion.
func _guide_length() -> float:
	var start: Vector2 = game.balls[0].position
	var shot_dir := Vector2.from_angle(game.angle)
	var best := 640.0
	for index in range(1,game.balls.size()):
		if game.balls[index].sunk: continue
		var offset: Vector2 = game.balls[index].position-start
		var along := offset.dot(shot_dir)
		var miss := absf(offset.cross(shot_dir))
		if along > 0 and miss < 20: best = minf(best,along-sqrt(400-miss*miss))
	for limit in [(630-start.x)/shot_dir.x if shot_dir.x > .001 else INF,(10-start.x)/shot_dir.x if shot_dir.x < -.001 else INF,
			(310-start.y)/shot_dir.y if shot_dir.y > .001 else INF,(10-start.y)/shot_dir.y if shot_dir.y < -.001 else INF]:
		best = minf(best,limit)
	return maxf(best,0.0)
