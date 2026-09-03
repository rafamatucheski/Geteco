class_name CentralDocksHarbor
extends Node2D

## As Docas do Cais Central (Central Docks Harbor)
## Cais industrial completo localizado ao sul da Garagem do Mano Otto:
## Água azul-escura do porto com ondulações, quebra-mar de concreto, navio cargueiro atracado,
## pilhas de contêineres Maersk/Hapag coloridos, guindastes portuários e iluminação industrial.

const WATER_RECT := Rect2(30, 1020, 750, 240)
const PIER_EDGE_Y := 1020.0

var _water_clock: float = 0.0

func _ready() -> void:
	z_index = 0
	add_to_group("docks_harbor")
	queue_redraw()
	_create_static_docks_props()

func _process(delta: float) -> void:
	_water_clock += delta * 1.8
	queue_redraw()

func _draw() -> void:
	# 1. Água do Oceano / Porto Profundo (Azul-Marinho com reflexos)
	draw_rect(WATER_RECT, Color("#0c2461"))
	
	# Ondas animadas e reflexos na superfície da água
	for i in range(7):
		var y_pos = WATER_RECT.position.y + 25.0 + float(i * 30)
		var wave_offset = sin(_water_clock + float(i) * 0.85) * 16.0
		var p1 = Vector2(WATER_RECT.position.x, y_pos + sin(_water_clock * 1.2 + float(i)) * 4.0)
		var p2 = Vector2(WATER_RECT.end.x, y_pos + cos(_water_clock * 1.2 + float(i)) * 4.0)
		draw_line(p1 + Vector2(wave_offset, 0), p2 + Vector2(wave_offset, 0), Color(0.15, 0.45, 0.85, 0.30), 2.5)

	# 2. Cais de Concreto / Quebra-mar com Meio-Fio Industrial Zebrado (Amarelo e Preto)
	var pier_top_rect := Rect2(30, 990, 750, 32)
	draw_rect(pier_top_rect, Color("#3d3d3d"))
	
	# Faixas zebradas de perigo na borda da água
	var stripe_w := 24.0
	var num_stripes := int(750.0 / stripe_w)
	for s in range(num_stripes):
		var sx = 30.0 + float(s) * stripe_w
		var col = Color("#f1c40f") if s % 2 == 0 else Color("#1e272e")
		draw_line(Vector2(sx, PIER_EDGE_Y - 4), Vector2(sx + 14, PIER_EDGE_Y + 4), col, 4.0)

	# Cabeços de amarração de navios (Mooring Bollards) de ferro fundido
	for b in range(6):
		var bx = 80.0 + float(b * 120)
		draw_circle(Vector2(bx, PIER_EDGE_Y - 10), 6.0, Color("#2d3436"))
		draw_circle(Vector2(bx, PIER_EDGE_Y - 10), 4.0, Color("#636e72"))

func _create_static_docks_props() -> void:
	# 3. Grande Navio Cargueiro Atracado no Cais ("SS Liberty Star")
	_create_cargo_ship(Vector2(420, 1140))
	
	# 4. Pilhas de Contêineres Coloridos (Azul, Vermelho, Verde, Laranja)
	_create_container_stack(Vector2(140, 950), Color("#0984e3"), "MAERSK")
	_create_container_stack(Vector2(210, 950), Color("#d63031"), "HAPAG")
	_create_container_stack(Vector2(175, 925), Color("#00b894"), "EVERGREEN") # Empilhado em cima
	
	_create_container_stack(Vector2(580, 950), Color("#e17055"), "HAMBURG")
	_create_container_stack(Vector2(650, 950), Color("#0984e3"), "MAERSK")
	_create_container_stack(Vector2(615, 925), Color("#fdcb6e"), "COSCO")
	
	# 5. Guindaste de Pórtico Amarelo Gigante (Container Gantry Crane)
	_create_gantry_crane(Vector2(320, 980))

