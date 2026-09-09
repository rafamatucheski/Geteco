class_name GarageVisualProposal
extends Node2D

## Proposta Visual de Oficina/Garagem Compacta e Densa
## Organizada por zonas funcionais:
## 1. Baia Principal com Elevador Automotivo Hidráulico e Carro Esportivo
## 2. Estação de Ferramentas: Bancada pesada, Pegboard, Carrinho móvel, Tambores de óleo e Pneus
## 3. Lounge Executivo VIP do Jäger "Maciota" com mesa nobre e tapete persa
## 4. Espaço Reservado para o Quadro de Missões e Contratos (preparado para Claude Code)
## 5. Corredores livres de manobra veicular e circulação de pedestres até a saída sul

const ROOM_SIZE := Vector2(680, 440)
const HALF_SIZE := ROOM_SIZE * 0.5

@export var show_circulation_plan: bool = false:
	set(val):
		show_circulation_plan = val
		if circulation_overlay:
			circulation_overlay.visible = val
		if npc_labels_group:
			npc_labels_group.visible = !val

var circulation_overlay: Node2D
var npc_labels_group: Node2D
var main_camera: Camera2D

func _ready() -> void:
	npc_labels_group = Node2D.new()
	npc_labels_group.name = "NPCLabelsGroup"
	npc_labels_group.z_index = 12
	add_child(npc_labels_group)

	_build_blackout_and_walls()
	_build_collisions()
	_build_floor_and_zones()
	_build_vehicles_and_npcs()
	_build_lighting()
	_build_circulation_overlay()
	_setup_camera()

func _build_blackout_and_walls() -> void:
	var blackout := Polygon2D.new()
	blackout.name = "Blackout"
	blackout.color = Color(0.04, 0.05, 0.06, 1.0)
	blackout.polygon = PackedVector2Array([
		Vector2(-2000, -1500), Vector2(2000, -1500),
		Vector2(2000, 1500), Vector2(-2000, 1500)
	])
	blackout.z_index = -10
	add_child(blackout)

	var walls_node := Node2D.new()
	walls_node.name = "PerimeterWalls"
	add_child(walls_node)

	var wall_dark := Color("#12161c")
	var wall_concrete := Color("#1a2129")
	var wall_trim := Color("#d4ac0d")

	# Parede Norte
	_build_wall_slab(walls_node, Vector2(-HALF_SIZE.x - 30, -HALF_SIZE.y - 30), Vector2(HALF_SIZE.x + 30, -HALF_SIZE.y), wall_dark, wall_concrete, wall_trim)
	# Parede Leste
	_build_wall_slab(walls_node, Vector2(HALF_SIZE.x, -HALF_SIZE.y - 30), Vector2(HALF_SIZE.x + 30, HALF_SIZE.y + 30), wall_dark, wall_concrete, wall_trim)
	# Parede Oeste
	_build_wall_slab(walls_node, Vector2(-HALF_SIZE.x - 30, -HALF_SIZE.y - 30), Vector2(-HALF_SIZE.x, HALF_SIZE.y + 30), wall_dark, wall_concrete, wall_trim)
	# Parede Sul Esquerda
	_build_wall_slab(walls_node, Vector2(-HALF_SIZE.x - 30, HALF_SIZE.y), Vector2(-95, HALF_SIZE.y + 30), wall_dark, wall_concrete, wall_trim)
	# Parede Sul Direita
	_build_wall_slab(walls_node, Vector2(95, HALF_SIZE.y), Vector2(HALF_SIZE.x + 30, HALF_SIZE.y + 30), wall_dark, wall_concrete, wall_trim)

	# Portão Sul / Vão de Saída
	var gate_threshold := Polygon2D.new()
	gate_threshold.name = "GateThreshold"
	gate_threshold.color = Color("#22272e")
	gate_threshold.polygon = PackedVector2Array([
		Vector2(-95, HALF_SIZE.y - 4), Vector2(95, HALF_SIZE.y - 4),
		Vector2(95, HALF_SIZE.y + 26), Vector2(-95, HALF_SIZE.y + 26)
	])
	gate_threshold.z_index = 1
	add_child(gate_threshold)

	for s in [-95, 95]:
		var guide := Polygon2D.new()
		guide.color = Color("#34495e")
		guide.polygon = PackedVector2Array([
			Vector2(s - 4, HALF_SIZE.y - 10), Vector2(s + 4, HALF_SIZE.y - 10),
			Vector2(s + 4, HALF_SIZE.y + 26), Vector2(s - 4, HALF_SIZE.y + 26)
		])
		guide.z_index = 9
		add_child(guide)

