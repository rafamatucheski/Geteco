extends Node2D

const SKI_LAYOUT := preload("res://world/mountain_pass/MountainSkiLayout.gd")

## Reserva de fallback caso mountain.cold_hud ainda não exista quando este
## bloco é montado. A temperatura agora vive junto de vida/colete à direita,
## portanto os avisos curtos podem começar na margem livre da esquerda.
const STACK_TOP_FALLBACK := 24.0
const STACK_LEFT := 24.0
const STACK_WIDTH := 300.0
var mountain: Node2D
var region_ready := false
var _streamed := false
var prompt: Label
var readout: Label
var _readout_panel: PanelContainer
var _prompt_panel: PanelContainer
var message_time := 0.0
var previous_altitude := 0.0
var _was_indoors := false
var tutorial_seen: Dictionary = {}
var shop_position := Vector2(5980, 650)
var _arrival_time := 0.0

func _ready() -> void:
	mountain = get_parent()
	_streamed = bool(mountain.get("streamed_region"))
	set_process(false)
	set_process_unhandled_key_input(false)
	_build_shop()
	await _budget_pause()
	_build_boundaries()
	await _budget_pause()
	_build_summit()
	await _budget_pause()
	await _build_residents()
	var hud := CanvasLayer.new()
	hud.layer = 106
	add_child(hud)

	# ColdStatusHUD expõe a margem segura da coluna esquerda. O vital térmico
	# em si está integrado ao HUD principal, junto de vida e colete.
	var stack_top := STACK_TOP_FALLBACK
	if mountain.cold_hud != null and mountain.cold_hud.has_method("get_stack_bottom_offset"):
		stack_top = mountain.cold_hud.get_stack_bottom_offset()

	# Altitude: painel de fundo (em vez de texto solto + sombra) para
	# contraste legível sobre céu/neve claros.
	_readout_panel = _make_backdrop_panel(Vector2(STACK_LEFT, stack_top), STACK_WIDTH)
	hud.add_child(_readout_panel)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 15)
	readout.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	readout.add_theme_constant_override("outline_size", 3)
	_readout_panel.add_child(readout)
	_readout_panel.hide()

	# Avisos temporários (frio, túnel, casaco, chefe): painel próprio logo
	# abaixo, com quebra de linha automática para nunca cortar texto mais
	# longo, escondido quando não há aviso ativo.
	_prompt_panel = _make_backdrop_panel(Vector2(STACK_LEFT, stack_top + 40.0), STACK_WIDTH)
	hud.add_child(_prompt_panel)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt.add_theme_constant_override("outline_size", 3)
	prompt.custom_minimum_size = Vector2(STACK_WIDTH - 24.0, 0)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_panel.add_child(prompt)
	_prompt_panel.visible = false

	region_ready = true
	set_process(true)
	set_process_unhandled_key_input(true)

