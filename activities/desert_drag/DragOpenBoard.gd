extends PanelContainer
signal action_requested(action: String)
var heading: Label
var state_label: Label
var queue_label: Label
var now_button: Button
var cancel_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(900,640)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11171e")
	style.set_content_margin_all(36)
	style.border_color = Color("ffbc55")
	style.border_width_top = 4
	add_theme_stylebox_override("panel",style)
	add_theme_font_override("font",preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"))
	add_theme_font_size_override("font_size",24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	heading = Label.new()
	heading.text = "BATERIAS LIVRES  /  800 M"
	heading.add_theme_font_size_override("font_size",38)
	column.add_child(heading)
	state_label = Label.new()
	column.add_child(state_label)
	queue_label = Label.new()
	queue_label.custom_minimum_size.y = 72
	queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(queue_label)
	now_button = _button(column,"Correr agora","now")
	cancel_button = _button(column,"Sair da fila","cancel")
	var note := Label.new()
	note.text = "Bateria livre: tempo e resultado sem pontos no ranking."
	note.add_theme_font_size_override("font_size",19)
	column.add_child(note)
	_button(column,"Voltar ao ranking","back")

func _button(column: VBoxContainer, title: String, action: String) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.pressed.connect(func(): action_requested.emit(action))
	column.add_child(button)
	return button

func show_ticket(data: Dictionary) -> void:
	var queued: bool = data.queued
	state_label.text = "NA PISTA · "+{"lining":"ALINHANDO","staging":"PREPARANDO A LARGADA","racing":"BATERIA EM ANDAMENTO","finished":"LIBERANDO A PISTA","blocked":"PISTA OBSTRUÍDA","idle":"LIVRE"}.get(str(data.heat),"LIVRE")
	queue_label.text = "INSCRIÇÃO #%02d · %dª POSIÇÃO\nPode esperar a pé. Volte ao carro inscrito quando chegar sua vez."%[int(data.number),int(data.position)] if queued else "Dois carros por bateria. Escolha Correr agora para alinhar com seu adversário."
	if queued and not str(data.get("reason","")).is_empty():
		queue_label.text = "INSCRIÇÃO #%02d · %dª POSIÇÃO\n%s"%[int(data.number),int(data.position),str(data.reason)]
	now_button.text = "Correr agora"
	now_button.disabled = queued
	cancel_button.visible = queued