func _build_collisions() -> void:
	var walls_body := StaticBody2D.new()
	walls_body.name = "PerimeterCollisions"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)

	# Parede Norte
	_add_box_col(walls_body, Vector2(0, -HALF_SIZE.y - 15), Vector2(ROOM_SIZE.x + 60, 30))
	# Parede Leste
	_add_box_col(walls_body, Vector2(HALF_SIZE.x + 15, 0), Vector2(30, ROOM_SIZE.y + 60))
	# Parede Oeste
	_add_box_col(walls_body, Vector2(-HALF_SIZE.x - 15, 0), Vector2(30, ROOM_SIZE.y + 60))
	# Parede Sul Esquerda
	_add_box_col(walls_body, Vector2(-HALF_SIZE.x * 0.5 - 55, HALF_SIZE.y + 15), Vector2(HALF_SIZE.x - 70, 30))
	# Parede Sul Direita
	_add_box_col(walls_body, Vector2(HALF_SIZE.x * 0.5 + 55, HALF_SIZE.y + 15), Vector2(HALF_SIZE.x - 70, 30))

	# Colisões dos móveis e equipamentos
	var props_body := StaticBody2D.new()
	props_body.name = "PropCollisions"
	props_body.collision_layer = 1
	props_body.collision_mask = 0
	add_child(props_body)

	# Bancada mecânica
	_add_box_col(props_body, Vector2(140, -185), Vector2(170, 46))
	# Suporte do motor V8
	_add_box_col(props_body, Vector2(45, -170), Vector2(24, 24))
	# Carrinho de ferramentas e tambor de óleo
	_add_box_col(props_body, Vector2(260, -80), Vector2(46, 36))
	# Estante de pneus
	_add_box_col(props_body, Vector2(275, 50), Vector2(28, 70))
	# Colunas do elevador automotivo (postes laterais com espaço aberto entre eles)
	_add_box_col(props_body, Vector2(68, -20), Vector2(24, 44))
	_add_box_col(props_body, Vector2(212, -20), Vector2(24, 44))
	# Mesa e divisórias do Maciota
	_add_box_col(props_body, Vector2(-165, -135), Vector2(70, 32))
	_add_box_col(props_body, Vector2(-190, -195), Vector2(210, 8))
	_add_box_col(props_body, Vector2(-85, -135), Vector2(8, 120))
	# Quadro de missões (parede oeste)
	_add_box_col(props_body, Vector2(-270, 40), Vector2(20, 60))

