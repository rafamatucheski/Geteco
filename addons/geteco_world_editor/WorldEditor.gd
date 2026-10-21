@tool
extends VBoxContainer
signal map_focus_changed(expanded: bool)
signal ready_to_edit
var deferred_bootstrap := false
var initialized := false
var _startup_error := ""
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
var region_selector: OptionButton
var location_ids: Array[String] = []
var asset_search: LineEdit
var asset_filter: OptionButton
var asset_list: ItemList
var asset_count: Label
var asset_items: Array[Dictionary] = []
var visible_assets: Array[Dictionary] = []
var placement_template: Dictionary = {}
var clipboard_row: Dictionary = {}
var capture_error := ""
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
var active_interior := ""
var environment_loading := false
var environment_generation := 0
var unit_index_generation := 0
var interior_floor := 0
var interior_catalog: Dictionary = {}
var interior_validation: Dictionary = {}
var interior_selector: OptionButton
var interior_floor_selector: SpinBox
var interior_ids: Array[String] = [""]
var exterior_view := {}
var region_bounds_cache: Dictionary = {}
var terrain_mode := false
var background_topography_enabled := true
var topography_loader: Control
var topography_status: Label
var topography_timer: Timer
var topography_cache: Dictionary = {}
var topography_cache_order: Array[String] = []
var topography_requested := ""
var topography_installed: Dictionary = {}
var topography_units_installed: Dictionary = {}
var topography_unit_jobs: Dictionary = {}
var terrain_toggle: Button
var terrain_settings := {"affect_track":false,"radius":12.0,"mode":"offset","height":0.0,"strength":1.0,"falloff":.5,"surface":"earth"}
var view_mode: OptionButton
const LOG_LIMIT := 200
var activity_log: Array[String] = []
var log_view: TextEdit
var log_dialog: AcceptDialog
var restored_draft := false
var last_refresh_profile: Dictionary = {}
var worker_output := ""
var worker_log := ""
var worker_cancel: Button
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
	var logs := _button(header,"Logs",_show_logs)
	logs.tooltip_text = "Histórico desta sessão, erros e caminhos dos logs auxiliares"
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
	region_selector = regions
	for label in ["Mundo inteiro","Harbor","Montanha","Deserto"]: regions.add_item(label)
	regions.select(1)
	regions.item_selected.connect(func(index):
		if index == 0: _fit_world()
		else: _switch_region(["harbor","mountain","desert"][index-1],true,true))
	actions_bar.add_child(regions)
	interior_selector = OptionButton.new()
	interior_selector.fit_to_longest_item = false
	interior_selector.custom_minimum_size.x = 150
	interior_selector.tooltip_text = "Escolher exterior ou interior de uma casa/empresa"
	interior_selector.add_item("Exterior")
	for definition in preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd").definitions():
		interior_ids.append(str(definition.id))
		interior_selector.add_item(str(definition.get("original_name",definition.id)))
	interior_selector.item_selected.connect(func(index): _switch_interior(interior_ids[index]))
	actions_bar.add_child(interior_selector)
	interior_floor_selector = SpinBox.new()
	interior_floor_selector.prefix = "Andar "
	interior_floor_selector.min_value = 0
	interior_floor_selector.max_value = 20
	interior_floor_selector.step = 1
	interior_floor_selector.value_changed.connect(func(value):
		interior_floor = int(value)
		if not active_interior.is_empty():
			interior_catalog.erase(_interior_key())
			_refresh()
			if is_instance_valid(live_preview): live_preview.refresh()
			_sync_live_preview())
	interior_floor_selector.hide()
	actions_bar.add_child(interior_floor_selector)
	regions.tooltip_text = "Ir para um mapa; todos continuam visíveis em 2D"
	_button(actions_bar,"Selecionar",func():
		_set_terrain_mode(false)
		junction_editor.set_enabled(false)
		placement_template.clear()
		canvas.armed = ""
		canvas.queue_redraw()
		_report("Selecione e arraste um objeto."))
	terrain_toggle = _button(actions_bar,"Terreno",func(): _set_terrain_mode(terrain_toggle.button_pressed))
	terrain_toggle.toggle_mode = true
	terrain_toggle.tooltip_text = "Esculpir relevo e pintar o chão real da montanha e do motocross"
	rotation_toggle = _button(actions_bar,"Girar",func():
		canvas.cancel_drag()
		canvas.rotation_enabled = rotation_toggle.button_pressed
		canvas.queue_redraw()
		_select(canvas.selected_id))
	rotation_toggle.toggle_mode = true
	rotation_toggle.tooltip_text = "Ativar/desativar o círculo verde de rotação"
	var add := MenuButton.new()
	add.text = "Adicionar"
	for label in ["Árvore","Prédio","Rua","Poste com braço lateral","Terreno / grama"]: add.get_popup().add_item(label)
	add.get_popup().id_pressed.connect(func(index):
		placement_template.clear()
		canvas.armed = ["tree","building","road","light","ground"][index]
		canvas.queue_redraw()
		canvas.grab_focus()
		_report("Clique no mapa para colocar. Esc cancela."))
	actions_bar.add_child(add)
	undo_button = _button(actions_bar,"Desfazer",undo)
	redo_button = _button(actions_bar,"Refazer",redo)
	_button(actions_bar,"Prévia 3D",_preview)
	var play_here := _button(actions_bar,"▶ Jogar aqui",_play_here)
	play_here.tooltip_text = "Abre o jogo com Dante no objeto selecionado (ou no centro da visão), com as alterações ainda não salvas. Nada é gravado."
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
	for label in ["Todos","Árvores","Prédios","Ruas","Luzes","Objetos","Peças","Locais","Pisos e calçadas","Bueiros"]: filter.add_item(label)
	filter.item_selected.connect(func(index):
		canvas.filter_type = ["all","tree","building","road","light","prop","piece","context","ground","manhole"][index]
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
	menu.add_item("Enquadrar mapa atual",5)
	menu.add_item("Recarregar relevo 2D",29)
	menu.add_check_item("Limites dos mapas",6)
	menu.set_item_checked(menu.get_item_index(6),true)
	menu.add_item("Atualizar base",3)
	menu.add_separator()
	for action in [["Copiar · Ctrl+C",24],["Colar · Ctrl+V",25],["Duplicar · Ctrl+D",27],["Excluir · Del",26],["Desfazer · Ctrl+Z",20],["Refazer · Ctrl+Y",21],["Prévia 3D em outra janela",22],["Jogar aqui",23],["Girar objetos",28]]:
		menu.add_item(action[0],action[1])
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
	var status_bar := HBoxContainer.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(status)
	topography_status = Label.new()
	topography_status.clip_text = true
	topography_status.custom_minimum_size.x = 260
	topography_status.hide()
	status_bar.add_child(topography_status)
	topography_timer = Timer.new()
	topography_timer.wait_time = .5
	topography_timer.timeout.connect(_poll_topography)
	add_child(topography_timer)
	topography_timer.start()
	worker_cancel = _button(status_bar,"Cancelar carga",_cancel_catalog)
	worker_cancel.hide()
	add_child(status_bar)
	log_dialog = AcceptDialog.new()
	log_dialog.title = "Atividade do editor de mundo"
	log_dialog.min_size = Vector2i(600,300)
	add_child(log_dialog)
	var log_box := VBoxContainer.new()
	log_dialog.add_child(log_box)
	var log_actions := HBoxContainer.new()
	log_box.add_child(log_actions)
	_button(log_actions,"Atualizar",func(): log_view.text = _collect_logs())
	_button(log_actions,"Copiar logs",func(): DisplayServer.clipboard_set(_collect_logs()))
	log_view = TextEdit.new()
	log_view.editable = false
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(560,230)
	log_box.add_child(log_view)
	resized.connect(_apply_layout)
	_apply_layout()
	worker_timer = Timer.new()
	worker_timer.wait_time = .5
	worker_timer.timeout.connect(_poll_worker)
	add_child(worker_timer)
	if deferred_bootstrap:
		load_error = "Preparando os mapas. Aguarde a conclusão da carga."
		save_button.disabled = true
		_report("Preparando os mapas…")
		_bootstrap_deferred.call_deferred(weakref(self),get_tree())
	else: _bootstrap()

func _bootstrap() -> void:
	_report("1/3 · Lendo alterações salvas…")
	_load_saved_document()
	_report("2/3 · Carregando catálogo dos mapas…")
	_load_catalog()
	_report("3/3 · Preparando mapa e seleção…")
	_finish_bootstrap()

static func _bootstrap_deferred(reference: WeakRef,tree: SceneTree) -> void:
	var editor = reference.get_ref()
	if not is_instance_valid(editor): return
	editor._report("1/3 · Lendo alterações salvas…")
	await tree.process_frame
	editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return
	editor._load_saved_document()
	editor._report("2/3 · Carregando catálogo dos mapas…")
	await tree.process_frame
	editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return
	editor._load_catalog()
	editor._report("3/3 · Preparando mapa e seleção…")
	await tree.process_frame
	editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return
	editor._finish_bootstrap(false)
	editor._report("Indexando mapa 2D…")
	var canvas_reference: WeakRef = weakref(editor.canvas)
	var progress := Callable(editor,"_bootstrap_index_progress")
	var indexer = load("res://addons/geteco_world_editor/WorldMapContextIndex.gd")
	if indexer == null:
		editor._report("Não foi possível iniciar a indexação do mapa 2D.","error")
		return
	var indexed: bool = await indexer.build(canvas_reference,tree,3000,progress)
	editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return
	if not indexed:
		editor._report("A preparação do mapa 2D foi interrompida. Reabra o editor de mundo.","error")
		return
	editor._complete_bootstrap()

func _bootstrap_index_progress(done: int,total: int) -> void:
	status.text = "Preparando índice do mapa 2D…" if total <= 0 else "Indexando mapa 2D · %d / %d · %d%%" % [done,total,int(100.0*done/total)]
	status.tooltip_text = status.text

func _load_saved_document() -> void:
	var loaded := DATA.read_document(edits_path)
	junction_editor.setup(self)
	canvas.junction_editor = junction_editor
	load_error = loaded.error
	if load_error.is_empty():
		document = loaded.document
		saved_document = document.duplicate(true)
		expected_hash = DATA.disk_hash(edits_path)
		_restore_draft()
		_invalidate_interior_validation(saved_document,document)

func _finish_bootstrap(build_context := true) -> void:
	_switch_region(region,build_context)
	if build_context: _complete_bootstrap()

func _complete_bootstrap() -> void:
	_report("Rascunho recuperado. Revise as alterações e use Salvar mundo para aplicá-las." if restored_draft else "Pronto · Arraste para mover · Ctrl+C / Ctrl+V para copiar e colar · Ctrl+S para salvar.")
	if not load_error.is_empty(): _report(load_error,"error")
	elif not _startup_error.is_empty(): _report(_startup_error,"error")
	initialized = true
	_refresh_controls()
	ready_to_edit.emit()

func _report(message: String,level: String = "info") -> void:
	if not initialized and level == "error": _startup_error = message
	if status != null:
		status.text = message
		status.tooltip_text = message
		status.modulate = Color("f3af93") if level == "error" else Color.WHITE
	var line := "%s [%s] %s" % [Time.get_time_string_from_system(),level.to_upper(),message]
	activity_log.append(line)
	if activity_log.size() > LOG_LIMIT: activity_log.pop_front()
	if log_view != null and log_dialog.visible: log_view.text = _collect_logs()
	print("WORLD_EDITOR ",line)

func _collect_logs() -> String:
	var text := "\n".join(activity_log)
	var paths: Array[String] = []
	if not worker_log.is_empty(): paths.append(worker_log)
	if is_instance_valid(live_preview) and not str(live_preview.folder).is_empty(): paths.append(str(live_preview.folder)+"/worker.log")
	if is_instance_valid(topography_loader) and not str(topography_loader.folder).is_empty(): paths.append(str(topography_loader.folder)+"/worker.log")
	for path in paths:
		if not FileAccess.file_exists(path): continue
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: continue
		file.seek(maxi(0,file.get_length()-32768))
		text += "\n\n--- "+ProjectSettings.globalize_path(path)+" ---\n"+file.get_buffer(32768).get_string_from_utf8()
		file.close()
	return text

func _show_logs() -> void:
	log_view.text = _collect_logs()
	log_dialog.popup_centered_ratio(.7)

func _cancel_catalog() -> void:
	if worker_pid <= 0: return
	if OS.is_process_running(worker_pid): OS.kill(worker_pid)
	worker_pid = -1
	worker_timer.stop()
	worker_cancel.hide()
	rebuild_button.disabled = false
	_report("Atualização cancelada. O catálogo anterior e suas alterações continuam disponíveis.")

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
		_report("Catálogo ausente. Use Opções > Atualizar base.","error")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("regions") is Dictionary:
		_report("Catálogo inválido: "+path+". Tentando catálogo original.","error")
		path = CATALOG_PATH
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("regions") is Dictionary:
		_report("Não foi possível carregar os mapas. Use Opções > Atualizar base.","error")
		return
	catalog = parsed.regions
	region_bounds_cache.clear()
	if not catalog.has("desert"):
		var desert := preload("res://addons/geteco_world_editor/WorldDesertCatalog.gd").read()
		if not desert.is_empty(): catalog.desert = desert
	if catalog.has("desert"): preload("res://addons/geteco_world_editor/WorldDesertCatalog.gd").add_locations(catalog.desert)
	SESSION_CONTEXT.upgrade(catalog,SESSION_CONTEXT.read(),FileAccess.get_modified_time(SESSION_CONTEXT.PATH)>FileAccess.get_modified_time(path))
	# Lugares do runtime que o catálogo gravado não tem (supermercado, arcade, parque...).
	preload("res://addons/geteco_world_editor/WorldPlaceCatalog.gd").add_missing(catalog)
	DATA.normalize_catalog_heights(catalog)
	preload("res://runtime/UrbanTransitPresentation.gd").upgrade_editor_catalog(catalog)
	if catalog.has("harbor"):
		catalog.harbor.objects.merge(preload("res://world/editing/WorldPaving.gd").catalog(),true)
	# Bueiros e entradas subterrâneas moram no código, não no catálogo gravado: entram a cada carga.
	for area in ["harbor","desert"]:
		if catalog.has(area): catalog[area].objects.merge(preload("res://world/editing/WorldManholes.gd").catalog(area),true)
	# Nada é protegido: peças que antes eram só visíveis (poste, fio, luz, equipamento) também
	# se movem. `warn` apenas avisa que há mecânica/gatilho que o visual não leva junto.
	for area in catalog:
		for row in catalog[area].get("context",{}).values():
			if row.get("kind","") == "motocross_course": row["label"] = "Motocross"
			if row.get("type","") == "piece" and row.get("locked",false):
				row.locked = false
				row.warn = true
		for row in catalog[area].get("objects",{}).values():
			if row.get("locked",false):
				row.locked = false
				row.warn = true
	asset_items = LIBRARY.build(catalog)
	for spec in [["Terreno do motocross",Vector2(-176,-96),"motocross"],["Terreno da montanha",Vector2(650,-400),"mountain"]]:
		var terrain_row := DATA.new_entity("terrain",spec[1])
		terrain_row["target"] = spec[2]
		var terrain_item := LIBRARY.entry(spec[0],terrain_row,"relevo altura textura encosta montanha motocross")
		terrain_item["action"] = "terrain_mode"
		asset_items.append(terrain_item)
	for area in catalog:
		for row in catalog[area].get("context",{}).values():
			if row.type != "piece": continue
			var item := LIBRARY.entry(str(row.get("label",row.id)),row,str(row.id))
			item.action = "select"
			asset_items.append(item)
	_filter_assets()

func _interior_key() -> String:
	return active_interior+"/%d" % interior_floor

func _scope_changes() -> Dictionary:
	return document.get("interiors",{}).get(active_interior,{}) if not active_interior.is_empty() else document.regions.get(region,{})

func _switch_interior(id: String) -> void:
	if deferred_bootstrap and not initialized:
		_report("Aguarde a preparação dos mapas antes de abrir um interior.")
		return
	if id == active_interior: return
	canvas.cancel_drag()
	_set_terrain_mode(false)
	junction_editor.set_enabled(false)
	if active_interior.is_empty(): exterior_view = {"center":canvas.center,"zoom":canvas.zoom,"region":region}
	environment_generation += 1
	active_interior = id
	environment_loading = false
	interior_floor = 0
	interior_floor_selector.set_value_no_signal(0)
	canvas.selected_id = ""
	placement_template.clear()
	canvas.armed = ""
	canvas.objects.clear()
	canvas.rebuild_context()
	if id.is_empty():
		region = str(exterior_view.get("region",region))
		interior_floor_selector.hide()
		terrain_toggle.disabled = false
		_set_background()
		environment_loading = true
		_refresh([],true,false)
		_finish_exterior_index.call_deferred(weakref(self),get_tree(),environment_generation)
		canvas.center = exterior_view.get("center",canvas.center)
		canvas.zoom = float(exterior_view.get("zoom",canvas.zoom))
		_sync_live_preview()
		_report("Preparando exterior · Alterações dos interiores preservadas no rascunho.")
	else:
		var definition: Dictionary = preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd").definition(id)
		region = str(definition.get("region","harbor"))
		interior_floor_selector.max_value = int(definition.get("floor_count",0))
		interior_floor_selector.visible = int(definition.get("floor_count",0)) > 0
		terrain_toggle.disabled = true
		canvas.center = Vector2.ZERO
		canvas.zoom = clampf(minf(canvas.size.x,canvas.size.y)/maxf(10,float(definition.get("camera_size",16))*1.5),4,24)
		_set_background()
		_refresh()
		if not is_instance_valid(live_preview): _set_view_mode(1)
		if is_instance_valid(live_preview):
			live_preview.view_size = float(definition.get("camera_size",16))*1.5
			live_preview.yaw = 0.0
			live_preview.pitch = atan2(18.0,15.0)
			live_preview.refresh()
		_sync_live_preview()
		_report("Interior: "+str(definition.get("original_name",id))+" · Selecione móveis, paredes e piso para editar.")
	interior_selector.select(maxi(0,interior_ids.find(id)))
	canvas.queue_redraw()

static func _finish_exterior_index(reference: WeakRef,tree: SceneTree,generation: int) -> void:
	var editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree() or not editor.active_interior.is_empty() or editor.environment_generation != generation: return
	var indexer = load("res://addons/geteco_world_editor/WorldMapContextIndex.gd")
	if indexer == null:
		editor.environment_loading = false
		editor._report("Não foi possível preparar o índice do exterior.","error")
		return
	var indexed: bool = await indexer.build(weakref(editor.canvas),tree,3000,Callable(editor,"_exterior_index_progress"))
	editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree() or not editor.active_interior.is_empty() or editor.environment_generation != generation: return
	editor.environment_loading = false
	editor._refresh_controls()
	if not indexed:
		editor._report("A indexação do exterior foi interrompida.","error")
		return
	editor._sync_live_preview()
	editor._report("Exterior pronto · Alterações dos interiores preservadas no rascunho.")

func _exterior_index_progress(done: int,total: int) -> void:
	if active_interior.is_empty() and environment_loading: _bootstrap_index_progress(done,total)

func _refresh_interior(changed_ids: Array,full: bool) -> void:
	var started := Time.get_ticks_usec()
	canvas.cancel_drag()
	_set_background()
	var sources: Dictionary = interior_catalog.get(_interior_key(),{}).get("context",{})
	var ids := sources.keys()
	for id in _scope_changes():
		var change: Dictionary = _scope_changes()[id]
		if int(change.get("interior_floor",0)) != interior_floor: continue
		if change.get("type","") == "piece" and not sources.has(id) and not sources.has(str(change.get("clone_of",""))): continue
		if id not in ids: ids.append(id)
	canvas.objects.clear()
	for id in ids:
		var row := _effective_row(region,str(id))
		if not row.is_empty(): canvas.objects[id] = row
	canvas.rebuild_context()
	_update_locations()
	_refresh_controls()
	_select(canvas.selected_id)
	canvas.queue_redraw()
	last_refresh_profile = {"mode":"interior","changed":changed_ids.size(),"full":full,"total_ms":(Time.get_ticks_usec()-started)/1000.0}
	print("WORLD_EDITOR_REFRESH ",JSON.stringify(last_refresh_profile))

func _merge_interior_units(id: String,rows: Array) -> void:
	if id != active_interior: return
	var source_floor := int(rows[0].get("interior_floor",0)) if not rows.is_empty() else interior_floor
	var context := {}
	var bounds := Rect2()
	var has_bounds := false
	for row in rows:
		context[str(row.id)] = row
		var extent := DATA.point(row.get("size",[1,1]))
		var rect := Rect2(DATA.point(row.position)-extent*.5,extent)
		bounds = bounds.merge(rect) if has_bounds else rect
		has_bounds = true
	interior_catalog[id+"/%d" % source_floor] = {"objects":{},"context":context,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}
	if source_floor != interior_floor: return
	_merging_units = true
	_refresh()
	_merging_units = false
	_refresh_controls()

func _validation_key(id: String,floor_index: int) -> String:
	return id+"/%d" % floor_index

static func _floor_changes(source: Dictionary,id: String,floor_index: int) -> Dictionary:
	var result := {}
	for key in source.get("interiors",{}).get(id,{}):
		var row: Dictionary = source.interiors[id][key]
		if int(row.get("interior_floor",0)) == floor_index: result[key] = row
	return result

func _interior_validation_ready(id: String,error: String,incoming: Dictionary,floor_index := 0) -> void:
	var current := _floor_changes(document,id,floor_index)
	if not _equivalent(_floor_changes(incoming,id,floor_index),current): return
	var key := _validation_key(id,floor_index)
	if current.is_empty(): interior_validation.erase(key)
	else: interior_validation[key] = error
	if not error.is_empty(): _report(id+" · Andar %d: " % floor_index+error,"error")
	_refresh_controls()

func _invalidate_interior_validation(before: Dictionary,after: Dictionary) -> void:
	var ids: Array = before.get("interiors",{}).keys()
	for id in after.get("interiors",{}):
		if id not in ids: ids.append(id)
	for id in ids:
		var floors := {}
		for source in [before,after]:
			for row in source.get("interiors",{}).get(id,{}).values(): floors[int(row.get("interior_floor",0))] = true
		for floor_index in floors:
			var key := _validation_key(str(id),int(floor_index))
			var current := _floor_changes(after,str(id),int(floor_index))
			if current.is_empty(): interior_validation.erase(key)
			elif not _equivalent(_floor_changes(before,str(id),int(floor_index)),current):
				interior_validation[key] = "Reabra este interior neste andar e aguarde a validação 3D antes de salvar."

static func _equivalent(a: Variant,b: Variant) -> bool:
	if DATA.number(a) and DATA.number(b): return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _equivalent(a[i],b[i]): return false
		return true
	return a == b

func _switch_region(value: String,build_context := true,fit_view := false) -> void:
	if not active_interior.is_empty():
		_report("Escolha Exterior para navegar pelos mapas.")
		return
	if deferred_bootstrap and not initialized and build_context:
		_report("Aguarde a preparação dos mapas antes de trocar de região.")
		return
	region = value
	canvas.region = value
	canvas.selected_id = ""
	canvas.selected_point = -1
	canvas.center = DATA.point(catalog.get(region,{}).get("spawn",[45,110]))
	_set_background()
	_refresh([],canvas.objects.is_empty(),build_context)
	if fit_view: _frame_region()
	_report("Mapa: "+{"harbor":"Harbor","mountain":"Montanha","desert":"Deserto"}.get(region,region)+" · %d objetos disponíveis em 2D" % canvas.objects.size())

func _refresh(changed_ids: Array = [],full := true,build_context := true) -> void:
	if not active_interior.is_empty():
		_refresh_interior(changed_ids,full)
		return
	if not full or not changed_ids.is_empty():
		_refresh_incremental(changed_ids)
		return
	var started := Time.get_ticks_usec()
	if region_selector != null: region_selector.select(["harbor","mountain","desert"].find(region)+1)
	canvas.cancel_drag()
	canvas.objects = {}
	for area in ["harbor","mountain","desert"]:
		var base: Dictionary = catalog.get(area,{}).get("objects",{})
		var rows := DATA.effective(base,document.regions.get(area,{}))
		for id in catalog.get(area,{}).get("context",{}):
			var base_row: Dictionary = catalog[area].context[id]
			# Cópia profunda só de quem recebe edição do documento (o catálogo tem dezenas de milhares de linhas).
			var row: Dictionary = base_row.duplicate(document.regions.get(area,{}).has(id) or base_row.get("shape_editable_pending",false))
			if row.type == "piece":
				row["shape_editable"] = not row.get("locked",false) and PIECES.is_shape_editable(str(id))
				if row.shape_editable: row["default_outline"] = _base_outline(base_row)
			if row.type == "piece" and document.regions.get(area,{}).has(id):
				if not _overlay_piece(row,base_row,document.regions[area][id]): continue
			rows[id] = row
		# Cópias: nascem da linha-base da origem e levam a própria edição por cima.
		for id in document.regions.get(area,{}):
			var change: Dictionary = document.regions[area][id]
			if change.get("type","") != "piece" or str(change.get("clone_of","")) == "" or change.get("deleted",false): continue
			var source: Dictionary = catalog.get(area,{}).get("context",{}).get(str(change.clone_of),{})
			if source.is_empty(): continue
			var copy: Dictionary = source.duplicate(true)
			copy["id"] = id
			copy["label"] = str(source.get("label",id))+" (cópia)"
			copy["locked"] = false
			copy["shape_editable"] = PIECES.is_shape_editable(str(change.clone_of))
			if copy.shape_editable: copy["default_outline"] = _base_outline(source)
			if _overlay_piece(copy,source,change): rows[id] = copy
		for row in rows.values(): row["editor_region"] = area
		canvas.objects.merge(rows)
	var rows_ready := Time.get_ticks_usec()
	_update_locations()
	var locations_ready := Time.get_ticks_usec()
	junction_editor.rebuild()
	var junctions_ready := Time.get_ticks_usec()
	if build_context: canvas.rebuild_context()
	var context_ready := Time.get_ticks_usec()
	canvas.queue_redraw()
	_refresh_controls()
	_sync_service_entries()
	_select(canvas.selected_id)
	last_refresh_profile = {"mode":"full","rows_ms":(rows_ready-started)/1000.0,"locations_ms":(locations_ready-rows_ready)/1000.0,"junctions_ms":(junctions_ready-locations_ready)/1000.0,"context_ms":(context_ready-junctions_ready)/1000.0,"controls_ms":(Time.get_ticks_usec()-context_ready)/1000.0,"total_ms":(Time.get_ticks_usec()-started)/1000.0}
	print("WORLD_EDITOR_REFRESH ",JSON.stringify(last_refresh_profile))

func _refresh_controls() -> void:
	if region_selector != null: region_selector.select(["harbor","mountain","desert"].find(region)+1)
	deleted_ids.clear()
	deleted_menu.get_popup().clear()
	var changes := _scope_changes()
	for id in changes:
		if changes[id].get("deleted",false) and (active_interior.is_empty() or int(changes[id].get("interior_floor",0)) == interior_floor):
			deleted_menu.get_popup().add_item(id,deleted_ids.size())
			deleted_ids.append(id)
	deleted_menu.disabled = deleted_ids.is_empty()
	undo_button.disabled = history.is_empty()
	redo_button.disabled = future.is_empty()
	save_button.disabled = not load_error.is_empty() or (deferred_bootstrap and not initialized) or environment_loading or _merging_units
	save_button.tooltip_text = "Salvar mundo · Ctrl+S"
	for id in interior_validation:
		if not str(interior_validation[id]).is_empty():
			save_button.disabled = true
			save_button.tooltip_text = str(id)+": "+str(interior_validation[id])
			break
	save_state.text = "Alterações não salvas" if document != saved_document else "Mundo salvo"
	save_button.text = "Salvar mundo *" if document != saved_document else "Salvar mundo"
	if region_selector != null: region_selector.disabled = not active_interior.is_empty()

## Rebuild only rows touched by a gesture/history action; the world catalog is immutable.
func _refresh_incremental(changed_ids: Array) -> void:
	var started := Time.get_ticks_usec()
	canvas.cancel_drag()
	var context_changed := false
	var roads_changed := false
	var locations_changed := false
	var services_changed := false
	for item in changed_ids:
		var id := str(item)
		var area := str(canvas.objects.get(id,{}).get("editor_region",region))
		for candidate in ["harbor","mountain","desert"]:
			if document.regions.get(candidate,{}).has(id) or catalog.get(candidate,{}).get("objects",{}).has(id) or catalog.get(candidate,{}).get("context",{}).has(id):
				area = candidate
				break
		var previous: Dictionary = canvas.objects.get(id,{})
		var row := _effective_row(area,id)
		for value in [previous,row]:
			var type := str(value.get("type",""))
			context_changed = context_changed or type in ["context","piece"]
			roads_changed = roads_changed or type == "road"
			locations_changed = locations_changed or _location_row(value)
			services_changed = services_changed or value.get("service_building",false)
		if row.is_empty(): canvas.objects.erase(id)
		else: canvas.objects[id] = row
	if not changed_ids.is_empty() and canvas.has_method("invalidate_overview"): canvas.invalidate_overview()
	var rows_ready := Time.get_ticks_usec()
	if locations_changed: _update_locations()
	var locations_ready := Time.get_ticks_usec()
	if roads_changed:
		junction_editor.rebuild()
		canvas.road_ready = false
	var junctions_ready := Time.get_ticks_usec()
	if context_changed:
		if canvas.has_method("update_context"): canvas.update_context(changed_ids)
		else: canvas.rebuild_context()
	var context_ready := Time.get_ticks_usec()
	canvas.queue_redraw()
	_refresh_controls()
	if services_changed: _sync_service_entries()
	_select(canvas.selected_id)
	last_refresh_profile = {"mode":"incremental","changed":changed_ids.size(),"rows_ms":(rows_ready-started)/1000.0,"locations_ms":(locations_ready-rows_ready)/1000.0,"junctions_ms":(junctions_ready-locations_ready)/1000.0,"context_ms":(context_ready-junctions_ready)/1000.0,"controls_ms":(Time.get_ticks_usec()-context_ready)/1000.0,"total_ms":(Time.get_ticks_usec()-started)/1000.0}
	print("WORLD_EDITOR_REFRESH ",JSON.stringify(last_refresh_profile))

func _effective_row(area: String,id: String) -> Dictionary:
	var change: Dictionary = _scope_changes().get(id,{}) if not active_interior.is_empty() else document.regions.get(area,{}).get(id,{})
	if change.get("deleted",false): return {}
	var source: Dictionary = catalog.get(area,{}).get("objects",{}).get(id,{})
	var context: Dictionary = catalog.get(area,{}).get("context",{})
	if not active_interior.is_empty():
		source = interior_catalog.get(_interior_key(),{}).get("objects",{}).get(id,{})
		context = interior_catalog.get(_interior_key(),{}).get("context",{})
	if source.is_empty(): source = context.get(id,{})
	if change.get("type","") == "piece" and not str(change.get("clone_of","")).is_empty(): source = context.get(str(change.clone_of),{})
	if source.is_empty() and change.is_empty(): return {}
	var row: Dictionary = source.duplicate(not change.is_empty()) if not source.is_empty() else change.duplicate(true)
	if row.get("type","") == "piece":
		row["shape_editable"] = not row.get("locked",false) and PIECES.is_shape_editable(str(change.get("clone_of",id)))
		if row.shape_editable: row["default_outline"] = _base_outline(source)
		if change.has("clone_of"): row["label"] = str(source.get("label",id))+" (cópia)"
		if not change.is_empty() and not _overlay_piece(row,source,change): return {}
	else:
		if not change.is_empty(): row = change.duplicate(true)
	row["editor_region"] = area
	if not active_interior.is_empty(): row["editor_interior"] = active_interior
	return row

func _changed_ids(before: Dictionary,after: Dictionary) -> Array:
	var result: Array = []
	if not active_interior.is_empty():
		var old_rows: Dictionary = before.get("interiors",{}).get(active_interior,{})
		var new_rows: Dictionary = after.get("interiors",{}).get(active_interior,{})
		for id in old_rows:
			if old_rows[id] != new_rows.get(id): result.append(id)
		for id in new_rows:
			if not old_rows.has(id): result.append(id)
		return result
	for area in ["harbor","mountain","desert"]:
		var old_rows: Dictionary = before.regions.get(area,{})
		var new_rows: Dictionary = after.regions.get(area,{})
		for id in old_rows:
			if old_rows[id] != new_rows.get(id): result.append(id)
		for id in new_rows:
			if not old_rows.has(id): result.append(id)
	return result

## Aplica a edição do documento a uma linha de peça do mapa (move, gira e estica o desenho
## base). Devolve false se a peça foi excluída.
func _overlay_piece(row: Dictionary,base_row: Dictionary,change: Dictionary) -> bool:
	if change.get("deleted",false): return false
	var angle := -deg_to_rad(float(change.get("rotation",0)))
	var stretch := DATA.point(change.get("stretch",[1,1]))
	for part in row.get("parts",[]):
		if part.size() == 6:
			part.append([[part[0],part[1]],[part[0]+part[2],part[1]],[part[0]+part[2],part[1]+part[3]],[part[0],part[1]+part[3]]])
		if part.size() < 7: continue
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
	return true

func _sync_service_entries() -> void:
	if not active_interior.is_empty(): return
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
	if is_instance_valid(live_preview) and live_preview.has_method("refresh_lod_selection"): live_preview.refresh_lod_selection()
	_sync_live_preview()
	if junction_editor.enabled:
		active_sidebar = "properties"
		_apply_layout()
	elif not id.is_empty() and properties_requested:
		active_sidebar = "properties"
		_apply_layout()
	elif id.is_empty():
		active_sidebar = "properties" if terrain_mode else "library"
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
		if terrain_mode:
			_terrain_controls(terrain_settings)
			return
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Selecione um objeto no mapa ou na visão 3D: tudo se move, gira, estica, eleva, duplica e exclui (poste, fio, pedra, mobiliário...).\n\nPeças automáticas aparecem depois que a visão 3D carregar a área.\n\nVerde: árvores\nBlocos: prédios\nAmarelo: luzes\nCruz rosa: acesso\n\n▶ Jogar aqui abre o jogo com Dante perto da seleção."
		properties.add_child(hint)
		return
	var row: Dictionary = canvas.objects[id]
	region = str(row.get("editor_region",region))
	canvas.region = region
	var label := Label.new()
	label.text = preload("res://world/editing/WorldGroundFactory.gd").LABELS[preload("res://world/editing/WorldGroundFactory.gd").SURFACES.find(row.surface)] if row.type == "ground" and not row.get("paving",false) else str(row.get("label",row.id))
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	properties.add_child(label)
	if row.type == "context":
		if row.get("kind","") in ["motocross_course","terrain"]:
			_button(properties,"Editar terreno",func():
				canvas.center = DATA.point(row.position)
				_set_terrain_mode(true))
		var lock := Label.new()
		lock.text = "Fundo do mapa (silhueta do catálogo).\nAbra a visão 3D: cada peça deste lugar é selecionável e editável lá."
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		properties.add_child(lock)
		_button(properties,"Ver este local em 3D",func(): _set_view_mode(1); _sync_live_preview())
		_button(properties,"Copiar geometria",_copy)
		return
	if row.get("warn",false) and row.type != "piece":
		var warning := Label.new()
		warning.text = "Local com serviço/interior: o visual se move, mas a porta, o gatilho e o interior ficam onde estavam."
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		properties.add_child(warning)
	var transform_hint := Label.new()
	transform_hint.text = "Arraste as setas X/Z para mover." if row.get("paving",false) or not canvas.rotation_enabled else "Arraste as setas X/Z para mover.\nAnel Y: girar · Shift: passos de 15°."
	transform_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_child(transform_hint)
	if row.type != "road":
		_number("X (m)",float(row.position[0]),-10000,10000,func(value): _set_array("position",0,value))
		_number("Z (m)",float(row.position[1]),-10000,10000,func(value): _set_array("position",1,value))
		if not row.get("paving",false) and row.type != "terrain": _number("Rotação (°)",float(row.get("rotation",0)),-360,360,func(value): _set_value("rotation",value))
	match str(row.type):
		"terrain":
			_terrain_controls(row)
		"tree":
			_number("Escala",float(row.scale),.05,30,func(value): _set_value("scale",value),.05)
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
			_number("Largura (m)",extent.x*stretch.x,extent.x*.02,extent.x*30,func(value): _resize_piece(0,value))
			_number("Profundidade (m)",extent.y*stretch.y,extent.y*.02,extent.y*30,func(value): _resize_piece(1,value))
			_number("Altura (×)",float(row.get("height_stretch",1.0)),.02,30,func(value): _set_value("height_stretch",value),.05)
			_number("Elevação (m)",float(row.get("lift",0.0)),-500,3000,func(value): _set_value("lift",value),.1)
			if row.get("warn",false):
				var warning := Label.new()
				warning.text = "Equipamento ligado à operação: o visual se move, mas a mecânica e o gatilho originais ficam onde estavam."
				warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				properties.add_child(warning)
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
			else: _number("Escala",float(row.scale),.05,30,func(value): _set_value("scale",value),.05)
			if row.model != "static_snapshot": _color(row)
		"building":
			var base: Dictionary = row.get("service_base",{})
			_number("Largura (m)",float(row.size[0]),1,1000,func(value): _set_array("size",0,value))
			_number("Profundidade (m)",float(row.size[1]),1,1000,func(value): _set_array("size",1,value))
			_number("Altura (m)",float(row.height),1,1000,func(value): _set_value("height",value))
			if not row.get("service_building",false): _choice("Modelo",DATA.BUILDING_TYPES,DATA.BUILDING_LABELS,str(row.model),func(value): _set_value("model",value))
			_color(row)
		"light":
			_number("Altura (m)",float(row.height),.5,200,func(value): _set_value("height",value))
			_number("Alcance (m)",float(row.range),.5,500,func(value): _set_value("range",value))
			_number("Energia (0 apaga)",float(row.energy),0,100,func(value): _set_value("energy",value),.05)
			_color(row)
			var note := Label.new()
			note.text = "Luz constante, sem sombras."
			properties.add_child(note)
		"road":
			var extend := _button(properties,"Continuar rua",_continue_road)
			extend.disabled = canvas.selected_point not in [0,row.points.size()-1]
			var turn := _button(properties,"Criar retorno",_create_road_return)
			turn.disabled = extend.disabled or row.get("pathway",false) or float(row.width) < 5 or not canvas.road_connection(DATA.point(row.points[maxi(canvas.selected_point,0)]),row,.01,canvas.selected_point).is_empty()
			_number("Largura (m)",float(row.width),.5,120,func(value): _set_value("width",value))
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
	if row.type == "piece" and not str(row.get("source_record","")).is_empty():
		_button(actions,"Copiar",_copy)
		_button(actions,"Duplicar",_duplicate)
	if row.type != "piece":
		_button(actions,"Copiar",_copy)
		if not row.get("service_building",false) and row.type != "manhole": _button(actions,"Duplicar",_duplicate)
	_button(actions,"Excluir",_delete)
	var restore := _button(properties,"Restaurar original",_restore_original)
	restore.disabled = not _scope_changes().has(id)

func _set_terrain_mode(enabled: bool) -> void:
	if enabled and not active_interior.is_empty():
		_report("O pincel de relevo é usado no exterior; pisos do interior são editados pelos próprios objetos.")
		if terrain_toggle != null: terrain_toggle.set_pressed_no_signal(false)
		return
	terrain_mode = enabled
	if terrain_toggle != null: terrain_toggle.set_pressed_no_signal(enabled)
	if canvas == null: return
	canvas.cancel_drag()
	if enabled:
		junction_editor.set_enabled(false)
		placement_template.clear()
		canvas.armed = "terrain"
		canvas.selected_id = ""
		active_sidebar = "properties"
		properties_requested = true
		_select("")
		_report("Terreno · Clique no chão para aplicar relevo e textura · Desfazer remove a última aplicação · Salvar mundo confirma.")
		topography_requested = ""
		_queue_topography()
	else:
		if is_instance_valid(live_preview) and live_preview.has_method("hide_terrain_cursor"): live_preview.hide_terrain_cursor()
		if canvas.armed == "terrain": canvas.armed = ""
		_select(canvas.selected_id)
	canvas.queue_redraw()

func _terrain_controls(row: Dictionary) -> void:
	_number("Raio (m)",float(row.get("radius",12)),4 if row.get("target","") == "mountain" or region == "mountain" else 2,256,func(value): _terrain_value(row,"radius",value),1)
	_choice("Relevo",["offset","flatten"],["Elevar / baixar","Nivelar na altura"],str(row.get("mode","offset")),func(value): _terrain_value(row,"mode",value))
	_number("Altura (m)",float(row.get("height",0)),-100,100,func(value): _terrain_value(row,"height",value),.25)
	_number("Intensidade",float(row.get("strength",1)),0,1,func(value): _terrain_value(row,"strength",value),.05)
	_number("Suavidade da borda",float(row.get("falloff",.5)),.05,1,func(value): _terrain_value(row,"falloff",value),.05)
	var track := CheckButton.new()
	track.text = "Incluir pista do motocross"
	track.button_pressed = bool(row.get("affect_track",false))
	track.toggled.connect(func(value): _terrain_value(row,"affect_track",value))
	properties.add_child(track)
	_choice("Textura",["keep","grass","earth","sand","gravel","rock","snow","asphalt"],["Preservar","Grama","Terra","Areia","Cascalho","Rocha","Neve","Asfalto"],str(row.get("surface","earth")),func(value): _terrain_value(row,"surface",value))

func _terrain_value(row: Dictionary,key: String,value: Variant) -> void:
	terrain_settings[key] = value
	if row.has("id"):
		_set_value(key,value)
	else:
		canvas.queue_redraw()

func _terrain_target(at: Vector2) -> String:
	if Rect2(-247,-147,155,112).has_point(at): return "motocross"
	return "mountain" if _region_at(at) == "mountain" else ""

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

func can_edit_world() -> bool:
	return not environment_loading and not _merging_units and (initialized or not deferred_bootstrap)

func _unit_index_progress(done: int,total: int,token: int) -> void:
	if token != unit_index_generation or not _merging_units: return
	status.text = "Indexando objetos em 2D…" if total <= 0 else "Indexando objetos em 2D · %d / %d" % [done,total]
	status.tooltip_text = status.text

func _editing_wait() -> bool:
	if can_edit_world(): return false
	_report("Indexando objetos. A câmera e a navegação continuam disponíveis; aguarde para editar ou salvar.")
	return true

func _commit(row: Dictionary) -> void:
	if _editing_wait(): return
	if environment_loading or (deferred_bootstrap and not initialized):
		_report("Aguarde a preparação dos mapas antes de editar.")
		return
	row.erase("editor_region")
	row.erase("editor_interior")
	if row.type == "ground" and row.has("outline"):
		var extent := _outline_extent(row)
		row.size = [extent.x,extent.y]
	if row.get("type", "") == "piece":
		# Persist transforms only; base triangles stay in the editor catalog.
		var authored := {"id":row.id,"type":"piece","position":row.position,"rotation":row.get("rotation",0),"source_record":row.get("source_record","")}
		if row.has("clone_of"): authored.clone_of = row.clone_of
		if row.get("deleted",false): authored.deleted = true
		for key in ["stretch","outline"]:
			if row.has(key): authored[key] = row[key].duplicate(true)
		for key in ["height_stretch","lift"]:
			if row.has(key) and not is_equal_approx(float(row[key]),1.0 if key == "height_stretch" else 0.0): authored[key] = float(row[key])
		row = authored
	if not active_interior.is_empty(): row["interior_floor"] = interior_floor
	if not load_error.is_empty():
		_report(load_error,"error")
		_refresh([row.id])
		return
	var error := DATA.validate_entity(row)
	if error.is_empty(): error = _placement_error(row)
	var original: Dictionary = catalog.get(region,{}).get("objects",{}).get(row.id,catalog.get(region,{}).get("context",{}).get(row.id,{}))
	if active_interior.is_empty() and not free_placement and not row.get("deleted",false) and row.type not in ["road","piece"] and not row.get("paving",false):
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
		_report(error,"error")
		_refresh([row.id])
		return
	if _scope_changes().get(row.id,{}) == row: return
	var previous_row: Dictionary = canvas.objects.get(row.id,{}).duplicate(true)
	_checkpoint()
	if active_interior.is_empty():
		if not document.regions.has(region): document.regions[region] = {}
		document.regions[region][row.id] = row.duplicate(true)
	else:
		if not document.has("interiors"): document.interiors = {}
		if not document.interiors.has(active_interior): document.interiors[active_interior] = {}
		document.interiors[active_interior][row.id] = row.duplicate(true)
		interior_validation[_validation_key(active_interior,interior_floor)] = "Aguarde a validação 3D do interior antes de salvar."

	if is_instance_valid(live_preview): live_preview.after_commit(previous_row,row)
	canvas.selected_id = row.id
	_refresh([row.id])
	if _write_draft(): _report("Alteração pronta. Salve para aplicá-la na próxima execução do jogo.")

func _checkpoint() -> void:
	history.append(document.duplicate(true))
	if history.size() > 100: history.pop_front()
	future.clear()
func undo() -> void:
	if _editing_wait(): return
	if history.is_empty(): return
	future.append(document.duplicate(true))
	var previous := document
	document = history.pop_back()
	_invalidate_interior_validation(previous,document)
	if is_instance_valid(live_preview): live_preview.refresh()
	_refresh(_changed_ids(previous,document),false)
	if _write_draft(): _report("Alteração desfeita. Salvar mundo confirma o resultado.")
func redo() -> void:
	if _editing_wait(): return
	if future.is_empty(): return
	history.append(document.duplicate(true))
	var previous := document
	document = future.pop_back()
	_invalidate_interior_validation(previous,document)
	if is_instance_valid(live_preview): live_preview.refresh()
	_refresh(_changed_ids(previous,document),false)
	if _write_draft(): _report("Alteração refeita. Salvar mundo confirma o resultado.")
func _delete() -> void:
	if not canvas.objects.has(canvas.selected_id): return
	var row: Dictionary = canvas.objects[canvas.selected_id].duplicate(true)
	if row.type == "context": return
	row.deleted = true
	_commit(row)
func _duplicate() -> void:
	if canvas.objects.has(canvas.selected_id) and canvas.objects[canvas.selected_id].type == "piece":
		_duplicate_piece()
		return
	if not _copy(): return
	var original: Dictionary = canvas.objects[canvas.selected_id]
	var at := canvas.pivot(original)
	if original.type == "road": at.y += 12
	else: at.x += float(original.get("size",[1,1])[0])+2 if original.type == "building" else 3
	_commit(_clone_at(clipboard_row,at))
## Cópia de uma peça do cenário (pedra, poste, mobiliário...): nasce da forma original da
## peça-mãe, 3 m ao lado, e tem edição própria. É aplicada pelo jogo junto com a peça-mãe.
func _duplicate_piece() -> void:
	var row: Dictionary = canvas.objects[canvas.selected_id]
	if str(row.get("source_record","")).is_empty():
		_report("Esta peça não pode ser copiada.")
		return
	var clone := {"id":"piece/clone/%d_%d" % [Time.get_ticks_usec(),randi()],"type":"piece","clone_of":str(row.get("clone_of",row.id)),
		"source_record":str(row.source_record),"position":[float(row.position[0])+3.0,float(row.position[1])+3.0],"rotation":float(row.get("rotation",0.0))}
	for key in ["stretch","height_stretch","lift","outline"]:
		if row.has(key): clone[key] = row[key].duplicate(true) if row[key] is Array else row[key]
	_commit(clone)

func _restore_original() -> void:
	_restore_id(canvas.selected_id)
func _restore_id(id: String) -> void:
	if _editing_wait(): return
	_checkpoint()
	_scope_changes().erase(id)
	if not history.is_empty(): _invalidate_interior_validation(history[-1],document)
	if is_instance_valid(live_preview): live_preview.refresh()
	_refresh([id])
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
	if _editing_wait(): return false
	if environment_loading or (deferred_bootstrap and not initialized):
		_report("Aguarde a preparação dos mapas antes de salvar.")
		return false
	# finish_drag emits selection even when idle, rebuilding the property controls.
	# Apply the focused number before that rebuild can discard its pending text.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and focused.get_parent() is SpinBox: focused.get_parent().apply()
	junction_editor.finish()
	if is_instance_valid(live_preview) and live_preview.edit_control != null:
		live_preview.edit_control.finish_road()
		live_preview.edit_control.finish()
	canvas.finish_drag()
	if not load_error.is_empty():
		_report(load_error,"error")
		return false
	for interior_id in interior_validation:
		if not str(interior_validation[interior_id]).is_empty():
			_report(str(interior_id)+": "+str(interior_validation[interior_id]),"error")
			return false
	var error := DATA.validate_document(document)
	if error.is_empty() and DATA.disk_hash(edits_path) != expected_hash: error = "Arquivo mudou fora do editor. Reabra o editor antes de salvar; suas alterações continuam na tela."
	if error.is_empty():
		var snapshots = load("res://world/editing/WorldStaticSnapshots.gd")
		if snapshots != null: error = snapshots.promote_document(document)
	if error.is_empty(): error = DATA.save_document(document,expected_hash,edits_path)
	if not error.is_empty():
		_report(error,"error")
		return false
	expected_hash = DATA.disk_hash(edits_path)
	saved_document = document.duplicate(true)
	var draft_ok := _write_draft()
	_refresh([],false)
	if draft_ok: _report("Mundo salvo. A próxima execução do jogo usará estas alterações.")
	return true
func _play() -> void:
	_play_here()
func _write_draft() -> bool:
	var recovery: Dictionary = preload("res://addons/geteco_world_editor/WorldEditorDraftArchive.gd").protect(draft_path,expected_hash,edits_path,Callable(self,"_copy_draft_archive"))
	if not recovery.ok:
		_report("Rascunho mantido em "+ProjectSettings.globalize_path(draft_path)+". "+str(recovery.error)+" Arquivo de recuperação: "+ProjectSettings.globalize_path(str(recovery.archive_path)),"error")
		return false
	if not str(recovery.archive_path).is_empty():
		_report("Rascunho anterior arquivado e verificado por SHA-256 em "+ProjectSettings.globalize_path(str(recovery.archive_path)))
	var temporary := draft_path+".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		_report("Rascunho não recuperável após fechar: "+error_string(FileAccess.get_open_error()),"error")
		return false
	file.store_string(JSON.stringify({"base_hash":expected_hash,"edits_path":edits_path,"document":document}))
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK and DATA.disk_hash(draft_path) != str(recovery.get("source_hash","")):
		_report("O rascunho mudou durante a gravação. O arquivo externo foi mantido em "+ProjectSettings.globalize_path(draft_path)+"; as alterações desta sessão continuam na tela.","error")
		return false
	if result == OK: result = DirAccess.rename_absolute(temporary,draft_path)
	if result != OK:
		_report("Falha ao guardar rascunho: "+error_string(result),"error")
		return false
	return true

func _copy_draft_archive(source: String, destination: String) -> int:
	return DirAccess.copy_absolute(source,destination)

func _restore_draft() -> void:
	if not FileAccess.file_exists(draft_path): return
	var draft: Variant = JSON.parse_string(FileAccess.get_file_as_string(draft_path))
	if not draft is Dictionary:
		_report("Rascunho inválido; o mundo salvo foi preservado.","error")
		return
	if draft.get("edits_path",edits_path) != edits_path: return
	if draft.get("base_hash","") != expected_hash:
		_report("Há um rascunho de outra versão do mundo em "+ProjectSettings.globalize_path(draft_path)+". Novas alterações só poderão substituí-lo depois de criar e verificar seu arquivo de recuperação.","error")
		return
	var error := DATA.validate_document(draft.get("document"))
	if not error.is_empty():
		_report("Rascunho inválido: "+error,"error")
		return
	document = draft.document
	restored_draft = document != saved_document

func _rebuild_catalog() -> void:
	if environment_loading or (deferred_bootstrap and not initialized):
		_report("Aguarde a preparação inicial dos mapas antes de atualizar a base.")
		return
	if worker_pid > 0: return
	# Each request has its own output: an old cache cannot masquerade as successful work.
	worker_output = "res://.godot/world_editor_catalog_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_msec()]
	worker_log = worker_output.trim_suffix(".json")+".log"
	worker_pid = OS.create_process(OS.get_executable_path(),PackedStringArray(["--resolution","64x64","--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/export_catalog.gd","--log-file",ProjectSettings.globalize_path(worker_log),"--","--output="+worker_output]))
	if worker_pid < 0:
		_report("Não foi possível abrir o gerador de catálogo.","error")
		return
	worker_started = Time.get_ticks_msec()
	rebuild_button.disabled = true
	worker_cancel.show()
	_report("Gerando catálogo em processo separado · Log: "+ProjectSettings.globalize_path(worker_log))
	worker_timer.start()

func _poll_worker() -> void:
	if worker_pid <= 0: return
	if OS.is_process_running(worker_pid):
		var elapsed := (Time.get_ticks_msec()-worker_started)/1000
		status.text = "Gerando catálogo · %ds · Você pode continuar editando · Logs ou Cancelar carga" % elapsed
		status.tooltip_text = ProjectSettings.globalize_path(worker_log)
		return
	worker_timer.stop()
	worker_pid = -1
	worker_cancel.hide()
	rebuild_button.disabled = false
	var generated: Variant = JSON.parse_string(FileAccess.get_file_as_string(worker_output)) if FileAccess.file_exists(worker_output) else null
	if not generated is Dictionary or not generated.get("regions") is Dictionary or not generated.regions.has("harbor") or not generated.regions.has("mountain"):
		_report("A geração do catálogo falhou. O catálogo anterior foi mantido. Log: "+ProjectSettings.globalize_path(worker_log),"error")
		return
	var replaced := DirAccess.rename_absolute(worker_output,CACHE_PATH)
	if replaced != OK:
		_report("Catálogo gerado, mas não foi possível ativá-lo: "+error_string(replaced),"error")
		return
	_load_catalog()
	_set_background()
	_refresh()
	_report("Base atualizada. Suas alterações não salvas foram preservadas.")
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()
	elif canvas.has_focus() or (is_instance_valid(live_preview) and live_preview.edit_control != null and live_preview.surface.has_focus()):
		if event.ctrl_pressed and event.keycode == KEY_C: _copy()
		elif event.ctrl_pressed and event.keycode == KEY_V: _paste()
		elif event.ctrl_pressed and event.keycode == KEY_D: _duplicate()
		elif event.ctrl_pressed and event.keycode == KEY_Y: redo()
		elif event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed: redo()
			else: undo()
		elif event.keycode == KEY_DELETE: _delete()
		else: return
		get_viewport().set_input_as_handled()

func _placement_error(row: Dictionary) -> String:
	if not active_interior.is_empty():
		return "Use objetos e pisos para editar esta sala." if row.type in ["road","terrain"] else ""
	if row.type == "terrain":
		return "" if _terrain_target(DATA.point(row.position)) == str(row.get("target","")) else "Este pincel precisa estar no terreno da montanha ou do motocross."
	if catalog.is_empty(): return "Clique em Atualizar base antes de editar."
	if row.get("deleted",false): return ""
	if row.type == "piece": return "Mantenha a peça na sua região de origem." if _region_at(DATA.point(row.position)) != region else ""
	if row.type != "road" and _region_at(DATA.point(row.position)) != region: return "Para mover entre regiões, adicione o objeto na região de destino."
	# Colocação livre (padrão): nenhuma sobreposição é recusada, nem sobre prédios com serviço.
	if free_placement: return ""
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
	if canvas.has_method("set_terrain_topography_visible"): canvas.set_terrain_topography_visible(active_interior.is_empty())
	if not active_interior.is_empty():
		canvas.land = []
		canvas.terrain = []
		canvas.land_polygons = []
		canvas.entries = []
		if canvas.has_method("set_region_bounds"): canvas.set_region_bounds({})
		return
	if canvas.has_method("set_region_bounds"):
		if region_bounds_cache.is_empty() and not canvas.objects.is_empty():
			for area in ["harbor","mountain","desert"]: region_bounds_cache[area] = region_bounds(area)
		canvas.set_region_bounds(region_bounds_cache)
	canvas.land = catalog.get("harbor",{}).get("land",[])
	canvas.terrain = catalog.get("mountain",{}).get("terrain",[]).duplicate()
	canvas.terrain.append_array(catalog.get("desert",{}).get("terrain",[]))
	canvas.land_polygons = catalog.get("harbor",{}).get("land_polygons",[])
	canvas.entries = catalog.get("harbor",{}).get("entries",[]).duplicate()
	canvas.entries.append_array(catalog.get("mountain",{}).get("entries",[]))
	canvas.entries.append_array(catalog.get("desert",{}).get("entries",[]))

func region_bounds(area: String) -> Rect2:
	if not active_interior.is_empty():
		var local: Array = interior_catalog.get(_interior_key(),{}).get("bounds",[-10,-10,20,20])
		return Rect2(float(local[0]),float(local[1]),float(local[2]),float(local[3]))
	var result := Rect2()
	var has_bounds := false
	for tile in catalog.get(area,{}).get("terrain",[]):
		var bounds := Rect2(float(tile[0]),float(tile[1]),float(tile[2]),float(tile[3]))
		result = result.merge(bounds) if has_bounds else bounds
		has_bounds = true
	for row in canvas.objects.values():
		if str(row.get("editor_region","")) != area: continue
		var bounds := Rect2()
		if row.type == "road":
			if row.get("points",[]).is_empty(): continue
			bounds = Rect2(DATA.point(row.points[0]),Vector2.ZERO)
			for point in row.points: bounds = bounds.expand(DATA.point(point))
			bounds = bounds.grow(float(row.get("width",0))*.5)
		elif row.has("position"):
			var extent := DATA.point(row.get("size",[2,2]))*.5
			bounds = Rect2(DATA.point(row.position)-extent,extent*2)
		else: continue
		result = result.merge(bounds) if has_bounds else bounds
		has_bounds = true
	return result if has_bounds else Rect2(canvas.center-Vector2(25,25),Vector2(50,50))

func _frame_region() -> void:
	var bounds := region_bounds(region)
	canvas.center = bounds.get_center()
	canvas.zoom = clampf(minf(canvas.size.x/maxf(1,bounds.size.x+40),canvas.size.y/maxf(1,bounds.size.y+40)),CANVAS.MIN_ZOOM,24)
	canvas.queue_redraw()
	if is_instance_valid(live_preview) and live_preview.has_method("frame_region"):
		live_preview.frame_region(region,bounds)
	else: _sync_live_preview()
	_report("Mapa enquadrado · "+{"harbor":"Harbor","mountain":"Montanha","desert":"Deserto"}.get(region,region))

func _fit_world() -> void:
	var bounds := canvas.world_bounds()
	canvas.center = bounds.get_center()
	canvas.zoom = clampf(minf(canvas.size.x/(bounds.size.x+80),canvas.size.y/(bounds.size.y+80)),CANVAS.MIN_ZOOM,24)
	canvas.queue_redraw()
	_sync_live_preview()
	if region_selector != null: region_selector.select(0)
	_report("Mundo inteiro em 2D · Escolha Harbor, Montanha ou Deserto para focar uma região.")

func _location_row(row: Dictionary) -> bool:
	if row.get("kind","") == "terrain": return false
	var type := str(row.get("type",""))
	return type in ["context","manhole"] or (type == "piece" and row.get("editor_region","") == "desert") or (type == "building" and (row.get("locked",false) or row.get("service_building",false)))

func _update_locations() -> void:
	locations.clear()
	location_ids.clear()
	locations.add_item("Ir para local…")
	var rows: Array = []
	for row in canvas.objects.values():
		if _location_row(row):
			rows.append(row)
	rows.sort_custom(func(a,b): return str(a.get("label",a.id)).naturalnocasecmp_to(str(b.get("label",b.id))) < 0)
	for row in rows:
		location_ids.append(row.id)
		locations.add_item(str(row.get("label",row.id)).trim_prefix("building/")+" · "+str(row.get("editor_region","harbor")))

func _go_location(index: int) -> void:
	if index <= 0: return
	var id := location_ids[index-1]
	var row: Dictionary = canvas.objects[id]
	canvas.center = DATA.point(row.position)
	canvas.zoom = clampf(minf(canvas.size.x,canvas.size.y)/maxf(50,DATA.point(row.size).length()*1.2),.3,12)
	_select(id)
	canvas.queue_redraw()

## Terrain-only background worker never changes the chosen 2D/3D layout or camera.
func _topography_interest() -> bool:
	return active_interior.is_empty() and (terrain_mode or region in ["mountain","desert"] or Rect2(-247,-147,155,112).grow(25).has_point(canvas.center))

func _poll_topography() -> void:
	if not is_inside_tree() or canvas == null: return
	if is_instance_valid(topography_loader) and topography_status != null and not topography_requested.is_empty():
		var message_label = topography_loader.get("message")
		if message_label is Label:
			topography_status.text = "Relevo 2D · "+str(message_label.text)
			topography_status.tooltip_text = str(message_label.tooltip_text)
	_queue_topography()

func _queue_topography() -> void:
	if is_instance_valid(live_preview): return # The visible preview owns terrain generation in 3D/split mode.
	if not background_topography_enabled or not can_edit_world() or not _topography_interest(): return
	var area := region if region in ["mountain","desert"] else "harbor"
	var preview_script = preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
	var signature: String = preview_script.terrain_revision(document,area)
	var key := area+"/"+signature
	if topography_installed.get(area,"") == signature: return
	if topography_cache.has(key):
		_topography_ready(area,signature,topography_cache[key])
		return
	if topography_requested == key: return
	if not is_instance_valid(topography_loader):
		topography_loader = preview_script.new()
		add_child(topography_loader)
		topography_loader.hide()
		topography_loader.topo_ready.connect(_topography_ready)
		topography_loader.activity.connect(func(message: String,level: String): _report("Relevo 2D · "+message,level))
	topography_requested = key
	if topography_status != null:
		topography_status.text = "Relevo 2D · Preparando terreno real…"
		topography_status.show()
	_report("Carregando relevo 2D de "+str({"mountain":"Montanha","desert":"Deserto"}.get(area,"Harbor / motocross"))+" · Você pode continuar navegando.")
	topography_loader.request_topography(document,canvas.center,area,signature)

func _topography_ready(area: String,signature: String,tiles: Array) -> void:
	if tiles.is_empty():
		if topography_status != null: topography_status.text = "Relevo 2D indisponível · consulte Logs"
		_report("O auxiliar não retornou superfícies para o relevo 2D de "+area+". Use Opções → Recarregar relevo 2D e consulte Logs.","error")
		return
	var key := area+"/"+signature
	topography_cache[key] = tiles
	topography_cache_order.erase(key)
	topography_cache_order.append(key)
	while topography_cache_order.size() > 6:
		topography_cache.erase(topography_cache_order.pop_front())
	var preview_script = preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
	if signature != str(preview_script.terrain_revision(document,area)): return
	if canvas.has_method("set_terrain_topography"): canvas.set_terrain_topography(area,tiles)
	topography_installed[area] = signature
	if active_interior.is_empty() and not is_instance_valid(live_preview) and not tiles[0].get("units",[]).is_empty():
		preload("res://addons/geteco_world_editor/WorldTopographyUnits.gd").run(weakref(self),get_tree(),area,signature,tiles[0].units)
	if topography_requested == key:
		topography_requested = ""
		if topography_status != null:
			topography_status.text = "Relevo 2D atualizado"
			topography_status.tooltip_text = "Altura e bordas extraídas da geometria real do terreno; cores indicam o tipo de solo."
	_report("Relevo 2D atualizado · "+area+" · %d partes" % tiles.size())

func _stop_background_topography() -> void:
	if is_instance_valid(topography_loader):
		topography_loader.stop()
		topography_loader.free()
		topography_loader = null
	topography_requested = ""

func _live_topography_ready(area: String,signature: String,tiles: Array) -> void:
	if tiles.is_empty() or not active_interior.is_empty() or not is_instance_valid(live_preview): return
	var preview_script = preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
	if signature != str(preview_script.terrain_revision(document,area)): return
	if not tiles.is_empty() and int(tiles[0].get("coverage_radius",0)) == -1:
		_topography_ready(area,signature,tiles)
	elif topography_installed.get(area,"") != signature:
		# Nearby 3D terrain is useful in 2D, but never claims complete regional coverage.
		if canvas.has_method("set_terrain_topography"): canvas.set_terrain_topography(area,tiles)
	if topography_status != null:
		topography_status.text = "Relevo 2D · Área da prévia 3D"
		topography_status.tooltip_text = "A visão 2D usa o terreno carregado na prévia. Em 2D sozinho, a cobertura regional completa carrega em segundo plano."
		topography_status.show()

func _toggle_live_preview() -> void:
	if is_instance_valid(live_preview):
		live_preview.stop()
		live_preview.free()
		live_preview = null
		canvas.show()
		view_mode.select(0)
		live_toggle.set_pressed_no_signal(false)
	else:
		_stop_background_topography()
		live_preview = preload("res://addons/geteco_world_editor/WorldLivePreview.gd").new()
		live_split.add_child(live_preview)
		live_preview.enable_editing(self)
		view_mode.select(2)
		live_preview.activity.connect(_report)
		live_preview.topo_ready.connect(_live_topography_ready)
		live_preview.focus_requested.connect(_sync_live_preview)
		live_preview.units_ready.connect(_merge_units)
		live_preview.interior_units_ready.connect(_merge_interior_units)
		live_preview.interior_validation_ready.connect(_interior_validation_ready)
		live_preview.view_moved.connect(func(at: Vector2):
			canvas.center = at
			canvas.queue_redraw()
			live_preview.request(document,at,region if not active_interior.is_empty() else _region_at(at),active_interior,interior_floor))
		live_toggle.set_pressed_no_signal(true)
		_sync_live_preview()
	_apply_layout()

func _set_view_mode(index: int) -> void:
	if deferred_bootstrap and not initialized:
		_report("Aguarde a preparação do mapa 2D antes de abrir a visão 3D.")
		return
	if index == 0:
		if is_instance_valid(live_preview): _toggle_live_preview()
	else:
		if not is_instance_valid(live_preview): _toggle_live_preview()
		canvas.visible = index == 2
	view_mode.select(index)
	_apply_layout()

func _sync_live_preview() -> void:
	if environment_loading: return
	if junction_editor.dragging or _merging_units: return
	if not is_instance_valid(live_preview) or canvas.dragging: return
	if live_preview.edit_control != null:
		live_preview.edit_control.queue_redraw()
		if live_preview.edit_control.synchronizing or live_preview.edit_control.dragging: return
	var at := canvas.center
	if junction_editor.enabled and not junction_editor.current().is_empty(): at = junction_editor.current().position
	elif canvas.objects.has(canvas.selected_id): at = canvas.pivot(canvas.objects[canvas.selected_id])
	live_preview.request(document,at,region if not active_interior.is_empty() else _region_at(at),active_interior,interior_floor)

func _preview() -> void:
	if not active_interior.is_empty():
		_set_view_mode(1)
		_sync_live_preview()
		return
	var focus := canvas.center
	var width := 55.0
	if canvas.objects.has(canvas.selected_id):
		var row: Dictionary = canvas.objects[canvas.selected_id]
		if row.has("position"): focus = DATA.point(row.position)
		if row.has("size"): width = clampf(DATA.point(row.size).length()*1.4,35,180)
	var preview_path := "res://.godot/world_editor_preview_edits.json"
	var file := FileAccess.open(preview_path,FileAccess.WRITE)
	if file == null:
		_report("Não foi possível preparar a prévia.")
		return
	file.store_string(JSON.stringify(document))
	file.close()
	var area := _region_at(focus)
	var pid := OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--script","res://addons/geteco_world_editor/preview_world.gd","--","--no-save","--edits="+preview_path,"--region="+area,"--x="+str(focus.x),"--z="+str(focus.y),"--size="+str(width)]))
	_report("Prévia 3D aberta. Setas movem a câmera; Esc fecha. O progresso do jogo não é salvo." if pid > 0 else "Não foi possível abrir a prévia 3D.")
var _merging_units := false
var play_pid := -1

## Peças automáticas (pedra, poste, fio...) chegam do auxiliar da prévia 3D, já construídas.
## Entram no catálogo da região e passam a ser selecionáveis no mapa e na visão 3D.
func _merge_units(area: String,rows: Array) -> void:
	if not catalog.has(area) or rows.is_empty(): return
	var changed: Array = []
	for row in rows:
		if _merge_unit(area,row): changed.append(str(row.id))
	if changed.is_empty(): return
	_merging_units = true
	_refresh(changed)
	_merging_units = false
	_refresh_controls()

func _merge_unit(area: String,row: Dictionary) -> bool:
	var context: Dictionary = catalog[area].context
	var id := str(row.id)
	var known: Dictionary = context.get(id,{})
	if not known.is_empty() and not known.get("auto",false): return false
	if not known.is_empty() and known.get("position") == row.get("position") and known.get("size") == row.get("size") and known.get("parts") == row.get("parts"): return false
	context[id] = row
	return true

## Abre o jogo de verdade, com as alterações ainda não salvas, e põe Dante no ponto escolhido.
func _play_here() -> void:
	if not active_interior.is_empty():
		_report("Para jogar com Dante, volte ao Exterior e escolha um ponto. A edição da sala está disponível na prévia 3D.")
		return
	if not load_error.is_empty():
		_report(load_error,"error")
		return
	var error := DATA.validate_document(document)
	if not error.is_empty():
		_report(error,"error")
		return
	var at := canvas.center
	var where := "centro do mapa"
	if is_instance_valid(live_preview) and live_preview.is_visible_in_tree():
		at = Vector2(live_preview.focus.x,live_preview.focus.z)
		where = "centro da visão 3D"
	if canvas.objects.has(canvas.selected_id):
		var row: Dictionary = canvas.objects[canvas.selected_id]
		at = canvas.pivot(row)
		if row.has("size"): at.y += DATA.point(row.size).y*.5+3.0
		where = "perto de "+str(row.get("label",row.id))
	var path := "res://.godot/world_play_edits_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		_report("Não foi possível preparar o jogo.")
		return
	file.store_string(JSON.stringify(document))
	file.close()
	var area := _region_at(at)
	var pid := OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--","--no-save","--skip-arrival","--no-prewarm","--edits="+path,"--play-at=%s,%.2f,%.2f" % [area,at.x,at.y]]))
	play_pid = pid
	_report(("Jogo aberto com Dante em %s (%s, %.0f / %.0f). Alterações não salvas incluídas; nada é gravado." % [where,area,at.x,at.y]) if pid > 0 else "Não foi possível abrir o jogo.")

func _region_at(at: Vector2) -> String:
	if preload("res://world/desert/DesertLayout.gd").BOUNDS.has_point(at): return "desert"
	return "mountain" if at.x >= 456.25 and at.y < -125 else "harbor"

func _place(type: String,at: Vector2) -> void:
	if _editing_wait(): return
	if placement_template.get("type","") == "piece" and str(placement_template.get("editor_interior","")) != active_interior:
		_report("Carregue a peça em 3D e copie sua geometria para colar em outro ambiente.","error")
		return
	if not active_interior.is_empty():
		if type in ["road","terrain","continue_road"]:
			_report("Use objetos e pisos para editar esta sala.","error")
			return
		var added := _clone_at(placement_template,at) if not placement_template.is_empty() else DATA.new_entity(type,at)
		placement_template.clear()
		canvas.armed = ""
		_commit(added)
		return
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
	if type == "terrain":
		var target := _terrain_target(at)
		if target.is_empty():
			_report("O editor de relevo está disponível na montanha e no terreno do motocross. Escolha um desses terrenos.","error")
			return
		region = "harbor" if target == "motocross" else "mountain"
		canvas.region = region
		var stamp := _clone_at(placement_template,at) if placement_template.get("type","") == "terrain" else DATA.new_entity("terrain",at)
		if placement_template.get("type","") != "terrain": stamp.merge(terrain_settings,true)
		stamp.target = target
		if target == "mountain": stamp.radius = maxf(4,float(stamp.radius))
		stamp.order = int(Time.get_unix_time_from_system()*1000)
		_commit(stamp)
		if not terrain_mode: placement_template.clear()
		canvas.armed = "terrain" if terrain_mode else ""
		return
	var destination := _region_at(at)
	if placement_template.get("type","") == "piece" and str(placement_template.get("editor_region",region)) != destination:
		_report("Esta peça do cenário só pode ser colada no mapa de origem. Escolha um destino em "+str(placement_template.get("editor_region",region))+"; a cópia continua disponível.","error")
		return
	region = destination
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
	for label in ["Todos os assets","Prédios","Objetos","Árvores","Ruas","Luzes","Peças do mundo","Terrenos e pisos","Relevo e textura"]: asset_filter.add_item(label)
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
	var type: String = ["all","building","prop","tree","road","light","piece","ground","terrain"][asset_filter.selected]
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
	if item.action == "terrain_mode":
		if not active_interior.is_empty():
			_report("Escolha Exterior antes de editar o relevo.")
			return
		canvas.center = DATA.point(item.row.position)
		canvas.zoom = 2
		region = "harbor" if item.row.get("target","") == "motocross" else "mountain"
		canvas.region = region
		_set_terrain_mode(true)
		_sync_live_preview()
		return
	if item.action == "select":
		var row: Dictionary = canvas.objects.get(item.row.id,{})
		if row.is_empty(): return
		canvas.center = DATA.point(row.position)
		canvas.zoom = 10
		_select(row.id)
		canvas.queue_redraw()
		canvas.grab_focus()
		_report("Peça existente selecionada. Arraste para mover ou ajuste a rotação à direita.")
		return
	placement_template = item.row.duplicate(true)
	canvas.armed = item.row.type
	canvas.grab_focus()
	_report(str(item.label)+": clique no mapa para colocar. Esc cancela.")

func _copy() -> bool:
	capture_error = ""
	if not canvas.objects.has(canvas.selected_id): return false
	var row: Dictionary = canvas.objects[canvas.selected_id]
	var native: bool = row.type in ["piece","context","manhole"] or row.get("service_building",false) or (row.type == "building" and row.get("model","") not in DATA.BUILDING_TYPES)
	if native and _capture_static_copy(row): return true
	if not capture_error.is_empty(): return false
	if row.type == "piece" and not str(row.get("source_record","")).is_empty():
		clipboard_row = row.duplicate(true)
		_report("Copiado. Ctrl+V e clique no destino no mesmo mapa. Para colar em outro mapa, carregue esta peça na visão 3D e copie novamente.")
		return true
	if native:
		_report("Carregue este objeto na visão 3D para copiar sua geometria. Use 3D e Focar seleção; depois copie novamente.","error")
		return false
	clipboard_row = row.duplicate(true)
	_report("Copiado. Ctrl+V e clique no destino para colar.")
	return true

func _capture_static_copy(row: Dictionary) -> bool:
	if not is_instance_valid(live_preview) or live_preview.edit_control == null: return false
	var nodes: Array = live_preview.edit_control.groups.get(str(row.id),[])
	if nodes.is_empty(): return false
	var snapshots = load("res://world/editing/WorldStaticSnapshots.gd")
	if snapshots == null:
		capture_error = "Não foi possível abrir o armazenamento de peças copiadas."
		_report(capture_error,"error")
		return false
	var at := DATA.point(row.position) if row.has("position") else canvas.pivot(row)
	var ground_y := 0.0
	var found_ground := false
	for node in nodes:
		if is_instance_valid(node) and node.has_meta("world_snapshot_ground_height"):
			ground_y = float(node.get_meta("world_snapshot_ground_height"))
			found_ground = true
			break
	if not found_ground and active_interior.is_empty() and str(row.get("editor_region",region)) != "harbor":
		capture_error = "Atualize a visão 3D antes de copiar: falta a altura do chão neste objeto."
		_report(capture_error,"error")
		return false
	var captured: Dictionary = snapshots.capture(nodes,Vector3(at.x,ground_y,at.y))
	if not str(captured.get("error","")).is_empty():
		capture_error = str(captured.error)
		_report(capture_error,"error")
		return false
	var template := DATA.new_entity("prop",at)
	template.model = "static_snapshot"
	template.snapshot_id = captured.snapshot_id
	template.size = captured.size
	template.height = captured.height
	template.color = "ffffff"
	template.label = str(row.get("label",row.id))+" (cópia)"
	clipboard_row = template
	_report("Geometria copiada. Ctrl+V para colar em qualquer mapa; Salvar mundo confirma a cópia.")
	return true

func _paste() -> void:
	if clipboard_row.is_empty():
		_report("Selecione um objeto e pressione Ctrl+C primeiro.")
		return
	placement_template = clipboard_row.duplicate(true)
	canvas.armed = placement_template.type
	_report("Clique no destino para colar. Esc cancela.")

func _clone_at(template: Dictionary,at: Vector2) -> Dictionary:
	var row := template.duplicate(true)
	if row.type == "piece":
		row.id = "piece/clone/%d_%d" % [Time.get_ticks_usec(),randi()]
		row.clone_of = str(template.get("clone_of",template.id))
	else: row.id = DATA.new_entity(row.type,at).id
	for key in ["locked","deleted","editor_region","editor_interior","paving"]: row.erase(key)
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
	# Use the native GPU format up front instead of converting every RGB thumbnail
	# in the renderer and flooding verbose editor logs with format warnings.
	if icon.get_format() != Image.FORMAT_RGBA8: icon.convert(Image.FORMAT_RGBA8)
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
	for action in actions_bar.get_children():
		if action is Button and action.text in ["Desfazer","Refazer","Prévia 3D","▶ Jogar aqui","Girar"]:
			action.visible = size.x >= 900
			if not action.visible: action.position = Vector2.ZERO
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
		20: undo()
		21: redo()
		22: _preview()
		23: _play_here()
		24: _copy()
		25: _paste()
		26: _delete()
		27: _duplicate()
		28:
			canvas.rotation_enabled = not canvas.rotation_enabled
			rotation_toggle.set_pressed_no_signal(canvas.rotation_enabled)
			_select(canvas.selected_id)
			canvas.queue_redraw()
		5: _frame_region()
		29:
			topography_requested = ""
			topography_installed.clear()
			topography_cache.clear()
			topography_cache_order.clear()
			if _topography_interest(): _queue_topography()
			else: _report("Escolha Montanha ou vá ao motocross para carregar o relevo 2D.")
		6:
			var checked := not menu.is_item_checked(menu.get_item_index(6))
			menu.set_item_checked(menu.get_item_index(6),checked)
			if canvas.has_method("set_region_bounds_visible"): canvas.set_region_bounds_visible(checked)
			if is_instance_valid(live_preview) and live_preview.has_method("set_region_bounds_visible"): live_preview.set_region_bounds_visible(checked)
		4:
			canvas.road_snap_enabled = not canvas.road_snap_enabled
			menu.set_item_checked(menu.get_item_index(4),canvas.road_snap_enabled)

func _continue_road() -> void:
	canvas.armed = "continue_road"
	canvas.grab_focus()
	_report("Clique no destino para continuar a rua. Esc cancela.")

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
