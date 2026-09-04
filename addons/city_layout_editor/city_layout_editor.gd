@tool
extends EditorPlugin

const ROAD_SCRIPT := preload("res://city_demo/scripts/roads/CityRoadSegment.gd")
const ROAD_CURVE_SCRIPT := preload("res://city_demo/scripts/roads/CityRoadCurve.gd")
const LOT_SCRIPT := preload("res://city_demo/scripts/roads/CityLot.gd")
const INTERSECTION_SCRIPT := preload("res://city_demo/scripts/roads/CityIntersection.gd")
const CROSSWALK_SCRIPT := preload("res://city_demo/scripts/roads/CityCrosswalk.gd")
const LAMP_SCENE := preload("res://StreetLamp.tscn")
const UNIFIED_ROAD_NETWORK_SCRIPT := preload("res://district/roads/UnifiedRoadNetwork2D.gd")

# Predio "de verdade": o mesmo script (ProceduralBuilding.gd) usado pelo
# CentralDistrict e pelo Bairro1, desenhado por codigo (sem sprite fixo) e
# com uma variedade grande de "building_kind" ja prontos -- por isso o menu
# de biblioteca abaixo usa ele em vez da CityBuilding.tscn antiga (um
# placeholder simples, visualmente diferente do resto do mapa).
const PROCEDURAL_BUILDING_SCRIPT := preload("res://ProceduralBuilding.gd")
const PROCEDURAL_TREE_SCRIPT := preload("res://district/nature/ProceduralStreetTree.gd")
const PROCEDURAL_ROCK_SCRIPT := preload("res://district/nature/ProceduralUrbanRock.gd")

# Biblioteca de prédios: rótulo em português -> (building_kind, footprint
# padrão). "building_kind" é lido por ProceduralBuilding._draw() e por
# _facade_color()/_roof_style() etc. (ver ProceduralBuilding.gd) para
# escolher janelas, cor, letreiro e telhado.
const BUILDING_LIBRARY := [
	{"label": "Loja / Comércio", "kind": "commercial", "footprint": Vector2(180, 150)},
	{"label": "Loja de Roupas", "kind": "clothing_shop", "footprint": Vector2(190, 200)},
	{"label": "Ammu-Nation", "kind": "ammunation_shop", "footprint": Vector2(170, 200)},
	{"label": "Loja de Esquina", "kind": "corner_shop", "footprint": Vector2(180, 158)},
	{"label": "Escritório", "kind": "office", "footprint": Vector2(190, 260)},
	{"label": "Galpão / Armazém", "kind": "warehouse", "footprint": Vector2(190, 130)},
	{"label": "Garagem", "kind": "garage", "footprint": Vector2(300, 290)},
	{"label": "Hospital", "kind": "hospital", "footprint": Vector2(234, 254)},
	{"label": "Necrotério / IML", "kind": "morgue", "footprint": Vector2(254, 160)},
	{"label": "Delegacia", "kind": "police", "footprint": Vector2(244, 192)},
	{"label": "Quartel de Bombeiros", "kind": "fire_station", "footprint": Vector2(270, 280)},
	{"label": "Casa Geminada", "kind": "rowhouse", "footprint": Vector2(184, 116)},
	{"label": "Sobrado", "kind": "brownstone", "footprint": Vector2(176, 116)},
	{"label": "Praça / Parque", "kind": "park", "footprint": Vector2(234, 80)},
]

const TREE_LIBRARY := [
	{"label": "Árvore de Rua", "style": 0}, # ProceduralStreetTree.TreeStyle.STREET
	{"label": "Copa Larga", "style": 1}, # BROADLEAF
	{"label": "Pinheiro", "style": 2}, # PINE
	{"label": "Costeira", "style": 3}, # COASTAL
]

const INTERSECTION_LIBRARY := [
	{"label": "4 vias", "type": INTERSECTION_SCRIPT.JunctionType.CROSS_4_WAY},
	{"label": "T - Norte", "type": INTERSECTION_SCRIPT.JunctionType.T_JUNCTION_NORTH},
	{"label": "T - Sul", "type": INTERSECTION_SCRIPT.JunctionType.T_JUNCTION_SOUTH},
	{"label": "T - Leste", "type": INTERSECTION_SCRIPT.JunctionType.T_JUNCTION_EAST},
	{"label": "T - Oeste", "type": INTERSECTION_SCRIPT.JunctionType.T_JUNCTION_WEST},
	{"label": "Rotatória", "type": INTERSECTION_SCRIPT.JunctionType.ROUNDABOUT},
]

const LOT_LIBRARY := [
	{"label": "Lote Edificável", "kind": "buildable"},
	{"label": "Área Proibida", "kind": "forbidden"},
]

