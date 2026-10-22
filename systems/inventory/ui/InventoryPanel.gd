extends "res://systems/inventory/ui/InventoryViewState.gd"
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
const OUTFITS := preload("res://data/catalogs/OutfitCatalog.gd")
const THERMAL := preload("res://runtime/cold/ThermalState.gd")
const GOLD=STYLE.ACCENT
const TRUNK_MARGIN_RATIO := .025
var wardrobe_visible := false
var selected_outfit := ""
var device_hint: Label
var screen_scroll: ScrollContainer
var content_column: VBoxContainer
var drop_button: Button
var boards: Array=[]
var feedback_clock:=0.0
var equipment_buttons: Dictionary = {}
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=STYLE.create_theme(14)
	hide(); set_process(false); get_viewport().size_changed.connect(_layout)
	get_node("/root/GameInput").device_changed.connect(_update_hints)
	get_node("/root/GameInput").bindings_changed.connect(_update_hints)
func _style(color: Color,border: Color,radius:=3) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=color; style.border_color=border
	style.set_border_width_all(1); style.set_corner_radius_all(radius)
	style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=8; style.content_margin_bottom=8
	return style
func _layout() -> void:
	if not is_instance_valid(card): return
	var view:=get_viewport_rect().size
	if is_instance_valid(screen_scroll) and is_instance_valid(content_column) and is_instance_valid(body):
		# Reserve the actual header, details, actions and hints before sizing
		# the grid viewport. Only the grids scroll; actions never leave view.
		var body_size:=body.get_combined_minimum_size()
		var fixed_height:=content_column.get_combined_minimum_size().y-screen_scroll.get_combined_minimum_size().y
		var body_height:=maxf(72,minf(body_size.y,view.y-96-fixed_height))
		var overflow:=body_size.y>body_height
		screen_scroll.custom_minimum_size=Vector2(body_size.x+(14 if overflow else 0),body_height)
	card.reset_size()
	if trunk_visible:
		# Porta-malas (pedido de jogo, 21/10/2026): no centro o painel cobria o carro. Encosta à
		# direita com margem e deixa a esquerda livre; TrunkView põe a bandeja no meio dessa área
		# (trunk_view_focus). Em canvas_items 1280x720, 1920x1080 e 3440x1440 (1720x720 lógico).
		var margin:=maxf(16.0,view.x*TRUNK_MARGIN_RATIO)
		card.position=Vector2(view.x-card.size.x-margin,(view.y-card.size.y)*.5).max(Vector2(16,16))
	else:
		card.position=((view-card.size)*.5).max(Vector2(16,16))

## Onde a câmera do porta-malas deve pôr a bandeja: centro da área livre à esquerda do
## painel, em fração do viewport. `null` enquanto o painel ainda não tem tamanho.
func trunk_view_focus() -> Variant:
	if not visible or not trunk_visible or not is_instance_valid(card) or card.size.x<=0.0: return null
	var view:=get_viewport_rect().size
	if view.x<=0.0 or view.y<=0.0: return null
	return Vector2(clampf(card.position.x*.5/view.x,.15,.5),.5)
