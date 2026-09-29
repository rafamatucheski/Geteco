extends "res://systems/inventory/ui/InventoryViewState.gd"
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
const OUTFITS := preload("res://data/catalogs/OutfitCatalog.gd")
const THERMAL := preload("res://runtime/cold/ThermalState.gd")
const GOLD=STYLE.ACCENT
var wardrobe_visible := false
var selected_outfit := ""
var device_hint: Label
var screen_scroll: ScrollContainer
var content_column: VBoxContainer
var drop_button: Button
var boards: Array=[]
var feedback_clock:=0.0
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=STYLE.create_theme(14)
	hide(); set_process(false); get_viewport().size_changed.connect(_layout)
	get_node("/root/GameInput").device_changed.connect(_update_hints)
	get_node("/root/GameInput").bindings_changed.connect(_update_hints)
func _style(color: Color,border: Color,radius:=10) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=color; style.border_color=border
	style.set_border_width_all(1); style.set_corner_radius_all(radius)
	style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=8; style.content_margin_bottom=8
	return style
func _layout() -> void:
	if not is_instance_valid(card): return
	var view:=get_viewport_rect().size
	if is_instance_valid(screen_scroll) and is_instance_valid(content_column):
		var content_size := content_column.get_combined_minimum_size()
		var overflow := content_size.y>view.y-96
		screen_scroll.custom_minimum_size=Vector2(content_size.x+(14 if overflow else 0),minf(content_size.y,view.y-96))
	card.reset_size()
	card.position=((view-card.size)*.5).max(Vector2(16,16))
func refresh() -> void:
	if not visible: return
	if is_instance_valid(card): remove_child(card); card.queue_free()
	boards.clear(); drop_button=null
	card=PanelContainer.new(); card.name="InventoryCard"; add_child(card)
	card.add_theme_stylebox_override("panel",STYLE.compact(false,12,Vector2(18,16))); card.resized.connect(_layout)
	screen_scroll=ScrollContainer.new(); screen_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; screen_scroll.follow_focus=true; card.add_child(screen_scroll)
	var outer:=_column(screen_scroll,10); content_column=outer
	var header:=_row(outer)
	_label(header,"INVENTÁRIO",18).size_flags_horizontal=SIZE_EXPAND_FILL
	_button(header,"Roupas",func(): wardrobe_visible=not wardrobe_visible; selected_outfit=""; refresh())
	var trunk:=_button(header,"Monaliza",func(): trunk_visible=not trunk_visible; refresh())
	trunk.name="ToggleTrunk"; trunk.tooltip_text="Armas e munição • acesso pelo porta-malas"; trunk.modulate=GOLD if trunk_visible else Color.WHITE
	_button(header,"×",adapter.close).tooltip_text="Fechar"
	body=_row(outer,16)
	var left:=_column(body,8); left.custom_minimum_size.x=296
	var snapshot: Dictionary=adapter.economy().grid_snapshot()
	var loadout: Dictionary=adapter.economy().personal_loadout()
	_label(left,"ARMAS",11).modulate=STYLE.MUTED
	var equipment:=_row(left,6)
	for slot in ["curta","longa","corpo","granada"]:
		var id:=str(loadout.get(slot,""))
		var weapon:=_button(equipment,"",func(): equipment_id=id; selected_index=-1; selected_outfit=""; _details())
		weapon.custom_minimum_size=Vector2(69,48); weapon.expand_icon=true; weapon.add_theme_constant_override("icon_max_width",56)
		weapon.icon=ICONS.get_icon(id) if not id.is_empty() else null
		weapon.text="—" if id.is_empty() else ""; weapon.disabled=id.is_empty()
		weapon.tooltip_text=str(GRID.spec("weapon:"+id).get("label",slot)) if not id.is_empty() else "Sem arma • "+slot
	_label(left,"ITENS",11).modulate=STYLE.MUTED
	var pockets:=_row(left)
	_label(pockets,"Bolsos",12).size_flags_horizontal=SIZE_EXPAND_FILL
	_board(pockets,"pockets",snapshot,44)
	var kind:=str(snapshot.bag)
	var bag_header:=_row(left)
	bag_header.visible = not kind.is_empty()
	_icon(bag_header,"case" if kind=="handbag" else "bag",32)
	_label(bag_header,"Mala" if kind=="handbag" else "Mochila" if kind=="backpack" else "Sem mochila",17).size_flags_horizontal=SIZE_EXPAND_FILL
	if not kind.is_empty():
		_label(bag_header,"%d / %d"%[_used(snapshot.storage),GRID.dimensions(snapshot,"storage").x*GRID.dimensions(snapshot,"storage").y],12).modulate=GOLD
		var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(296,216); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		left.add_child(scroll); _board(scroll,"storage",snapshot,72)
		drop_button=_button(left,"↓  Soltar mochila     G" if kind=="backpack" else "↓  Soltar mala     G",_drop)
		drop_button.name="DropBag"; drop_button.custom_minimum_size.y=42
		drop_button.add_theme_font_size_override("font_size",15)
		drop_button.add_theme_stylebox_override("normal",STYLE.button())
		drop_button.tooltip_text="Deixa a bagagem e seu conteúdo no chão. Você pode pegá-la novamente."
	if wardrobe_visible: _wardrobe(left)
	if trunk_visible:
		var right:=_column(body,8); right.custom_minimum_size.x=240
		var trunk_header:=_row(right)
		_label(trunk_header,"MONALIZA",16).size_flags_horizontal=SIZE_EXPAND_FILL
		_label(trunk_header,"%d / 24"%_used(snapshot.trunk),12).modulate=GOLD
		var access: bool=adapter.trunk_access()
		var lock_label:=_label(right,"●  Porta-malas aberto" if access else "⌁  Aproxime-se do porta-malas",12)
		lock_label.modulate=STYLE.MUTED if access else GOLD
		lock_label.tooltip_text="Até 6 pilhas de munição, com 99 tiros por pilha. Outros itens não entram."
		_board(right,"trunk",snapshot,60)
	details=_column(left,5); details.custom_minimum_size.x=296
	feedback=_label(left,"",12); feedback.custom_minimum_size.x=296; feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; feedback.hide(); feedback.modulate=GOLD
	var footer:=_row(outer)
	device_hint=_label(footer,"",11); device_hint.modulate=STYLE.MUTED
	_details(); _update_hints(); _layout.call_deferred()
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
	for board in boards: board.mark_selected(index if board.container_id==container else -1)
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
	details.visible=not id.is_empty()
	if id.is_empty(): _layout.call_deferred(); return
	var spec:=GRID.spec(id)
	var title:=_row(details,8); _icon(title,str(spec.get("icon","quest")),32)
	var label:=_label(title,str(spec.label),14); label.size_flags_horizontal=SIZE_EXPAND_FILL; label.tooltip_text=str(spec.get("description","")); label.mouse_filter=MOUSE_FILTER_STOP
	if spec.get("quest",false): _label(title,"Missão",11).modulate=GOLD
	if spec.has("weapon"):
		var ammo: Dictionary=adapter.economy().snapshot().weapons.get(spec.weapon,{})
		if int(ammo.get("magazine",-1))>=0: _label(title,"%d / 99"%(int(ammo.magazine)+int(ammo.reserve)),12).modulate=GOLD
	var actions:=_row(details,5)
	var editable: bool=adapter.can_edit(selected_container) if equipment_id.is_empty() else true
	if spec.has("heal"): _button(actions,"Beber" if id=="water" else "Comer" if id in ["apple","sandwich"] else "Usar",func(): adapter.consume(selected_container,selected_index),not editable)
	if spec.has("weapon"): _button(actions,"Equipar",func(): adapter.equip(selected_container,selected_index,equipment_id),not editable or not adapter.session.state.weapons_allowed())
	if not equipment_id.is_empty():
		_button(actions,"↓ Mochila",func(): adapter.store_weapon(equipment_id,"storage"),data.bag=="")
		if trunk_visible: _button(actions,"→ Carro",func(): adapter.store_weapon(equipment_id,"trunk"),not adapter.trunk_access())
	else:
		if selected_container!="pockets": _button(actions,"Bolso",func(): adapter.move(selected_container,selected_index,"pockets"),not editable)
		if selected_container!="storage": _button(actions,"Mochila",func(): adapter.move(selected_container,selected_index,"storage"),not editable or data.bag=="")
		if selected_container!="trunk" and trunk_visible and GRID.accepts("trunk",id): _button(actions,"→ Carro",func(): adapter.move(selected_container,selected_index,"trunk"),not adapter.trunk_access())
		if int(spec.get("w",1))>1: _button(actions,"↻",func(): adapter.rotate(selected_container,selected_index),not editable).tooltip_text="Girar • R"
	_layout.call_deferred()
	STYLE.trap_focus.call_deferred(card,false)