var toolbar: HBoxContainer
var building_dropdown: OptionButton
var tree_dropdown: OptionButton
var intersection_dropdown: OptionButton
var lot_dropdown: OptionButton

func _enter_tree() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "CityLayoutToolbar"
	_add_button("Ver Cidade Inteira", _frame_entire_city)
	_add_button("+ Rua", _create_road)
	_add_button("+ Curva", _create_road_curve)
	_add_button("Ligar 2 pontos", _connect_selected_points)
	intersection_dropdown = _add_dropdown(INTERSECTION_LIBRARY)
	_add_button("+ Cruzamento", _create_intersection)
	_add_button("+ Faixa", _create_crosswalk)
	lot_dropdown = _add_dropdown(LOT_LIBRARY)
	_add_button("+ Lote", _create_lot)
	building_dropdown = _add_dropdown(BUILDING_LIBRARY)
	_add_button("+ Prédio", _create_building)
	tree_dropdown = _add_dropdown(TREE_LIBRARY)
	_add_button("+ Árvore", _create_tree)
	_add_button("+ Pedra", _create_rock)
	_add_button("+ Poste", _create_lamp)
	_add_button("Atualizar Ligações", _resync_connected_roads)
	_add_button("Validar Malha", _validate_road_network)
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

## Cria o menu suspenso (dropdown) de biblioteca que fica ao lado do botão
## "+ Prédio"/"+ Árvore": cada opção é um item pronto do jogo (ver
## BUILDING_LIBRARY / TREE_LIBRARY acima), então adicionar variedade não
## exige escrever nada -- só escolher no menu e clicar no botão.
func _add_dropdown(library: Array) -> OptionButton:
	var dropdown := OptionButton.new()
	for entry in library:
		dropdown.add_item(entry["label"])
	dropdown.tooltip_text = "Escolha o tipo antes de clicar no botão + ao lado."
	toolbar.add_child(dropdown)
	return dropdown

func _frame_entire_city() -> void:
	var root := get_editor_interface().get_edited_scene_root() as Node2D
	if root == null:
		push_warning("Abra a cena da cidade antes de enquadrá-la.")
		return
	var bounds := _collect_city_bounds(root)
	if not bounds.size.x > 0.0 or not bounds.size.y > 0.0:
		push_warning("Não foi possível calcular os limites visuais da cidade.")
		return
	_request_editor_frame(bounds, root)

func _collect_city_bounds(root: Node) -> Rect2:
	# IMPORTANTE: este scan tem que somar os limites de TODAS as fontes abaixo,
	# nunca parar na primeira que encontrar um ponto. O bug antigo usava
	# "if not has_point:" para so cair no fallback generico quando a rede
	# UnifiedRoadNetwork nao existia -- na pratica a cena Main tem varios
	# distritos irmaos (CentralDistrict, CoastalExtension, EmergencyDepots,
	# DistrictInteriors, etc.) e so UM deles (DistrictOneComplete) tem uma
	# UnifiedRoadNetwork. Assim que ela era achada, o calculo parava ali e
	# "Ver Cidade Inteira" so enquadrava aquele distrito, cortando o resto do
	# mapa fora da tela (metade da cidade "sumia").
	var bounds := Rect2()
	var has_point := false

	for road_graph in root.find_children("*", "", true, false):
		if road_graph.has_method("get_graph_data") and String(road_graph.name).begins_with("UnifiedRoadNetwork"):
			var graph_data: Dictionary = road_graph.call("get_graph_data")
			for road in graph_data.get("roads", []):
				for local_point in (road as Dictionary).get("points", PackedVector2Array()):
					if local_point is Vector2 and road_graph is Node2D:
						var point := (road_graph as Node2D).to_global(local_point)
						bounds = _expand_bounds(bounds, point, has_point)
						has_point = true

	for node in root.find_children("*", "Node2D", true, false):
		var city_node := node as Node2D
		if city_node == null:
			continue

		if city_node is CityRoadSegment and city_node.has_method("get_start_point") and city_node.has_method("get_end_point"):
			var start_point := city_node.get_start_point() as Vector2
			var end_point := city_node.get_end_point() as Vector2
			bounds = _expand_bounds(bounds, start_point, has_point)
			has_point = true
			bounds = _expand_bounds(bounds, end_point, has_point)
			has_point = true
			continue

		if city_node.has_method("get_road_graph_definitions"):
			for definition in city_node.call("get_road_graph_definitions"):
				var definition_points := (definition as Dictionary).get("points", PackedVector2Array())
				for local_point in definition_points:
					if local_point is Vector2:
						var point := city_node.to_global(local_point)
						bounds = _expand_bounds(bounds, point, has_point)
						has_point = true
			continue

		if city_node.has_method("get_bounds"):
			var lot_bounds: Rect2 = city_node.call("get_bounds")
			if lot_bounds.size.x > 0.0 and lot_bounds.size.y > 0.0:
				bounds = _expand_bounds(bounds, city_node.to_global(lot_bounds.position), has_point)
				has_point = true
				bounds = _expand_bounds(bounds, city_node.to_global(lot_bounds.end), has_point)
				has_point = true
				continue

		var marker_name := String(city_node.name)
		if marker_name.begins_with("Crossing") or marker_name.begins_with("Road") or marker_name.begins_with("Control") or city_node is Marker2D:
			bounds = _expand_bounds(bounds, city_node.global_position, has_point)
			has_point = true

	return bounds if has_point else Rect2()