func refresh() -> void:
	if not visible: return
	if is_instance_valid(card): remove_child(card); card.queue_free()
	boards.clear(); equipment_buttons.clear(); drop_button=null
	card=PanelContainer.new(); card.name="InventoryCard"; add_child(card)
	card.add_theme_stylebox_override("panel",_style(STYLE.INK,STYLE.LINE.darkened(.25),3)); card.resized.connect(_layout)
	var outer:=_column(card,10); content_column=outer
	var header:=_row(outer)
	_label(header,"INVENTÁRIO",20).size_flags_horizontal=SIZE_EXPAND_FILL
	_button(header,"Roupas",func(): wardrobe_visible=not wardrobe_visible; selected_outfit=""; refresh())
	if adapter.session.get("wine") != null:
		_button(header,"Vinhos",func(): adapter.close(); adapter.session.wine.open_bag())
	var travel_bag: bool = adapter.travel_bag_available()
	_button(header,"×",adapter.close).tooltip_text="Fechar"
	screen_scroll=ScrollContainer.new(); screen_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; screen_scroll.follow_focus=true; outer.add_child(screen_scroll)
	body=_row(screen_scroll,16)
	var left:=_column(body,8); left.custom_minimum_size.x=296
	var snapshot: Dictionary=adapter.economy().grid_snapshot()
	var loadout: Dictionary=adapter.economy().personal_loadout()
	_label(left,"EQUIPAMENTO",12).modulate=STYLE.MUTED
	var equipment:=_row(left,6)
	for slot in ["curta","longa","corpo","granada"]:
		var id:=str(loadout.get(slot,""))
		var weapon:=_button(equipment,"",_select_equipment.bind(id))
		equipment_buttons[id]=weapon
		weapon.custom_minimum_size=Vector2(69,44); weapon.expand_icon=true; weapon.add_theme_constant_override("icon_max_width",56)
		weapon.icon=ICONS.get_icon(id) if not id.is_empty() else null
		weapon.text="—" if id.is_empty() else ""; weapon.disabled=id.is_empty()
		weapon.tooltip_text=str(GRID.spec("weapon:"+id).get("label",slot)) if not id.is_empty() else "Sem arma • "+slot
	_label(left,"BAGAGEM",12).modulate=STYLE.MUTED
	var pockets:=_row(left)
	var pocket_labels:=_column(pockets,2)
	pocket_labels.size_flags_horizontal=SIZE_EXPAND_FILL
	_label(pocket_labels,"Bolsos",14)
	_label(pocket_labels,"%d / 2 espaços"%_used(snapshot.pockets),12).modulate=STYLE.MUTED
	_board(pockets,"pockets",snapshot,44)
	var kind:=str(snapshot.bag)
	var bag_header:=_row(left)
	bag_header.visible = not kind.is_empty()
	_icon(bag_header,"case" if kind=="handbag" else "bag",32)
	_label(bag_header,"Mala" if kind=="handbag" else "Mochila" if kind=="backpack" else "Sem mochila",17).size_flags_horizontal=SIZE_EXPAND_FILL
	if not kind.is_empty():
		_label(bag_header,"%d / %d espaços"%[_used(snapshot.storage),GRID.dimensions(snapshot,"storage").x*GRID.dimensions(snapshot,"storage").y],12).modulate=STYLE.MUTED
		var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(296,216); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		left.add_child(scroll); _board(scroll,"storage",snapshot,72)
		drop_button=_button(left,"↓  Soltar mochila     G" if kind=="backpack" else "↓  Soltar mala     G",_drop)
		drop_button.name="DropBag"; drop_button.custom_minimum_size.y=34
		drop_button.add_theme_font_size_override("font_size",14)
		drop_button.add_theme_stylebox_override("normal",_control_style())
		drop_button.tooltip_text="Deixa a bagagem e seu conteúdo no chão. Você pode pegá-la novamente."
	else:
		var empty:=_label(left,"Sem mochila equipada",14); empty.modulate=STYLE.MUTED
	if kind=="handbag":
		_label(left,"Mala na mão · armas longas bloqueadas",12).modulate=STYLE.MUTED
	if wardrobe_visible: _wardrobe(left)
	if trunk_visible:
		var right:=_column(body,8); right.custom_minimum_size.x=240
		var trunk_header:=_row(right)
		_label(trunk_header,"PORTA-MALAS",18).size_flags_horizontal=SIZE_EXPAND_FILL
		_label(trunk_header,"%d / 24 espaços"%_used(snapshot.trunk),12).modulate=STYLE.MUTED
		_label(right,"MONALIZA",12).modulate=STYLE.MUTED
		var access: bool=adapter.trunk_access()
		var lock_label:=_label(right,"●  Transferência disponível" if access else "Aproxime-se do porta-malas",12)
		lock_label.modulate=STYLE.MUTED if access else STYLE.TEXT
		lock_label.name="TrunkAccess"
		var limits:=_label(right,"Armas e munição\nAté 6 pilhas de 99 tiros",12); limits.modulate=STYLE.MUTED
		_board(right,"trunk",snapshot,60)
		if travel_bag:
			var offer := _label(right,"Presente do Maciota (Prova de rua ou as dez cartas de Vicente). Retire sua mala aqui.",12)
			offer.custom_minimum_size.x=240; offer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			var take := _button(right,"Trocar mochila por mala" if kind=="backpack" else "Retirar mala do Maciota",func(): adapter.claim_travel_bag(),not access)
			take.name="ClaimTravelBag"
			var hint := _label(right,"24 espaços · bloqueia armas longas.\n"+("Seus itens passam para a mala; a mochila fica vazia no chão." if kind=="backpack" else "Solte a mala atual antes de retirar esta." if kind=="handbag" else "A mala fica na mão esquerda."),12)
			hint.custom_minimum_size.x=240; hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.modulate=STYLE.MUTED
	if is_instance_valid(drop_button):
		drop_button.reparent(outer)
		drop_button.size_flags_horizontal=SIZE_SHRINK_BEGIN
		drop_button.custom_minimum_size.x=296
	var divider:=HSeparator.new(); outer.add_child(divider)
	details=_column(outer,7); details.custom_minimum_size.x=296
	details.name="SelectedItem"
	feedback=_label(outer,"",13); feedback.custom_minimum_size.x=296; feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; feedback.hide(); feedback.modulate=STYLE.MUTED
	var footer:=_row(outer)
	device_hint=_label(footer,"",12); device_hint.modulate=STYLE.MUTED
	device_hint.custom_minimum_size.x=296
	device_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	device_hint.size_flags_horizontal=SIZE_EXPAND_FILL
	_details(); _update_hints(); _layout.call_deferred()
	for board in boards: board.mark_selected(selected_index if board.container_id==selected_container and equipment_id.is_empty() else -1)
	for key in equipment_buttons:
		if not key.is_empty() and key==equipment_id: equipment_buttons[key].add_theme_stylebox_override("normal",_control_style(true))
	STYLE.trap_focus.call_deferred(card)
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode==KEY_G and is_instance_valid(drop_button):
		get_viewport().set_input_as_handled(); _drop()
	elif event.physical_keycode==KEY_R and selected_index>=0:
		get_viewport().set_input_as_handled(); adapter.rotate(selected_container,selected_index)