func _update_hints() -> void:
	if not is_instance_valid(device_hint): return
	var controls := get_node("/root/GameInput")
	device_hint.text=("%s  selecionar   ·   %s  fechar"%[controls.prompt("ui_accept"),controls.prompt("ui_cancel")]) if controls.using_gamepad else "%s  fechar   ·   Arrastar  mover   ·   Clique direito  usar"%controls.prompt("inventory")
	if controls.get_meta("touch_controls_active",false): device_hint.text="Toque para selecionar · Arraste para mover"
	if is_instance_valid(drop_button):
		var kind: String=adapter.economy().grid_snapshot().bag
		drop_button.text=("Soltar mochila" if kind=="backpack" else "Soltar mala")+("" if controls.using_gamepad else "     G")
		if controls.get_meta("touch_controls_active",false): drop_button.text="Soltar mochila" if kind=="backpack" else "Soltar mala"

func _wardrobe(parent: Control) -> void:
	_label(parent,"ROUPAS",11).modulate=STYLE.MUTED
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",6); parent.add_child(row)
	for id in OUTFITS.OUTFITS:
		if not adapter.economy().owns_outfit(id): continue
		var button := _button(row,"",func(): selected_outfit=id; selected_index=-1; equipment_id=""; _details())
		button.custom_minimum_size=Vector2(44,42); button.tooltip_text=str(OUTFITS.OUTFITS[id].name).capitalize()
		var glyph := GLYPH.new("shirt",OUTFITS.OUTFITS[id].jacket_color.lightened(.35)); button.add_child(glyph); glyph.position=Vector2(12,9); glyph.size=Vector2(20,24)
		if id==adapter.economy().outfit: button.add_theme_stylebox_override("normal",STYLE.compact(true,8))

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
		if adapter.economy().equip_outfit(selected_outfit):
			adapter.session.apply_outfit(); adapter.session.save_game(); refresh(),equipped)
	_layout.call_deferred(); STYLE.trap_focus.call_deferred(card,false)
	screen_scroll.ensure_control_visible.call_deferred(details)
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
	var button:=Button.new(); button.text=text; button.disabled=disabled; button.add_theme_font_size_override("font_size",12); button.custom_minimum_size.y=32; button.pressed.connect(action); parent.add_child(button); return button