func _add_box_col(parent: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	parent.add_child(col)

func _build_wall_slab(parent: Node, top_left: Vector2, btm_right: Vector2, col_base: Color, _col_top: Color, trim_col: Color) -> void:
	var poly := Polygon2D.new()
	poly.color = col_base
	poly.polygon = PackedVector2Array([
		top_left, Vector2(btm_right.x, top_left.y),
		btm_right, Vector2(top_left.x, btm_right.y)
	])
	poly.z_index = 8
	parent.add_child(poly)

	var inner_edge := Line2D.new()
	inner_edge.width = 3.0
	inner_edge.default_color = trim_col
	inner_edge.points = PackedVector2Array([
		top_left, Vector2(btm_right.x, top_left.y),
		btm_right, Vector2(top_left.x, btm_right.y), top_left
	])
	inner_edge.z_index = 9
	parent.add_child(inner_edge)

func _build_floor_and_zones() -> void:
	var floor_node := GaragePropBuilder.build_concrete_floor(ROOM_SIZE)
	floor_node.z_index = 0
	add_child(floor_node)

	var guide_lane := Line2D.new()
	guide_lane.name = "GuideLane"
	guide_lane.points = PackedVector2Array([
		Vector2(0, HALF_SIZE.y - 10),
		Vector2(0, 95),
		Vector2(65, 30),
		Vector2(140, -10)
	])
	guide_lane.width = 4.0
	guide_lane.default_color = Color(0.95, 0.77, 0.05, 0.45)
	guide_lane.z_index = 1
	add_child(guide_lane)

	var lift := GaragePropBuilder.build_automotive_lift(Vector2(140, -20))
	lift.z_index = 2
	add_child(lift)

	var bench := GaragePropBuilder.build_mechanic_workbench(Vector2(140, -180))
	bench.z_index = 4
	add_child(bench)

	# Suporte com bloco de motor V8
	var engine_stand := Node2D.new()
	engine_stand.name = "EngineStand"
	engine_stand.position = Vector2(45, -170)
	engine_stand.z_index = 4

	var stand_base := Polygon2D.new()
	stand_base.color = Color("#2c3e50")
	stand_base.polygon = PackedVector2Array([
		Vector2(-12, -10), Vector2(12, -10), Vector2(12, 10), Vector2(-12, 10)
	])
	engine_stand.add_child(stand_base)

	var v8_block := Polygon2D.new()
	v8_block.color = Color("#95a5a6")
	v8_block.polygon = PackedVector2Array([
		Vector2(-9, -8), Vector2(9, -8), Vector2(11, 8), Vector2(-11, 8)
	])
	engine_stand.add_child(v8_block)

	for s in [-6, 6]:
		var head := Polygon2D.new()
		head.color = Color("#c0392b")
		head.polygon = PackedVector2Array([
			Vector2(s - 3, -6), Vector2(s + 3, -6), Vector2(s + 3, 6), Vector2(s - 3, 6)
		])
		engine_stand.add_child(head)
	add_child(engine_stand)

	var cart_oil := GaragePropBuilder.build_tool_cart_and_oil(Vector2(260, -80))
	cart_oil.z_index = 4
	add_child(cart_oil)

	var tires := GaragePropBuilder.build_tire_racks(Vector2(275, 50))
	tires.z_index = 4
	add_child(tires)

	var maciota_lounge := GaragePropBuilder.build_maciota_vip_lounge(Vector2(-190, -125))
	maciota_lounge.z_index = 3
	add_child(maciota_lounge)

	var mission_board := GaragePropBuilder.build_mission_board_zone(Vector2(-270, 40))
	mission_board.z_index = 4
	add_child(mission_board)

	var exit_label := Label.new()
	exit_label.text = "▼ SAÍDA / PORTÃO PRINCIPAL ▼"
	exit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_label.position = Vector2(-120, HALF_SIZE.y - 32)
	exit_label.size = Vector2(240, 16)
	exit_label.add_theme_font_size_override("font_size", 9)
	exit_label.add_theme_color_override("font_color", Color("#f1c40f"))
	exit_label.z_index = 7
	add_child(exit_label)

func _build_vehicles_and_npcs() -> void:
	var car_node := Node2D.new()
	car_node.name = "LiftSportsCar"
	car_node.position = Vector2(140, -20)
	car_node.rotation = -PI * 0.5
	car_node.z_index = 5

	var body_poly := Polygon2D.new()
	body_poly.color = Color("#c0392b")
	body_poly.polygon = PackedVector2Array([
		Vector2(-38, -15), Vector2(30, -15), Vector2(38, -10),
		Vector2(38, 10), Vector2(30, 15), Vector2(-38, 15),
		Vector2(-40, 10), Vector2(-40, -10)
	])
	car_node.add_child(body_poly)

	var body_stroke := Line2D.new()
	body_stroke.points = body_poly.polygon
	body_stroke.width = 1.8
	body_stroke.default_color = Color("#78281f")
	car_node.add_child(body_stroke)

	var windshield := Polygon2D.new()
	windshield.color = Color("#1b2631")
	windshield.polygon = PackedVector2Array([
		Vector2(-14, -11), Vector2(14, -11), Vector2(18, -8),
		Vector2(18, 8), Vector2(14, 11), Vector2(-14, 11)
	])
	car_node.add_child(windshield)

	var stripe := Line2D.new()
	stripe.points = PackedVector2Array([Vector2(-38, 0), Vector2(38, 0)])
	stripe.width = 4.0
	stripe.default_color = Color("#17202a")
	car_node.add_child(stripe)

	var spoiler := Polygon2D.new()
	spoiler.color = Color("#17202a")
	spoiler.polygon = PackedVector2Array([
		Vector2(-38, -16), Vector2(-34, -16), Vector2(-34, 16), Vector2(-38, 16)
	])
	car_node.add_child(spoiler)

	add_child(car_node)

	# Tito
	var tito := Node2D.new()
	tito.name = "MechanicTito"
	tito.position = Vector2(140, -135)
	tito.z_index = 6
	_create_npc_token(tito, Color("#2980b9"), Color("#1b4f72"), "Tito 'Graxa'\n[Mecânico Chefe]")
	add_child(tito)

	# Maciota
	var maciota := Node2D.new()
	maciota.name = "JagerMaciota"
	maciota.position = Vector2(-195, -115)
	maciota.z_index = 6
	_create_npc_token(maciota, Color("#7d3c98"), Color("#d4ac0d"), "Jäger 'Maciota'\n[Contatos / VIP]")
	add_child(maciota)

func _create_npc_token(parent: Node2D, shirt_col: Color, accent_col: Color, label_text: String) -> void:
	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.polygon = PackedVector2Array([
		Vector2(-12, 6), Vector2(12, 6), Vector2(14, 12), Vector2(-14, 12)
	])
	parent.add_child(shadow)

	var body := Polygon2D.new()
	body.color = shirt_col
	body.polygon = PackedVector2Array([
		Vector2(-9, -4), Vector2(9, -4), Vector2(11, 7), Vector2(-11, 7)
	])
	parent.add_child(body)

	var head := Polygon2D.new()
	head.color = Color("#f5cba7")
	var pts := PackedVector2Array()
	for i in 16:
		var ang := float(i) * TAU / 16.0
		pts.append(Vector2(0, -9) + Vector2(cos(ang), sin(ang)) * 6.5)
	head.polygon = pts
	parent.add_child(head)

	var hair := Line2D.new()
	hair.points = PackedVector2Array([Vector2(-6, -12), Vector2(0, -15), Vector2(6, -12)])
	hair.width = 3.0
	hair.default_color = accent_col
	parent.add_child(hair)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = parent.position + Vector2(-90, 14)
	lbl.size = Vector2(180, 40)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color("#f7f9f9"))
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	npc_labels_group.add_child(lbl)