func _drop() -> void:
	if adapter.drop_bag(): adapter.close()
func _select(container: String,index: int) -> void:
	selected_container=container; selected_index=index; equipment_id=""; selected_outfit=""; _details()
	for weapon in equipment_buttons.values(): weapon.add_theme_stylebox_override("normal",_control_style())
	for board in boards: board.mark_selected(index if board.container_id==container else -1)
func _select_equipment(id: String) -> void:
	equipment_id=id; selected_index=-1; selected_outfit=""
	for board in boards: board.mark_selected(-1)
	for key in equipment_buttons:
		equipment_buttons[key].add_theme_stylebox_override("normal",_control_style(key==id))
	_details()

func quick_use(container: String,index: int) -> void:
	if not adapter.can_edit(container): return
	var data: Dictionary=adapter.economy().grid_snapshot()
	if index<0 or index>=data[container].size(): return
	var spec:=GRID.spec(str(data[container][index].id))
	if spec.has("heal"): adapter.consume(container,index)
	elif spec.has("weapon"): adapter.equip(container,index)
	else: _select(container,index)
func quick_transfer(container: String,index: int) -> void:
	var target:="storage" if container=="trunk" else "trunk" if trunk_visible else "storage" if container=="pockets" else "pockets"
	adapter.move(container,index,target)
