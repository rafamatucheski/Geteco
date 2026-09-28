@tool
extends VBoxContainer
signal map_focus_changed(expanded: bool)
const DATA := preload("res://world/editing/WorldEditData.gd")
const LIBRARY := preload("res://addons/geteco_world_editor/WorldAssetLibrary.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
const SESSION_CONTEXT := preload("res://addons/geteco_world_editor/WorldSessionContext.gd")
const CATALOG_PATH := "res://addons/geteco_world_editor/base_catalog.json"
const CACHE_PATH := "res://.godot/world_editor_catalog.json"
const DRAFT_PATH := "res://.godot/world_editor_draft.json"
var edits_path := DATA.PATH
var draft_path := DRAFT_PATH
var document := DATA.empty_document()
var saved_document := DATA.empty_document()
var expected_hash := ""
var catalog := {}
var region := "harbor"
var canvas: CANVAS
var properties: VBoxContainer
var status: Label
var selection_label: Label
var undo_button: Button
var redo_button: Button
var save_button: Button
var history: Array[Dictionary] = []
var future: Array[Dictionary] = []
var worker_pid := -1
var worker_started := 0
var worker_timer: Timer
var rebuild_button: Button
var deleted_menu: MenuButton
var deleted_ids: Array[String] = []
var load_error := ""
var locations: OptionButton
var location_ids: Array[String] = []
var asset_search: LineEdit
var asset_filter: OptionButton
var asset_list: ItemList
var asset_count: Label
var asset_items: Array[Dictionary] = []
var visible_assets: Array[Dictionary] = []
var placement_template: Dictionary = {}
var clipboard_row: Dictionary = {}
var save_state: Label
var free_placement := true
var asset_icons: Dictionary = {}
var library_panel: VBoxContainer
var properties_scroll: ScrollContainer
var library_toggle: Button
var properties_toggle: Button
var focus_toggle: Button
var actions_bar: HFlowContainer
var library_requested := true
var properties_requested := true
var active_sidebar := "library"
var map_expanded := false
var _announced_map_expanded := false
var options_menu: MenuButton
var rotation_toggle: Button
var live_toggle: Button
var live_split: HSplitContainer
var live_preview: Control
var view_mode: OptionButton
var junction_editor := preload("res://addons/geteco_world_editor/WorldJunctionEditor.gd").new()

func _draw() -> void: draw_rect(Rect2(Vector2.ZERO,size),Color("222c32"))

func _ready() -> void:
	name = "MundoGeteco"
	add_theme_constant_override("separation",4)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",6)
	add_child(header)
	var title := Label.new()
	title.text = "Mundo"
	title.add_theme_font_size_override("font_size",18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	library_toggle = _button(header,"Assets",func(): _toggle_sidebar("library"))
	library_toggle.toggle_mode = true
	library_toggle.tooltip_text = "Mostrar ou recolher a biblioteca de assets"
	properties_toggle = _button(header,"Propriedades",func(): _toggle_sidebar("properties"))
	properties_toggle.toggle_mode = true
	properties_toggle.tooltip_text = "Mostrar ou recolher as propriedades"
	focus_toggle = _button(header,"Ampliar mapa",func():
		map_expanded = not map_expanded
		_apply_layout())
	focus_toggle.toggle_mode = true
	focus_toggle.tooltip_text = "Recolher as duas laterais; clique novamente para restaurar"
	save_state = Label.new()
	header.add_child(save_state)
	save_button = _button(header,"Salvar mundo",save)
	save_button.tooltip_text = "Salvar mundo · Ctrl+S"
	save_button.custom_minimum_size = Vector2(125,30)
	for style in ["normal","hover","pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("2d785f") if style == "normal" else Color("399677")
		box.set_corner_radius_all(5)
		box.content_margin_left = 10
		box.content_margin_right = 10
		save_button.add_theme_stylebox_override(style,box)
	actions_bar = HFlowContainer.new()
	actions_bar.add_theme_constant_override("h_separation",4)
	actions_bar.add_theme_constant_override("v_separation",4)
	add_child(actions_bar)
	var regions := OptionButton.new()
	for label in ["Mundo inteiro","Harbor","Montanha"]: regions.add_item(label)
	regions.select(1)
	regions.item_selected.connect(func(index):
		if index == 0: _fit_world()
		else: _switch_region("harbor" if index == 1 else "mountain"))
	actions_bar.add_child(regions)
	_button(actions_bar,"Selecionar",func():
		junction_editor.set_enabled(false)
		placement_template.clear()
		canvas.armed = ""
		canvas.queue_redraw()
		status.text = "Selecione e arraste um objeto.")
	rotation_toggle = _button(actions_bar,"Girar",func():
		canvas.cancel_drag()
		canvas.rotation_enabled = rotation_toggle.button_pressed
		canvas.queue_redraw()
		_select(canvas.selected_id))
	rotation_toggle.toggle_mode = true
	rotation_toggle.tooltip_text = "Ativar/desativar o círculo verde de rotação"
	var add := MenuButton.new()
	add.text = "Adicionar"
	for label in ["Árvore","Prédio","Rua","Luz","Terreno / grama"]: add.get_popup().add_item(label)
	add.get_popup().id_pressed.connect(func(index):
		placement_template.clear()
		canvas.armed = ["tree","building","road","light","ground"][index]
		canvas.queue_redraw()
		canvas.grab_focus()
		status.text = "Clique no mapa para colocar. Esc cancela.")
	actions_bar.add_child(add)
	undo_button = _button(actions_bar,"Desfazer",undo)
	redo_button = _button(actions_bar,"Refazer",redo)
	_button(actions_bar,"Prévia 3D",_preview)
	live_toggle = _button(actions_bar,"2D + 3D",_toggle_live_preview)
	live_toggle.toggle_mode = true
	live_toggle.tooltip_text = "Editar o mapa com a visão 3D ao lado"
	live_toggle.hide()
	view_mode = OptionButton.new()
	for label in ["2D","3D","Lado a lado"]: view_mode.add_item(label)
	view_mode.item_selected.connect(_set_view_mode)
	actions_bar.add_child(view_mode)
	var filter := OptionButton.new()
	filter.tooltip_text = "Filtrar objetos no mapa"
	for label in ["Todos","Árvores","Prédios","Ruas","Luzes","Objetos","Peças","Locais","Pisos e calçadas"]: filter.add_item(label)
	filter.item_selected.connect(func(index):
		canvas.filter_type = ["all","tree","building","road","light","prop","piece","context","ground"][index]
		canvas.queue_redraw())
	actions_bar.add_child(filter)
	locations = OptionButton.new()
	locations.custom_minimum_size.x = 145
	locations.fit_to_longest_item = false
	locations.item_selected.connect(_go_location)
	actions_bar.add_child(locations)
	options_menu = MenuButton.new()
	options_menu.text = "Opções"
	var menu := options_menu.get_popup()
	menu.hide_on_checkable_item_selection = false
	menu.add_check_item("Grade de 1 m",0)
	menu.add_check_item("Colocação livre",1)
	menu.set_item_checked(0,true)
	menu.set_item_checked(1,true)
	menu.add_check_item("Encaixar ruas",4)
	menu.set_item_checked(menu.get_item_index(4),true)
	menu.add_separator()
	menu.add_item("Ir ao início",2)
	menu.add_item("Atualizar base",3)
	menu.id_pressed.connect(_layout_option)
	actions_bar.add_child(options_menu)
	rebuild_button = options_menu
	deleted_menu = MenuButton.new()
	deleted_menu.text = "Excluídos"
	deleted_menu.get_popup().id_pressed.connect(func(index): _restore_id(deleted_ids[index]))
	actions_bar.add_child(deleted_menu)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_build_library(split)
	var workspace := HSplitContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(workspace)
	canvas = CANVAS.new()
	canvas.custom_minimum_size = Vector2(240,200)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.selected.connect(_select)
	canvas.committed.connect(_commit)
	canvas.placed.connect(_place)
	live_split = HSplitContainer.new()
	live_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(live_split)
	live_split.add_child(canvas)
	properties_scroll = ScrollContainer.new()
	properties_scroll.custom_minimum_size.x = 225
	properties_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(properties_scroll)
	properties = VBoxContainer.new()
	properties.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties.add_theme_constant_override("separation",6)
	properties_scroll.add_child(properties)
	status = Label.new()
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size.y = 22
	status.mouse_entered.connect(func(): status.tooltip_text = status.text)
	add_child(status)
	resized.connect(_apply_layout)
	_apply_layout()
	worker_timer = Timer.new()
	worker_timer.wait_time = .5
	worker_timer.timeout.connect(_poll_worker)
	add_child(worker_timer)
	var loaded := DATA.read_document(edits_path)
	junction_editor.setup(self)
	canvas.junction_editor = junction_editor
	load_error = loaded.error
	if load_error.is_empty():
		document = loaded.document
		saved_document = document.duplicate(true)
		expected_hash = DATA.disk_hash(edits_path)
		_restore_draft()
	_load_catalog()
	_switch_region(region)
	status.text = "Arraste os pontos amarelos para mudar o traçado de uma rua. Salve e inicie uma nova execução do jogo."
	if not load_error.is_empty(): status.text = load_error

func _button(parent: Node,label: String,callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _load_catalog() -> void:
	var path := CACHE_PATH if FileAccess.file_exists(CACHE_PATH) and FileAccess.get_modified_time(CACHE_PATH) > FileAccess.get_modified_time(CATALOG_PATH) else CATALOG_PATH
	if not FileAccess.file_exists(path):
		catalog = {}
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("regions") is Dictionary: catalog = parsed.regions
	SESSION_CONTEXT.upgrade(catalog,SESSION_CONTEXT.read(),FileAccess.get_modified_time(SESSION_CONTEXT.PATH)>FileAccess.get_modified_time(path))
	DATA.normalize_catalog_heights(catalog)
	preload("res://runtime/UrbanTransitPresentation.gd").upgrade_editor_catalog(catalog)
	if catalog.has("harbor"):
		catalog.harbor.objects.merge(preload("res://world/editing/WorldPaving.gd").catalog(),true)
	asset_items = LIBRARY.build(catalog)
	for area in catalog:
		for row in catalog[area].get("context",{}).values():
			if row.type != "piece": continue
			var item := LIBRARY.entry(str(row.get("label",row.id)),row,str(row.id))
			item.action = "select"
			asset_items.append(item)
	_filter_assets()

func _switch_region(value: String) -> void:
	region = value
	canvas.region = value
	canvas.selected_id = ""
	canvas.selected_point = -1
	canvas.center = DATA.point(catalog.get(region,{}).get("spawn",[45,110]))
	_set_background()
	_refresh()

func _refresh() -> void:
	canvas.cancel_drag()
	canvas.objects = {}
	for area in ["harbor","mountain"]:
		var base: Dictionary = catalog.get(area,{}).get("objects",{})
		var rows := DATA.effective(base,document.regions.get(area,{}))
		for id in catalog.get(area,{}).get("context",{}):
			var base_row: Dictionary = catalog[area].context[id]
			var row: Dictionary = base_row.duplicate(true)
			if row.type == "piece":
				row["shape_editable"] = not row.get("locked",false) and PIECES.is_shape_editable(str(id))
				if row.shape_editable: row["default_outline"] = _base_outline(base_row)
			if row.type == "piece" and document.regions.get(area,{}).has(id):
				var change: Dictionary = document.regions[area][id]
				if change.get("deleted",false): continue
				var angle := -deg_to_rad(float(change.get("rotation",0)))
				var stretch := DATA.point(change.get("stretch",[1,1]))
				for part in row.get("parts",[]):
					var bounds := Rect2()
					for i in part[6].size():
						var point := DATA.point(part[6][i])
						point = DATA.point(change.position)+((point-DATA.point(base_row.position))*stretch).rotated(angle)
						part[6][i] = [point.x,point.y]
						bounds = Rect2(point,Vector2.ZERO) if i == 0 else bounds.expand(point)
					part[0] = bounds.position.x
					part[1] = bounds.position.y
					part[2] = bounds.size.x
					part[3] = bounds.size.y
				row.merge(change,true)
				if row.has("outline"):
					var color := str(base_row.parts[-1][5]) if not base_row.get("parts",[]).is_empty() else "897053"
					var height := float(base_row.parts[-1][4]) if not base_row.get("parts",[]).is_empty() else .08
					var polygon := PackedVector2Array()
					for item in row.outline: polygon.append(DATA.point(row.position)+(DATA.point(item)*stretch).rotated(angle))
					row.parts = []
					var indices := Geometry2D.triangulate_polygon(polygon)
					for i in range(0,indices.size(),3):
						var bounds := Rect2(polygon[indices[i]],Vector2.ZERO)
						var triangle: Array = []
						for j in 3:
							var point := polygon[indices[i+j]]
							bounds = bounds.expand(point)
							triangle.append([point.x,point.y])
						row.parts.append([bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,height,color,triangle])
			rows[id] = row
		for row in rows.values(): row["editor_region"] = area
		canvas.objects.merge(rows)
	_update_locations()
	junction_editor.rebuild()
	canvas.rebuild_context()
	canvas.queue_redraw()
	deleted_ids.clear()
	deleted_menu.get_popup().clear()
	for id in document.regions.get(region,{}):
		if document.regions[region][id].get("deleted",false):
			deleted_menu.get_popup().add_item(id,deleted_ids.size())
			deleted_ids.append(id)
	deleted_menu.disabled = deleted_ids.is_empty()
	undo_button.disabled = history.is_empty()
	redo_button.disabled = future.is_empty()
	save_button.disabled = not load_error.is_empty()
	save_state.text = "Alterações não salvas" if document != saved_document else "Mundo salvo"
	_sync_service_entries()
	_select(canvas.selected_id)

func _sync_service_entries() -> void:
	_set_background()
	var edited := false
	for row in document.regions.harbor.values():
		if row.has("service_base"): edited = true; break
	if not edited: return
	var services := preload("res://world/editing/WorldServiceBuildings.gd")
	for definition in preload("res://world/places/PlaceCatalog.gd").definitions():
		var building: Variant = services.PLACES.find_key(definition.id)
		if building == null: continue
		var row: Dictionary = document.regions.harbor.get("building/"+str(building),{})
		if not row.has("service_base"): continue
		var original_transform: Transform3D = definition.get("editor_transform",Transform3D.IDENTITY)
		for field in ["entry_position","return_position"]:
			var original: Vector3 = original_transform.affine_inverse()*definition[field]
			var target := services.transform_for(row)*original
			for index in canvas.entries.size():
				if DATA.point(canvas.entries[index]).distance_to(Vector2(original.x,original.z)) < .02:
					canvas.entries[index] = [target.x,target.z]

func _service_accesses(row: Dictionary) -> Array:
	if not row.get("service_building",false): return []
	var services := preload("res://world/editing/WorldServiceBuildings.gd")
	var id: String = services.PLACES.get(str(row.id).trim_prefix("building/"),"")
	if id.is_empty(): return []
	var definition := preload("res://world/places/PlaceCatalog.gd").get_definition(id)
	var old_transform: Transform3D = definition.get("editor_transform",Transform3D.IDENTITY)
	var transform := services.transform_for(row)*old_transform.affine_inverse()
	var points: Array = []
	for field in ["entry_position","return_position"]:
		var point: Vector3 = transform*definition[field]
		points.append(Vector2(point.x,point.z))
	return points

func _select(id: String) -> void:
	if canvas.selected_id != id: canvas.edit_points = false; canvas.selected_point = -1
	canvas.selected_id = id
	_sync_live_preview()
	if junction_editor.enabled:
		active_sidebar = "properties"
		_apply_layout()
	elif not id.is_empty() and properties_requested:
		active_sidebar = "properties"
		_apply_layout()
	elif id.is_empty():
		active_sidebar = "library"
		_apply_layout()
	for child in properties.get_children():
		properties.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size",19)
	heading.text = "Propriedades"
	properties.add_child(heading)
	if junction_editor.enabled:
		junction_editor.properties()
		return
	if not canvas.objects.has(id):
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Selecione um objeto no mapa.\n\nVerde: árvores\nBlocos: prédios\nAmarelo: luzes\nCruz rosa: acesso protegido"
		properties.add_child(hint)
		return
	var row: Dictionary = canvas.objects[id]
	region = str(row.get("editor_region",region))
	canvas.region = region
	var label := Label.new()
	label.text = preload("res://world/editing/WorldGroundFactory.gd").LABELS[preload("res://world/editing/WorldGroundFactory.gd").SURFACES.find(row.surface)] if row.type == "ground" and not row.get("paving",false) else str(row.get("label",row.id))
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	properties.add_child(label)
	if row.get("locked",false):
		var lock := Label.new()
		lock.text = "Conjunto do cenário.\nGeometria visível; edição protegida." if row.type == "context" else ("Equipamento ligado à operação do local.\nPosição protegida." if row.type == "piece" else "Local com serviço/interior.\nPosição protegida.")
		properties.add_child(lock)
		_button(properties,"Ver este local em 3D",_preview)
		return
	var transform_hint := Label.new()
	transform_hint.text = "Arraste as setas X/Z para mover." if row.type == "light" or row.get("paving",false) or not canvas.rotation_enabled else "Arraste as setas X/Z para mover.\nAnel Y: girar · Shift: passos de 15°."
	transform_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_child(transform_hint)
	if row.type != "road":
		_number("X (m)",float(row.position[0]),-10000,10000,func(value): _set_array("position",0,value))
		_number("Z (m)",float(row.position[1]),-10000,10000,func(value): _set_array("position",1,value))
		if row.type != "light" and not row.get("paving",false): _number("Rotação (°)",float(row.get("rotation",0)),-360,360,func(value): _set_value("rotation",value))
	match str(row.type):
		"tree":
			_number("Escala",float(row.scale),.25,3,func(value): _set_value("scale",value),.05)
			_number("Variante",float(row.variant),0,7,func(value): _set_value("variant",int(value)),1)
			var snow := CheckButton.new()
			snow.text = "Neve"
			snow.visible = row.get("tree_model","pine") != "harbor"
			snow.button_pressed = row.snow
			snow.toggled.connect(func(value): _set_value("snow",value))
			properties.add_child(snow)
		"piece":
			var stretch := DATA.point(row.get("stretch",[1,1]))
			var extent := _outline_extent(row)
			_number("Largura (m)",extent.x*stretch.x,extent.x*.1,extent.x*4,func(value): _resize_piece(0,value))
			_number("Profundidade (m)",extent.y*stretch.y,extent.y*.1,extent.y*4,func(value): _resize_piece(1,value))
			if row.get("shape_editable",false): _shape_controls(row)
		"ground":
			var paving: bool = row.get("paving",false)
			_number("Largura (m)",float(row.size[0]),.25 if paving else 1,512 if paving else 64,func(value): _set_array("size",0,value))
			_number("Profundidade (m)",float(row.size[1]),.25 if paving else 1,512 if paving else 64,func(value): _set_array("size",1,value))
			var ground := preload("res://world/editing/WorldGroundFactory.gd")
			_choice("Piso",["concrete","pavers"] if paving else ground.SURFACES,["Concreto","Pedras"] if paving else ground.LABELS,str(row.surface),func(value): _set_value("surface",value))
			if paving: _color(row)
			else: _shape_controls(row)
		"prop":
			if row.model == "footbridge":
				# Altura fixa (5,6 m livres sob o tabuleiro); o vão é o comprimento menos as escadas.
				_number("Largura (m)",float(row.size[0]),1.8,6,func(value): _set_array("size",0,value))
				_number("Comprimento total (m)",float(row.size[1]),29,60,func(value): _set_array("size",1,value))
				var span := Label.new()
				span.text = "Vão livre: %.1f m" % preload("res://world/urban_detail/UrbanFootbridge3D.gd").span_for(float(row.size[1]))
				properties.add_child(span)
			else: _number("Escala",float(row.scale),.25,3,func(value): _set_value("scale",value),.05)
			_color(row)
		"building":
			var base: Dictionary = row.get("service_base",{})
			_number("Largura (m)",float(row.size[0]),base.get("size",[3,3])[0],minf(40,base.get("size",[40,40])[0]*3),func(value): _set_array("size",0,value))
			_number("Profundidade (m)",float(row.size[1]),base.get("size",[3,3])[1],minf(40,base.get("size",[40,40])[1]*3),func(value): _set_array("size",1,value))
			_number("Altura (m)",float(row.height),base.get("height",2),minf(40,base.get("height",40)*3),func(value): _set_value("height",value))
			if not row.get("service_building",false): _choice("Modelo",DATA.BUILDING_TYPES,DATA.BUILDING_LABELS,str(row.model),func(value): _set_value("model",value))
			_color(row)
		"light":
			_number("Altura (m)",float(row.height),1,12,func(value): _set_value("height",value))
			_number("Alcance (m)",float(row.range),1,30,func(value): _set_value("range",value))
			_number("Energia (0 apaga)",float(row.energy),0,8,func(value): _set_value("energy",value),.05)
			_color(row)
			var note := Label.new()
			note.text = "Luz constante, sem sombras."
			properties.add_child(note)
		"road":
			var extend := _button(properties,"Continuar rua",_continue_road)
			extend.disabled = canvas.selected_point not in [0,row.points.size()-1]
			var turn := _button(properties,"Criar retorno",_create_road_return)
			turn.disabled = extend.disabled or row.get("pathway",false) or float(row.width) < 5 or not canvas.road_connection(DATA.point(row.points[maxi(canvas.selected_point,0)]),row,.01,canvas.selected_point).is_empty()
			_number("Largura (m)",float(row.width),.5 if row.get("pathway",false) else 2,30,func(value): _set_value("width",value))
			if region == "harbor" and not row.get("pathway",false):
				_number("Calçada (m)",float(row.get("sidewalk_width",2.625)),0,10,func(value): _set_value("sidewalk_width",value))
				_number("Faixas por sentido",float(row.get("lanes_per_direction",1)),1,2,func(value): _set_value("lanes_per_direction",int(value)),1)
				var crossings := CheckButton.new()
				crossings.text = "Faixas de pedestres"
				crossings.button_pressed = row.get("crossings",true)
				crossings.toggled.connect(func(value): _set_value("crossings",value))
				properties.add_child(crossings)
				_number("Afastar faixas (m)",float(row.get("crossing_offset",0)),0,10,func(value): _set_value("crossing_offset",value))
				_number("Profundidade faixa (m)",float(row.get("crossing_depth",1.875)),.5,5,func(value): _set_value("crossing_depth",value))
			if region == "mountain" and not row.get("pathway",false): _choice("Piso",["asphalt","earth"],["Asfalto","Terra"],str(row.get("surface","asphalt")),func(value): _set_value("surface",value))
			_button(properties,"Adicionar ponto",_add_road_point)
			var remove := _button(properties,"Remover ponto selecionado",_remove_road_point)
			remove.disabled = canvas.selected_point < 0 or row.points.size() <= 2
	var actions := HBoxContainer.new()
	properties.add_child(actions)
	if row.type != "piece":
		if not row.get("paving",false) and not row.get("service_building",false):
			_button(actions,"Copiar",_copy)
			_button(actions,"Duplicar",_duplicate)
	if not row.get("service_building",false): _button(actions,"Excluir",_delete)
	var restore := _button(properties,"Restaurar original",_restore_original)
	restore.disabled = not document.regions.get(region,{}).has(id)

func _number(label: String,value: float,minimum: float,maximum: float,callback: Callable,step := .25) -> void:
	var box := HBoxContainer.new()
	properties.add_child(box)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = value
	input.custom_minimum_size.x = 90
	box.add_child(input)
	input.value_changed.connect(func(new_value): callback.call(new_value))

func _choice(label: String,values: Array,names: Array,current: String,callback: Callable) -> void:
	values = values.duplicate()
	names = names.duplicate()
	if current not in values:
		values.append(current)
		names.append(current.capitalize())
	var input := OptionButton.new()
	input.fit_to_longest_item = false
	input.tooltip_text = label
	for text in names: input.add_item(text)
	input.select(maxi(0,values.find(current)))
	input.item_selected.connect(func(index): callback.call(values[index]))
	properties.add_child(input)

func _color(row: Dictionary) -> void:
	var input := ColorPickerButton.new()
	input.color = Color(row.color)
	input.edit_alpha = false
	input.text = "Cor"
	var id := str(row.id)
	var area := str(row.get("editor_region",region))
	var original := str(row.color)
	input.popup_closed.connect(func():
		# Finish the native popup callback before rebuilding its parent controls.
		# Capture the object's identity now: selection may change before the call.
		var color := input.color.to_html(false)
		if color != original: _commit_color.call_deferred(id,area,original,color))
	properties.add_child(input)

func _commit_color(id: String,area: String,original: String,color: String) -> void:
	if not is_inside_tree() or not canvas.objects.has(id): return
	var row: Dictionary = canvas.objects[id].duplicate(true)
	if row.get("locked",false) or row.get("deleted",false) or str(row.get("color","")) != original: return
	var selection := canvas.selected_id
	var previous_region := region
	row.color = color
	region = area
	_commit(row)
	if selection != id:
		region = previous_region
		_select(selection if canvas.objects.has(selection) else "")

func _set_value(key: String,value: Variant) -> void:
	if not canvas.objects.has(canvas.selected_id): return
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	row[key] = value
	_commit(row)
func _set_array(key: String,index: int,value: float) -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if key == "size" and row.type == "ground" and row.has("outline"):
		var ratio := value/float(row.size[index])
		for point in row.outline: point[index] = float(point[index])*ratio
	row[key][index] = value
	_commit(row)

func _commit(row: Dictionary) -> void:
	row.erase("editor_region")
	if row.type == "ground" and row.has("outline"):
		var extent := _outline_extent(row)
		row.size = [extent.x,extent.y]
	if row.get("type", "") == "piece":
		# Persist transforms only; base triangles stay in the editor catalog.
		var authored := {"id":row.id,"type":"piece","position":row.position,"rotation":row.get("rotation",0),"source_record":row.get("source_record","")}
		if row.get("deleted",false): authored.deleted = true
		for key in ["stretch","outline"]:
			if row.has(key): authored[key] = row[key].duplicate(true)
		row = authored
	if not load_error.is_empty():
		status.text = load_error
		_refresh()
		return
	var error := DATA.validate_entity(row)
	if error.is_empty(): error = _placement_error(row)
	var original: Dictionary = catalog.get(region,{}).get("objects",{}).get(row.id,catalog.get(region,{}).get("context",{}).get(row.id,{}))
	if original.get("locked",false): error = "Este local tem acesso protegido."
	if not row.get("deleted",false) and row.type not in ["road","piece"] and not row.get("paving",false):
		var own_accesses := _service_accesses(canvas.objects.get(row.id,row))
		var new_accesses := _service_accesses(row)
		for entry in canvas.entries:
			var own := false
			for point in own_accesses:
				if point.distance_to(DATA.point(entry)) < .02: own = true; break
			if own: continue
			for point in new_accesses:
				if point.distance_to(DATA.point(entry)) < 1.5: error = "A entrada ficou perto demais de outro acesso. Afaste o prédio."
			var local := (DATA.point(entry)-DATA.point(row.position)).rotated(deg_to_rad(float(row.get("rotation",0))))
			var half := DATA.point(row.size)*.5+Vector2.ONE if row.type in ["building","ground"] else Vector2.ONE
			var covers := Geometry2D.is_point_in_polygon(DATA.point(entry),canvas.corners(row)) if row.type == "ground" else Rect2(-half,half*2).has_point(local)
			if covers: error = "Mantenha livre o acesso marcado em rosa."
	if not error.is_empty():
		status.text = error
		_refresh()
		return
	if document.regions.get(region,{}).get(row.id,{}) == row: return
	_checkpoint()
	document.regions[region][row.id] = row.duplicate(true)
	canvas.selected_id = row.id
	_refresh()
	_write_draft()
	status.text = "Alteração pronta. Salve para aplicá-la na próxima execução do jogo."

func _checkpoint() -> void:
	history.append(document.duplicate(true))
	if history.size() > 100: history.pop_front()
	future.clear()
func undo() -> void:
	if history.is_empty(): return
	future.append(document.duplicate(true))
	document = history.pop_back()
	_refresh()
	_write_draft()
func redo() -> void:
	if future.is_empty(): return
	history.append(document.duplicate(true))
	document = future.pop_back()
	_refresh()
	_write_draft()
func _delete() -> void:
	if not canvas.objects.has(canvas.selected_id): return
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if row.get("locked",false) or row.get("service_building",false):
		status.text = "Este objeto está ligado a um serviço ou acesso protegido."
		return
	row.deleted = true
	_commit(row)
func _duplicate() -> void:
	if not _copy(): return
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	row.id = DATA.new_entity(row.type,Vector2.ZERO).id
	if row.get("paving",false):
		row.erase("paving")
		row.size = [minf(64,row.size[0]),minf(64,row.size[1])]
	row.erase("locked")
	if row.type == "road":
		for p in row.points: p[1] += 12
	else: row.position[0] += float(row.size[0])+2 if row.type == "building" else 3
	_commit(row)
func _restore_original() -> void:
	_restore_id(canvas.selected_id)
func _restore_id(id: String) -> void:
	_checkpoint()
	document.regions[region].erase(id)
	_refresh()
	_write_draft()
func _add_road_point() -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	var index := mini(maxi(canvas.selected_point,0),row.points.size()-2)
	var middle := (DATA.point(row.points[index])+DATA.point(row.points[index+1]))*.5
	row.points.insert(index+1,[middle.x,middle.y])
	canvas.selected_point = index+1
	_commit(row)
func _remove_road_point() -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if canvas.selected_point < 0 or row.points.size() <= 2: return
	row.points.remove_at(canvas.selected_point)
	canvas.selected_point = -1
	_commit(row)

func save() -> bool:
	junction_editor.finish()
	canvas.finish_drag()
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and focused.get_parent() is SpinBox: focused.get_parent().apply()
	if not load_error.is_empty():
		status.text = load_error
		return false
	var error := DATA.save_document(document,expected_hash,edits_path)
	if not error.is_empty():
		status.text = error
		return false
	expected_hash = DATA.disk_hash(edits_path)
	saved_document = document.duplicate(true)
	_write_draft()
	_refresh()
	status.text = "Mundo salvo. A próxima execução do jogo usará estas alterações."
	return true
func _play() -> void:
	if not save(): return
	if Engine.is_editor_hint(): EditorInterface.play_main_scene()
func _write_draft() -> void:
	var file := FileAccess.open(draft_path,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"base_hash":expected_hash,"document":document}))
		file.close()
func _restore_draft() -> void:
	if not FileAccess.file_exists(draft_path): return
	var draft: Variant = JSON.parse_string(FileAccess.get_file_as_string(draft_path))
	if draft is Dictionary and draft.get("base_hash","") == expected_hash and DATA.validate_document(draft.get("document")).is_empty():
		document = draft.document
func _rebuild_catalog() -> void:
	if worker_pid > 0: return
	worker_pid = OS.create_process(OS.get_executable_path(),PackedStringArray(["--minimized","--resolution","64x64","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/export_catalog.gd","--log-file",ProjectSettings.globalize_path("res://.godot/world_editor_catalog.log"),"--","--output="+CACHE_PATH]))
	if worker_pid < 0:
		status.text = "Não foi possível abrir o gerador de catálogo."
		return
	worker_started = Time.get_ticks_msec()
	rebuild_button.disabled = true
	status.text = "Atualizando a base do mundo…"
	worker_timer.start()
func _poll_worker() -> void:
	if OS.is_process_running(worker_pid):
		if Time.get_ticks_msec()-worker_started > 120000:
			status.text = "Catálogo ainda em geração. Consulte .godot/world_editor_catalog.log."
		return
	worker_timer.stop()
	worker_pid = -1
	rebuild_button.disabled = false
	_load_catalog()
	_set_background()
	_refresh()
	status.text = "Base atualizada." if FileAccess.file_exists(CACHE_PATH) else "Falha ao gerar base. Consulte .godot/world_editor_catalog.log."
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()
	elif canvas.has_focus():
		if event.ctrl_pressed and event.keycode == KEY_C: _copy()
		elif event.ctrl_pressed and event.keycode == KEY_V: _paste()
		elif event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed: redo()
			else: undo()
		elif event.keycode == KEY_DELETE: _delete()
		else: return
		get_viewport().set_input_as_handled()

func _placement_error(row: Dictionary) -> String:
	if catalog.is_empty(): return "Clique em Atualizar base antes de editar."
	if row.get("deleted",false): return ""
	if row.type == "piece": return "Mantenha a peça na sua região de origem." if _region_at(DATA.point(row.position)) != region else ""
	if row.type != "road" and _region_at(DATA.point(row.position)) != region: return "Para mover entre regiões, adicione o objeto na região de destino."
	if row.type == "ground":
		if row.get("paving",false): return ""
		for other in canvas.objects.values():
			if other.type == "building" and other.get("locked",false):
				if not Geometry2D.intersect_polygons(canvas.corners(row),canvas.corners(other)).is_empty(): return "Mantenha livre o prédio com serviço."
		return ""
	if free_placement:
		# Free placement allows authored overlaps, while keeping service facades usable.
		if row.type != "road":
			for other in canvas.objects.values():
				if other.type != "building" or not other.get("locked",false): continue
				if row.type == "building":
					if not Geometry2D.intersect_polygons(canvas.corners(row),canvas.corners(other)).is_empty(): return "Este prédio tem acesso protegido."
				else:
					var local := (DATA.point(row.position)-DATA.point(other.position)).rotated(deg_to_rad(float(other.get("rotation",0))))
					var half := DATA.point(other.size)*.5
					if Rect2(-half,half*2).has_point(local): return "Mantenha livre o prédio com serviço."
		return ""
	if row.type == "road":
		# Existing authored roads may already touch facades. Check newly drawn routes;
		# existing roads keep their IDs for traffic and mission compatibility.
		if not str(row.id).begins_with("new/"): return ""
		for building in canvas.objects.values():
			if building.type != "building" or not building.get("locked",false): continue
			for p in row.points:
				var local := (DATA.point(p)-DATA.point(building.position)).rotated(deg_to_rad(float(building.get("rotation",0))))
				var half := DATA.point(building.size)*.5+Vector2.ONE*float(row.width)*.5
				if Rect2(-half,half*2).has_point(local): return "A rua atravessa um local protegido."
		return ""
	var position := DATA.point(row.position)
	var radius := .35*float(row.get("scale",1)) if row.type == "tree" else .3
	var polygon := canvas.corners(row) if row.type == "building" else PackedVector2Array()
	for other in canvas.objects.values():
		if other.id == row.id: continue
		if other.type == "building":
			if row.type == "building":
				if not Geometry2D.intersect_polygons(polygon,canvas.corners(other)).is_empty(): return "O prédio sobrepõe outra construção."
			else:
				var local := (position-DATA.point(other.position)).rotated(deg_to_rad(float(other.get("rotation",0))))
				var half := DATA.point(other.size)*.5+Vector2.ONE*radius
				if Rect2(-half,half*2).has_point(local): return "Escolha um ponto fora da construção."
		elif other.type == "road":
			for i in range(other.points.size()-1):
				var a := DATA.point(other.points[i])
				var b := DATA.point(other.points[i+1])
				if row.type != "building":
					if position.distance_to(Geometry2D.get_closest_point_to_segment(position,a,b)) < float(other.width)*.5+radius: return "Mantenha livre a pista."
				else:
					var normal := (b-a).orthogonal().normalized()*float(other.width)*.5
					if not Geometry2D.intersect_polygons(polygon,PackedVector2Array([a+normal,b+normal,b-normal,a-normal])).is_empty(): return "O prédio invade a pista."
	return ""
func _set_background() -> void:
	canvas.land = catalog.get("harbor",{}).get("land",[])
	canvas.terrain = catalog.get("mountain",{}).get("terrain",[])
	canvas.land_polygons = catalog.get("harbor",{}).get("land_polygons",[])
	canvas.entries = catalog.get("harbor",{}).get("entries",[]).duplicate()
	canvas.entries.append_array(catalog.get("mountain",{}).get("entries",[]))

func _fit_world() -> void:
	var bounds := canvas.world_bounds()
	canvas.center = bounds.get_center()
	canvas.zoom = clampf(minf(canvas.size.x/(bounds.size.x+80),canvas.size.y/(bounds.size.y+80)),CANVAS.MIN_ZOOM,24)
	canvas.queue_redraw()

func _update_locations() -> void:
	locations.clear()
	location_ids.clear()
	locations.add_item("Ir para local…")
	var rows: Array = []
	for row in canvas.objects.values():
		if row.type == "context" or (row.type == "building" and (row.get("locked",false) or row.get("service_building",false))):
			rows.append(row)
	rows.sort_custom(func(a,b): return str(a.get("label",a.id)).naturalnocasecmp_to(str(b.get("label",b.id))) < 0)
	for row in rows:
		location_ids.append(row.id)
		locations.add_item(str(row.get("label",row.id)).trim_prefix("building/")+" · "+str(row.editor_region))

func _go_location(index: int) -> void:
	if index <= 0: return
	var id := location_ids[index-1]
	var row: Dictionary = canvas.objects[id]
	canvas.center = DATA.point(row.position)
	canvas.zoom = clampf(minf(canvas.size.x,canvas.size.y)/maxf(50,DATA.point(row.size).length()*1.2),.3,12)
	_select(id)
	canvas.queue_redraw()

func _toggle_live_preview() -> void:
	if is_instance_valid(live_preview):
		live_preview.stop()
		live_preview.free()
		live_preview = null
		canvas.show()
		view_mode.select(0)
		live_toggle.set_pressed_no_signal(false)
	else:
		live_preview = preload("res://addons/geteco_world_editor/WorldLivePreview.gd").new()
		live_split.add_child(live_preview)
		live_preview.enable_editing(self)
		view_mode.select(2)
		live_preview.focus_requested.connect(_sync_live_preview)
		live_preview.view_moved.connect(func(at: Vector2):
			canvas.center = at
			canvas.queue_redraw()
			live_preview.request(document,at,_region_at(at)))
		live_toggle.set_pressed_no_signal(true)
		_sync_live_preview()
	_apply_layout()

func _set_view_mode(index: int) -> void:
	if index == 0:
		if is_instance_valid(live_preview): _toggle_live_preview()
	else:
		if not is_instance_valid(live_preview): _toggle_live_preview()
		canvas.visible = index == 2
	view_mode.select(index)
	_apply_layout()

func _sync_live_preview() -> void:
	if junction_editor.dragging: return
	if not is_instance_valid(live_preview) or canvas.dragging: return
	if live_preview.edit_control != null:
		live_preview.edit_control.queue_redraw()
		if live_preview.edit_control.synchronizing or live_preview.edit_control.dragging: return
	var at := canvas.center
	if junction_editor.enabled and not junction_editor.current().is_empty(): at = junction_editor.current().position
	elif canvas.objects.has(canvas.selected_id): at = canvas.pivot(canvas.objects[canvas.selected_id])
	live_preview.request(document,at,_region_at(at))

func _preview() -> void:
	var focus := canvas.center
	var width := 55.0
	if canvas.objects.has(canvas.selected_id):
		var row: Dictionary = canvas.objects[canvas.selected_id]
		if row.has("position"): focus = DATA.point(row.position)
		if row.has("size"): width = clampf(DATA.point(row.size).length()*1.4,35,180)
	var preview_path := "res://.godot/world_editor_preview_edits.json"
	var file := FileAccess.open(preview_path,FileAccess.WRITE)
	if file == null:
		status.text = "Não foi possível preparar a prévia."
		return
	file.store_string(JSON.stringify(document))
	file.close()
	var area := "mountain" if focus.x >= 456.25 and focus.y < -125 else "harbor"
	var pid := OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/preview_world.gd","--","--no-save","--edits="+preview_path,"--region="+area,"--x="+str(focus.x),"--z="+str(focus.y),"--size="+str(width)]))
	status.text = "Prévia 3D aberta. Setas movem a câmera; Esc fecha. O progresso do jogo não é salvo." if pid > 0 else "Não foi possível abrir a prévia 3D."
func _region_at(at: Vector2) -> String:
	return "mountain" if at.x >= 456.25 and at.y < -125 else "harbor"

func _place(type: String,at: Vector2) -> void:
	if type == "continue_road":
		if not canvas.objects.has(canvas.selected_id): return
		var extended: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
		var join := canvas.road_connection(at,extended,minf(6,maxf(1.5,14.0/canvas.zoom)),canvas.selected_point) if canvas.road_snap_enabled else {}
		if not join.is_empty(): at = join.point
		if canvas.selected_point == 0: extended.points.push_front([at.x,at.y])
		else:
			extended.points.append([at.x,at.y])
			canvas.selected_point = extended.points.size()-1
		canvas.armed = ""
		_commit(extended)
		return
	region = _region_at(at)
	canvas.region = region
	var row := _clone_at(placement_template,at) if not placement_template.is_empty() else DATA.new_entity(type,at)
	placement_template = {}
	canvas.armed = ""
	canvas.filter_type = "all"
	_commit(row)

func _build_library(parent: Node) -> void:
	var panel := VBoxContainer.new()
	library_panel = panel
	panel.custom_minimum_size = Vector2(210,200)
	panel.add_theme_constant_override("separation",8)
	parent.add_child(panel)
	var title := Label.new()
	title.text = "Biblioteca"
	title.add_theme_font_size_override("font_size",16)
	panel.add_child(title)
	asset_search = LineEdit.new()
	asset_search.placeholder_text = "Buscar assets…"
	asset_search.clear_button_enabled = true
	asset_search.text_changed.connect(func(_value): _filter_assets())
	panel.add_child(asset_search)
	asset_filter = OptionButton.new()
	asset_filter.fit_to_longest_item = false
	for label in ["Todos os assets","Prédios","Objetos","Árvores","Ruas","Luzes","Peças do mundo","Terrenos e pisos"]: asset_filter.add_item(label)
	asset_filter.item_selected.connect(func(_index): _filter_assets())
	panel.add_child(asset_filter)
	asset_list = ItemList.new()
	asset_list.set_drag_forwarding(_asset_drag,Callable(),Callable())
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.fixed_icon_size = Vector2i(56,42)
	asset_list.add_theme_constant_override("v_separation",5)
	asset_list.auto_height = false
	asset_list.item_activated.connect(_arm_asset)
	panel.add_child(asset_list)
	_button(panel,"Usar selecionado",func():
		var selected := asset_list.get_selected_items()
		if not selected.is_empty(): _arm_asset(selected[0]))
	asset_count = Label.new()
	panel.add_child(asset_count)
	asset_list.tooltip_text = "Duplo clique e clique no mapa para colocar. Ctrl+C / Ctrl+V no mapa copia e cola. Esc cancela."

func _filter_assets() -> void:
	if asset_list == null: return
	asset_list.clear()
	visible_assets.clear()
	var query := LIBRARY.normalized(asset_search.text.strip_edges())
	var type: String = ["all","building","prop","tree","road","light","piece","ground"][asset_filter.selected]
	for item in asset_items:
		if type != "all" and item.type != type: continue
		var matches := true
		for word in query.split(" ",false):
			if not str(item.search).contains(word): matches = false
		if not matches: continue
		asset_list.add_item(item.label,_asset_icon(item))
		asset_list.set_item_tooltip(asset_list.item_count-1,"Selecionar peça existente" if item.action == "select" else "Colocar no mundo: "+str(item.label))
		visible_assets.append(item)
	asset_count.text = "%d itens" % visible_assets.size()

func _asset_drag(at: Vector2) -> Variant:
	var index := asset_list.get_item_at_position(at,true)
	if index < 0 or index >= visible_assets.size(): return null
	var item: Dictionary = visible_assets[index]
	if item.action == "select": return null
	var hint := Label.new()
	hint.text = item.label
	asset_list.set_drag_preview(hint)
	return {"geteco_asset":true,"item":item.duplicate(true)}

func _arm_asset(index: int) -> void:
	if index < 0 or index >= visible_assets.size(): return
	var item: Dictionary = visible_assets[index]
	if item.action == "select":
		var row: Dictionary = canvas.objects.get(item.row.id,{})
		if row.is_empty(): return
		canvas.center = DATA.point(row.position)
		canvas.zoom = 10
		_select(row.id)
		canvas.queue_redraw()
		canvas.grab_focus()
		status.text = "Peça existente selecionada. Arraste para mover ou ajuste a rotação à direita."
		return
	placement_template = item.row.duplicate(true)
	canvas.armed = item.row.type
	canvas.grab_focus()
	status.text = str(item.label)+": clique no mapa para colocar. Esc cancela."

func _copy() -> bool:
	if not canvas.objects.has(canvas.selected_id): return false
	var row: Dictionary = canvas.objects[canvas.selected_id]
	if row.get("locked",false) or row.get("paving",false) or row.get("service_building",false) or row.type in ["piece","context"]:
		status.text = "Esta peça mantém sua identidade no mundo. Arraste para mover."
		return false
	if row.type == "building" and row.model not in DATA.BUILDING_TYPES:
		status.text = "Use um modelo de prédio da biblioteca para criar uma nova construção."
		return false
	clipboard_row = row.duplicate(true)
	status.text = "Copiado. Ctrl+V e clique no destino para colar."
	return true

func _paste() -> void:
	if clipboard_row.is_empty():
		status.text = "Selecione um objeto e pressione Ctrl+C primeiro."
		return
	placement_template = clipboard_row.duplicate(true)
	canvas.armed = placement_template.type
	status.text = "Clique no destino para colar. Esc cancela."

func _clone_at(template: Dictionary,at: Vector2) -> Dictionary:
	var row := template.duplicate(true)
	row.id = DATA.new_entity(row.type,at).id
	for key in ["locked","deleted","editor_region"]: row.erase(key)
	if row.type == "road":
		var anchor := Vector2.ZERO
		for point in row.points: anchor += DATA.point(point)
		anchor /= row.points.size()
		for i in row.points.size():
			var point := DATA.point(row.points[i])+at-anchor
			row.points[i] = [point.x,point.y]
	else: row.position = [at.x,at.y]
	return row

func _asset_icon(item: Dictionary) -> Texture2D:
	var model := "ground_"+str(item.row.surface) if item.type == "ground" else str(item.row.get("model",item.type))
	if asset_icons.has(model): return asset_icons[model]
	var path := "res://addons/geteco_world_editor/thumbnails/"+model+".png"
	var icon: Image
	if item.type == "ground":
		icon = preload("res://world/editing/WorldGroundFactory.gd").texture(item.row.surface)
	elif FileAccess.file_exists(path):
		icon = Image.new()
		icon.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	else:
		var colors := {"building":"ac9473","prop":"b8a27a","tree":"64997d","road":"8c9ca5","light":"efd78b","piece":"9db7c4"}
		icon = Image.create(16,16,false,Image.FORMAT_RGBA8)
		icon.fill(Color(colors.get(item.type,"819590")))
	var texture := ImageTexture.create_from_image(icon)
	asset_icons[model] = texture
	return texture

func _toggle_sidebar(which: String) -> void:
	if which == "library": library_requested = not library_panel.visible
	else: properties_requested = not properties_scroll.visible
	active_sidebar = which
	map_expanded = false
	_apply_layout()

func _apply_layout() -> void:
	# Keep map coordinates stable while a click becomes a drag. Open panels on release.
	if canvas != null and canvas.dragging: return
	if is_instance_valid(live_preview) and live_preview.edit_control != null and (live_preview.edit_control.dragging or live_preview.edit_control.synchronizing): return
	if library_panel == null or properties_scroll == null: return
	var show_library := library_requested and not map_expanded
	var has_selection: bool = canvas != null and canvas.objects.has(canvas.selected_id)
	var show_properties := properties_requested and not map_expanded and (has_selection or active_sidebar == "properties")
	if is_instance_valid(live_preview) and size.x < 760:
		show_library = false
		show_properties = false
	# The available plugin area matters, including when Godot's own docks are open.
	if size.x < 1100 and show_library and show_properties:
		show_library = active_sidebar == "library"
		show_properties = not show_library
	library_panel.visible = show_library
	properties_scroll.visible = show_properties
	library_toggle.set_pressed_no_signal(show_library)
	properties_toggle.set_pressed_no_signal(show_properties)
	focus_toggle.set_pressed_no_signal(map_expanded)
	focus_toggle.text = "Restaurar painéis" if map_expanded else "Ampliar mapa"
	save_state.visible = size.x >= 1100
	if _announced_map_expanded != map_expanded:
		_announced_map_expanded = map_expanded
		map_focus_changed.emit(map_expanded)

func _layout_option(id: int) -> void:
	var menu := options_menu.get_popup()
	match id:
		0,1:
			var index := menu.get_item_index(id)
			menu.set_item_checked(index,not menu.is_item_checked(index))
			if id == 0: canvas.grid = 1.0 if menu.is_item_checked(index) else 0.0
			else: free_placement = menu.is_item_checked(index)
		2:
			canvas.center = DATA.point(catalog.get(region,{}).get("spawn",[45,110]))
			canvas.zoom = 4
			canvas.queue_redraw()
		3: _rebuild_catalog()
		4:
			canvas.road_snap_enabled = not canvas.road_snap_enabled
			menu.set_item_checked(menu.get_item_index(4),canvas.road_snap_enabled)

func _continue_road() -> void:
	canvas.armed = "continue_road"
	canvas.grab_focus()
	status.text = "Clique no destino para continuar a rua. Esc cancela."

func _create_road_return() -> void:
	var source: Dictionary = canvas.objects[canvas.selected_id]
	var index := canvas.selected_point
	if index not in [0,source.points.size()-1]: return
	var at := DATA.point(source.points[index])
	var adjacent := DATA.point(source.points[1 if index == 0 else index-1])
	var forward := (at-adjacent).normalized()
	var side := forward.orthogonal()
	var radius := maxf(8,float(source.width)*1.5)
	var row := DATA.new_entity("road",at)
	row.width = source.width
	row.surface = source.get("surface","asphalt")
	# Rejoin the approach behind the endpoint so the existing final segment belongs
	# to the circuit too; a circle touching only the tip would strand incoming cars.
	var join := at-forward*minf(radius,at.distance_to(adjacent)*.65)
	row.points = []
	for point in [at,at+forward*radius,at+forward*radius+side*radius*2,join+side*radius*2,join]:
		row.points.append([point.x,point.y])
	canvas.selected_point = -1
	_commit(row)

func _base_outline(row: Dictionary) -> Array:
	var points := PackedVector2Array()
	for part in row.get("parts",[]):
		if part.size() > 6:
			for point in part[6]: points.append(DATA.point(point)-DATA.point(row.position))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[-1]): hull.remove_at(hull.size()-1)
	var result: Array = []
	for point in hull: result.append([point.x,point.y])
	return result

func _resize_piece(axis: int,value: float) -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	var stretch: Array = row.get("stretch",[1.0,1.0]).duplicate()
	stretch[axis] = value/_outline_extent(row)[axis]
	row.stretch = stretch
	_commit(row)

func _shape_controls(_row: Dictionary) -> void:
	var toggle := _button(properties,"Editar pontos",_toggle_points)
	toggle.toggle_mode = true
	toggle.button_pressed = canvas.edit_points
	if canvas.edit_points:
		_button(properties,"Adicionar ponto",_add_shape_point)
		var remove := _button(properties,"Remover ponto",_remove_shape_point)
		remove.disabled = canvas.selected_point < 0 or canvas.local_outline(_row).size() <= 3

func _toggle_points() -> void:
	canvas.edit_points = not canvas.edit_points
	canvas.selected_point = -1
	if canvas.edit_points and not canvas.objects[canvas.selected_id].has("outline"):
		var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
		row.outline = canvas.local_outline(row).duplicate(true)
		_commit(row)
	else: _select(canvas.selected_id)
	canvas.queue_redraw()

func _add_shape_point() -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if not row.has("outline") or row.outline.size() >= 32: return
	var index := canvas.selected_point
	if index < 0:
		var longest := -1.0
		for i in row.outline.size():
			var length := DATA.point(row.outline[i]).distance_squared_to(DATA.point(row.outline[(i+1)%row.outline.size()]))
			if length > longest: longest = length; index = i
	var midpoint := (DATA.point(row.outline[index])+DATA.point(row.outline[(index+1)%row.outline.size()]))*.5
	row.outline.insert(index+1,[midpoint.x,midpoint.y])
	canvas.selected_point = index+1
	_commit(row)

func _remove_shape_point() -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if not row.has("outline") or row.outline.size() <= 3 or canvas.selected_point < 0: return
	row.outline.remove_at(canvas.selected_point)
	canvas.selected_point = -1
	_commit(row)

func _outline_extent(row: Dictionary) -> Vector2:
	if not row.has("outline") or row.outline.is_empty(): return DATA.point(row.size)
	var bounds := Rect2(DATA.point(row.outline[0]),Vector2.ZERO)
	for point in row.outline: bounds = bounds.expand(DATA.point(point))
	return bounds.size
