extends Control
## Manual consultável na pausa. Os comandos vêm das configurações atuais.
signal closed
const STYLE = preload("res://ui/GameStyle.gd")
const TOPICS := [
	["Primeiros passos", "Você é Dante. Explore, converse com os personagens e acompanhe os objetivos para avançar na campanha.\n\nComece conversando com Maciota. O diário reúne as missões disponíveis e o objetivo da missão em andamento. As atividades pelo mundo complementam a história; você pode voltar a elas depois.", ["interact", "journal"]],
	["Exploração e mapa", "Aproxime-se de pessoas, entradas e objetos e observe a ação indicada na tela. A ação depende de onde Dante está e do que há por perto.\n\nAbra o mapa / GPS para se orientar. Algumas passagens dependem do avanço da campanha: a continuação para o mapa 2 só abre ao concluir a última missão da primeira cidade. O acesso à montanha é independente dessa obra.", ["interact", "world_map", "sprint", "jump"]],
	["Missões e atividades", "Consulte o diário para escolher uma missão disponível e conferir seu objetivo. Siga as instruções da missão; chegar ao local pode ser apenas uma das etapas.\n\nProcure os pontos de atividade no mundo. Corridas, provas de esqui e colecionáveis oferecem outras formas de explorar. Na montanha também há investigações, uma descida noturna de carro e uma trilha de jipe por checkpoints.", ["journal", "world_map"]],
	["Veículos e garagem", "Aproxime-se de um veículo e confira a ação disponível para entrar. Ao dirigir, você pode acelerar, frear, usar o freio de mão e controlar os faróis.\n\nVisite a garagem do Maciota e interaja para consultar os serviços disponíveis. A garagem é uma área sem armas: Dante guarda a arma ao entrar e volta a poder usá-la ao sair.\n\nO porta-malas permite acessar itens e armas armazenados quando a interação estiver disponível.", ["vehicle_interact", "exit_vehicle", "handbrake", "headlights", "trunk"]],
	["Inventário e cuidados", "Abra o inventário para consultar os itens e equipamentos que Dante carrega. Armas guardadas no porta-malas precisam ser acessadas por lá.\n\nAcompanhe os indicadores do HUD durante a exploração. Consulte seus itens de recuperação e os serviços disponíveis quando precisar se preparar para outra missão.", ["inventory", "weapon_wheel", "interact", "trunk", "unarmed"]],
	["Combate e polícia", "Selecione uma arma, mire e dispare. Recarregue quando necessário e use mãos livres para guardar a arma. Observe os indicadores de munição e saúde.\n\nCrimes e confronto podem atrair a polícia. Acompanhe o estado da perseguição na tela e procure sair do perigo. A ação de rendição permite se entregar quando estiver disponível.", ["weapon_wheel", "interact", "aim", "fire", "reload", "weapon_next", "unarmed", "surrender"]],
	["Coleções e progresso", "No menu de pausa, abra Conquistas e Colecionáveis para consultar o que já encontrou e o que desbloqueou.\n\nUse Salvar jogo quando estiver disponível. Algumas situações, como viagens e transições, impedem salvar temporariamente; o próprio menu informa o motivo. Antes de voltar ao menu principal, você pode escolher salvar seu progresso.", ["pause_game"]],
	["Controles", "Os comandos abaixo refletem suas configurações e o dispositivo em uso ao abrir este tópico. Para mudar teclas ou botões, volte à pausa e abra Configurações → Controles.\n\nUse as setas ou o direcional para navegar pelo guia, confirme para escolher um tópico e use Voltar para retornar à pausa.", ["move_up", "move_down", "move_left", "move_right", "interact", "inventory", "journal", "world_map", "pause_game"]],
]
var topics: ItemList
var article: RichTextLabel
var back: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.name = "GuidePanelFrame"
	var arrange := func(): preload("res://ui/HarborMenuPresentation.gd").fit_panel(margin,size)
	resized.connect(arrange)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.add_child(STYLE.label("Guia do jogo", 28, STYLE.ACCENT))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	topics = ItemList.new()
	topics.custom_minimum_size.x = 190
	topics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topics.size_flags_stretch_ratio = 1
	topics.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for topic in TOPICS: topics.add_item(topic[0])
	body.add_child(topics)
	article = RichTextLabel.new()
	article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article.size_flags_stretch_ratio = 3
	article.focus_mode = Control.FOCUS_ALL
	article.selection_enabled = true
	article.bbcode_enabled = false
	body.add_child(article)
	back = Button.new()
	back.text = "Voltar"
	column.add_child(back)
	back.pressed.connect(close)
	topics.item_selected.connect(show_topic)
	STYLE.apply(self)
	arrange.call_deferred()
	hide()

func open() -> void:
	show()
	topics.select(0)
	show_topic(0)
	STYLE.trap_focus(self, false)
	topics.grab_focus()

func show_topic(index: int) -> void:
	var topic: Array = TOPICS[index]
	var input := GameInput
	article.text = str(topic[0]) + "\n\n" + str(topic[1])
	if index in [4, 5]:
		var wheel_help := "Hold %s to open the weapon wheel and slow down the world. Point at an item with the mouse and release to confirm. While holding the wheel key, press %s to switch between weapons and consumables. Release over a consumable to use one item." if TranslationServer.get_locale().begins_with("en") else "Segure %s para abrir a roda de armas e desacelerar o mundo. Aponte para um item com o mouse e solte a tecla para confirmar. Enquanto segura a roda, aperte %s para alternar entre armas e consumíveis. Ao soltar sobre um consumível, Dante usa uma unidade."
		article.text += "\n\n" + wheel_help % [input.hint("weapon_wheel", true), input.hint("interact", true)]
	article.text += "\n\nComandos\n"
	for action in topic[2]:
		article.text += "%s  ·  %s\n" % [input.label(action), input.hint(action)]
	article.scroll_to_line(0)

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