func _build_lighting() -> void:
	var env_mod := CanvasModulate.new()
	env_mod.color = Color(0.40, 0.44, 0.50, 1.0)
	add_child(env_mod)

	var ceiling_lights = [
		Vector2(140, -100), Vector2(140, 60),
		Vector2(-60, -100), Vector2(-60, 60),
		Vector2(0, 140)
	]
	for lpos in ceiling_lights:
		var light := PointLight2D.new()
		light.position = lpos
		light.energy = 0.85
		light.color = Color(0.90, 0.95, 1.0, 1.0)
		light.texture = _create_radial_gradient(250, Color(1, 1, 1, 0.70))
		light.z_index = 6
		add_child(light)

		var box := Polygon2D.new()
		box.color = Color("#2c3e50")
		box.polygon = PackedVector2Array([
			lpos + Vector2(-25, -4), lpos + Vector2(25, -4),
			lpos + Vector2(25, 4), lpos + Vector2(-25, 4)
		])
		box.z_index = 7
		add_child(box)

		var tube := Line2D.new()
		tube.points = PackedVector2Array([lpos + Vector2(-21, 0), lpos + Vector2(21, 0)])
		tube.width = 3.0
		tube.default_color = Color("#f4f6f7")
		tube.z_index = 8
		add_child(tube)

	var bench_light := PointLight2D.new()
	bench_light.position = Vector2(140, -180)
	bench_light.energy = 1.05
	bench_light.color = Color(1.0, 0.92, 0.75, 1.0)
	bench_light.texture = _create_radial_gradient(220, Color(1, 1, 1, 0.85))
	bench_light.z_index = 6
	add_child(bench_light)

	var maciota_light := PointLight2D.new()
	maciota_light.position = Vector2(-190, -125)
	maciota_light.energy = 1.20
	maciota_light.color = Color(1.0, 0.82, 0.50, 1.0)
	maciota_light.texture = _create_radial_gradient(240, Color(1, 1, 1, 0.90))
	maciota_light.z_index = 6
	add_child(maciota_light)

	var board_light := PointLight2D.new()
	board_light.position = Vector2(-270, 40)
	board_light.energy = 1.10
	board_light.color = Color(1.0, 0.95, 0.80, 1.0)
	board_light.texture = _create_radial_gradient(200, Color(1, 1, 1, 0.85))
	board_light.z_index = 6
	add_child(board_light)