func _expand_bounds(current_bounds: Rect2, point: Vector2, has_point: bool) -> Rect2:
	if not has_point:
		return Rect2(point, Vector2.ZERO)
	current_bounds = current_bounds.expand(point)
	return current_bounds

func _request_editor_frame(bounds: Rect2, root: Node) -> void:
	var road_graph := root.find_child("UnifiedRoadNetwork", true, false)
	var road_graph_node = null
	if road_graph is Node2D:
		road_graph_node = road_graph
	# O CanvasItemEditor sobrescreve global_canvas_transform a cada redraw. Para que
	# zoom, barras e régua continuem sincronizados, use o enquadramento nativo
	# (Shift+F) sobre dois marcadores editoriais nos cantos da cidade.
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
	call_deferred("_finish_city_frame", corner_a, corner_b, road_graph_node)

func _finish_city_frame(corner_a: Marker2D, corner_b: Marker2D, road_graph) -> void:
	if is_instance_valid(corner_a):
		corner_a.queue_free()
	if is_instance_valid(corner_b):
		corner_b.queue_free()
	var selection := get_editor_interface().get_selection()
	selection.clear()
	if is_instance_valid(road_graph) and road_graph is Node2D:
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
	var scene_root: Node = null
	if get_editor_interface() != null:
		scene_root = get_editor_interface().get_edited_scene_root()
	item.owner = scene_root
	if scene_root != null:
		_assign_owner_recursive(item, scene_root)
	if item is CityRoadSegment:
		(item as CityRoadSegment).render_legacy_road = false
		_ensure_unified_road_network()

func _assign_owner_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_assign_owner_recursive(child, scene_root)

func _create_road() -> void:
	var road = ROAD_SCRIPT.new()
	road.length = 360.0
	road.add_street_lamps = false # postes devem ser nós independentes e arrastáveis
	_add_editable_item(road, "Rua")

func _create_road_curve() -> void:
	var curve: Node2D = ROAD_CURVE_SCRIPT.new()
	_add_editable_item(curve, "CurvaRua")

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
	var index := intersection_dropdown.selected if intersection_dropdown != null else 0
	if index < 0:
		index = 0
	var entry: Dictionary = INTERSECTION_LIBRARY[index]
	var junction := INTERSECTION_SCRIPT.new() as CityIntersection
	junction.junction_type = int(entry["type"])
	_add_editable_item(junction, "Cruzamento")

func _validate_road_network() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("Abra uma cena da cidade antes de validar a malha.")
		return
	var validation_errors: Array[String] = []
	for node in root.find_children("*", "", true, false):
		if not node.has_method("get_validation_errors"):
			continue
		for validation_error in node.call("get_validation_errors"):
			validation_errors.append(String(validation_error))
	if validation_errors.is_empty():
		push_warning("Malha OK: 0 avisos")
		return
	for validation_error in validation_errors:
		push_warning(validation_error)

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

func _create_lot() -> void:
	var index := lot_dropdown.selected if lot_dropdown != null else 0
	if index < 0:
		index = 0
	var entry: Dictionary = LOT_LIBRARY[index]
	var kind: String = String(entry.get("kind", "buildable"))
	var lot: Node2D = LOT_SCRIPT.new()
	lot.set("lot_kind", kind)
	var half_size := 50.0
	var default_points := PackedVector2Array([
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size),
	])
	lot.set("points", default_points)
	var lot_name := "Lote" if kind == "buildable" else "AreaProibida"
	_add_editable_item(lot, lot_name)