func _create_cargo_ship(pos: Vector2) -> void:
	var ship := Node2D.new()
	ship.name = "CargoShip"
	ship.position = pos
	ship.z_index = 1
	
	# Casco do navio (360x120px)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([
		Vector2(-180, -40), Vector2(140, -40), Vector2(180, 0),
		Vector2(140, 40), Vector2(-180, 40)
	])
	hull.color = Color("#2d3436") # Casco preto industrial
	ship.add_child(hull)
	
	# Convés de madeira/aço vermelho
	var deck := Polygon2D.new()
	deck.polygon = PackedVector2Array([
		Vector2(-170, -32), Vector2(130, -32), Vector2(165, 0),
		Vector2(130, 32), Vector2(-170, 32)
	])
	deck.color = Color("#b71540") # Vermelho marítimo
	ship.add_child(deck)
	
	# Cabine de comando de popa (Branca)
	var bridge := Polygon2D.new()
	bridge.polygon = PackedVector2Array([
		Vector2(-160, -24), Vector2(-110, -24), Vector2(-110, 24), Vector2(-160, 24)
	])
	bridge.color = Color("#f5f6fa")
	ship.add_child(bridge)
	
	# Chaminé com listra
	var funnel := Polygon2D.new()
	funnel.polygon = PackedVector2Array([
		Vector2(-145, -10), Vector2(-130, -10), Vector2(-130, 10), Vector2(-145, 10)
	])
	funnel.color = Color("#e84118")
	bridge.add_child(funnel)
	
	# Contêineres no convés do navio
	var ship_c1 = _make_rect(Vector2(-90, -22), Vector2(40, 20), Color("#0984e3"))
	var ship_c2 = _make_rect(Vector2(-40, -22), Vector2(40, 20), Color("#e17055"))
	var ship_c3 = _make_rect(Vector2(10, -22), Vector2(40, 20), Color("#00b894"))
	var ship_c4 = _make_rect(Vector2(60, -22), Vector2(40, 20), Color("#fdcb6e"))
	var ship_c5 = _make_rect(Vector2(-65, 2), Vector2(40, 20), Color("#d63031"))
	var ship_c6 = _make_rect(Vector2(-15, 2), Vector2(40, 20), Color("#0984e3"))
	var ship_c7 = _make_rect(Vector2(35, 2), Vector2(40, 20), Color("#e17055"))
	
	ship.add_child(ship_c1)
	ship.add_child(ship_c2)
	ship.add_child(ship_c3)
	ship.add_child(ship_c4)
	ship.add_child(ship_c5)
	ship.add_child(ship_c6)
	ship.add_child(ship_c7)
	
	# Colisão física do navio na água
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(360, 80)
	col.shape = shape
	blocker.add_child(col)
	ship.add_child(blocker)
	
	add_child(ship)

func _create_container_stack(pos: Vector2, col: Color, label_text: String) -> void:
	var container := Node2D.new()
	container.position = pos
	container.z_index = 5
	
	# Caixa do contêiner 3D (60x30px)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-30, -15), Vector2(30, -15), Vector2(30, 15), Vector2(-30, 15)
	])
	body.color = col
	container.add_child(body)
	
	# Frisos ondulados metálicos do contêiner
	for i in range(5):
		var fx = -22.0 + float(i * 10)
		var stripe = Line2D.new()
		stripe.width = 1.5
		stripe.default_color = Color(0, 0, 0, 0.25)
		stripe.add_point(Vector2(fx, -14))
		stripe.add_point(Vector2(fx, 14))
		container.add_child(stripe)
		
	var lbl = Label.new()
	lbl.text = label_text
	lbl.position = Vector2(-26, -7)
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	container.add_child(lbl)
	
	# Colisão sólida do contêiner
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	var col_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60, 30)
	col_shape.shape = shape
	blocker.add_child(col_shape)
	container.add_child(blocker)
	
	add_child(container)

func _create_gantry_crane(pos: Vector2) -> void:
	var crane := Node2D.new()
	crane.position = pos
	crane.z_index = 15
	
	# Estrutura amarela de vigas treliçadas (120x80px)
	var leg_l = Line2D.new()
	leg_l.width = 6.0
	leg_l.default_color = Color("#f39c12")
	leg_l.add_point(Vector2(-45, 30))
	leg_l.add_point(Vector2(-35, -40))
	crane.add_child(leg_l)
	
	var leg_r = Line2D.new()
	leg_r.width = 6.0
	leg_r.default_color = Color("#f39c12")
	leg_r.add_point(Vector2(45, 30))
	leg_r.add_point(Vector2(35, -40))
	crane.add_child(leg_r)
	
	var beam = Line2D.new()
	beam.width = 10.0
	beam.default_color = Color("#f39c12")
	beam.add_point(Vector2(-60, -40))
	beam.add_point(Vector2(60, -40))
	crane.add_child(beam)
	
	# Cabine do operador
	var cab := Polygon2D.new()
	cab.polygon = PackedVector2Array([
		Vector2(-12, -48), Vector2(12, -48), Vector2(12, -32), Vector2(-12, -32)
	])
	cab.color = Color("#e67e22")
	crane.add_child(cab)
	
	# Cabo e gancho erguendo contêiner
	var cable = Line2D.new()
	cable.width = 2.0
	cable.default_color = Color("#2c3e50")
	cable.add_point(Vector2(0, -32))
	cable.add_point(Vector2(0, 0))
	crane.add_child(cable)
	
	add_child(crane)

func _make_rect(pos: Vector2, size: Vector2, col: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)
	])
	p.color = col
	return p