func _details() -> void:
	if not is_instance_valid(details): return
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	if not selected_outfit.is_empty():
		_outfit_details(); return
	var data: Dictionary=adapter.economy().grid_snapshot()
	var id:="weapon:"+equipment_id if not equipment_id.is_empty() else ""
	if selected_index>=0 and data.has(selected_container) and selected_index<data[selected_container].size(): id=str(data[selected_container][selected_index].id)
	details.show()
	if id.is_empty():
		_label(details,"Selecione um item",14).modulate=STYLE.MUTED
		_layout.call_deferred(); return
	var spec:=GRID.spec(id)
	var title:=_row(details,8); _icon(title,str(spec.get("icon","quest")),32)
	var label:=_label(title,str(spec.label),16); label.custom_minimum_size.x=180; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=SIZE_EXPAND_FILL; label.tooltip_text=str(spec.get("description","")); label.mouse_filter=MOUSE_FILTER_STOP
	if spec.get("quest",false): _label(title,"Missão",11).modulate=STYLE.MUTED
	if spec.has("weapon"):
		var ammo: Dictionary=adapter.economy().snapshot().weapons.get(spec.weapon,{})
		if int(ammo.get("magazine",-1))>=0: _label(title,"%d / 99"%(int(ammo.magazine)+int(ammo.reserve)),12).modulate=STYLE.MUTED
	if spec.has("heal"): _label(details,"Recupera %d de vida"%int(spec.heal),13).modulate=STYLE.MUTED
	var location:=_label(details,"Equipamento" if not equipment_id.is_empty() else {"pockets":"Bolsos","storage":"Mala" if data.bag=="handbag" else "Mochila","trunk":"Porta-malas"}.get(selected_container,""),12)
	location.modulate=STYLE.MUTED
	var actions:=HFlowContainer.new(); actions.add_theme_constant_override("h_separation",6); actions.add_theme_constant_override("v_separation",6); details.add_child(actions)
	var editable: bool=adapter.can_edit(selected_container) if equipment_id.is_empty() else true
	if spec.has("heal"): _primary(actions,"Beber" if id=="water" else "Comer" if id in ["apple","sandwich"] else "Usar",func(): adapter.consume(selected_container,selected_index),not editable)
	if spec.has("weapon"): _primary(actions,"Equipar",func(): adapter.equip(selected_container,selected_index,equipment_id),not editable or not adapter.session.state.weapons_allowed() or (data.bag=="handbag" and spec.weapon in GRID.LONG))
	if not equipment_id.is_empty():
		_button(actions,"↓ Mala" if data.bag=="handbag" else "↓ Mochila",func(): adapter.store_weapon(equipment_id,"storage"),data.bag=="")
		if trunk_visible: _button(actions,"→ Carro",func(): adapter.store_weapon(equipment_id,"trunk"),not adapter.trunk_access())
	else:
		if selected_container!="pockets": _button(actions,"Bolso",func(): adapter.move(selected_container,selected_index,"pockets"),not editable)
		if selected_container!="storage": _button(actions,"Mala" if data.bag=="handbag" else "Mochila",func(): adapter.move(selected_container,selected_index,"storage"),not editable or data.bag=="")
		if selected_container!="trunk" and trunk_visible and GRID.accepts("trunk",id): _button(actions,"→ Carro",func(): adapter.move(selected_container,selected_index,"trunk"),not adapter.trunk_access())
		if int(spec.get("w",1))>1: _button(actions,"↻",func(): adapter.rotate(selected_container,selected_index),not editable).tooltip_text="Girar • R"
	_layout.call_deferred()
	STYLE.trap_focus.call_deferred(card,false)

func _update_hints() -> void:
	if not is_instance_valid(device_hint): return
	var controls := get_node("/root/GameInput")
	device_hint.text=(String(TranslationServer.translate("%s  selecionar   ·   %s  fechar"))%[controls.prompt("ui_accept"),controls.prompt("ui_cancel")]) if controls.using_gamepad else String(TranslationServer.translate("%s  fechar   ·   Arrastar  mover · Clique direito  usar\nShift + clique  transferir · R  girar"))%controls.prompt("inventory")
	if controls.get_meta("touch_controls_active",false): device_hint.text=tr("Toque para selecionar · Arraste para mover")
	if is_instance_valid(drop_button):
		var kind: String=adapter.economy().grid_snapshot().bag
		drop_button.text=tr("Soltar mochila" if kind=="backpack" else "Soltar mala")+("" if controls.using_gamepad else "     G")
		if controls.get_meta("touch_controls_active",false): drop_button.text=tr("Soltar mochila" if kind=="backpack" else "Soltar mala")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_hints.call_deferred()