func _create_building() -> void:
	var index := building_dropdown.selected if building_dropdown != null else 0
	if index < 0:
		index = 0
	var entry: Dictionary = BUILDING_LIBRARY[index]
	var parent := _get_parent_for_new_item()
	if parent == null:
		push_warning("Abra uma cena 2D antes de criar um elemento urbano.")
		return
	var building := PROCEDURAL_BUILDING_SCRIPT.new() as ProceduralBuilding
	building.name = String(entry["label"]).validate_node_name()
	building.footprint = entry["footprint"]
	building.building_kind = String(entry["kind"])
	building.variant_seed = randi() % 1000
	building.position = parent.get_local_mouse_position()
	# O prédio em si só desenha (Node2D puro, sem colisão própria -- o mesmo
	# vale para o ProceduralBuilding usado no CentralDistrict/Bairro1), então
	# criamos junto um StaticBody2D bloqueador do tamanho certo, do mesmo
	# jeito que CentralDistrict._add_building_collision faz. Sem isso o
	# prédio ficaria "fantasma" (visual only, dá pra atravessar andando).
	var blocker := StaticBody2D.new()
	blocker.name = "%s_Blocker" % building.name
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = entry["footprint"]
	collision.shape = shape
	blocker.add_child(collision)
	var is_park := "park" in String(entry["kind"])
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Adicionar %s" % building.name)
	undo_redo.add_do_method(self, "_attach_building_with_blocker", parent, building, blocker, is_park)
	undo_redo.add_undo_method(parent, "remove_child", building)
	if not is_park:
		# Parque não ganha bloqueador (ver _attach_building_with_blocker), então
		# desfazer não pode tentar remover um nó que nunca virou filho de "parent"
		# -- isso derrubaria o editor com "not a child" ao apertar Ctrl+Z.
		undo_redo.add_undo_method(parent, "remove_child", blocker)
	undo_redo.add_do_reference(building)
	undo_redo.add_do_reference(blocker)
	undo_redo.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(building)

func _attach_building_with_blocker(parent: Node2D, building: Node2D, blocker: Node2D, is_park: bool) -> void:
	parent.add_child(building)
	building.owner = get_editor_interface().get_edited_scene_root()
	# Parques são espaço público andável; só estruturas de verdade bloqueiam.
	if is_park:
		return
	parent.add_child(blocker)
	blocker.owner = get_editor_interface().get_edited_scene_root()
	blocker.position = building.position

func _create_tree() -> void:
	var index := tree_dropdown.selected if tree_dropdown != null else 0
	if index < 0:
		index = 0
	var entry: Dictionary = TREE_LIBRARY[index]
	var tree := PROCEDURAL_TREE_SCRIPT.new() as Node2D
	tree.set("tree_style", int(entry["style"]))
	tree.set("variant_seed", randi() % 1000)
	_add_editable_item(tree, String(entry["label"]).validate_node_name())

func _create_rock() -> void:
	var rock := PROCEDURAL_ROCK_SCRIPT.new() as Node2D
	rock.set("variant_seed", randi() % 1000)
	_add_editable_item(rock, "Pedra")

func _create_lamp() -> void:
	_add_editable_item(LAMP_SCENE.instantiate() as Node2D, "Poste")

## "Ligar 2 pontos" cria uma CityRoadSegment presa a dois marcadores
## (start_anchor/end_anchor), mas por padrão ela só se ajusta ao arrastar
## desses marcadores quando você liga manualmente "Update Connection Now" no
## Inspector -- de propósito, pra nunca desfazer um ajuste manual da rua
## enquanto o artista está arrastando ela mesma. Este botão faz esse "clique
## no Update Connection Now" de uma vez para TODAS as ruas ligadas da cena
## atual, então o fluxo de "arrastei os dois pontos, agora a rua acompanha"
## vira um clique só em vez de abrir o Inspector de cada rua.
func _resync_connected_roads() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("Abra a cena da cidade antes de atualizar as ligações.")
		return
	var roads: Array[Node] = []
	for node in root.find_children("*", "", true, false):
		if node is CityRoadSegment:
			var road := node as CityRoadSegment
			if not road.start_anchor.is_empty() and not road.end_anchor.is_empty():
				roads.append(road)
	if roads.is_empty():
		push_warning("Nenhuma rua ligada a dois pontos (start_anchor/end_anchor) foi encontrada.")
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Atualizar Ligações de Rua")
	for road in roads:
		var r := road as CityRoadSegment
		var prev_state := {
			"global_position": r.global_position,
			"length": r.length,
			"orientation": r.orientation,
			"custom_angle_degrees": r.custom_angle_degrees,
		}
		undo_redo.add_do_method(r, "snap_between_anchors")
		undo_redo.add_undo_method(self, "_restore_road_state", r, prev_state)
	undo_redo.commit_action()
	print("Atualizei %d rua(s) ligada(s) aos seus pontos." % roads.size())

func _restore_road_state(road: CityRoadSegment, state: Dictionary) -> void:
	road.global_position = state["global_position"]
	road.orientation = state["orientation"]
	road.custom_angle_degrees = state["custom_angle_degrees"]
	road.length = state["length"]