func _make_backdrop_panel(pos: Vector2, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.11, 0.72)
	style.border_color = Color(0.75, 0.82, 0.88, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _budget_pause() -> void:
	if _streamed: await get_tree().process_frame

## A CGI de abertura roda numa CanvasLayer própria em layer=100
## (HarborArrivalMission.gd:_opening_layer); nossa hud CanvasLayer usa
## layer=106 e renderizaria por cima dela se os dois chegarem a coexistir.
## Ver o mesmo helper em ColdStatusHUD.gd.
func _is_cgi_playing() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var mission := scene.get_node_or_null("ArrivalMission")
	if mission == null:
		return false
	var opening_layer = mission.get("_opening_layer")
	return opening_layer != null and is_instance_valid(opening_layer)

func _process(delta: float) -> void:
	if not mountain.region_selected:
		return
	if is_instance_valid(_readout_panel) and mountain.cold_hud != null:
		_readout_panel.position.y = mountain.cold_hud.get_stack_bottom_offset()
		if is_instance_valid(_prompt_panel): _prompt_panel.position.y = _readout_panel.position.y
	var cgi_playing := _is_cgi_playing()
	if is_instance_valid(_readout_panel):
		_readout_panel.visible = false
	if cgi_playing:
		if is_instance_valid(_prompt_panel):
			_prompt_panel.visible = false
		return
	var actor: Node2D = mountain.player_instance
	if not is_instance_valid(actor):
		return
	if actor.is_in_dialogue:
		_readout_panel.hide()
		_prompt_panel.hide()
		return
	var indoors := bool(actor.get_meta("mountain_interior", false)) or bool(actor.get_meta("harbor_interior",false))
	if not indoors and not actor.is_in_dialogue and not actor.is_dead:
		_arrival_time += delta
	if indoors != _was_indoors:
		message_time = 0.0
		prompt.text = ""
		_was_indoors = indoors
	var local_actor: Vector2 = mountain.to_local(actor.global_position)
	var altitude := clampf(680.0 + (400.0 - local_actor.y) * 0.62, 680.0, 2780.0)
	if local_actor.y < SKI_LAYOUT.RIDGE_Y:
		# Após a crista, a coordenada continua para o norte da tela, mas o
		# terreno passa a descer pela face oposta da montanha.
		altitude = clampf(2780.0 - (SKI_LAYOUT.RIDGE_Y - local_actor.y) * 0.55, 1450.0, 2780.0)
	previous_altitude = altitude
	readout.text = ""
	mountain.cold_controller.has_thermal_suit = actor.mountain_thermal_coat
	mountain.cold_controller.outfit_protection = OutfitCatalog.cold_protection(actor.current_outfit_id)
	message_time = maxf(0.0, message_time - delta)
	if message_time == 0.0:
		prompt.text = ""
	if message_time == 0.0:
		if not indoors and mountain.cold_controller.current_temperature < 65.0 and not tutorial_seen.has("cold"):
			_notice("cold", "FRIO INTENSO")
		elif mountain.tunnel.contains_actor(actor) and not tutorial_seen.has("tunnel"):
			_notice("tunnel", "TÚNEL: diminua a velocidade. [L] faróis / [Espaço] freio de mão.")
	# Sincroniza o painel de fundo do aviso com o texto atual -- roda por
	# último e sempre (não dentro de um early-return), senão o painel nunca
	# aparece enquanto message_time > 0 (ou seja, bem quando o aviso está
	# ativo).
	if is_instance_valid(_prompt_panel):
		_prompt_panel.visible = prompt.text != ""

func _unhandled_key_input(_event: InputEvent) -> void:
	pass

func _notice(id: String, text: String) -> void:
	tutorial_seen[id] = true
	var tutorials := get_tree().get_first_node_in_group("gameplay_tutorials")
	if tutorials != null and id in ["cold", "tunnel", "thermal_shop"]:
		tutorials.request_context("cold_shelter" if id == "cold" else id)
		return
	prompt.text = text
	message_time = 8.0

func _box(parent: Node2D, rect: Rect2, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	poly.color = color
	parent.add_child(poly)

func _sign(parent: Node2D, pos: Vector2, text: String) -> void:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("f4dfaa"))
	parent.add_child(label)

func _wall(a: Vector2, b: Vector2, _bridge_edge := false) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var segment := SegmentShape2D.new()
	segment.a = a
	segment.b = b
	shape.shape = segment
	body.add_child(shape)
	add_child(body)

func _build_boundaries() -> void:
	# Closed regional perimeter, preserving the bridge corridor and every existing POI.
	var west := 3000.0 if mountain.streamed_region else 2900.0
	var points := PackedVector2Array([Vector2(west, 290), Vector2(4650, 290), Vector2(4800, -1800), Vector2(5750, -3300), Vector2(6100, -5050), Vector2(8100, -5050), Vector2(8250, -3350), Vector2(9150, -800), Vector2(9200, 1150), Vector2(5000, 1400), Vector2(4650, 510), Vector2(west, 510), Vector2(west, 290)])
	for i in points.size() - 1:
		if mountain.streamed_region and i == points.size() - 2: continue
		_wall(points[i], points[i + 1], i == 0 or i == 8)

func _build_shop() -> void:
	var shop := preload("res://world/mountain_pass/MountainOutfittersFacade.gd").new()
	shop.name = "SnowOutfitters"
	shop.position = shop_position
	shop.mountain = mountain
	add_child(shop)

func _build_summit() -> void:
	var summit := preload("res://world/mountain_pass/MountainBunkerFacade.gd").new()
	summit.name = "IceWolvesStronghold"
	summit.position = Vector2(6500, -2800)
	summit.z_index = 5
	for side in [-1.0, 1.0]:
		for i in 4:
			_box(summit, Rect2(side * 135 - 15, -80 + i * 32, 30, 23), Color("625c4a"))
		_box(summit, Rect2(side * 105, -150, 8, 65), Color("353c47"))
		_box(summit, Rect2(side * 105 + 8, -145, 35, 23), Color("9f3f35"))
	var car = preload("res://world/mountain_pass/ArcticJeep.gd").new()
	car.name = "WhiteoutSpecial"
	car.position = Vector2(300, -30)
	car.paint_color = Color("d6ad58")
	car.max_speed = 580.0
	car.acceleration = 480.0
	summit.add_child(car)
	var door_visual := Polygon2D.new()
	door_visual.name = "StationZeroSlidingDoor"
	door_visual.polygon = PackedVector2Array([Vector2(-21,-108),Vector2(21,-108),Vector2(21,-42),Vector2(-21,-42)])
	door_visual.color = Color("313b42")
	summit.add_child(door_visual)
	summit.door_leaf = door_visual
	var entrance := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "StationZeroEntrance"
	entrance.position = Vector2(0, -42)
	entrance.destination_id = &"mountain_bunker"
	entrance.display_name = "ESTAÇÃO ZERO"
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	summit.add_child(entrance)
	entrance.get_node("Facade").hide()
	summit.entrance = entrance
	# Solid facade prevents walking straight through the bunker outside.
	var facade := StaticBody2D.new()
	facade.name = "StationZeroFacadeCollision"
	facade.collision_layer = 1
	facade.collision_mask = 0
	for entry in [
		[Vector2(-73,-105),Vector2(94,105)],
		[Vector2(73,-105),Vector2(94,105)],
		[Vector2(0,-146),Vector2(52,22)],
		[Vector2(0,-75),Vector2(42,66)],
	]:
		var collider := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = entry[1]
		collider.shape = box
		collider.position = entry[0]
		facade.add_child(collider)
		if entry[0] == Vector2(0,-75): summit.door_collision = collider
	summit.add_child(facade)
	add_child(summit)
	summit.inline_room = mountain.interior_manager.get_interior(&"mountain_bunker")
	summit.inline_room.attach_inline_facade(summit, entrance, mountain.interior_manager)
	summit.inline_room.global_position = entrance.global_position - summit.inline_room.project_floor(Vector2(0, 5.8))
	var vista := preload("res://world/mountain_pass/MountainVista.gd").new()
	vista.name = "SummitVista"
	add_child(vista)

func _build_residents() -> void:
	var people := [
		[Vector2(6045, 680), "Mara / Último Abrigo", Color("53778e"), [
			"Parka térmica aqui. Entre na loja e experimente.",
			"Os Cobras continuam subindo carga pela serra.",
			"Os Lobos de Gelo controlam a passagem no cume.",
			"Depois dos picos, a rodovia leva à cidade."
		]],
		[Vector2(6430, 635), "Ivo / Madeireira", Color("59715b"), [
			"Reduza antes das curvas. Gelo não perdoa.",
			"O fogo está aceso para quem ficou na subida.",
			"O 4x4 dourado do bunker é o Whiteout."
		]]
	]
	for entry in people:
		var npc := preload("res://world/mountain_pass/WinterResident.gd").new()
		npc.position = entry[0]
		npc.resident_name = entry[1]
		npc.coat_color = entry[2]
		npc.role = "logger" if String(entry[1]).begins_with("Ivo") else "trader"
		npc.lines.assign(entry[3])
		add_child(npc)
		await _budget_pause()