func _create_radial_gradient(size: int, peak_color: Color) -> Texture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([peak_color, Color(peak_color.r, peak_color.g, peak_color.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

func _build_circulation_overlay() -> void:
	circulation_overlay = Node2D.new()
	circulation_overlay.name = "CirculationFloorPlan"
	circulation_overlay.visible = show_circulation_plan
	circulation_overlay.z_index = 20
	add_child(circulation_overlay)

	var dim_bg := Polygon2D.new()
	dim_bg.color = Color(0.02, 0.04, 0.06, 0.65)
	dim_bg.polygon = PackedVector2Array([
		Vector2(-HALF_SIZE.x, -HALF_SIZE.y), Vector2(HALF_SIZE.x, -HALF_SIZE.y),
		Vector2(HALF_SIZE.x, HALF_SIZE.y), Vector2(-HALF_SIZE.x, HALF_SIZE.y)
	])
	circulation_overlay.add_child(dim_bg)

	# Rota Veicular Livre
	var veh_corridor := Polygon2D.new()
	veh_corridor.color = Color(0.18, 0.80, 0.44, 0.20)
	veh_corridor.polygon = PackedVector2Array([
		Vector2(-55, HALF_SIZE.y), Vector2(55, HALF_SIZE.y),
		Vector2(75, 80), Vector2(195, -20), Vector2(195, -70),
		Vector2(85, -70), Vector2(-30, 60), Vector2(-55, HALF_SIZE.y)
	])
	circulation_overlay.add_child(veh_corridor)

	var veh_path := Line2D.new()
	veh_path.points = PackedVector2Array([
		Vector2(0, HALF_SIZE.y),
		Vector2(0, 100),
		Vector2(50, 40),
		Vector2(140, -20)
	])
	veh_path.width = 5.0
	veh_path.default_color = Color("#2ecc71")
	circulation_overlay.add_child(veh_path)

	# Rotas de Pedestres
	var ped_routes = [
		[Vector2(0, 170), Vector2(-70, 100), Vector2(-120, -20), Vector2(-170, -75)],
		[Vector2(0, 170), Vector2(-120, 120), Vector2(-220, 40)],
		[Vector2(0, 170), Vector2(60, 100), Vector2(70, -20), Vector2(70, -140), Vector2(140, -140)],
		[Vector2(-170, -75), Vector2(-190, 0), Vector2(-220, 40)],
		[Vector2(-120, -90), Vector2(0, -90), Vector2(70, -140), Vector2(140, -140)]
	]
	for r in ped_routes:
		var line := Line2D.new()
		line.points = PackedVector2Array(r)
		line.width = 3.0
		line.default_color = Color("#00cec9")
		circulation_overlay.add_child(line)

	# Beacons de Interação
	var beacons = [
		{"pos": Vector2(0, HALF_SIZE.y - 15), "lbl_pos": Vector2(0, HALF_SIZE.y - 45), "col": Color("#2ecc71"), "title": "PORTÃO DE SAÍDA", "desc": "Retorno ao Exterior"},
		{"pos": Vector2(140, -20), "lbl_pos": Vector2(140, 25), "col": Color("#e67e22"), "title": "BAIA ELEVADOR", "desc": "Manutenção / Tuning"},
		{"pos": Vector2(140, -155), "lbl_pos": Vector2(140, -120), "col": Color("#3498db"), "title": "BANCADA TITO", "desc": "Diálogo / Modificações"},
		{"pos": Vector2(-185, -95), "lbl_pos": Vector2(-185, -55), "col": Color("#f1c40f"), "title": "JÄGER 'MACIOTA'", "desc": "Contratos / Missões VIP"},
		{"pos": Vector2(-250, 40), "lbl_pos": Vector2(-250, -5), "col": Color("#9b59b6"), "title": "QUADRO DE MISSÕES", "desc": "Área Reservada (Claude Code)"}
	]
	for b in beacons:
		var circle := Polygon2D.new()
		circle.color = b.col
		var pts := PackedVector2Array()
		for i in 16:
			var ang := float(i) * TAU / 16.0
			pts.append(b.pos + Vector2(cos(ang), sin(ang)) * 13.0)
		circle.polygon = pts
		circulation_overlay.add_child(circle)

		var beacon_border := Line2D.new()
		beacon_border.points = pts
		beacon_border.width = 2.0
		beacon_border.default_color = Color.WHITE
		circulation_overlay.add_child(beacon_border)

		var label := Label.new()
		label.text = "[ %s ]\n%s" % [b.title, b.desc]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = b.lbl_pos + Vector2(-90, -16)
		label.size = Vector2(180, 32)
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", b.col)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		circulation_overlay.add_child(label)

	var legend_panel := Polygon2D.new()
	legend_panel.color = Color(0.08, 0.10, 0.14, 0.92)
	legend_panel.polygon = PackedVector2Array([
		Vector2(-HALF_SIZE.x + 10, HALF_SIZE.y - 75),
		Vector2(-HALF_SIZE.x + 290, HALF_SIZE.y - 75),
		Vector2(-HALF_SIZE.x + 290, HALF_SIZE.y - 10),
		Vector2(-HALF_SIZE.x + 10, HALF_SIZE.y - 10)
	])
	circulation_overlay.add_child(legend_panel)

	var legend_stroke := Line2D.new()
	legend_stroke.points = legend_panel.polygon
	legend_stroke.width = 1.5
	legend_stroke.default_color = Color("#4a6572")
	circulation_overlay.add_child(legend_stroke)

	var leg_text := Label.new()
	leg_text.text = "PLANTA TÉCNICA DE CIRCULAÇÃO & ACESSIBILIDADE\n• Corredor Veicular Livre (Verde): 110px de largura\n• Corredores de Pedestre (Ciano): 100% desobstruídos\n• Zonas de Interação demarcadas e acessíveis a pé"
	leg_text.position = Vector2(-HALF_SIZE.x + 18, HALF_SIZE.y - 70)
	leg_text.size = Vector2(270, 60)
	leg_text.add_theme_font_size_override("font_size", 8)
	leg_text.add_theme_color_override("font_color", Color("#ecf0f1"))
	circulation_overlay.add_child(leg_text)

func _setup_camera() -> void:
	main_camera = Camera2D.new()
	main_camera.name = "ProposalCamera"
	main_camera.position = Vector2(0, 0)
	main_camera.zoom = Vector2(1.55, 1.55)
	add_child(main_camera)
	main_camera.make_current()

func set_camera_view(pos: Vector2, zoom: Vector2) -> void:
	if main_camera:
		main_camera.position = pos
		main_camera.zoom = zoom