func _wardrobe(parent: Control) -> void:
	_label(parent,"ROUPAS",11).modulate=STYLE.MUTED
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",6); parent.add_child(row)
	for id in OUTFITS.OUTFITS:
		if not adapter.economy().owns_outfit(id): continue
		var button := _button(row,"",func(): selected_outfit=id; selected_index=-1; equipment_id=""; _details())
		button.custom_minimum_size=Vector2(44,42); button.tooltip_text=str(OUTFITS.OUTFITS[id].name).capitalize()
		var glyph := GLYPH.new("shirt",OUTFITS.OUTFITS[id].jacket_color.lightened(.35)); button.add_child(glyph); glyph.position=Vector2(12,9); glyph.size=Vector2(20,24)
		if id==adapter.economy().outfit: button.add_theme_stylebox_override("normal",_control_style(true))

func _outfit_details() -> void:
	details.show()
	var spec: Dictionary=OUTFITS.OUTFITS[selected_outfit]
	var label := _label(details,str(spec.name).capitalize(),16); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size.x=280
	var protection := _row(details,6)
	_label(protection,"Proteção contra frio",12).modulate=STYLE.MUTED
	var level := ceili(float(THERMAL.PROTECTION.get(selected_outfit,0))*3)
	for i in 3:
		var glyph := GLYPH.new("cold",STYLE.COLD if i<level else STYLE.DISABLED); protection.add_child(glyph)
	var equipped: bool=adapter.economy().outfit==selected_outfit
	_button(details,"Equipada" if equipped else "Equipar",func():
		if preload("res://runtime/OutfitDisguise.gd").equip(adapter.session, selected_outfit):
			adapter.session.save_game(); refresh(),equipped)
	_layout.call_deferred(); STYLE.trap_focus.call_deferred(card,false)
func say(text: String) -> void:
	if not is_instance_valid(feedback): return
	feedback.text=text; feedback.show(); feedback_clock=3; set_process(true)
func _process(delta: float) -> void:
	feedback_clock-=delta
	if feedback_clock<=0:
		if is_instance_valid(feedback): feedback.hide()
		set_process(false)
func _used(entries: Array) -> int:
	var used:=0
	for entry in entries: used+=GRID.extent(entry).x*GRID.extent(entry).y
	return used
func _board(parent: Node,container: String,data: Dictionary,cell: float) -> Control:
	var board:=BOARD.new(); parent.add_child(board); board.configure(adapter,container,data,cell); board.selected.connect(_select); boards.append(board); return board
func _row(parent: Node,gap:=8) -> HBoxContainer:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",gap); parent.add_child(row); return row
func _column(parent: Node,gap:=8) -> VBoxContainer:
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",gap); parent.add_child(column); return column
func _icon(parent: Node,id: String,pixels: int) -> TextureRect:
	var icon:=TextureRect.new(); icon.texture=ICONS.get_icon(id); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size=Vector2(pixels,pixels); icon.mouse_filter=MOUSE_FILTER_IGNORE; parent.add_child(icon); return icon
func _label(parent: Node,text: String,font_size: int) -> Label:
	var label:=Label.new(); label.text=text; label.add_theme_font_size_override("font_size",font_size); parent.add_child(label); return label
func _button(parent: Node,text: String,action: Callable,disabled:=false) -> Button:
	var button:=Button.new(); button.text=text; button.disabled=disabled; button.add_theme_font_size_override("font_size",14); button.custom_minimum_size.y=34; button.pressed.connect(action)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var active: bool=state in ["hover","pressed","focus"]
		var box:=_control_style(active)
		if state=="disabled": box.bg_color=STYLE.SURFACE.darkened(.12)
		if state=="focus": box.bg_color=Color.TRANSPARENT; box.set_border_width_all(2)
		button.add_theme_stylebox_override(state,box)
	parent.add_child(button); return button

func _primary(parent: Node,text: String,action: Callable,disabled:=false) -> Button:
	var button:=_button(parent,text,action,disabled)
	var normal:=_control_style(true); normal.bg_color=GOLD
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_color_override("font_color",STYLE.INK)
	button.add_theme_color_override("font_focus_color",STYLE.INK)
	return button

func _control_style(active:=false) -> StyleBoxFlat:
	var box:=_style(STYLE.SURFACE.lightened(.035) if active else STYLE.SURFACE, GOLD if active else STYLE.LINE.darkened(.25),2)
	box.content_margin_left=10; box.content_margin_right=10
	box.content_margin_top=5; box.content_margin_bottom=5
	return box
