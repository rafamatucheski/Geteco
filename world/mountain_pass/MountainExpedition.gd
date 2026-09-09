extends Node2D

const COAT_PRICE := 650
## Reserva de fallback caso mountain.cold_hud ainda não exista quando este
## bloco é montado (ordem de _ready() entre irmãos não é garantida) --
## coincide com ColdStatusHUD.BLOCK_TOP + 96, ver ui/HUD_LAYOUT_NOTES.md.
const STACK_TOP_FALLBACK := 350.0
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
var shop_position := Vector2(5980, 530)

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

	# Empilha abaixo do bloco de temperatura/proteção térmica de
	# ColdStatusHUD.gd (contrato: get_stack_bottom_offset()) em vez de um
	# número mágico solto -- evita que os dois blocos voltem a se sobrepor
	# se um deles crescer.
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
	var cgi_playing := _is_cgi_playing()
	if is_instance_valid(_readout_panel):
		_readout_panel.visible = not cgi_playing
	if cgi_playing:
		if is_instance_valid(_prompt_panel):
			_prompt_panel.visible = false
		return
	var actor: Node2D = mountain.player_instance
	if not is_instance_valid(actor):
		return
	var indoors := bool(actor.get_meta("mountain_interior", false)) or bool(actor.get_meta("harbor_interior",false))
	if indoors != _was_indoors:
		message_time = 0.0
		prompt.text = ""
		_was_indoors = indoors
	var local_actor: Vector2 = mountain.to_local(actor.global_position)
	var altitude := clampf(680.0 + (400.0 - local_actor.y) * 0.62, 680.0, 2780.0)
	var slope := "SUBINDO" if altitude > previous_altitude + 0.1 else ("DESCENDO" if altitude < previous_altitude - 0.1 else "")
	previous_altitude = altitude
	readout.text = "SERRA DA NEVASCA  /  %d m  %s" % [int(altitude), slope] if not indoors else "ABRIGO / RECUPERANDO CALOR"
	mountain.cold_controller.has_thermal_suit = actor.mountain_thermal_coat
	mountain.cold_controller.outfit_protection = OutfitCatalog.cold_protection(actor.current_outfit_id)
	message_time = maxf(0.0, message_time - delta)
	if message_time == 0.0:
		prompt.text = ""
	if message_time == 0.0:
		if not indoors and actor.visible and local_actor.distance_to(shop_position) < 105.0:
			prompt.text = "[E] ENTRAR / ROUPAS DE FRIO"
		elif not indoors and local_actor.y < -1450 and not tutorial_seen.has("cold"):
			_notice("cold", "FRIO: temperatura zerada causa dano contínuo à vida.
Carros, lareiras e túneis oferecem abrigo.")
		elif mountain.tunnel.contains_actor(actor) and not tutorial_seen.has("tunnel"):
			_notice("tunnel", "TÚNEL: diminua a velocidade. [L] faróis / [Espaço] freio de mão.")
		elif local_actor.distance_to(Vector2(6500, -2800)) < 220 and not tutorial_seen.has("boss"):
			_notice("boss", "COVIL DOS LOBOS DE GELO
O chefe controla a passagem para a rodovia do deserto.")
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
	if tutorials != null and id in ["cold", "tunnel"]:
		tutorials.request_context("cold_shelter" if id == "cold" else "tunnel")
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

func _wall(a: Vector2, b: Vector2, bridge_edge := false) -> void:
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
	var edge := Line2D.new()
	edge.points = PackedVector2Array([a, b])
	edge.width = 5 if bridge_edge else 32
	edge.default_color = Color("a4b5ba") if bridge_edge else Color("566575")
	edge.z_index = 3
	add_child(edge)

func _build_boundaries() -> void:
	# Closed regional perimeter, preserving the bridge corridor and every existing POI.
	var west := 3000.0 if mountain.streamed_region else 2900.0
	var points := PackedVector2Array([Vector2(west, 290), Vector2(4650, 290), Vector2(4800, -1800), Vector2(5750, -3300), Vector2(7400, -3300), Vector2(9150, -800), Vector2(9200, 1150), Vector2(5000, 1400), Vector2(4650, 510), Vector2(west, 510), Vector2(west, 290)])
	for i in points.size() - 1:
		if mountain.streamed_region and i == points.size() - 2: continue
		_wall(points[i], points[i + 1], i == 0 or i == 8)

func _build_shop() -> void:
	var shop := Node2D.new()
	shop.name = "SnowOutfitters"
	shop.position = shop_position
	shop.z_index = 5
	add_child(shop)
	var model := preload("res://world/mountain_pass/MountainOutfitters3D.gd").new()
	shop.add_child(model)
	_sign(shop, Vector2(-110, -150), "ÚLTIMO ABRIGO / ROUPAS DE NEVE")
	_sign(shop, Vector2(-72, 75), "ROUPAS  [E]")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(190, 90)
	collision.position.y = -20
	collision.shape = shape
	wall.add_child(collision)
	shop.add_child(wall)
	# A warm service counter provides a safe first stop.
	var heater := Node2D.new()
	heater.position = Vector2(0, 65)
	heater.add_to_group("heat_source")
	shop.add_child(heater)
	var recovery := Marker2D.new()
	recovery.name = "MountainRecoverySpawn"
	recovery.position = Vector2(0, 105)
	recovery.add_to_group("hospital_spawn")
	shop.add_child(recovery)

func _build_summit() -> void:
	var summit := Node2D.new()
	summit.name = "IceWolvesStronghold"
	summit.position = Vector2(6500, -2800)
	summit.z_index = 5
	add_child(summit)
	_sign(summit, Vector2(-115, -175), "LOBOS DE GELO / ESTAÇÃO ZERO")
	for side in [-1.0, 1.0]:
		for i in 4:
			_box(summit, Rect2(side * 135 - 15, -80 + i * 32, 30, 23), Color("625c4a"))
		_box(summit, Rect2(side * 105, -150, 8, 65), Color("353c47"))
		_box(summit, Rect2(side * 105 + 8, -145, 35, 23), Color("9f3f35"))
	var car = preload("res://world/mountain_pass/ArcticJeep.gd").new()
	car.name = "WhiteoutSpecial"
	car.position = Vector2(230, 100)
	car.paint_color = Color("d6ad58")
	car.max_speed = 580.0
	car.acceleration = 480.0
	summit.add_child(car)
	_sign(summit, Vector2(50, 140), "WHITEOUT / 4x4 ESPECIAL")
	var entrance := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "StationZeroEntrance"
	entrance.position = Vector2(0, -42)
	entrance.destination_id = &"mountain_bunker"
	entrance.display_name = "ESTAÇÃO ZERO"
	entrance.custom_prompt_text = "[E] ENTRAR NA ESTAÇÃO ZERO"
	summit.add_child(entrance)
	mountain.interior_manager.register_exterior_entrance(entrance, &"mountain_bunker", mountain.to_global(Vector2(6500, -2790)))
	# Solid facade prevents walking straight through the bunker outside.
	var facade := StaticBody2D.new()
	facade.name = "StationZeroFacadeCollision"
	facade.collision_layer = 1
	facade.collision_mask = 0
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(240, 105)
	collider.shape = box
	collider.position = Vector2(0, -105)
	facade.add_child(collider)
	summit.add_child(facade)
	var vista := preload("res://world/mountain_pass/MountainVista.gd").new()
	vista.name = "SummitVista"
	add_child(vista)

func _build_residents() -> void:
	var people := [
		[Vector2(6065, 615), "Mara / Último Abrigo", Color("bf744b"), [
			"Sou Mara. Casaco no balcão, por $650. Na serra, roupa boa compra tempo; abrigo salva a vida.",
			"Ouvi o rádio do porto. Os Cobras perderam o controle, mas os carregamentos continuam subindo para cá.",
			"Os Lobos de Gelo ocupam a antiga estação no cume. Quem controla aquela passagem cobra de todos.",
			"Depois dos picos vem a rodovia do deserto. Os pilotos correm rumo à cidade das luzes. Você consegue vê-la lá de cima."
		]],
		[Vector2(6430, 635), "Ivo / Madeireira", Color("59715b"), [
			"A estrada faz curvas fechadas. Tire o pé antes de entrar; frear em cima do gelo só piora.",
			"A gente mantém o fogo aceso para quem ficou preso na subida. Pode chegar.",
			"Vi um 4x4 dourado no bunker. Chamam de Whiteout. Não é carro de lenhador."
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
