@tool
extends EditorPlugin

const ROAD_SCRIPT := preload("res://city_demo/scripts/roads/CityRoadSegment.gd")
const INTERSECTION_SCRIPT := preload("res://city_demo/scripts/roads/CityIntersection.gd")
const CROSSWALK_SCRIPT := preload("res://city_demo/scripts/roads/CityCrosswalk.gd")
const BUILDING_SCENE := preload("res://city_demo/scenes/CityBuilding.tscn")
const LAMP_SCENE := preload("res://StreetLamp.tscn")
const UNIFIED_ROAD_NETWORK_SCRIPT := preload("res://district/roads/UnifiedRoadNetwork2D.gd")

var toolbar: HBoxContainer

func _enter_tree() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "CityLayoutToolbar"
	_add_button("Ver Cidade Inteira", _frame_entire_city)
	_add_button("+ Rua", _create_road)
	_add_button("Ligar 2 pontos", _connect_selected_points)
	_add_button("+ Cruzamento", _create_intersection)
	_add_button("+ Faixa", _create_crosswalk)
	_add_button("+ Prédio", _create_building)
	_add_button("+ Poste", _create_lamp)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)

func _exit_tree() -> void:
	if toolbar != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
		toolbar.queue_free()

func _add_button(label_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = "Adiciona à cidade atual. Selecione um distrito ou Node2D para definir onde o item ficará na árvore."
	button.pressed.connect(callback)
	toolbar.add_child(button)

func _frame_entire_city() -> void:
	var root := get_editor_interface().get_edited_scene_root() as Node2D
	if root == null:
		push_warning("Abra a cena da cidade antes de enquadrá-la.")
		return
	var road_graph := root.find_child("UnifiedRoadNetwork", true, false) as Node2D
	if road_graph == null or not road_graph.has_method("get_graph_data"):
		push_warning("A cena atual não contém uma UnifiedRoadNetwork.")
		return
	var graph_data: Dictionary = road_graph.call("get_graph_data")
	var bounds := Rect2()
	var has_point := false
	for road in graph_data.get("roads", []):
		for local_point in (road as Dictionary).get("points", PackedVector2Array()):
			var point := road_graph.to_global(local_point)
			if not has_point:
				bounds = Rect2(point, Vector2.ZERO)
				has_point = true
			else:
				bounds = bounds.expand(point)
	if not has_point or bounds.size.x < 1.0 or bounds.size.y < 1.0:
		push_warning("Não foi possível calcular os limites visuais da cidade.")
		return
	# O CanvasItemEditor sobrescreve global_canvas_transform a cada redraw. Para que
	# zoom, barras e régua continuem sincronizados, use o enquadramento nativo
	# (Shift+F) sobre dois marcadores editoriais temporários nos cantos da cidade.
	bounds = bounds.grow(180.0)
	var corner_a := Marker2D.new()
	var corner_b := Marker2D.new()
	corner_a.name = "_CityFrameMin"
	corner_b.name = "_CityFrameMax"
	root.add_child(corner_a)
	root.add_child(corner_b)
	corner_a.global_position = bounds.position
	corner_b.global_position = bounds.end

	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(corner_a)
	selection.add_node(corner_b)

	var frame_event := InputEventKey.new()
	frame_event.keycode = KEY_F
	frame_event.physical_keycode = KEY_F
	frame_event.shift_pressed = true
	frame_event.pressed = true
	Input.parse_input_event(frame_event)
	frame_event = frame_event.duplicate()
	frame_event.pressed = false
	Input.parse_input_event(frame_event)
	call_deferred("_finish_city_frame", corner_a, corner_b, road_graph)

func _finish_city_frame(corner_a: Marker2D, corner_b: Marker2D, road_graph: Node2D) -> void:
	if is_instance_valid(corner_a):
		corner_a.queue_free()
	if is_instance_valid(corner_b):
		corner_b.queue_free()
	var selection := get_editor_interface().get_selection()
	selection.clear()
	if is_instance_valid(road_graph):
		selection.add_node(road_graph)

func _get_parent_for_new_item() -> Node2D:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	if not selected.is_empty() and selected[0] is Node2D:
		return selected[0] as Node2D
	# Sem seleção, o item entra na Main real; nunca em uma cidade-demo paralela.
	return root as Node2D

func _add_editable_item(item: Node2D, item_name: String) -> void:
	var parent := _get_parent_for_new_item()
	if parent == null:
		push_warning("Abra uma cena 2D antes de criar um elemento urbano.")
		return
	item.name = item_name
	item.position = parent.get_local_mouse_position()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Adicionar %s" % item_name)
	undo_redo.add_do_method(self, "_attach_item", parent, item)
	undo_redo.add_undo_method(parent, "remove_child", item)
	undo_redo.add_do_reference(item)
	undo_redo.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(item)

func _attach_item(parent: Node2D, item: Node2D) -> void:
	parent.add_child(item)
	item.owner = get_editor_interface().get_edited_scene_root()
	if item is CityRoadSegment:
		(item as CityRoadSegment).render_legacy_road = false
		_ensure_unified_road_network()

func _create_road() -> void:
	var road = ROAD_SCRIPT.new()
	road.length = 360.0
	road.add_street_lamps = false # postes devem ser nós independentes e arrastáveis
	_add_editable_item(road, "Rua")

func _connect_selected_points() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	if selected.size() != 2 or not (selected[0] is Node2D) or not (selected[1] is Node2D):
		push_warning("Selecione exatamente dois pontos/Marker2D para criar uma ligação.")
		return
	var start := selected[0] as Node2D
	var finish := selected[1] as Node2D
	if start.global_position.distance_to(finish.global_position) < 32.0:
		push_warning("Os dois pontos da ligação estão muito próximos.")
		return
	var road = ROAD_SCRIPT.new()
	road.name = "LigacaoRua"
	road.add_street_lamps = false
	var parent := get_editor_interface().get_edited_scene_root() as Node2D
	if parent == null:
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Criar ligação viária")
	undo_redo.add_do_method(self, "_attach_connected_road", parent, road, start, finish)
	undo_redo.add_undo_method(parent, "remove_child", road)
	undo_redo.add_do_reference(road)
	undo_redo.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(road)

func _attach_connected_road(parent: Node2D, road, start: Node2D, finish: Node2D) -> void:
	parent.add_child(road)
	road.owner = get_editor_interface().get_edited_scene_root()
	road.render_legacy_road = false
	road.start_anchor = road.get_path_to(start)
	road.end_anchor = road.get_path_to(finish)
	road.snap_between_anchors()
	_ensure_unified_road_network()

func _create_intersection() -> void:
	var junction := Marker2D.new()
	junction.set_meta("road_junction", true)
	_add_editable_item(junction, "Cruzamento")

func _ensure_unified_road_network() -> void:
	var root := get_editor_interface().get_edited_scene_root() as Node2D
	if root == null:
		return
	if root.find_child("UnifiedRoadNetwork", true, false) != null:
		return
	var network := UNIFIED_ROAD_NETWORK_SCRIPT.new() as Node2D
	network.name = "UnifiedRoadNetwork"
	network.provider_paths = []
	root.add_child(network)
	network.owner = root

func _create_crosswalk() -> void:
	_add_editable_item(CROSSWALK_SCRIPT.new() as Node2D, "Faixa")

func _create_building() -> void:
	_add_editable_item(BUILDING_SCENE.instantiate() as Node2D, "Predio")

func _create_lamp() -> void:
	_add_editable_item(LAMP_SCENE.instantiate() as Node2D, "Poste")
