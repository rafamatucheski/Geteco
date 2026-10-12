extends Control
const STYLE := preload("res://ui/GameStyle.gd")
const CATALOG := preload("res://gameplay/wine/WineCatalog.gd")
var adapter
var shop := true
var country := "Grécia"
var selected := "zacharias_nemea"
var feedback := ""

func set_voice_message(message: String) -> void:
	feedback = message
	if is_inside_tree() and visible: refresh()
var card: PanelContainer
var status: Label
var drink_button: Button
var buy_button: Button
var details: VBoxContainer

func _ready() -> void:
	name="WinePanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	theme=STYLE.create_theme(16)
	get_viewport().size_changed.connect(_layout)
	hide()

func refresh() -> void:
	if not visible: return
	if is_instance_valid(card): remove_child(card); card.queue_free()
	card=PanelContainer.new()
	card.name="CellarCard"
	var surface:=STYLE.compact(true,12,Vector2(24,20))
	surface.bg_color=Color("211a20")
	card.add_theme_stylebox_override("panel",surface)
	add_child(card)
	var column:=_column(card,14)
	var header:=_row(column,12)
	_label(header,"CURITIBA CELLAR" if shop else "MEUS VINHOS",26).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(header,"R$ %d"%adapter.session.state.economy.balance,20).modulate=STYLE.ACCENT
	_button(header,"×",adapter.close).tooltip_text="Fechar"
	status=_label(column,"",15)
	status.modulate=Color("dcc6a7")
	if shop:
		var tabs:=_row(column,8)
		for name_country in CATALOG.COUNTRIES:
			var choice:=_button(tabs,name_country,func(): country=name_country; selected=""; feedback=""; refresh())
			choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			choice.modulate=STYLE.ACCENT if country==name_country else Color.WHITE
	var body:=_row(column,22)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(360,300)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	body.add_child(scroll)
	var list:=_column(scroll,8)
	list.custom_minimum_size.x=344
	var shown: Array[String]=[]
	for id in CATALOG.ORDER:
		var wine:=CATALOG.spec(id)
		if (shop and wine.country==country) or (not shop and adapter.model.count(id)>0): shown.append(id)
	if not shown.has(selected): selected=shown[0] if not shown.is_empty() else ""
	if shown.is_empty(): _label(list,"Nenhuma garrafa guardada.",18)
	for id in shown:
		var wine:=CATALOG.spec(id)
		var caption: String=wine.name+"\n"+wine.style+" · "+wine.country
		var choice:=_button(list,caption,func(): selected=id; feedback=""; refresh())
		choice.alignment=HORIZONTAL_ALIGNMENT_LEFT
		choice.custom_minimum_size.y=64
		choice.modulate=STYLE.ACCENT if selected==id else Color.WHITE
		choice.add_theme_font_size_override("font_size",17)
	details=_column(body,10)
	details.custom_minimum_size.x=300
	drink_button=null; buy_button=null
	if not selected.is_empty():
		var wine:=CATALOG.spec(selected)
		var bottle:=_row(details,14)
		var art:=preload("res://gameplay/wine/WineBottleIcon.gd").new()
		art.tint=wine.color
		art.custom_minimum_size=Vector2(62,120)
		bottle.add_child(art)
		var identity:=_column(bottle,6)
		var title:=_label(identity,wine.name,21)
		title.custom_minimum_size.x=222
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_label(identity,wine.country+" · "+wine.style,15).modulate=STYLE.ACCENT
		var grape:=_label(identity,wine.grape,14)
		grape.custom_minimum_size.x=222
		grape.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_label(details,String(TranslationServer.translate("Guardado: %d taças"))%adapter.model.count(selected),18)
		_label(details,String(TranslationServer.translate("Por taça: +%d vida · +%d álcool"))%[wine.heal,int(wine.alcohol)],15)
		if shop:
			buy_button=_button(details,String(TranslationServer.translate("Comprar garrafa · R$ %d"))%wine.price,func(): adapter.buy(selected))
			buy_button.tooltip_text="Guarda 3 taças. Não consome automaticamente."
			_label(details,"3 taças por garrafa · valores do jogo",12).modulate=STYLE.MUTED
		drink_button=_button(details,"Beber uma taça",func(): adapter.drink(selected))
	if not feedback.is_empty():
		var message:=_label(column,feedback,15)
		message.custom_minimum_size.x=680
		message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		message.modulate=STYLE.ACCENT
	var footer:=_row(column,10)
	if shop:
		_button(footer,"Ouvir Nelson",adapter.tell_story)
		if not adapter.model.data.gift_claimed: _button(footer,"Presente de boas-vindas",adapter.claim_gift)
		_button(footer,"Meus vinhos",func(): shop=false; refresh())
	elif adapter._near("nelson"):
		_button(footer,"Comprar",func(): shop=true; refresh())
	_button(footer,"Voltar ao jogo",adapter.close)
	update_status()
	_layout.call_deferred()
	STYLE.trap_focus.call_deferred(card)

func update_status() -> void:
	if not is_instance_valid(status): return
	var cooldown: float=adapter.model.data.cooldown
	status.text=String(TranslationServer.translate("Vida %d / 100    ·    %s %d / 100    ·    %d / 36 taças"))%[roundi(adapter.session.world.gameplay.health),adapter.model.stage(),roundi(adapter.model.data.alcohol),adapter.model.total_servings()]
	if is_instance_valid(drink_button):
		var reason: String=adapter.model.drink_reason(selected,float(adapter.session.world.gameplay.health))
		drink_button.disabled=not reason.is_empty()
		drink_button.text=String(TranslationServer.translate("Aguarde %.1f s"))%cooldown if reason=="cooldown" else "Espere recuperar o equilíbrio" if reason=="alcohol_limit" else "Beber uma taça"
		drink_button.tooltip_text=adapter.reason_text(reason) if not reason.is_empty() else "Consumir uma taça guardada. Aumenta o efeito do álcool."
	if is_instance_valid(buy_button):
		buy_button.disabled=adapter.session.state.economy.balance<int(CATALOG.spec(selected).price) or adapter.model.total_servings()+CATALOG.SERVINGS>adapter.MODEL.MAX_SERVINGS

func _layout() -> void:
	if not is_instance_valid(card): return
	card.reset_size()
	card.position=((get_viewport_rect().size-card.size)*0.5).max(Vector2(12,12))
func _column(parent: Node, gap: int) -> VBoxContainer:
	var result:=VBoxContainer.new(); result.add_theme_constant_override("separation",gap); parent.add_child(result); return result
func _row(parent: Node, gap: int) -> HBoxContainer:
	var result:=HBoxContainer.new(); result.add_theme_constant_override("separation",gap); parent.add_child(result); return result
func _label(parent: Node, value: String, size_font: int) -> Label:
	var result:=Label.new(); result.text=value; result.add_theme_font_size_override("font_size",size_font); parent.add_child(result); return result
func _button(parent: Node, value: String, action: Callable) -> Button:
	var result:=Button.new(); result.text=value; result.custom_minimum_size.y=40; result.pressed.connect(action); parent.add_child(result); return result
